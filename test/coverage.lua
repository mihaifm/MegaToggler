-- Lightweight line coverage using debug.sethook
-- Tracks executed lines for files under configured include prefixes

local M = {}

local cfg = { include = {} }
local files = {} -- { [path] = { executed = { [line]=true }, total_lines = n, non_code = { [line]=true } } }
local hook_set = false
local instrumented_by_name = {}
local orig_searchers = nil
local top_mod_name = nil
local top_mod_init_path = nil

local project_root = nil

local function is_included(path)
  if type(path) ~= 'string' or path == '' then return false end

  -- Absolute match against configured prefixes
  for _, pfx in ipairs(cfg.include or {}) do
    if #pfx > 0 and path:find(pfx, 1, true) == 1 then return true end
  end

  -- Relative fallback: files starting under 'lua/' from cwd
  if path:sub(1, 4) == 'lua/' then return true end

  -- Absolute fallback: ensure it's inside project_root and under /lua/
  if project_root and path:find(project_root, 1, true) == 1 and path:find('/lua/', 1, true) then
    return true
  end

  return false
end

local function mark(path, line)
  local f = files[path]
  if not f then
    f = { executed = {}, total_lines = nil, non_code = {} }
    files[path] = f
  end
  f.executed[line] = true
end

local function line_hook(event, line)
  if event ~= 'line' then return end

  local info = debug.getinfo(2, 'S')
  local src = info and info.source or ''

  if type(src) ~= 'string' or src:sub(1, 1) ~= '@' then return end

  local path = src:sub(2)
  if not is_included(path) then return end
  mark(path, line)
end

local function default_include_prefixes()
  local function getcwd()
    if _G.vim and vim.fn and vim.fn.getcwd then
      return vim.fn.getcwd()
    end
    return os.getenv('PWD') or '.'
  end

  local root = getcwd()
  do
    local last = root:sub(-1)
    if last ~= '/' and last ~= '\\' and last ~= ' ' then
      root = root .. '/'
    end
  end
  return { root .. 'lua/' }
end

