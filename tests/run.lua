-- Simple test runner for MegaToggler (no Plenary)
-- Discovers and runs Lua test files under tests/unit and tests/integration.
-- Usage:
--   nvim --headless -u tests/minimal_init.lua --noplugin -i NONE -n -c "lua dofile('tests/run.lua')"

local function glob(pattern)
  return vim.fn.glob(pattern, false, true)
end

-- Normalize print to write to stdout with newline + flush to avoid mixing
local function normalize_print()
  _G.print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do
      parts[#parts + 1] = tostring(select(i, ...))
    end
    io.stdout:write(table.concat(parts, '\t') .. '\n')
    io.stdout:flush()
  end
end

local function read_tests()
  local files = {}
  local function push(list)
    for _, f in ipairs(list or {}) do table.insert(files, f) end
  end
  push(glob('tests/unit/*.lua'))
  push(glob('tests/integration/*.lua'))
  table.sort(files)
  return files
end

local function cleanup()
  -- Try to close dashboard if open
  pcall(function()
    local ok, mt = pcall(require, 'megatoggler')
    if ok and mt and type(mt.close) == 'function' then mt.close() end
  end)
  -- Delete user command if present to avoid redefinition errors
  pcall(vim.api.nvim_del_user_command, 'MegaToggler')
  -- Wipe buffers with our filetype
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local ft = vim.bo[b].filetype
    if ft == 'mega_toggler' then pcall(vim.api.nvim_buf_delete, b, { force = true }) end
  end
  -- Return to a clean scratch buffer in normal mode
  pcall(vim.cmd, 'enew | stopinsert')
  -- Unload the module so each test gets a fresh instance
  package.loaded['megatoggler'] = nil
  package.loaded['megatoggler.init'] = nil
end

local function run_file(path)
  local ok, err = pcall(dofile, path)
  if ok then
    print(string.format('PASS %s\n', path))
  else
    print(string.format('FAIL %s\n%s', path, tostring(err)))
  end
  -- Always cleanup between tests to avoid cross-test pollution
  cleanup()
  return ok
end

local function main()
  normalize_print()
  local tests = read_tests()
  if #tests == 0 then
    print('No tests found')
    vim.cmd('qa')
    return
  end
  local passed, failed = 0, 0
  for _, t in ipairs(tests) do
    if run_file(t) then passed = passed + 1 else failed = failed + 1 end
  end
  print(string.format('\nSummary: %d passed, %d failed, %d total', passed, failed, #tests), '\n')
  if failed > 0 then
    vim.cmd('cquit 1')
  else
    vim.cmd('qa')
  end
end

main()
