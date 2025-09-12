-- MegaToggler: Tabbed keyboard-driven toggle dashboard for Neovim 0.9+
--
-- This module provides a floating window with tabs and checkbox-like items.
-- Users navigate with the keyboard and toggle items that run user-provided
-- callbacks. State persists across sessions via a small JSON file.
--
-- Keyboard UX:
-- - Movement: j/k, Up/Down, gg/G (native buffer navigation)
-- - Tabs: h/l, Left/Right, Tab/Shift-Tab
-- - Toggle item: <CR> or <Space>
-- - Close: q or <Esc>
--
local M = {}

-- Dedicated namespace for extmark-based highlights (Neovim 0.11+)
local NS = vim.api.nvim_create_namespace('MegaToggler')

-- Defaults and config baseline
local defaults = {
  tabs = {},
  ui = {
    width = 60,
    height = 18,
    border = 'rounded',
    title = 'MegaToggler',
    zindex = 200,
    icons = {
      checked = ' ',
      unchecked = ' ',
    },
  },
  persist = true,
  persist_namespace = 'default',
  persist_file = vim.fn.stdpath('state') .. '/megatoggler/state.json',
}

-- Default icons; users may override per item
local ICONS = { checked = ' ', unchecked = ' ' }

-- Internal ephemeral state for the dashboard instance
local state = {
  config = nil,
  current_tab = 1,
  buf = nil,
  win = nil,
  prev_win = nil, -- window id active before opening dashboard
  prev_buf = nil, -- buffer id active before opening dashboard
  persisted = {},
}

-- Forward declaration for helper used before its definition
local with_target_window

-- Forward declaration for persist-all helper
local persist_all_current_states

-- Forward declaration for item_effective_state used before its definition
local item_effective_state

-- deepcopy: recursively copies tables to avoid mutating user-provided options
local function deepcopy(tbl)
  if type(tbl) ~= 'table' then return tbl end
  local res = {}
  for k, v in pairs(tbl) do
    res[k] = deepcopy(v)
  end
  return res
end

-- merge: recursively merges table `b` into `a`, returning a fresh table.
-- Primitive values from `b` override those in `a`.
local function merge(a, b)
  local res = deepcopy(a)
  for k, v in pairs(b or {}) do
    if type(v) == 'table' and type(res[k]) == 'table' then
      res[k] = merge(res[k], v)
    else
      res[k] = v
    end
  end
  return res
end

-- Persistence helpers
local function persist_file()
  local cfg = state.config or defaults
  local custom = cfg and cfg.persist_file
  if type(custom) == 'string' and #custom > 0 then
    return vim.fn.expand(custom)
  end
  return defaults.persist_file
end

-- load_state: read JSON state into memory; initialize empty if none
local function load_state()
  if not state.config or state.config.persist == false then
    state.persisted = {}
    return
  end
  local ok = vim.uv.fs_stat(persist_file()) ~= nil
  if not ok then
    state.persisted = {}
    return
  end
  local lines = vim.fn.readfile(persist_file())
  local content = table.concat(lines, '\n')
  local ok2, decoded = pcall(vim.json.decode, content)
  if ok2 and type(decoded) == 'table' then
    state.persisted = decoded
  else
    state.persisted = {}
  end
end

-- save_state: write the in-memory state to the JSON file
local function save_state()
  if not state.config or state.config.persist == false then return end
  local file = persist_file()
  local dir = vim.fn.fnamemodify(file, ':h')
  if dir and #dir > 0 then vim.fn.mkdir(dir, 'p') end
  local encoded = vim.json.encode(state.persisted or {})
  -- writefile expects a list of lines
  local lines = {}
  for s in encoded:gmatch("[^\n]+") do table.insert(lines, s) end
  if #lines == 0 then lines = { encoded } end
  vim.fn.writefile(lines, file)
end

-- get_persist: returns saved boolean for a given namespace/tab/item
local function get_persist(ns, tab_id, item_id)
  local root = state.persisted[ns]
  if not root then return nil end
  local t = root[tab_id]
  if not t then return nil end
  return t[item_id]
end

