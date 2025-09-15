-- Persistance test

local mt = require('megatoggler')
local tmp = vim.fn.tempname()

mt.setup({
  persist = true,
  persist_namespace = 'test_persistance',
  persist_file = tmp,
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

mt.open()
vim.wait(20)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
mt._toggle_at_cursor()
vim.wait(10)

local json = table.concat(vim.fn.readfile(tmp), '\n')
local ok, decoded = pcall(vim.json.decode, json)
assert(ok, 'JSON should parse')
assert(decoded.test_persistance and decoded.test_persistance.editor and decoded.test_persistance.editor.number ~= nil,
  'Expected persisted value at namespace/tab/item')

print('OK: integration test - toggle and persist')

