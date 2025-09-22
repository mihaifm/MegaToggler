-- MegaToggler: Toggle Neovim settings

local M = {}

-- Dedicated namespace for extmark-based highlights
local NS = vim.api.nvim_create_namespace('MegaToggler')

-- Defaults and config baseline
local defaults = {
  tabs = {},
  ui = {
    width = 60,
    height = 18,
    border = 'rounded',
    title = ' MegaToggler ',
    zindex = 200,
    value_input = 'overlay', -- 'overlay' | 'nui'
    padding = '  ',
    icons = {
      checked = '',
      unchecked = '',
    },
  },
  persist = true,
  persist_namespace = 'default',
  persist_file = vim.fn.stdpath('state') .. '/megatoggler/state.json',
}

-- Internal ephemeral state for the dashboard instance
local state = {
  config = nil,
  current_tab = 1,
  buf = nil,
  win = nil,
  prev_win = nil, -- window id active before opening dashboard
  prev_buf = nil, -- buffer id active before opening dashboard
  persisted = {},
  render_line_meta = nil, -- per-render metadata for editing items
  overlay_win = nil,
  overlay_buf = nil,
}

-- Persistence helpers
local function persist_file()
  local cfg = state.config or defaults
  local custom = cfg and cfg.persist_file
  if type(custom) == 'string' and #custom > 0 then
    return vim.fn.expand(custom)
  end
  return defaults.persist_file
end

-- Read JSON state into memory; initialize empty if none
local function load_state()
  if not state.config or state.config.persist == false then
    state.persisted = {}
    return
  end

  local ok_stat = vim.uv.fs_stat(persist_file()) ~= nil
  if not ok_stat then
    state.persisted = {}
    return
  end

  local lines = vim.fn.readfile(persist_file())
  local content = table.concat(lines, '\n')

  local ok_decoded, decoded = pcall(vim.json.decode, content)
  if ok_decoded and type(decoded) == 'table' then
    state.persisted = decoded
  else
    state.persisted = {}
  end
end

-- Write the in-memory state to the JSON file
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

-- Returns saved boolean for a given namespace/tab/item
local function get_persist(ns, tab_id, item_id)
  local root = state.persisted[ns]
  if not root then return nil end
  local t = root[tab_id]
  if not t then return nil end
  return t[item_id]
end

-- Item kinds: 'toggle' (boolean) or 'value' (text/numeric)
local function item_kind(item)
  if item.type == 'value' then return 'value' end
  if item.type == 'toggle' then return 'toggle' end
  if type(item.on_set) == 'function' then return 'value' end
  return 'toggle'
end