-- persist_all_current_states: snapshot current states for all items and write
-- them to the persistence file in a single save. Uses item.get() evaluated in
-- the target window context when available.
function persist_all_current_states()
  if not state.config or state.config.persist == false then return end
  local ns = state.config.persist_namespace or 'default'
  state.persisted[ns] = state.persisted[ns] or {}
  local ns_tbl = state.persisted[ns]
  for _, tab in ipairs(state.config.tabs or {}) do
    ns_tbl[tab.id] = ns_tbl[tab.id] or {}
    local tab_tbl = ns_tbl[tab.id]
    for _, item in ipairs(tab.items or {}) do
      if not item.disabled and item.persist ~= false and type(item.get) == 'function' then
        local val = item_effective_state(tab, item)
        tab_tbl[item.id] = val and true or false
      end
    end
  end
  save_state()
end

-- set_persist: saves a boolean for a given namespace/tab/item and writes file
local function set_persist(ns, tab_id, item_id, val)
  state.persisted[ns] = state.persisted[ns] or {}
  state.persisted[ns][tab_id] = state.persisted[ns][tab_id] or {}
  state.persisted[ns][tab_id][item_id] = val and true or false
  save_state()
end

-- apply_persisted_states: enforce persisted values by invoking user callbacks
-- when they differ from the current state. Uses optional item.get() when
-- available; otherwise falls back to the item's default `checked` value.
local function apply_persisted_states()
  -- Apply persisted values only once at setup time.
  -- If a persisted value exists and differs from get(), enforce it by calling
  -- on_toggle(pv). We do not write get() into persisted at startup.
  if not state.config or state.config.persist == false then return end
  local ns = state.config.persist_namespace or 'default'
  for _, tab in ipairs(state.config.tabs or {}) do
    for _, item in ipairs(tab.items or {}) do
      if not item.disabled and item.persist ~= false and type(item.get) == 'function' and type(item.on_toggle) == 'function' then
        local pv = get_persist(ns, tab.id, item.id)
        if pv ~= nil then
          local ok_get, cur = pcall(item.get)
          if not ok_get then
            vim.notify(string.format('MegaToggler: get() failed for %s: %s', item.label or item.id, cur), vim.log.levels.WARN)
          else
            local curb = not not cur
            if pv ~= curb then
              local ok_cb, err = pcall(item.on_toggle, pv)
              if not ok_cb then
                vim.notify(string.format('MegaToggler: error applying persisted %s: %s', item.label or item.id, err), vim.log.levels.ERROR)
              end
            end
          end
        end
      end
    end
  end
end

-- Utility: pick icons
local function get_icons(item)
  local cfg = state.config or defaults
  local cfg_icons = (cfg.ui and cfg.ui.icons) or nil
  local icons = (item and item.icons) or cfg_icons or ICONS
  return {
    checked = icons.checked or ICONS.checked,
    unchecked = icons.unchecked or ICONS.unchecked,
  }
end

-- Convenience helpers for current tab and item state resolution
local function current_tab_conf()
  return state.config.tabs[state.current_tab]
end

-- find tab by id; returns index and tab or nil
local function find_tab(tab_id)
  if not (state.config and state.config.tabs) then return nil, nil end
  for i, t in ipairs(state.config.tabs) do
    if t.id == tab_id then return i, t end
  end
  return nil, nil
end

function item_effective_state(tab, item)
  -- Effective state for UI is whatever get() reports on the target window.
  local ok, cur
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    ok, cur = with_target_window(item.get)
  else
    ok, cur = pcall(item.get)
  end
  if not ok then
    vim.notify(string.format('MegaToggler: get() failed for %s: %s', item.label or item.id, cur), vim.log.levels.WARN)
    return false
  end
  return not not cur
end

-- Make buffer scratchy, hidden, and isolated from user files
local function set_buf_opts(buf)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'mega_toggler'
end

-- apply_highlights: assigns highlight groups over (line, col) ranges
-- spans is an array of: { hl_group, lnum_0_based, start_col, end_col }
local function apply_highlights(buf, spans)
  -- spans: list of {hl, lnum (0-based), start_col, end_col}
  for _, s in ipairs(spans or {}) do
    local hl, lnum, start_col, end_col = s[1], s[2], s[3], s[4]
    pcall(vim.api.nvim_buf_set_extmark, buf, NS, lnum, start_col, {
      end_row = lnum,
      end_col = end_col,
      hl_group = hl,
    })
  end
end

