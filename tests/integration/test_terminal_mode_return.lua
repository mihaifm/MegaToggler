-- Integration test: ensure returning from toggling leaves dashboard in normal mode
-- Run with the test runner.

local mt = require('megatoggler')

-- Create a terminal buffer and enter terminal-insert mode
local function setup_terminal()
  vim.cmd('enew')
  vim.fn.termopen(vim.o.shell or 'sh')
  vim.cmd('startinsert')
end

mt.setup({
  persist = false,
  tabs = {
    { id = 'editor', items = {
      { id = 'number', label = 'Line Numbers', get = function() return vim.wo.number end, on_toggle = function(on) vim.wo.number = on end },
    } },
  },
})

setup_terminal()

-- Open dashboard (focus leaves terminal), toggle first item, ensure mode is normal
mt.open()
vim.wait(20)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
mt._toggle_at_cursor()
vim.wait(20)

local mode = vim.fn.mode()
assert(mode == 'n', 'Expected normal mode after toggling from terminal, got: ' .. tostring(mode))

mt.close()
print('OK: integration terminal mode return')

