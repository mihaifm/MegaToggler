-- Test syncing with external changes
-- Scenario:
-- 1) Open MegaToggler
-- 2) Switch to second tab
-- 3) Toggle first item there
-- 4) Close MegaToggler
-- 5) Flip the same item externally via :setlocal command
-- 6) Reopen MegaToggler and assert the UI reflects the external value

local mt = require('megatoggler')

-- Helper: first non-empty item line (line 3 visually)
local function item_line()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return lines[3] or ''
end

-- Prepare a simple config with two tabs and ASCII icons for reliable text checks
mt.setup({
  persist = false,
  ui = { icons = { checked = '[x]', unchecked = '[ ]' }, padding = '' },
  tabs = {
    { id = 'editor', label = 'Editor', items = {
      { id = 'number', label = 'Line Numbers', get = function() return vim.wo.number end, on_toggle = function(on) vim.wo.number = on end },
    } },
    { id = 'lang', label = 'Language', items = {
      { id = 'spell', label = 'Spell Check', get = function() return vim.wo.spell end, on_toggle = function(on) vim.wo.spell = on end },
    } },
  },
})

-- Track the real editing window and its option
local edit_win = vim.api.nvim_get_current_win()
local function get_spell()
  return vim.wo[edit_win].spell
end

local initial = get_spell()

-- 1) Open MegaToggler
mt.open()
vim.wait(30)

-- 2) Switch to second tab (Language)
mt.next_tab()
vim.wait(20)

-- 3) Toggle first item via cursor + _toggle_at_cursor
vim.api.nvim_win_set_cursor(0, { 3, 0 })
mt._toggle_at_cursor()
vim.wait(30)
local after_toggle = get_spell()
assert(after_toggle == (not initial), 'Expected spell toggled by MegaToggler')

-- Verify that UI reflects toggled state
local l = item_line()
local expected_icon = after_toggle and '[x]' or '[ ]'
assert(l:sub(1, #expected_icon) == expected_icon, 'UI should show expected icon after toggle')

-- 4) Close MegaToggler
mt.close()
vim.wait(20)

-- 5) Flip item externally via :setlocal
vim.cmd('setlocal spell!')
vim.wait(10)
local external = get_spell()
assert(external == (not after_toggle), 'External change should invert the value')

-- 6) Reopen MegaToggler - it should sync to current value
mt.open()
vim.wait(30)
local l2 = item_line()
local expected_icon2 = external and '[x]' or '[ ]'
assert(l2:sub(1, #expected_icon2) == expected_icon2, 'UI should sync with external option value on reopen')

mt.close()
print('OK: integration test - sync with external change')