-- enforce_toggler_winopts: make sure the dashboard window keeps predictable
-- window-local options, regardless of what user callbacks might change when we
-- temporarily jump to other windows to apply toggles.
local function enforce_toggler_winopts(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  pcall(function() vim.wo[win].number = false end)
  pcall(function() vim.wo[win].relativenumber = false end)
  pcall(function() vim.wo[win].signcolumn = 'no' end)
  pcall(function() vim.wo[win].wrap = false end)
  pcall(function() vim.wo[win].spell = false end)
  -- Ensure we are not left in insert mode after interacting with terminal buffers
  pcall(vim.cmd.stopinsert)
end

-- with_target_window: temporarily switch to the previous editor window (or a
-- best-effort non-floating fallback) to run `fn`, then switch back to the
-- dashboard window and re-assert its window-local options. Returns pcall tuple.
function with_target_window(fn)
  local cur_win = vim.api.nvim_get_current_win()
  local target = nil
  if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) then
    target = state.prev_win
  else
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if not state.win or w ~= state.win then
        local cfg = vim.api.nvim_win_get_config(w)
        if not cfg or cfg.relative == '' then
          target = w
          break
        end
      end
    end
  end
  if target and vim.api.nvim_win_is_valid(target) then
    pcall(vim.api.nvim_set_current_win, target)
  end
  local ok, res = pcall(fn)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_set_current_win, cur_win)
    enforce_toggler_winopts(state.win)
  else
    pcall(vim.api.nvim_set_current_win, cur_win)
    pcall(vim.cmd.stopinsert)
  end
  return ok, res
end

-- ensure_highlight_defaults: define our highlight groups by linking to common
-- defaults if they are not already defined by the colorscheme.
local function ensure_highlight_defaults()
  local function try(cmd)
    pcall(vim.api.nvim_command, cmd)
  end
  -- Define default highlight groups if they don't exist
  try('highlight default link MegaTogglerTitle Title')
  try('highlight default link MegaTogglerBorder FloatBorder')
  try('highlight default link MegaTogglerTab TabLine')
  try('highlight default link MegaTogglerTabActive TabLineSel')
  try('highlight default link MegaTogglerItem Normal')
  try('highlight default link MegaTogglerItemOn String')
  try('highlight default link MegaTogglerItemOff Comment')
  try('highlight default link MegaTogglerDesc Comment')
  try('highlight default link MegaTogglerHint NonText')
end

