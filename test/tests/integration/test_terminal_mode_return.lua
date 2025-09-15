-- Ensure returning from toggling leaves dashboard in normal mode

local mt = require('megatoggler')

mt.setup({
  persist = false,
  tabs = {
    {
      id = 'editor',
      items = {
        {
          id = 'number',
          label = 'Line Numbers',
          get = function() return vim.wo.number end,
          on_toggle = function(on)
            vim.wo.number = on
          end
        },
      }
    },
  },
})

-- Setup terminal
vim.cmd('enew')
vim.fn.jobstart(vim.o.shell, { term = true })
vim.cmd('startinsert')

-- Open dashboard (focus leaves terminal), toggle first item, ensure we are in normal mode
mt.open()
vim.wait(20)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
mt._toggle_at_cursor()
vim.wait(20)

local mode = vim.fn.mode()
assert(mode == 'n', 'Expected normal mode after toggling from terminal, got: ' .. tostring(mode))

mt.close()
print('OK: integration test - terminal mode return')

