-- Single-instance toggle behavior via :MegaToggler command

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
          on_toggle = function(on) vim.wo.number = on end
        }
      }
    }
  }
})

-- Open via command
vim.api.nvim_command('MegaToggler')
vim.wait(20)
assert(vim.bo[0].filetype == 'megatoggler', 'Expected dashboard open after :MegaToggler')

-- Invoke command again to close
vim.api.nvim_command('MegaToggler')
vim.wait(20)
assert(vim.bo[0].filetype ~= 'megatoggler', 'Expected dashboard closed after second :MegaToggler')

print('OK: integration test - single-instance command toggle')

