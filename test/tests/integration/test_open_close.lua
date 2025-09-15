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
        },
      }
    },
  },
})

mt.open()
vim.wait(20)
assert(vim.bo[0].filetype == 'megatoggler', 'Expected mega_toggler filetype')
mt.close()
vim.wait(10)
assert(vim.bo[0].filetype ~= 'megatoggler', 'Expected dashboard to be closed')

print('OK: integration test - open/close')

