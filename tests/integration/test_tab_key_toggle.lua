-- Integration test: navigate to second tab with <Tab> and toggle item via <CR>
-- Run with the test runner.

local mt = require('megatoggler')

local function t(keys)
  local term = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(term, 'x', false)
end

mt.setup({
  persist = false,
  tabs = {
    { id = 'editor', label = 'Editor', items = {
      { id = 'number', label = 'Line Numbers', get = function() return vim.wo.number end, on_toggle = function(on) vim.wo.number = on end },
    } },
    { id = 'lang', label = 'Language', items = {
      { id = 'spell', label = 'Spell Check', get = function() return vim.wo.spell end, on_toggle = function(on) vim.wo.spell = on end },
    } },
  },
})

-- Capture editing window and initial state for verification
local edit_win = vim.api.nvim_get_current_win()
local initial_spell = vim.wo[edit_win].spell

mt.open()
vim.wait(30)

-- Move to next tab using the mapped <Tab> key
t('<Tab>')
vim.wait(50)

-- Verify the Language tab content is rendered before toggling
local function buf_has(text)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, l in ipairs(lines) do
    if l:find(text, 1, true) then return true end
  end
  return false
end
assert(buf_has('Spell Check'), 'Expected to be on Language tab after <Tab>')

-- Toggle the first item on the Language tab using <CR>
t('<CR>')
vim.wait(50)

assert(vim.wo[edit_win].spell == (not initial_spell), 'Expected spell option toggled in target window')

-- Toggle back to restore original state
t('<CR>')
vim.wait(20)
assert(vim.wo[edit_win].spell == initial_spell, 'Expected spell option restored in target window')

mt.close()
print('OK: integration tab key navigation and toggle')
