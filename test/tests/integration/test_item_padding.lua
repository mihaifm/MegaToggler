-- Integration: item padding (global and per-item)

local mt = require('megatoggler')

mt.setup({
  persist = false,
  ui = { value_input = 'overlay', padding = '  ', icons = { checked = '[x]', unchecked = '[ ]' } },
  tabs = {
    { id = 'editor', items = {
      { id = 'a', label = 'A', get = function() return true end, on_toggle = function() end },
      { id = 'b', label = 'B', padding = 2, get = function() return true end, on_toggle = function() end },
      { id = 'c', label = 'C', padding = '      ', get = function() return true end, on_toggle = function() end },
    } },
  },
})

mt.open()
vim.wait(30)

local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

-- First item should have global padding of two spaces
do
  local l = lines[3] or ''
  assert(l:sub(1, 2) == '  ', 'Expected two-space padding for first item')
end

-- Second item padding = 2 means 2 x global ('  ') = 4 spaces
do
  local l = lines[4] or ''
  assert(l:sub(1, 4) == '    ', 'Expected four-space padding for second item')
end

-- Third item has explicit 6 spaces
do
  local l = lines[5] or ''
  assert(l:sub(1, 6) == '      ', 'Expected six-space padding for third item')
end

mt.close()
print('OK: integration test - item padding')

