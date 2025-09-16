-- Integration: render of value item and live update after set_value

local mt = require('megatoggler')

mt.setup({
  persist = false,
  ui = { icons = { checked = '[x]', unchecked = '[ ]' } },
  tabs = {
    { id = 'editor', label = 'Editor', items = {
      { id = 'tabstop', label = 'Tabstop', get = function() return vim.bo.tabstop end, on_set = function(v) vim.bo.tabstop = v end },
    } },
  },
})

local function item_line()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return lines[3] or ''
end

local initial = vim.bo.tabstop

mt.open()
vim.wait(30)

-- Verify initial render contains "Tabstop: <value>"
local line = item_line()
assert(line:find('Tabstop: ' .. tostring(initial), 1, true), 'Expected value line to show current tabstop')

-- Change value programmatically and check UI updates
mt.set_value('editor', 'tabstop', initial + 1)
vim.wait(20)
local line2 = item_line()
assert(line2:find('Tabstop: ' .. tostring(initial + 1), 1, true), 'Expected value line to update after set_value')

-- Restore
mt.set_value('editor', 'tabstop', initial)

mt.close()
print('OK: integration test - value item render and update')

