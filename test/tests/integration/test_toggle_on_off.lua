-- Toggling an item on and off restores original state

local mt = require('megatoggler')

local tmp = vim.fn.tempname()

-- Prepare a simple config with persistence to a temp file
mt.setup({
  persist = true,
  persist_namespace = 'toggle_on_off',
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
        },
      }
    }
  }
})

-- Capture the editing window (target) and its initial state
local edit_win = vim.api.nvim_get_current_win()
local function get_number(win)
  return vim.wo[win].number
end
local initial = get_number(edit_win)

mt.open()
vim.wait(20)
vim.api.nvim_win_set_cursor(0, { 3, 0 })

-- Toggle ON/OFF cycle
mt._toggle_at_cursor()
vim.wait(20)
assert(get_number(edit_win) == (not initial), 'First toggle should invert the value in target window')

mt._toggle_at_cursor()
vim.wait(20)
assert(get_number(edit_win) == initial, 'Second toggle should restore the original value in target window')

-- Final persisted value should equal the initial state
local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(tmp), '\n'))
assert(ok and type(decoded) == 'table', 'Persistence JSON should parse')
assert(decoded.toggle_on_off and decoded.toggle_on_off.editor, 'Expected namespace and tab in JSON')
assert(decoded.toggle_on_off.editor.number == initial, 'Final persisted value should match initial state')

mt.close()
print('OK: integration test - toggle on/off')