-- Make sure the dashboard window keeps the same window-local options
local function enforce_toggler_winopts(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  pcall(function() vim.wo[win].number = false end)
  pcall(function() vim.wo[win].relativenumber = false end)
  pcall(function() vim.wo[win].signcolumn = 'no' end)
  pcall(function() vim.wo[win].wrap = false end)
  pcall(function() vim.wo[win].spell = false end)
  -- Ensure we are not left in insert mode after interacting with certain buffers
  pcall(vim.cmd.stopinsert)
end

-- Temporarily switch to the previous editor window (or a best-effort
-- non-floating fallback) to run `fn`, then switch back to the dashboard
-- window and re-assert its window-local options. Returns pcall tuple.
local function with_target_window(fn)
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

-- Retrieve current value for an item, running in target window when possible
local function item_current_value(tab, item)
  local ok, cur
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    ok, cur = with_target_window(item.get)
  else
    ok, cur = pcall(item.get)
  end
  if not ok then
    vim.notify(string.format('MegaToggler: get() failed for %s: %s', item.label or item.id, cur), vim.log.levels.WARN)
    return nil
  end
  return cur
end

  -- For toggle items, normalize get() to boolean
local function item_effective_state(tab, item)
  local cur = item_current_value(tab, item)
  return not not cur
end

-- Snapshot current states for all items and write them to the persistence file
local function persist_all_current_states()
  if not state.config or state.config.persist == false then return end
  local ns = state.config.persist_namespace or 'default'
  state.persisted[ns] = state.persisted[ns] or {}
  local ns_tbl = state.persisted[ns]

  for _, tab in ipairs(state.config.tabs or {}) do
    ns_tbl[tab.id] = ns_tbl[tab.id] or {}
    local tab_tbl = ns_tbl[tab.id]
    for _, item in ipairs(tab.items or {}) do
      if not item.disabled and item.persist ~= false and type(item.get) == 'function' then
        local kind = item_kind(item)
        if kind == 'toggle' then
          local val = item_effective_state(tab, item)
          tab_tbl[item.id] = val and true or false
        else
          local v = item_current_value(tab, item)
          tab_tbl[item.id] = v
        end
      end
    end
  end
  save_state()
end

-- Saves a primitive value for a given namespace/tab/item and writes file
local function set_persist(ns, tab_id, item_id, val)
  state.persisted[ns] = state.persisted[ns] or {}
  state.persisted[ns][tab_id] = state.persisted[ns][tab_id] or {}
  state.persisted[ns][tab_id][item_id] = val
  save_state()
end

-- Apply persisted values only once at setup time.
-- If a persisted value exists and differs from get(), enforce it by calling
-- on_toggle/on_set. We do not write get() into persisted file at startup.
local function apply_persisted_states()
  if not state.config or state.config.persist == false then return end
  local ns = state.config.persist_namespace or 'default'
  for _, tab in ipairs(state.config.tabs or {}) do
    for _, item in ipairs(tab.items or {}) do
      if not item.disabled and item.persist ~= false and type(item.get) == 'function' then
        local pv = get_persist(ns, tab.id, item.id)
        if pv ~= nil then
          local cur = item_current_value(tab, item)
          if pv ~= cur then
            local kind = item_kind(item)
            if kind == 'toggle' and type(item.on_toggle) == 'function' then
              local ok_cb, err = pcall(item.on_toggle, pv)
              if not ok_cb then
                vim.notify(string.format('MegaToggler: error applying persisted %s: %s', item.label or item.id, err), vim.log.levels.ERROR)
              end
            elseif kind == 'value' and type(item.on_set) == 'function' then
              local ok_cb, err = pcall(item.on_set, pv)
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
  local base = (cfg.ui and cfg.ui.icons) or defaults.ui.icons
  local overrides = (item and item.icons) or {}
  return {
    checked = overrides.checked or base.checked,
    unchecked = overrides.unchecked or base.unchecked,
  }
end

-- Compute left padding for an item. Accepts per-item override:
--   string: used as-is
--   number: repeat global padding that many times
local function get_item_padding(item)
  local ui = (state.config and state.config.ui) or {}
  local base = (type(ui.padding) == 'string') and ui.padding or '  '
  local p = item and item.padding
  if p == nil then return base end
  if type(p) == 'string' then return p end
  if type(p) == 'number' then
    if p <= 0 then return '' end
    local out = {}
    for _ = 1, p do out[#out + 1] = base end
    return table.concat(out)
  end
  return base
end

-- Current tab helper
local function current_tab_conf()
  return state.config.tabs[state.current_tab]
end

-- Find tab by id - returns (index, tab) or (nil, nil)
local function find_tab(tab_id)
  if not (state.config and state.config.tabs) then return nil, nil end
  for i, t in ipairs(state.config.tabs) do
    if t.id == tab_id then return i, t end
  end
  return nil, nil
end

-- Make buffer scratchy, hidden, and isolated from user files
local function set_buf_opts(buf)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'megatoggler'
end

-- Assign highlight groups over (line, col) ranges.
-- spans is a list of: { hl_group, lnum_0_based, start_col, end_col }
local function apply_highlights(buf, spans)
  for _, s in ipairs(spans or {}) do
    local hl, lnum, start_col, end_col = s[1], s[2], s[3], s[4]
    pcall(vim.api.nvim_buf_set_extmark, buf, NS, lnum, start_col, {
      end_row = lnum,
      end_col = end_col,
      hl_group = hl,
    })
  end
end

-- Define our highlight groups by linking to common defaults
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
  try('highlight default link MegaTogglerItemOff String')
  try('highlight default link MegaTogglerDesc Comment')
  try('highlight default link MegaTogglerValueLabel Identifier')
  try('highlight default link MegaTogglerValueText Normal')
  -- Ephemeral (non-persisted) variants
  try('highlight default link MegaTogglerItemEphemeral Comment')
  try('highlight default link MegaTogglerItemOnEphemeral Constant')
  try('highlight default link MegaTogglerItemOffEphemeral Constant')
  try('highlight default link MegaTogglerValueLabelEphemeral Constant')
  try('highlight default link MegaTogglerValueTextEphemeral Normal')
end

-- Produce the tabline string (line 1) and highlight spans
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

-- Main rendering function
local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  vim.bo[state.buf].modifiable = true

  local lines = {}
  local hl_spans = {}
  state.render_line_meta = {}

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
    local kind = item_kind(item)
    if kind == 'toggle' then
      local pad = get_item_padding(item)
      local padlen = #pad
      local checked = item_effective_state(tab, item)
      local icons = get_icons(item)
      local icon = checked and (icons.checked or icons_default.checked) or (icons.unchecked or icons_default.unchecked)
      local label = item.label or item.id
      local desc = item.desc and (' — ' .. item.desc) or ''
      local line = string.format('%s%s  %s%s', pad, icon, label, desc)
      table.insert(lines, line)

      local lnum = #lines - 1 -- 0-based for highlights
      local ico_start = padlen
      local ico_end = ico_start + #icon
      local label_end = ico_end + 2 + #label
      local hl_group = (checked and 'MegaTogglerItemOn' or 'MegaTogglerItemOff')
      if item.persist == false then
        hl_group = hl_group .. 'Ephemeral'
      end
      table.insert(hl_spans, { hl_group, lnum, ico_start, label_end })
      if desc ~= '' then
        table.insert(hl_spans, { 'MegaTogglerDesc', lnum, label_end, label_end + #desc })
      end
    else
      local pad = get_item_padding(item)
      local padlen = #pad
      local label = item.label or item.id
      local value = item_current_value(tab, item)
      local value_str = tostring(value)
      local line = string.format('%s   %s  %s', pad, label, value_str)
      table.insert(lines, line)
      local lnum = #lines - 1
      local label_start = padlen + 3
      local label_end = label_start + #label
      -- label
      local hl_label = 'MegaTogglerValueLabel'
      if item.persist == false then hl_label = hl_label .. 'Ephemeral' end
      table.insert(hl_spans, { hl_label, lnum, label_start, label_end })
      -- include colon and space then value
      local hl_value = 'MegaTogglerValueText'
      if item.persist == false then hl_value = hl_value .. 'Ephemeral' end
      table.insert(hl_spans, { hl_value, lnum, label_end + 2, #line })
      -- record meta for inline edit: 1-based item index increments with loop
      state.render_line_meta[#state.render_line_meta + 1] = {
        kind = 'value',
        lnum = lnum, -- 0-based buffer row
        value_start = label_end + 2, -- 0-based start col of value (accounts for padding)
        value_len = #value_str,
      }
      goto continue
    end
    -- record meta for non-value items to keep indices aligned
    state.render_line_meta[#state.render_line_meta + 1] = { kind = 'toggle' }
    ::continue::
  end

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
  apply_highlights(state.buf, hl_spans)
  vim.bo[state.buf].modifiable = false
end

-- Create centered floating window, wire buffer-local keymaps and render
local function open_win()
  ensure_highlight_defaults()
  -- remember the window/buffer that was active before opening the dashboard
  state.prev_win = vim.api.nvim_get_current_win()
  state.prev_buf = vim.api.nvim_get_current_buf()

  -- persist all current states immediately upon opening, before user actions;
  -- at this point, state.win is not created yet, so get() runs in the target window
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

  -- use colon syntax for winhl mappings
  vim.wo[state.win].winhl = 'FloatBorder:MegaTogglerBorder,FloatTitle:MegaTogglerTitle'
  vim.wo[state.win].cursorline = true
  enforce_toggler_winopts(state.win)

  -- keymaps
  local opts = { nowait = true, noremap = true, silent = true, buffer = state.buf }
  vim.keymap.set('n', 'q', M.close, opts)
  vim.keymap.set('n', '<Esc>', M.close, opts)

  -- Toggle current line's item
  vim.keymap.set('n', '<CR>', function() M._toggle_at_cursor() end, opts)
  vim.keymap.set('n', '<Space>', function() M._toggle_at_cursor() end, opts)

  -- tabs navigation
  vim.keymap.set('n', 'h', function() M.prev_tab() end, opts)
  vim.keymap.set('n', 'l', function() M.next_tab() end, opts)
  vim.keymap.set('n', '<Left>', function() M.prev_tab() end, opts)
  vim.keymap.set('n', '<Right>', function() M.next_tab() end, opts)
  vim.keymap.set('n', '<Tab>', function() M.next_tab() end, opts)
  vim.keymap.set('n', '<S-Tab>', function() M.prev_tab() end, opts)

  -- render
  render()

  -- place cursor on first item line if exists
  vim.api.nvim_win_set_cursor(state.win, { 3, 0 })
end

--------------
-- Module API

-- Tear down the floating window and scratch buffer
function M.close()
  if state.overlay_win and vim.api.nvim_win_is_valid(state.overlay_win) then
    pcall(vim.api.nvim_win_close, state.overlay_win, true)
  end
  if state.overlay_buf and vim.api.nvim_buf_is_valid(state.overlay_buf) then
    pcall(vim.api.nvim_buf_delete, state.overlay_buf, { force = true })
  end
  state.overlay_win = nil
  state.overlay_buf = nil
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

-- Open: if already open closes, otherwise loads state and opens window
function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
    return
  end
  open_win()
end

-- Toggle: convenience wrapper to open/close the dashboard
function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open()
  end
end

-- Cycle to the next tab (wrap)
function M.next_tab()
  if not state.config or #(state.config.tabs) == 0 then return end
  state.current_tab = (state.current_tab % #state.config.tabs) + 1
  render()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { 3, 0 })
  end
end

-- Cycle to the previous tab (wrap)
function M.prev_tab()
  if not state.config or #(state.config.tabs) == 0 then return end
  state.current_tab = (state.current_tab - 2) % #state.config.tabs + 1
  render()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { 3, 0 })
  end
end

-- Compute item index from cursor (line 3 → index 1)
function M._toggle_at_cursor()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then return end
  local pos = vim.api.nvim_win_get_cursor(state.win)
  local lnum = pos[1] -- 1-based
  local idx = lnum - 2 -- items start at buffer line 3
  local tab = current_tab_conf()
  local item = tab and tab.items and tab.items[idx]
  if not item then return end
  if item_kind(item) == 'value' then
    M._edit_value_by_index(idx, lnum)
  else
    M._toggle_by_index(idx, lnum)
  end
end

-- Toggle item by index; run callback; persist; re-render
function M._toggle_by_index(idx, keep_cursor_lnum)
  if not idx or idx < 1 then return end
  local tab = current_tab_conf()
  local item = tab and tab.items and tab.items[idx]
  if not item or item.disabled then return end
  if item_kind(item) ~= 'toggle' then return end

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

-- Edit a value item by index using vim.ui.input; applies coerce/validate if provided
function M._edit_value_by_index(idx, keep_cursor_lnum)
  if not idx or idx < 1 then return end
  local tab = current_tab_conf()
  local item = tab and tab.items and tab.items[idx]
  if not item or item.disabled then return end
  if item_kind(item) ~= 'value' then return end

  local cur_val = item_current_value(tab, item)
  local default_text = cur_val ~= nil and tostring(cur_val) or ''

  -- item layout metadata for positioning
  local meta = state.render_line_meta and state.render_line_meta[idx]
  if not meta or meta.kind ~= 'value' then return end

  local function apply_value(val)
    local cur_win = vim.api.nvim_get_current_win()
    local target_win = nil
    if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) then
      target_win = state.prev_win
    else
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if w ~= state.win then
          local cfg = vim.api.nvim_win_get_config(w)
          if not cfg or cfg.relative == '' then target_win = w break end
        end
      end
    end

    if target_win and vim.api.nvim_win_is_valid(target_win) then
      pcall(vim.api.nvim_set_current_win, target_win)
    end

    local ok, err = pcall(item.on_set, val)
    if cur_win and vim.api.nvim_win_is_valid(cur_win) then
      pcall(vim.api.nvim_set_current_win, cur_win)
      enforce_toggler_winopts(cur_win)
    end
    if not ok then
      vim.notify(string.format('MegaToggler: error setting %s: %s', item.label or item.id, err), vim.log.levels.ERROR)
      return
    end

    if item.persist ~= false then
      set_persist(state.config.persist_namespace or 'default', tab.id, item.id, val)
    end

    render()

    if keep_cursor_lnum and state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_cursor(state.win, { keep_cursor_lnum, 0 })
    end
  end

  -- prefer configured provider
  local provider = (state.config.ui and state.config.ui.value_input) or 'overlay'

  -- attempt Nui-based input when requested
  if provider == 'nui' then
    local ok_nui, Input = pcall(require, 'nui.input')
    if not (ok_nui and Input) then
      vim.notify('MegaToggler: ui.value_input=nui requires nui.nvim', vim.log.levels.ERROR)
      return
    end

    local position = { row = meta.lnum - 1, col = meta.value_start - 1 }
    local width = ((vim.api.nvim_win_get_config(state.win) or {}).width) or (state.config.ui and state.config.ui.width) or 60
    local base_width = math.max(1, width - meta.value_start)
    local desired = base_width
    if type(item.edit_size) == 'number' and item.edit_size > 0 then
      desired = math.min(base_width, item.edit_size)
    end
    local size = { width = desired }
    local border_style = (state.config.ui and state.config.ui.border) or 'none'
    local opts = {
      relative = 'win',
      winid = state.win,
      position = position,
      size = size,
      border = { style = border_style },
      zindex = (state.config.ui and state.config.ui.zindex or 200) + 1,
    }
    local input
    local ok_construct, err_construct = pcall(function()
      input = Input(opts, {
        prompt = '',
        default_value = default_text,
        on_close = function()
          if state.win and vim.api.nvim_win_is_valid(state.win) then
            pcall(vim.api.nvim_set_current_win, state.win)
            enforce_toggler_winopts(state.win)
            if keep_cursor_lnum then pcall(vim.api.nvim_win_set_cursor, state.win, { keep_cursor_lnum, 0 }) end
          end
        end,
        on_submit = function(txt)
          local val
          if type(item.coerce) == 'function' then
            local okc, coerced = pcall(item.coerce, txt)
            val = okc and coerced or txt
          else
            local n = tonumber(txt)
            val = n ~= nil and n or txt
          end
          if type(item.validate) == 'function' then
            local okv, msg = item.validate(val)
            if not okv then
              vim.notify(string.format('MegaToggler: invalid value for %s%s', item.label or item.id, msg and (': ' .. tostring(msg)) or ''), vim.log.levels.WARN)
              return
            end
          end
          apply_value(val)
        end,
      })
    end)

    if not ok_construct or not input then
      vim.notify('MegaToggler: failed to construct nui input: ' .. tostring(err_construct), vim.log.levels.ERROR)
      return
    end
    local ok_mount, err_mount = pcall(function() input:mount() end)
    if not ok_mount then
      vim.notify('MegaToggler: failed to mount nui input: ' .. tostring(err_mount), vim.log.levels.ERROR)
      return
    end

    -- map <Esc> to unmount in both normal and insert modes
    pcall(function()
      input:map('n', '<Esc>', function()
        input:unmount()
      end, { noremap = true, nowait = true, silent = true })
      input:map('i', '<Esc>', function()
        input:unmount()
      end, { noremap = true, nowait = true, silent = true })
    end)
    return
  end

  -- use a 1-line overlay floating window positioned at the value text
  -- meta already computed above; close any existing overlay first
  if state.overlay_win and vim.api.nvim_win_is_valid(state.overlay_win) then
    pcall(vim.api.nvim_win_close, state.overlay_win, true)
  end
  if state.overlay_buf and vim.api.nvim_buf_is_valid(state.overlay_buf) then
    pcall(vim.api.nvim_buf_delete, state.overlay_buf, { force = true })
  end

  state.overlay_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.overlay_buf].buftype = 'nofile'
  vim.bo[state.overlay_buf].bufhidden = 'wipe'
  vim.bo[state.overlay_buf].swapfile = false
  vim.bo[state.overlay_buf].modifiable = true
  vim.bo[state.overlay_buf].filetype = 'megatoggler_input'
  vim.api.nvim_buf_set_lines(state.overlay_buf, 0, -1, false, { default_text })

  local win_cfg = vim.api.nvim_win_get_config(state.win)
  local parent_width = win_cfg and win_cfg.width or (state.config.ui and state.config.ui.width) or 60
  local available = math.max(1, parent_width - meta.value_start)
  local border_style = (state.config.ui and state.config.ui.border) or 'none'
  local has_border = border_style ~= 'none' and border_style ~= ''
  local content_width = math.max(1, available - (has_border and 2 or 0))
  if type(item.edit_size) == 'number' and item.edit_size > 0 then
    content_width = math.min(content_width, item.edit_size)
  end
  local wopts = {
    relative = 'win',
    win = state.win,
    row = math.max(0, meta.lnum - (has_border and 1 or 0)),
    col = math.max(0, meta.value_start - (has_border and 1 or 0)),
    width = content_width,
    height = 1,
    style = 'minimal',
    border = has_border and border_style or 'none',
    zindex = (state.config.ui and state.config.ui.zindex or 200) + 1,
    noautocmd = true,
  }
  state.overlay_win = vim.api.nvim_open_win(state.overlay_buf, true, wopts)
  enforce_toggler_winopts(state.overlay_win)
  vim.wo[state.overlay_win].winhl = ''
  vim.wo[state.overlay_win].cursorline = false

  local function finish(commit)
    local txt = default_text
    if commit then
      local lines = vim.api.nvim_buf_get_lines(state.overlay_buf, 0, 1, false)
      txt = lines[1] or ''
    end
    if state.overlay_win and vim.api.nvim_win_is_valid(state.overlay_win) then
      pcall(vim.api.nvim_win_close, state.overlay_win, true)
    end
    if state.overlay_buf and vim.api.nvim_buf_is_valid(state.overlay_buf) then
      pcall(vim.api.nvim_buf_delete, state.overlay_buf, { force = true })
    end
    state.overlay_win, state.overlay_buf = nil, nil
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      pcall(vim.api.nvim_set_current_win, state.win)
      enforce_toggler_winopts(state.win)
      if keep_cursor_lnum then pcall(vim.api.nvim_win_set_cursor, state.win, { keep_cursor_lnum, 0 }) end
    end

    if commit then
      local val
      if type(item.coerce) == 'function' then
        local okc, coerced = pcall(item.coerce, txt)
        val = okc and coerced or txt
      else
        local n = tonumber(txt)
        val = n ~= nil and n or txt
      end
      if type(item.validate) == 'function' then
        local okv, msg = item.validate(val)
        if not okv then
          vim.notify(string.format('MegaToggler: invalid value for %s%s', item.label or item.id, msg and (': ' .. tostring(msg)) or ''), vim.log.levels.WARN)
          return
        end
      end
      apply_value(val)
    end
  end

  local map_opts = { buffer = state.overlay_buf, nowait = true, noremap = true, silent = true }
  vim.keymap.set('n', '<CR>', function() finish(true) end, map_opts)
  vim.keymap.set('n', '<Esc>', function() finish(false) end, map_opts)
  vim.keymap.set('i', '<CR>', function() finish(true) end, map_opts)
  vim.keymap.set('i', '<Esc>', function() finish(false) end, map_opts)

  -- enter insert for natural typing UX
  -- place cursor at end for quick backspacing/overwrite
  local end_col = #default_text
  pcall(vim.api.nvim_win_set_cursor, state.overlay_win, { 1, end_col })
  vim.cmd.startinsert()
  -- ensure placement after mode switch (some UIs move cursor on startinsert)
  vim.defer_fn(function()
    if state.overlay_win and vim.api.nvim_win_is_valid(state.overlay_win) then
      pcall(vim.api.nvim_win_set_cursor, state.overlay_win, { 1, end_col })
    end
  end, 10)
end

-- Setup and config
function M.setup(opts)
  local cfg = vim.tbl_deep_extend('force', defaults, opts or {})
  assert(type(cfg.tabs) == 'table' and #cfg.tabs > 0, 'mega_toggler.setup: opts.tabs required')

  -- normalize tabs/items and validate IDs; require get() and on_toggle()/on_set
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
      elseif item_kind(item) == 'toggle' and type(item.on_toggle) ~= 'function' then
        vim.notify('MegaToggler: item ' .. item.id .. ' missing on_toggle(); ignoring', vim.log.levels.WARN)
      elseif item_kind(item) == 'value' and type(item.on_set) ~= 'function' then
        vim.notify('MegaToggler: item ' .. item.id .. ' missing on_set(); ignoring', vim.log.levels.WARN)
      else
        seen_item[item.id] = true
        table.insert(filtered, item)
      end
    end
    tab.items = filtered
  end

  state.config = cfg
  state.current_tab = 1

  -- load persisted state and apply it to Neovim options by invoking callbacks
  load_state()
  apply_persisted_states()

  -- create command
  vim.api.nvim_create_user_command('MegaToggler', function()
    M.toggle()
  end, { desc = 'Open/close MegaToggler dashboard' })

  return M
end

-- Persist: public API to snapshot and save current states for all items
function M.persist()
  persist_all_current_states()
end

-- Programmatic API to set a value item without UI
function M.set_value(tab_id, item_id, value)
  assert(type(tab_id) == 'string' and #tab_id > 0, 'set_value: tab_id must be a non-empty string')
  assert(type(item_id) == 'string' and #item_id > 0, 'set_value: item_id must be a non-empty string')
  local ti, tab = find_tab(tab_id)
  assert(tab, 'set_value: tab id not found: ' .. tostring(tab_id))
  local item
  for _, it in ipairs(tab.items or {}) do
    if it.id == item_id then item = it break end
  end
  assert(item, 'set_value: item id not found in tab ' .. tab_id .. ': ' .. item_id)
  assert(item_kind(item) == 'value', 'set_value: item is not a value item')

  -- optional validation
  if type(item.validate) == 'function' then
    local okv, msg = item.validate(value)
    assert(okv, 'set_value: invalid value' .. (msg and (': ' .. tostring(msg)) or ''))
  end

  local ok_cb, err = with_target_window(function()
    return item.on_set(value)
  end)
  if not ok_cb then
    error('set_value error for ' .. (item.label or item.id) .. ': ' .. tostring(err))
  end
  if item.persist ~= false then
    set_persist(state.config.persist_namespace or 'default', tab.id, item.id, value)
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) and state.current_tab == ti then
    render()
  end
  return true
end

-- Append a validated item to a given tab by id
-- Respects per-item persist flag: if a persisted value exists, applies it.
function M.add_item(tab_id, item)
  assert(type(tab_id) == 'string' and #tab_id > 0, 'add_item: tab_id must be a non-empty string')
  assert(type(item) == 'table', 'add_item: item must be a table')
  local ti, tab = find_tab(tab_id)
  assert(tab, 'add_item: tab id not found: ' .. tostring(tab_id))

  -- validate item
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
  local kind = item_kind(item)
  if kind == 'toggle' then
    if type(item.on_toggle) ~= 'function' then
      vim.notify('MegaToggler: item ' .. item.id .. ' missing on_toggle(); ignoring', vim.log.levels.WARN)
      return false
    end
  else
    if type(item.on_set) ~= 'function' then
      vim.notify('MegaToggler: item ' .. item.id .. ' missing on_set(); ignoring', vim.log.levels.WARN)
      return false
    end
  end

  tab.items = tab.items or {}
  table.insert(tab.items, item)

  -- if persistence enabled and item allows it, apply persisted value if present
  if state.config and state.config.persist ~= false and item.persist ~= false then
    local ns = state.config.persist_namespace or 'default'
    local pv = get_persist(ns, tab.id, item.id)
    if pv ~= nil then
      local cur = item_current_value(tab, item)
      if pv ~= cur then
        local ok_cb, err = with_target_window(function()
          if item_kind(item) == 'toggle' then return item.on_toggle(pv) else return item.on_set(pv) end
        end)
        if not ok_cb then
          vim.notify(string.format('MegaToggler: error applying persisted %s: %s', item.label or item.id, err), vim.log.levels.ERROR)
        end
      end
    end
  end

  -- rerender if dashboard is open and we're on this tab
  if state.win and vim.api.nvim_win_is_valid(state.win) and state.current_tab == ti then
    render()
  end

  return true
end

-- Remove an item by id from a given tab; returns true if removed
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

-- Append a new tab with validated items; returns index of new tab
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
    elseif item_kind(item) == 'toggle' and type(item.on_toggle) ~= 'function' then
      vim.notify('MegaToggler: item ' .. tostring(item.id) .. ' missing on_toggle(); ignoring', vim.log.levels.WARN)
    elseif item_kind(item) == 'value' and type(item.on_set) ~= 'function' then
      vim.notify('MegaToggler: item ' .. tostring(item.id) .. ' missing on_set(); ignoring', vim.log.levels.WARN)
    else
      seen_item[item.id] = true
      table.insert(filtered, item)
    end
  end
  tab.items = filtered

  table.insert(state.config.tabs, tab)
  local new_index = #state.config.tabs

  -- apply persisted values for items if allowed
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
