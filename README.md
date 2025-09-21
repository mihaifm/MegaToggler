# MegaToggler

A Neovim plugin where you can toggle things on and off.

- Floating dashboard with tabs and pretty checkboxes
- Toggle editor features via configurable callbacks
- Edit text/numeric values with a visual UI
- State persistence across sessions

## Install

Requirement: Neovim 0.11+

Sample lazy.nvim installation below.

MegaToggler does not come with any default items to be toggled. You will need to provide your own.

Below is a sample configuration that can help you get started:

```lua
{
  "mihaifm/megatoggler",
  config = function()
    require("megatoggler").setup({
      tabs = {
        {
          -- global options you might want to persist
          id = "Globals",
          items = {
            {
              id = "Ignore Case",
              -- all items must define a get method
              get = function() return vim.o.ignorecase end,
              -- items with boolean value must define on_toggle
              on_toggle = function(on) vim.o.ignorecase = on end,
            },
            {
              id = "Tabstop",
              label = "Tab Stop", -- optional label
              desc = "Tab size", -- optional description
              get = function()
                -- use opt_global for vim options you want to persist
                return vim.opt_global.tabstop:get()
              end,
              -- items with numeric/string value must define on_set
              on_set = function(v)
                vim.opt_global.tabstop = v
              end,
              -- size of the textbox when editing
              edit_size = 3
            },
            {
              id = "Expand Tab",
              get = function() return vim.opt_global.expandtab:get() end,
              on_toggle = function(on) vim.opt_global.expandtab = on end,
            },
            {
              id = "Inc Command",
              get = function() return vim.o.inccommand end,
              on_set = function(v) vim.o.inccommand = v end,
              edit_size = 10
            },
          }
        },
        {
          -- local options you might want to toggle but not persist
          id = "Local",
          items = {
            {
              id = 'Tabstop',
              -- disable persistance for buffer-local options
              persist = false,
              get = function() return vim.bo.tabstop end,
              on_set = function(v) vim.bo.tabstop = v end
            }
          }
        },
        {
          -- toggle features provided by other plugins
          id = "Features",
          items = {
            {
              id = 'Render Markdown',
              get = function() return require('render-markdown').get() end,
              on_toggle = function() require('render-markdown').toggle() end,
            },
            {
              id = "Neotree",
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
            {
              id = "Autopairs",
              get = function()
                -- check if plugin is loaded by Lazy
                -- only needed if you lazy load the plugin
                local lc = require("lazy.core.config")
                if not (lc.plugins["nvim-autopairs"] and lc.plugins["nvim-autopairs"]._.loaded) then
                  return false
                end

                return not require("nvim-autopairs").state.disabled
              end,
              on_toggle = function(on)
                -- avoid lazy loading the plugin if on == false
                if on == false then
                  local lc = require("lazy.core.config")
                  if not (lc.plugins["nvim-autopairs"] and lc.plugins["nvim-autopairs"]._.loaded) then
                    return
                  end
                end

                if on then
                  require("nvim-autopairs").enable()
                else
                  require("nvim-autopairs").disable()
                end
              end
            },
            {
              id = "Smooth scrolling",
              -- disable persistance when it's difficult to get the plugin's internal state
              persist = false,
              get = function() return true end,
              on_toggle = function() vim.cmd("ToggleNeoscroll") end,
              -- set custom icons for plugins where it's difficult to get the state
              icons = { checked = "", unchecked = "" },
            },
          }
        }
      }
    })
  end
```

## Configuration

Plugin configuration defaults:

```lua
{
  ui = { 
    width = 60, 
    height = 18, 
    border = "rounded", -- also used for value inputs
    value_input = 'overlay', -- 'overlay' | 'nui' (requires nui.nvim)
    padding = '  ', -- global left padding for items
    icons = { checked = '', unchecked = '' },
  },
  persist = true,
  persist_namespace = "default",
  persist_file = vim.fn.stdpath('state') .. '/megatoggler/state.json',
  tabs = {
    -- your items come here
    -- item specification below
  }
}
```

The default config comes with nerd font icons. Override with ascii values if not using a nerd font.

```lua
{
  ui = { icons = { checked = '[x]', unchecked = '[ ]' }
}
```

## Item Specification

```lua
item = {
  id = "",
  label = "", -- optional, item id is used when label is missing
  persist = true, -- persist the state of the item
  disabled = false, -- display the item but disable interraction
  get = function()
    -- should return the state of the item
  end,
  on_toggle = function(on) -- on: true | false - current value
    -- the action to take when toggling a boolean option
  end,
  on_set = function(v) -- v: number | string - current value
    -- the action to take when setting a numeric/string value
  end,
  validate = function(v) -- optional item validation
    -- must return: ok, msg
  end
  edit_size = 20, -- size of the textbox when editing values
  padding = 2 -- align items with a left padding
  icons = { checked = '', unchecked = '' }
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
- All actions triggered by the dashboard apply to the previously active window/buffer

## API

```lua
require("megatoggler").open()
require("megatoggler").close()
require("megatoggler").toggle()
require("megatoggler").persist()
require("megatoggler").add_item(tab_id, item)
require("megatoggler").remove_item(tab_id, item_id)
require("megatoggler").add_tab({ id, label, items = { ... } })
require("megatoggler").set_value(tab_id, item_id, value) -- programmatic setter for value items
```

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

Enjoy
