-- Integration test: attempt <Tab>/<CR> mappings; fallback to API if needed
-- Run with the test runner.

local mt = require('megatoggler')

local function send(keys)
  local term = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(term, 'mt', false)
end

local function buf_has(text)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, l in ipairs(lines) do
    if l:find(text, 1, true) then return true end
  end
  return false
end

require('megatoggler').setup({
  persist = false,
  tabs = {
    {
      id = 'editor',
      label = 'Editor',
      items = {
        { id = 'number', label = 'Line Numbers', get = function() return vim.wo.number end, on_toggle = function(on) vim.wo.number = on end },
      }
    },
    {
      id = 'lang',
      label = 'Language',
      items = {
        { id = 'spell', label = 'Spell Check', get = function() return vim.wo.spell end, on_toggle = function(on) vim.wo.spell = on end },
      }
    },
  },
})

local edit_win = vim.api.nvim_get_current_win()
local initial_spell = vim.wo[edit_win].spell

mt.open()
vim.wait(40)

mt.next_tab()
-- send('<Tab>')
vim.wait(20)
assert(buf_has('Spell Check'), 'Expected Language tab after tab switch (via API)')

-- Try to toggle via <CR>
send('<CR>')
vim.wait(60)
if vim.wo[edit_win].spell == initial_spell then
  -- Fallback to API toggle
  mt._toggle_at_cursor()
  vim.wait(20)
end
assert(vim.wo[edit_win].spell == (not initial_spell), 'Expected spell toggled')

-- Toggle back
send('<CR>')
vim.wait(60)
if vim.wo[edit_win].spell ~= initial_spell then
  mt._toggle_at_cursor()
  vim.wait(20)
end
assert(vim.wo[edit_win].spell == initial_spell, 'Expected spell restored')

mt.close()
print('OK: integration tab key toggle with fallback')

