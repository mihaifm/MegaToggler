# MegaToggler

A Neovim plugin where you can toggle things on and off.

- Floating dashboard with tabs and pretty checkboxes
- Toggle editor features via configurable callbacks
- State persistence across sessions

## Install

Requirement: Neovim 0.11+

Sample lazy.nvim installation below.

MegaToggler does not come with any default items to be toggled. You will need to provide your own.

For each item, you need to implement the following methods:
- **get**: returns true or false depending on the state of the feature you're trying to toggle
- **on_toggle**: callback for toggling the checkbox

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
    border = "rounded",
    icons = { checked = '', unchecked = '' },
  },
  persist = true,
  persist_namespace = "default",
  persist_file = vim.fn.stdpath('data') .. '/megatoggler/state.json',
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
- Toggle: `<CR>`, `<Space>`
- Close: `q`, `<Esc>`

Notes:
- Dashboard is single instance - invoking `:MegaToggler` again closes it
- Toggle actions apply to the previously active window/buffer

## API

```lua
require("mega_toggler").open()
require("mega_toggler").close()
require("mega_toggler").toggle()
require("mega_toggler").refresh()
require("mega_toggler").persist()
require("mega_toggler").add_item(tab_id, item)
require("mega_toggler").remove_item(tab_id, item_id)
require("mega_toggler").add_tab({ id, label, items = { ... } })
```

## Highlights

- `MegaTogglerTitle`
- `MegaTogglerBorder`
- `MegaTogglerTab`
- `MegaTogglerTabActive`
- `MegaTogglerItem`
- `MegaTogglerItemOn`
- `MegaTogglerItemOff`
- `MegaTogglerDesc`
- `MegaTogglerHint`

## License

MIT

Disclaimer: this is a vibe-coded plugin
