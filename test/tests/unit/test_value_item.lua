-- Unit test: value item set and persist

local mt = require('megatoggler')

local tmp = vim.fn.tempname()

mt.setup({
  persist = true,
  persist_namespace = 'value_unit',
  persist_file = tmp,
  tabs = {
    { id = 'editor', items = {
      {
        id = 'tabstop', label = 'Tabstop',
        get = function() return vim.bo.tabstop end,
        on_set = function(v) vim.bo.tabstop = v end,
      },
    } },
  },
})

local initial = vim.bo.tabstop

-- Set to a new value
assert(mt.set_value('editor', 'tabstop', initial + 1) == true, 'set_value should return true')
assert(vim.bo.tabstop == initial + 1, 'buffer tabstop should be updated')

-- Persist file should contain the numeric value
local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(tmp), '\n'))
assert(ok and type(decoded) == 'table', 'persist JSON should parse')
assert(decoded.value_unit and decoded.value_unit.editor, 'namespace and tab should exist')
assert(decoded.value_unit.editor.tabstop == initial + 1, 'persisted value should equal set value')

-- Restore original value
mt.set_value('editor', 'tabstop', initial)
assert(vim.bo.tabstop == initial, 'buffer tabstop should be restored')

print('OK: unit test - value item set and persist')