-- build_tabline: produce the tabline string (line 1) and highlight spans
-- for each tab label so the active tab can be visually distinguished.
local function build_tabline(tab_index)
  local tabs = state.config.tabs
  local pieces = {}
  local spans = {}
  local col = 0
  for i, t in ipairs(tabs) do
    local label = ' ' .. (t.label or t.id or ('Tab' .. i)) .. ' '
    local start_col = col
    local hl = (i == tab_index) and 'MegaTogglerTabActive' or 'MegaTogglerTab'
    table.insert(pieces, label)
    col = col + #label
    table.insert(spans, { hl, 0, start_col, col })
  end
  local line = table.concat(pieces, '')
  return line, spans
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  vim.bo[state.buf].modifiable = true

  local lines = {}
  local hl_spans = {}

  -- Tabline (line 1)
  local tabline, tab_spans = build_tabline(state.current_tab)
  table.insert(lines, tabline)
  for _, s in ipairs(tab_spans) do table.insert(hl_spans, s) end

  -- Blank separator
  table.insert(lines, '')

  -- Items (start at visual buffer line 3)
  local tab = current_tab_conf()
  local icons_default = get_icons()
  for _, item in ipairs(tab.items or {}) do
    local checked = item_effective_state(tab, item)
    local icons = get_icons(item)
    local icon = checked and (icons.checked or icons_default.checked) or (icons.unchecked or icons_default.unchecked)
    local label = item.label or item.id
    local desc = item.desc and (' — ' .. item.desc) or ''
    local line = string.format('%s %s%s', icon, label, desc)
    table.insert(lines, line)

    local lnum = #lines - 1 -- 0-based for highlights
    -- Highlight icon+label differently depending on state
    local ico_end = #icon
    local label_end = ico_end + 1 + #label
    table.insert(hl_spans, { checked and 'MegaTogglerItemOn' or 'MegaTogglerItemOff', lnum, 0, label_end })
    if desc ~= '' then
      table.insert(hl_spans, { 'MegaTogglerDesc', lnum, label_end, label_end + #desc })
    end
  end

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
  apply_highlights(state.buf, hl_spans)
  vim.bo[state.buf].modifiable = false
end

-- Create centered floating window, wire buffer-local keymaps, and render
-- open_win: create centered floating window, set keymaps, and render content
-- Notes:
-- - Uses minimal style and a configurable border/title.
-- - Sets window-local highlights for border/title.
-- - Keymaps are buffer-local to avoid global side effects.
local function open_win()
  ensure_highlight_defaults()
  -- Remember the window/buffer that was active before opening the dashboard.
  state.prev_win = vim.api.nvim_get_current_win()
  state.prev_buf = vim.api.nvim_get_current_buf()
  -- Persist all current states immediately upon opening, before user actions.
  -- At this point, state.win is not created yet, so get() runs in the target window.
  persist_all_current_states()
  local ui = state.config.ui or {}
  local width = ui.width or 60
  local height = ui.height or 18
  local cols = vim.o.columns
  local rows = vim.o.lines - vim.o.cmdheight

  local win_opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((rows - height) / 2),
    col = math.floor((cols - width) / 2),
    style = 'minimal',
    border = ui.border or 'rounded',
    title = ui.title or 'MegaToggler',
    title_pos = 'center',
    zindex = ui.zindex or 200,
  }

  state.buf = vim.api.nvim_create_buf(false, true)
  set_buf_opts(state.buf)

  state.win = vim.api.nvim_open_win(state.buf, true, win_opts)
  -- Use colon syntax for winhl mappings
  vim.wo[state.win].winhl = 'FloatBorder:MegaTogglerBorder,FloatTitle:MegaTogglerTitle'
  vim.wo[state.win].cursorline = true
  enforce_toggler_winopts(state.win)

  -- Keymaps
  local opts = { nowait = true, noremap = true, silent = true, buffer = state.buf }
  vim.keymap.set('n', 'q', M.close, opts)
  vim.keymap.set('n', '<Esc>', M.close, opts)

  -- Toggle current line's item
  vim.keymap.set('n', '<CR>', function() M._toggle_at_cursor() end, opts)
  vim.keymap.set('n', '<Space>', function() M._toggle_at_cursor() end, opts)

  -- Tabs navigation
  vim.keymap.set('n', 'h', function() M.prev_tab() end, opts)
  vim.keymap.set('n', 'l', function() M.next_tab() end, opts)
  vim.keymap.set('n', '<Left>', function() M.prev_tab() end, opts)
  vim.keymap.set('n', '<Right>', function() M.next_tab() end, opts)
  vim.keymap.set('n', '<Tab>', function() M.next_tab() end, opts)
  vim.keymap.set('n', '<S-Tab>', function() M.prev_tab() end, opts)

  -- Render
  render()

  -- Place cursor on first item line if exists
  vim.api.nvim_win_set_cursor(state.win, { 3, 0 })
end

-- close: tear down the floating window and scratch buffer
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
  state.prev_win = nil
  state.prev_buf = nil
end

-- open: if already open closes, otherwise loads state and opens window
function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
    return
  end
  open_win()
end

-- toggle: convenience wrapper to open/close the dashboard
function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open()
  end
end

-- refresh: re-render the current tab
function M.refresh()
  render()
end

-- next_tab: cycle to the next tab (wrap)
function M.next_tab()
  if not state.config or #(state.config.tabs) == 0 then return end
  state.current_tab = (state.current_tab % #state.config.tabs) + 1
  render()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { 3, 0 })
  end
end

-- prev_tab: cycle to the previous tab (wrap)
function M.prev_tab()
  if not state.config or #(state.config.tabs) == 0 then return end
  state.current_tab = (state.current_tab - 2) % #state.config.tabs + 1
  render()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { 3, 0 })
  end
end

-- _toggle_at_cursor: compute item index from cursor (line 3 → index 1)
function M._toggle_at_cursor()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then return end
  local pos = vim.api.nvim_win_get_cursor(state.win)
  local lnum = pos[1] -- 1-based
  local idx = lnum - 2 -- items start at buffer line 3
  M._toggle_by_index(idx, lnum)
end

