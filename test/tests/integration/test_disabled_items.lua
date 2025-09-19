-- Disabled items: should render but ignore interaction

local mt = require('megatoggler')

mt.setup({
  persist = false,
  tabs = {
    {
      id = 'editor',
      items = {
        {
          id = 'disabled_number',
          label = 'Disabled Number',
          disabled = true,
          get = function() return vim.wo.number end,
          on_toggle = function(on) vim.wo.number = on end
        }
      }
    }
  }
})

local before = vim.wo.number

mt.open()
vim.wait(20)

-- Cursor on first item and attempt to toggle; should have no effect
vim.api.nvim_win_set_cursor(0, { 3, 0 })
mt._toggle_at_cursor()
vim.wait(20)

assert(vim.wo.number == before, 'Disabled item should not change target window state on toggle')

mt.close()
print('OK: integration test - disabled items ignore interaction')

