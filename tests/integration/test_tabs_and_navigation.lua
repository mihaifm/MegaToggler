-- Integration test: tab navigation affects rendered items
-- Run with the test runner.

local mt = require('megatoggler')

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

mt.open()
vim.wait(20)

local function buf_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

-- On first tab, items should include 'Line Numbers'
local lines = buf_lines()
local found_editor = false
for _, l in ipairs(lines) do
  if l:find('Line Numbers', 1, true) then found_editor = true break end
end
assert(found_editor, 'Expected Line Numbers on first tab')

-- Navigate to next tab and verify 'Spell Check' appears
mt.next_tab()
vim.wait(10)
lines = buf_lines()
local found_lang = false
for _, l in ipairs(lines) do
  if l:find('Spell Check', 1, true) then found_lang = true break end
end
assert(found_lang, 'Expected Spell Check on Language tab')

-- Navigate back
mt.prev_tab()
vim.wait(10)
lines = buf_lines()
found_editor = false
for _, l in ipairs(lines) do
  if l:find('Line Numbers', 1, true) then found_editor = true break end
end
assert(found_editor, 'Expected Line Numbers after going back')

mt.close()
print('OK: integration tabs and navigation')

