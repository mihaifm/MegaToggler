-- Unit test: persist to configured file

local mt = require('megatoggler')

local tmp = vim.fn.tempname()
local cfg = {
  persist = true,
  persist_namespace = 'unit_spec',
  persist_file = tmp,
  tabs = {
    {
      id = 't',
      items = {
        { id = 'flag', label = 'Flag', get = function() return true end, on_toggle = function() end },
      }
    }
  }
}

mt.setup(cfg)
mt.persist()

local lines = vim.fn.readfile(tmp)
assert(#lines > 0, 'persist file should exist and be non-empty')

local ok, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
assert(ok and type(decoded) == 'table', 'persist file should contain valid JSON')
assert(decoded.unit_spec and decoded.unit_spec.t and decoded.unit_spec.t.flag ~= nil,
  'persisted structure should include namespace/tab/item')

print('OK: unit test - persist file')

