-- Integration test without Plenary: toggle + persist
-- Run with:
-- nvim --headless -u tests/minimal_init.lua -c "lua dofile('tests/integration/test_toggle_persist.lua')" -c qa

local mt = require('megatoggler')
local tmp = vim.fn.tempname()

mt.setup({
  persist = true,
  persist_namespace = 'no_plenary',
  persist_file = tmp,
  tabs = {
    { id = 'editor', items = {
      { id = 'number', label = 'Line Numbers', get = function() return vim.wo.number end, on_toggle = function(on) vim.wo.number = on end },
    } },
  },
})

mt.open()
vim.wait(20)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
mt._toggle_at_cursor()
vim.wait(10)

local json = table.concat(vim.fn.readfile(tmp), '\n')
local ok, decoded = pcall(vim.json.decode, json)
assert(ok, 'JSON should parse')
assert(decoded.no_plenary and decoded.no_plenary.editor and decoded.no_plenary.editor.number ~= nil, 'Expected persisted value at namespace/tab/item')

print('OK: integration toggle+persist')

