-- Integration: value item edit_size controls overlay width

local mt = require('megatoggler')

mt.setup({
  persist = false,
  ui = { value_input = 'overlay', border = 'none', padding = '' },
  tabs = {
    { id = 'editor', items = {
      { id = 'tabstop', label = 'Tabstop', get = function() return vim.bo.tabstop end, on_set = function(v) vim.bo.tabstop = v end, edit_size = 5 },
    } },
  },
})

mt.open()
vim.wait(30)

-- Trigger edit on first item
vim.api.nvim_win_set_cursor(0, {3, 0})
mt._toggle_at_cursor()
vim.wait(40)

-- Find overlay window and assert width equals edit_size (5)
local function find_overlay()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(w)
    if vim.bo[buf].filetype == 'megatoggler_input' then return w end
  end
end

local ow = find_overlay()
assert(ow ~= nil, 'Expected overlay input window')
local cfg = vim.api.nvim_win_get_config(ow)
assert(cfg.width == 5, 'Expected overlay content width 5, got ' .. tostring(cfg.width))

-- Dismiss edit
local term = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
vim.api.nvim_feedkeys(term, 'x', false)
vim.wait(10)

mt.close()
print('OK: integration test - edit_size controls overlay width')

