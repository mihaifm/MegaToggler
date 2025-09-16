# MegaToggler

A Neovim plugin where you can toggle things on and off.

- Floating dashboard with tabs and pretty checkboxes
- Toggle editor features via configurable callbacks
- Also edit text/numeric values (e.g., Tabstop: 4)
- State persistence across sessions
- Configurable padding/indent per item to build tree-like layouts

## Install

Requirement: Neovim 0.11+

Sample lazy.nvim installation below.

MegaToggler does not come with any default items to be toggled. You will need to provide your own.

Item types:
- Toggle items (booleans):
  - `get()` returns true/false
  - `on_toggle(checked)` applies the boolean
- Value items (numbers/strings):
  - `get()` returns the current value (number or string)
  - `on_set(value)` applies the value
  - Optional: `coerce(input_string) -> value`, `validate(value) -> ok, msg`

Below is a sample configuration that can help you get started:

```lua
{
  "mihaifm/megatoggler",
  config = function()
    require("megatoggler").setup({
      tabs = {
        {
          id = "editor",
          label = "Editor",
          items = {
            {
              id = "number",
              label = "Line Numbers", -- what gets displayed in the dasboard
              get = function() return vim.wo.number end, -- mandatory function returning item state
              on_toggle = function(on) vim.wo.number = on end, -- called when ticking the checkbox
            },
            {
              id = "relativenumber",
              label = "Relative Numbers",
              persist = false, -- do not save the state of this item across sessions
              get = function() return vim.wo.relativenumber end,
              on_toggle = function(on) vim.wo.relativenumber = on end,
            },
          },
        },
        {
          id = "UI",
          label = "Interface",
          items = {
            {
              id = 'tabline',
              label = 'Tabline',
              get = function() return vim.o.showtabline == 2 end,
              on_toggle = function(on)
                if on then 
                  vim.o.showtabline = 2
                else
                  vim.o.showtabline = 0
                end
              end
            },
            {
              id = 'neotree',
              label = 'Neotree',
              get = function()
                -- check if Neotree is loaded in window
                for _, win in ipairs(vim.api.nvim_list_wins()) do
                  local buf = vim.api.nvim_win_get_buf(win)
                  if vim.bo[buf].filetype == 'neo-tree' then
                    return true
                  end
                end
                return false
              end,
              on_toggle = function()
                vim.cmd("Neotree toggle")
              end
            },
          },
        },
        {
          id = "lang",
          label = "Lang",
          items = {
            {
              id = 'render-markdown',
              label = 'Render Markdown',
              get = function() return require('render-markdown').get() end,
              on_toggle = function() require('render-markdown').toggle() end,
            },
          },
        },
        {
          id = "settings",
          label = "Settings",
          items = {
            {
              id = 'tabstop',
              label = 'Tabstop',
              get = function() return vim.bo.tabstop end,
              on_set = function(v) vim.bo.tabstop = v end,
              -- optional helpers for input UX
              coerce = function(s) return tonumber(s) or s end,
              validate = function(v)
                return type(v) == 'number' and v >= 1 and v <= 16, 'must be a number 1..16'
              end,
            },
          }
        },
      },
    })
  end,
}
```

## Configuration

Default configuration:

```lua
{
  ui = { 
    width = 60, 
    height = 18, 
    border = "rounded", -- also used for value inputs (overlay and nui)
    value_input = 'overlay', -- 'overlay' (built-in) or 'nui' (requires nui.nvim, no fallback)
    padding = '  ', -- global left padding for items
    icons = { checked = '', unchecked = '' },
  },
  persist = true,
  persist_namespace = "default",
  persist_file = vim.fn.stdpath('state') .. '/megatoggler/state.json',
  tabs = {
    -- see examples above
    -- { id = "editor", label = "Editor", items = { ... } }
  }
}
```

The default config comes with nerd font icons. Override with ascii values if not using a nerd font.

```lua
{
  ui = { icons = { checked = '[x]', unchecked = '[ ]' }
}
```

## Usage

- Command: `:MegaToggler` (toggles MegaToggler)
- Movement: `j/k`, `<Up>/<Down>`, `gg/G`
- Tabs: `h/l`, `<Left>/<Right>`, `Tab`/`<S-Tab>`
- Toggle/value edit: `<CR>`, `<Space>` (toggles booleans; edits values inline)
- Close: `q`, `<Esc>`

Notes:
- Dashboard is single instance - invoking `:MegaToggler` again closes it
- Toggle actions apply to the previously active window/buffer

## API

```lua
require("megatoggler").open()
require("megatoggler").close()
require("megatoggler").toggle()
require("megatoggler").refresh()
require("megatoggler").persist()
require("megatoggler").add_item(tab_id, item)
require("megatoggler").remove_item(tab_id, item_id)
require("megatoggler").add_tab({ id, label, items = { ... } })
require("megatoggler").set_value(tab_id, item_id, value) -- programmatic setter for value items
```

### Value Input Provider

- Configure with `ui.value_input = 'overlay' | 'nui'` (default: `overlay`).
- `overlay`: built-in 1-line floating input placed over the value text.
- `nui`: uses `nui.nvim`'s input; when selected, `nui.nvim` must be installed (no fallback).


## Highlights

- `MegaTogglerTitle`
- `MegaTogglerBorder`
- `MegaTogglerTab`
- `MegaTogglerTabActive`
- `MegaTogglerItem`
- `MegaTogglerItemOn`
- `MegaTogglerItemOff`
- `MegaTogglerItemEphemeral`
- `MegaTogglerItemOnEphemeral`
- `MegaTogglerItemOffEphemeral`
- `MegaTogglerDesc`
- `MegaTogglerHint`
- `MegaTogglerValueLabel`
- `MegaTogglerValueText`
- `MegaTogglerValueLabelEphemeral`
- `MegaTogglerValueTextEphemeral`

## License

MIT

Disclaimer: this is a vibe-coded plugin
