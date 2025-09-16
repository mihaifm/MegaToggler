-- Test if overlay input border appears when configured

local function send(keys)
  local term = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(term, 'x', false)
end

local function open_overlay_and_get_win()
  -- Move cursor to first item (line 3) and trigger edit
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  require('megatoggler')._toggle_at_cursor()
  vim.wait(40)
  -- Find overlay window by filetype
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(w)
    if vim.bo[buf].filetype == 'megatoggler_input' then
      return w
    end
  end
  return nil
end

local function has_border(win)
  local cfg = vim.api.nvim_win_get_config(win)
  local b = cfg.border
  if type(b) == 'string' then return b ~= 'none' end
  if type(b) == 'table' then return #b > 0 end
  return false
end

-- Case 1: border present
do
  local mt = require('megatoggler')
  mt.setup({
    persist = false,
    ui = { value_input = 'overlay', border = 'single' },
    tabs = {
      { id = 'editor', items = {
        { id = 'tabstop', label = 'Tabstop', get = function() return vim.bo.tabstop end, on_set = function(v) vim.bo.tabstop = v end },
      } },
    },
  })

  mt.open()
  vim.wait(30)
  local ow = open_overlay_and_get_win()
  assert(ow ~= nil, 'Expected overlay window to open')
  assert(has_border(ow) == true, 'Expected overlay to have a border when ui.border is set')
  -- Dismiss overlay
  send('<Esc>')
  vim.wait(20)
  mt.close()
end

-- Case 2: border none
do
  local mt = require('megatoggler')
  mt.setup({
    persist = false,
    ui = { value_input = 'overlay', border = 'none' },
    tabs = {
      { id = 'editor', items = {
        { id = 'tabstop', label = 'Tabstop', get = function() return vim.bo.tabstop end, on_set = function(v) vim.bo.tabstop = v end },
      } },
    },
  })

  mt.open()
  vim.wait(30)
  local ow = open_overlay_and_get_win()
  assert(ow ~= nil, 'Expected overlay window to open (no border)')
  assert(has_border(ow) == false, 'Expected no border when ui.border = none')
  -- Dismiss overlay
  send('<Esc>')
  vim.wait(20)
  mt.close()
end

print('OK: integration test - overlay border on/off')

