-- Target-window fallback when prev_win is invalid

local mt = require('megatoggler')

-- Create two normal windows and ensure one remains after invalidating prev_win
vim.cmd('enew')
local w1 = vim.api.nvim_get_current_win()
vim.cmd('vsplit')
local w2 = vim.api.nvim_get_current_win()

-- Make w1 current (prev_win should capture this on open)
vim.api.nvim_set_current_win(w1)
local initial_w2 = vim.wo[w2].number

mt.setup({
  persist = false,
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
vim.wait(30)

-- Invalidate prev_win by closing w1; w2 remains as only normal window
pcall(vim.api.nvim_win_close, w1, true)
vim.wait(20)

-- Toggle first item; it should apply to w2 via fallback selection
vim.api.nvim_win_set_cursor(0, { 3, 0 })
mt._toggle_at_cursor()
vim.wait(30)

assert(vim.wo[w2].number == (not initial_w2), 'Expected toggle to apply to fallback target window when prev_win is invalid')

-- Restore
mt._toggle_at_cursor()
vim.wait(20)
assert(vim.wo[w2].number == initial_w2, 'Expected second toggle to restore original value on fallback window')

mt.close()
print('OK: integration test - target-window fallback when prev_win invalid')