-- _toggle_by_index: toggle item by index; run callback; persist; re-render
function M._toggle_by_index(idx, keep_cursor_lnum)
  if not idx or idx < 1 then return end
  local tab = current_tab_conf()
  local item = tab and tab.items and tab.items[idx]
  if not item or item.disabled then return end
  local checked = item_effective_state(tab, item)
  local new_checked = not checked
  -- Switch to the previously active window to apply buffer/window-local opts
  local cur_win = vim.api.nvim_get_current_win()
  local target_win = nil
  if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) then
    target_win = state.prev_win
  else
    -- fallback: find a non-floating window different from the dashboard
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if w ~= state.win then
        local cfg = vim.api.nvim_win_get_config(w)
        if not cfg or cfg.relative == '' then
          target_win = w
          break
        end
      end
    end
  end
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    pcall(vim.api.nvim_set_current_win, target_win)
  end
  local ok, err = pcall(item.on_toggle, new_checked)
  -- Switch back to the dashboard and re-assert its window-local options
  if cur_win and vim.api.nvim_win_is_valid(cur_win) then
    pcall(vim.api.nvim_set_current_win, cur_win)
    enforce_toggler_winopts(cur_win)
  end
  if not ok then
    vim.notify(string.format('MegaToggler: error toggling %s: %s', item.label or item.id, err), vim.log.levels.ERROR)
    return
  end
  if item.persist ~= false then
    set_persist(state.config.persist_namespace or 'default', tab.id, item.id, new_checked)
  end
  render()
  if keep_cursor_lnum and state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { keep_cursor_lnum, 0 })
  end
end

