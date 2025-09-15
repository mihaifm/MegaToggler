-- Unit test: add/remove item return values and basic behavior

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

-- Add a new valid item
local ok_add = mt.add_item('editor', {
    id = 'rnu',
    label = 'Relative Numbers',
    get = function() return vim.wo.relativenumber end,
    on_toggle = function(on) vim.wo.relativenumber = on end })
assert(ok_add == true, 'add_item should return true')

-- Removing an existing item should return true
local ok_rm = mt.remove_item('editor', 'rnu')
assert(ok_rm == true, 'remove_item should return true when item exists')

print('OK: unit test - add/remove item')
