-- Unit test: per-item persist=false and custom persist_file

local mt = require('megatoggler')

local tmp = vim.fn.tempname()

mt.setup({
  persist = true,
  persist_namespace = 'unit_ns',
  persist_file = tmp,
  tabs = {
    { id = 't', items = {
      { id = 'keep', label = 'Keep', get = function() return true end, on_toggle = function() end },
      { id = 'nopersist', label = 'NoPersist', get = function() return true end, on_toggle = function() end, persist = false },
    } },
  },
})

-- Snapshot all states
mt.persist()

local json = table.concat(vim.fn.readfile(tmp), '\n')
local ok, decoded = pcall(vim.json.decode, json)
assert(ok and type(decoded) == 'table', 'JSON should parse')
assert(decoded.unit_ns and decoded.unit_ns.t, 'Namespace and tab should exist')
assert(decoded.unit_ns.t.keep ~= nil, 'Persisted value for keep should exist')
assert(decoded.unit_ns.t.nopersist == nil, 'Item with persist=false should not be saved')

print('OK: unit test - persist semantics')

