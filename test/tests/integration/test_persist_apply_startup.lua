-- Persisted values should apply at startup

local mt = require('megatoggler')

local tmp = vim.fn.tempname()
local ns = 'startup_apply'

-- Determine current state and write opposite to the persist file before setup
local initial = vim.wo.number
local persisted = not initial

local payload = vim.json.encode({
  [ns] = {
    editor = { number = persisted }
  }
})
vim.fn.writefile({ payload }, tmp)

mt.setup({
  persist = true,
  persist_namespace = ns,
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

-- After setup, the window option should match the persisted value
assert(vim.wo.number == persisted, 'setup() should apply persisted value that differs from get()')

print('OK: integration test - persistence application at startup')