-- Setup and config
function M.setup(opts)
  local cfg = merge(defaults, opts or {})
  assert(type(cfg.tabs) == 'table' and #cfg.tabs > 0, 'mega_toggler.setup: opts.tabs required')
  -- normalize tabs/items and validate IDs; require get() and on_toggle()
  local seen_tab = {}
  for ti, tab in ipairs(cfg.tabs) do
    assert(tab.id and type(tab.id) == 'string', 'Tab at index ' .. ti .. ' must have string id')
    assert(not seen_tab[tab.id], 'Duplicate tab id: ' .. tab.id)
    seen_tab[tab.id] = true
    tab.items = tab.items or {}
    local filtered = {}
    local seen_item = {}
    for _, item in ipairs(tab.items) do
      if not (item.id and type(item.id) == 'string') then
        vim.notify('MegaToggler: ignoring item without string id in tab ' .. tab.id, vim.log.levels.WARN)
      elseif seen_item[item.id] then
        vim.notify('MegaToggler: duplicate item id in tab ' .. tab.id .. ': ' .. item.id .. ' (ignoring)', vim.log.levels.WARN)
      elseif type(item.get) ~= 'function' then
        vim.notify('MegaToggler: item ' .. item.id .. ' missing get(); ignoring', vim.log.levels.WARN)
      elseif type(item.on_toggle) ~= 'function' then
        vim.notify('MegaToggler: item ' .. item.id .. ' missing on_toggle(); ignoring', vim.log.levels.WARN)
      else
        seen_item[item.id] = true
        table.insert(filtered, item)
      end
    end
    tab.items = filtered
  end

  state.config = cfg
  state.current_tab = 1

  -- Load persisted state and apply it to Neovim options by invoking callbacks
  load_state()
  apply_persisted_states()

  -- Create command
  vim.api.nvim_create_user_command('MegaToggler', function()
    M.toggle()
  end, { desc = 'Open/close MegaToggler dashboard' })

  return M
end

-- persist: public API to snapshot and save current states for all items
function M.persist()
  persist_all_current_states()
end

-- add_item: append a validated item to a given tab by id
-- Respects per-item persist flag: if a persisted value exists, applies it.
function M.add_item(tab_id, item)
  assert(type(tab_id) == 'string' and #tab_id > 0, 'add_item: tab_id must be a non-empty string')
  assert(type(item) == 'table', 'add_item: item must be a table')
  local ti, tab = find_tab(tab_id)
  assert(tab, 'add_item: tab id not found: ' .. tostring(tab_id))

  -- Validate item
  if not (item.id and type(item.id) == 'string') then
    vim.notify('MegaToggler: ignoring item without string id in tab ' .. tab.id, vim.log.levels.WARN)
    return false
  end
  for _, it in ipairs(tab.items or {}) do
    if it.id == item.id then
      vim.notify('MegaToggler: duplicate item id in tab ' .. tab.id .. ': ' .. item.id .. ' (ignoring)', vim.log.levels.WARN)
      return false
    end
  end
  if type(item.get) ~= 'function' then
    vim.notify('MegaToggler: item ' .. item.id .. ' missing get(); ignoring', vim.log.levels.WARN)
    return false
  end
  if type(item.on_toggle) ~= 'function' then
    vim.notify('MegaToggler: item ' .. item.id .. ' missing on_toggle(); ignoring', vim.log.levels.WARN)
    return false
  end

  tab.items = tab.items or {}
  table.insert(tab.items, item)

  -- If persistence enabled and item allows it, apply persisted value if present
  if state.config and state.config.persist ~= false and item.persist ~= false then
    local ns = state.config.persist_namespace or 'default'
    local pv = get_persist(ns, tab.id, item.id)
    if pv ~= nil then
      local cur = item_effective_state(tab, item)
      if pv ~= cur then
        local ok_cb, err = with_target_window(function()
          return item.on_toggle(pv)
        end)
        if not ok_cb then
          vim.notify(string.format('MegaToggler: error applying persisted %s: %s', item.label or item.id, err), vim.log.levels.ERROR)
        end
      end
    end
  end

  -- Rerender if dashboard is open and we're on this tab
  if state.win and vim.api.nvim_win_is_valid(state.win) and state.current_tab == ti then
    render()
  end

  return true
end

-- remove_item: remove an item by id from a given tab; returns true if removed
function M.remove_item(tab_id, item_id)
  assert(type(tab_id) == 'string' and #tab_id > 0, 'remove_item: tab_id must be a non-empty string')
  assert(type(item_id) == 'string' and #item_id > 0, 'remove_item: item_id must be a non-empty string')
  local ti, tab = find_tab(tab_id)
  if not tab or not tab.items then return false end
  for idx, it in ipairs(tab.items) do
    if it.id == item_id then
      table.remove(tab.items, idx)
      if state.win and vim.api.nvim_win_is_valid(state.win) and state.current_tab == ti then
        render()
      end
      return true
    end
  end
  return false
end

-- add_tab: append a new tab with validated items; returns index of new tab
function M.add_tab(tab)
  assert(type(tab) == 'table', 'add_tab: tab must be a table')
  assert(tab.id and type(tab.id) == 'string', 'add_tab: tab.id (string) is required')
  local existing_index = select(1, find_tab(tab.id))
  assert(not existing_index, 'add_tab: duplicate tab id: ' .. tab.id)

  -- validate and filter items similar to setup
  tab.items = tab.items or {}
  local filtered, seen_item = {}, {}
  for _, item in ipairs(tab.items) do
    if not (item.id and type(item.id) == 'string') then
      vim.notify('MegaToggler: ignoring item without string id in tab ' .. tab.id, vim.log.levels.WARN)
    elseif seen_item[item.id] then
      vim.notify('MegaToggler: duplicate item id in tab ' .. tab.id .. ': ' .. item.id .. ' (ignoring)', vim.log.levels.WARN)
    elseif type(item.get) ~= 'function' then
      vim.notify('MegaToggler: item ' .. tostring(item.id) .. ' missing get(); ignoring', vim.log.levels.WARN)
    elseif type(item.on_toggle) ~= 'function' then
      vim.notify('MegaToggler: item ' .. tostring(item.id) .. ' missing on_toggle(); ignoring', vim.log.levels.WARN)
    else
      seen_item[item.id] = true
      table.insert(filtered, item)
    end
  end
  tab.items = filtered

  table.insert(state.config.tabs, tab)
  local new_index = #state.config.tabs

  -- Apply persisted values for items if allowed
  if state.config and state.config.persist ~= false then
    local ns = state.config.persist_namespace or 'default'
    for _, item in ipairs(tab.items) do
      if item.persist ~= false then
        local pv = get_persist(ns, tab.id, item.id)
        if pv ~= nil then
          local cur = item_effective_state(tab, item)
          if pv ~= cur then
            local ok_cb, err = with_target_window(function()
              return item.on_toggle(pv)
            end)
            if not ok_cb then
              vim.notify(string.format('MegaToggler: error applying persisted %s: %s', item.label or item.id, err), vim.log.levels.ERROR)
            end
          end
        end
      end
    end
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    render()
  end

  return new_index
end

return M
