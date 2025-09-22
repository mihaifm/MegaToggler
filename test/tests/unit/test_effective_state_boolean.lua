-- Unit test: item_effective_state must coerce to boolean

-- This test ensures that when an item's get() returns a truthy non-boolean
-- value (e.g., 1), persisted boolean values are compared correctly without
-- spurious toggles.

local mt = require('megatoggler')

local tmp = vim.fn.tempname()
local ns = 'effective_state_bool'

-- Pre-seed persistence so that tab 'added' / item 'flag' is true
local payload = vim.json.encode({ [ns] = { added = { flag = true } } })
vim.fn.writefile({ payload }, tmp)

local toggle_calls = 0
local flag_value = 1 -- non-boolean truthy representation of "on"

-- Minimal setup with an initial empty tab to satisfy setup contract
mt.setup({
  persist = true,
  persist_namespace = ns,
  persist_file = tmp,
  tabs = { { id = 'init', items = {} } },
})

-- Add a tab after setup; add_tab uses item_effective_state for compare
mt.add_tab({
  id = 'added',
  items = {
    {
      id = 'flag',
      get = function() return flag_value end,
      on_toggle = function(on)
        toggle_calls = toggle_calls + 1
        flag_value = on and 1 or nil
      end,
    },
  },
})

-- Persisted true equals logical state (flag_value == 1),
-- so no toggle should have been called if boolean coercion is applied.
assert(toggle_calls == 0, 'item_effective_state must coerce to boolean to avoid spurious toggles')

print('OK: unit test - effective_state boolean coercion')
