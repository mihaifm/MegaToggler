-- Minimal Neovim init for running tests locally (no external plugins)
-- Adds this repo to runtimepath so `require('megatoggler')` works.

-- Ensure current repo is on runtimepath (so `require('megatoggler')` works)
local root = vim.fn.fnamemodify(vim.fn.getcwd(), ':p')
vim.opt.rtp:prepend(root)

-- Optionally add Plenary to runtimepath if available
-- No Plenary or other plugins added here

-- Quiet down UI for headless
vim.o.more = false
vim.o.swapfile = false
vim.o.shada = ''
