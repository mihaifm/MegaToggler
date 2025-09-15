-- Unit tests for API methods: add_tab, add_item, remove_item
-- Run all tests with:
-- nvim --headless -u tests/minimal_init.lua --noplugin -i NONE -n -c "lua dofile('tests/run.lua')"

local mt = require('megatoggler')

mt.setup({
  persist = false,
  tabs = {
    { id = 'editor', items = {
      { id = 'number', label = 'Line Numbers', get = function() return vim.wo.number end, on_toggle = function(on) vim.wo.number = on end },
    } },
  },
})

-- add_item to existing tab returns true
do
  local ok = mt.add_item('editor', { id = 'rnu', label = 'Relative Numbers', get = function() return vim.wo.relativenumber end, on_toggle = function(on) vim.wo.relativenumber = on end })
  assert(ok == true, 'add_item should succeed for existing tab')
end

-- remove_item returns true when the item exists
do
  local ok = mt.remove_item('editor', 'rnu')
  assert(ok == true, 'remove_item should succeed for existing item')
  local ok2 = mt.remove_item('editor', 'does_not_exist')
  assert(ok2 == false, 'remove_item should return false for missing item')
end

-- add_tab with duplicate id errors
do
  local ok, _ = pcall(function()
    mt.add_tab({ id = 'editor', items = {} })
  end)
  assert(ok == false, 'add_tab should error for duplicate tab id')
end

-- add_tab with valid items appends and returns index
do
  local idx = mt.add_tab({ id = 'ui', label = 'UI', items = {
    { id = 'wrap', label = 'Wrap', get = function() return vim.wo.wrap end, on_toggle = function(on) vim.wo.wrap = on end },
  }})
  assert(type(idx) == 'number' and idx >= 1, 'add_tab should return a numeric index')
end

print('OK: unit api add_tab/add_item/remove_item')