function M.start(options)
  cfg = options or {}
  cfg.include = cfg.include or default_include_prefixes()
  project_root = cfg.include[1] and cfg.include[1]:gsub('lua/+$','') or nil

  -- Ensure LuaJIT does not skip line hooks by compiling functions
  if jit and type(jit.off) == 'function' then
    pcall(jit.off, true, true)
    if type(jit.flush) == 'function' then pcall(jit.flush) end
  end

  if hook_set then return end
  debug.sethook(line_hook, 'l')
  hook_set = true

  -- Hook package searchers/loaders to instrument immediately after load
  local searchers = package.loaders
  orig_searchers = {}

  for i, s in ipairs(searchers) do
    orig_searchers[i] = s

    if type(s) == 'function' then
      searchers[i] = function(name)
        local loader, param = s(name)

        local function should_instrument()
          if type(param) == 'string' and is_included(param) then return true end
          if type(name) == 'string' and top_mod_name and (name == top_mod_name or name:find(top_mod_name .. '%.', 1, true) == 1) then
            return true
          end
          return false
        end

        if type(loader) == 'function' and should_instrument() then
          local wrapped = function(...)
            local res = loader(...)
            if type(res) == 'table' and not instrumented_by_name[name] then
              instrumented_by_name[name] = true
              M.instrument_module_inplace(res, param)
            end
            return res
          end

          return wrapped, param
        end

        return loader, param
      end
    end
  end

  -- Best-effort preload hook for top-level modules under include path
  -- If include contains "/path/.../lua/<modname>/", instrument that module eagerly
  -- Discover top-level module under lua/ by scanning for init.lua
  do
    local first_inc = (cfg.include and cfg.include[1]) or nil
    local lua_root = first_inc or default_include_prefixes()[1]

    if type(lua_root) == 'string' then
      -- Normalize lua_root to end with '/'
      if lua_root:sub(-1) ~= '/' then lua_root = lua_root .. '/' end

      -- Prefer vim.uv if available to scan directory
      local entries = {}
      local ok_scandir = false
      if _G.vim and vim.uv and vim.uv.fs_scandir and vim.uv.fs_scandir_next then
        local handle = vim.uv.fs_scandir(lua_root)
        if handle then
          ok_scandir = true
          while true do
            local name, typ = vim.uv.fs_scandir_next(handle)
            if not name then break end
            if typ == 'directory' then entries[#entries+1] = name end
          end
        end
      end

      -- Fallback: attempt reading via io.popen(ls)
      if not ok_scandir then
        local p = io.popen('ls -1 "' .. lua_root .. '" 2>/dev/null')
        if p then
          for line in p:lines() do entries[#entries+1] = line end
          p:close()
        end
      end

      for _, dir in ipairs(entries) do
        local candidate = lua_root .. dir .. '/init.lua'
        local fh = io.open(candidate, 'r')
        if fh then
          fh:close()
          top_mod_name = dir
          top_mod_init_path = candidate
          break
        end
      end

      if top_mod_name and not package.loaded[top_mod_name] then
        package.preload[top_mod_name] = function()
          local chunk, err = loadfile(top_mod_init_path)
          if not chunk then error('coverage preload failed: ' .. tostring(err)) end
          local mod = chunk()
          if type(mod) == 'table' then M.instrument_module_inplace(mod, top_mod_init_path) end
          return mod
        end

        -- Force-load the module to ensure instrumentation
        pcall(function() require(top_mod_name) end)
      end
    end
  end
end

function M.stop()
  if hook_set then
    debug.sethook()
    hook_set = false
  end
  -- no-op for require restoration
  if orig_searchers then
    local searchers = package.loaders
    for i, s in ipairs(orig_searchers) do
      searchers[i] = s
    end
    orig_searchers = nil
  end
end

local function analyze_file(path, fdata)
  -- Prefer executable lines determined by debug info (top-level + exported funcs)
  local ok_lf, chunk = pcall(loadfile, path)
  if ok_lf and type(chunk) == 'function' then
    -- Top-level chunk activelines
    local ok_info, info = pcall(debug.getinfo, chunk, 'L')
    if ok_info and info and type(info.activelines) == 'table' then
      fdata.exec_lines = fdata.exec_lines or {}
      for ln, active in pairs(info.activelines) do if active then fdata.exec_lines[ln] = true end end
    end

    -- Also attempt to execute the chunk to get module table and include function activelines
    local ok_run, mod = pcall(chunk)
    if ok_run and type(mod) == 'table' then
      for _, fn in pairs(mod) do
        if type(fn) == 'function' then
          local ok_si, si = pcall(debug.getinfo, fn, 'SL')

          if ok_si and si and type(si) == 'table' and type(si.source) == 'string' then
            local src = si.source
            if src:sub(1,1) == '@' then src = src:sub(2) end
            if src == path then
              -- Mark activelines for this function; if unavailable, mark defined range
              local ok_fl, fl = pcall(debug.getinfo, fn, 'L')
              if ok_fl and fl and type(fl.activelines) == 'table' then
                fdata.exec_lines = fdata.exec_lines or {}
                for ln, active in pairs(fl.activelines) do if active then fdata.exec_lines[ln] = true end end
              else
                if type(si.linedefined) == 'number' and type(si.lastlinedefined) == 'number' then
                  fdata.exec_lines = fdata.exec_lines or {}
                  for ln = si.linedefined, si.lastlinedefined do fdata.exec_lines[ln] = true end
                end
              end
            end
          end
        end
      end
    end
  end

  -- Also record simple non-code lines and total lines for fallback
  local fh = io.open(path, 'r')
  if fh then
    local n = 0
    for line in fh:lines() do
      n = n + 1
      local s = line:match('^%s*(.*)$') or ''
      if s == '' or s:sub(1,2) == '--' then
        fdata.non_code[n] = true
      end
    end
    fh:close()
    fdata.total_lines = n
  end
end

local function summarize(path, fdata)
  if not fdata.total_lines then analyze_file(path, fdata) end

  local total, covered, miss = 0, 0, {}
  if fdata.exec_lines and next(fdata.exec_lines) ~= nil then
    -- Count only actual executable lines
    local lines = {}
    for ln, _ in pairs(fdata.exec_lines) do lines[#lines+1] = ln end

    table.sort(lines)

    total = #lines
    for _, ln in ipairs(lines) do
      if fdata.executed[ln] then covered = covered + 1 else miss[#miss+1] = ln end
    end
  else
    -- Fallback heuristic
    for i = 1, (fdata.total_lines or 0) do
      if not fdata.non_code[i] then
        total = total + 1
        if fdata.executed[i] then covered = covered + 1 else miss[#miss+1] = i end
      end
    end
  end

  local pct = total > 0 and (covered / total * 100.0) or 100.0
  return pct, total, covered, miss
end

local function compress_ranges(lines)
  local ranges = {}
  local s, prev
  for _, ln in ipairs(lines) do
    if not s then s, prev = ln, ln
    elseif ln == prev + 1 then
      prev = ln
    else
      ranges[#ranges+1] = { s, prev }
      s, prev = ln, ln
    end
  end
  if s then ranges[#ranges+1] = { s, prev } end
  return ranges
end

function M.report()
  local paths = {}
  for p, _ in pairs(files) do paths[#paths+1] = p end
  -- Order by path for stable output
  table.sort(paths)

  print('\nCoverage Report:')
  if #paths == 0 then
    print('  (no line coverage tracked)')
  else
    for _, p in ipairs(paths) do
      local fdata = files[p]
      local pct, total, covered, miss = summarize(p, fdata)
      print(string.format('  %s: %.1f%% (%d/%d)', p, pct, covered, total))

      if #miss > 0 then
        local ranges = compress_ranges(miss)
        local range_strs = {}
        for _, r in ipairs(ranges) do
          if r[1] == r[2] then range_strs[#range_strs+1] = tostring(r[1]) else range_strs[#range_strs+1] = (r[1] .. '-' .. r[2]) end
        end
        print('    Missed lines: ' .. table.concat(range_strs, ', '))
      end
    end
  end

  -- Function coverage (if any instrumented)
  if M._func_hits then
    local fpaths = {}
    for p, _ in pairs(M._func_hits) do
      if p ~= 'module' then
        fpaths[#fpaths+1] = p
      end
    end

    table.sort(fpaths)

    if #fpaths > 0 then
      print('\nFunction Coverage:')

      for _, p in ipairs(fpaths) do
        local map = M._func_hits[p]
        local names = {}
        for n, _ in pairs(map) do names[#names+1] = n end

        table.sort(names)

        local total, called = 0, 0
        for _, n in ipairs(names) do
          total = total + 1
          if map[n] > 0 then called = called + 1 end
        end

        local pct = total > 0 and (called / total * 100.0) or 100.0
        print(string.format('  %s: %.1f%% (%d/%d) functions called', p, pct, called, total))

        local missed = {}
        for _, n in ipairs(names) do if map[n] == 0 then missed[#missed+1] = n end end
        if #missed > 0 then
          print('    Missed functions: ' .. table.concat(missed, ', '))
        end
      end
    end
  end
end

-- In-place instrumentation of module table to preserve internal self-references
function M.instrument_module_inplace(mod, path_hint)
  if type(mod) ~= 'table' then return mod end

  local path = path_hint or 'module'
  M._func_hits = M._func_hits or {}
  M._func_hits[path] = M._func_hits[path] or {}
  local hits = M._func_hits[path]

  for k, v in pairs(mod) do
    if type(v) == 'function' then
      if not hits[k] then hits[k] = 0 end
      local orig = v
      mod[k] = function(...)
        hits[k] = (hits[k] or 0) + 1
        return orig(...)
      end
    end
  end
  return mod
end

return M
