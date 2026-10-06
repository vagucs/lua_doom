-- DOOM generic portado do python_doom para Lua com SDL2.
--
-- Por Wagner Nunes da Silva
--
-- vagucs@bol.com.br
-- vagucs@vagucs.com.br
-- vagucs@gmail.com
--
-- www.vagucs.com.br
--
-- WAD loader. Lump numbers stay 0-based, like wad.py.
-- The Lua array is 1-based, so every lookup adds 1.

local M = {}

local IWAD_NAMES = {
  "DOOM1.WAD",
  "doom1.wad",
  "DOOM.WAD",
  "doom.wad",
  "DOOM2.WAD",
  "doom2.wad",
  "PLUTONIA.WAD",
  "TNT.WAD",
  "freedoom1.wad",
  "freedoom2.wad",
}

local function u32(buf, at)
  local b1, b2, b3, b4 = buf:byte(at, at + 3)
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function name8(raw)
  local cut = raw:find("\0", 1, true)
  if cut then
    raw = raw:sub(1, cut - 1)
  end
  raw = raw:gsub("%s+$", "")
  return raw:upper()
end

local function key_of(name)
  local cut = name:find("\0", 1, true)
  if cut then
    name = name:sub(1, cut - 1)
  end
  name = name:gsub("%s+$", "")
  if #name > 8 then
    name = name:sub(1, 8)
  end
  return name:upper()
end

local function exists(path)
  local f = io.open(path, "rb")
  if not f then
    return false
  end
  f:close()
  return true
end

local function join(dir, name)
  if dir == "" then
    return name
  end
  local sep = package.config:sub(1, 1)
  if dir:sub(-1) == "/" or dir:sub(-1) == "\\" then
    return dir .. name
  end
  return dir .. sep .. name
end

local function pwd()
  local pipe = io.popen("cd")
  if not pipe then
    return "."
  end
  local line = pipe:read("*l") or "."
  pipe:close()
  return line
end

local function is_abs(path)
  return path:match("^%a:[/\\]") ~= nil or path:sub(1, 1) == "/" or path:sub(1, 1) == "\\"
end

local function script_dir()
  local src = debug.getinfo(1, "S").source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  src = src:gsub("^%.[/\\]", "")
  if not is_abs(src) then
    src = join(pwd(), src)
  end
  return src:match("^(.*)[/\\]") or "."
end

local function parent(path)
  return path:match("^(.*)[/\\]") or path
end

function M.find_iwad(explicit)
  if explicit and explicit ~= "" then
    if exists(explicit) then
      return explicit
    end
    error("IWAD not found: " .. explicit)
  end
  local env = os.getenv("DOOMWADDIR") or os.getenv("DOOMWADPATH") or ""
  local here = script_dir()
  local roots = { here, parent(here), parent(parent(here)) }
  local cwd = "." 
  table.insert(roots, 1, cwd)
  if env ~= "" then
    table.insert(roots, 1, env)
  end
  for i = 1, #roots do
    for n = 1, #IWAD_NAMES do
      local path = join(roots[i], IWAD_NAMES[n])
      if exists(path) then
        return path
      end
    end
  end
  error("No IWAD found. Put doom1.wad in this folder or pass -iwad file.wad")
end

function M.new()
  return { lumps = {}, index = {} }
end

function M.add_file(wad, path)
  local f = assert(io.open(path, "rb"))
  local header = f:read(12)
  if not header or #header < 12 then
    f:close()
    error("not a WAD: " .. path)
  end
  local ident = header:sub(1, 4)
  if ident ~= "IWAD" and ident ~= "PWAD" then
    f:close()
    error("not a WAD: " .. path)
  end
  local numlumps = u32(header, 5)
  local infotable = u32(header, 9)
  f:seek("set", infotable)
  local directory = f:read(numlumps * 16)
  f:close()
  if not directory or #directory < numlumps * 16 then
    error("truncated WAD directory: " .. path)
  end
  local start = #wad.lumps
  for i = 0, numlumps - 1 do
    local off = i * 16
    local lump = {
      name = name8(directory:sub(off + 9, off + 16)),
      position = u32(directory, off + 1),
      size = u32(directory, off + 5),
      cache = nil,
      wad_path = path,
    }
    wad.lumps[#wad.lumps + 1] = lump
  end
  for i = start, #wad.lumps - 1 do
    wad.index[wad.lumps[i + 1].name] = i
  end
  return wad
end

function M.num_lumps(wad)
  return #wad.lumps
end

function M.check_num_for_name(wad, name)
  local n = wad.index[key_of(name)]
  if n == nil then
    return -1
  end
  return n
end

function M.get_num_for_name(wad, name)
  local n = M.check_num_for_name(wad, name)
  if n < 0 then
    error("lump not found: " .. name)
  end
  return n
end

function M.lump_length(wad, num)
  return wad.lumps[num + 1].size
end

function M.cache_lump_num(wad, num)
  local lump = wad.lumps[num + 1]
  if lump.cache == nil then
    local f = assert(io.open(lump.wad_path, "rb"))
    f:seek("set", lump.position)
    local data = f:read(lump.size)
    f:close()
    if not data then
      data = ""
    end
    lump.cache = data
  end
  return lump.cache
end

function M.cache_lump_name(wad, name)
  return M.cache_lump_num(wad, M.get_num_for_name(wad, name))
end

function M.lump_name(wad, num)
  return wad.lumps[num + 1].name
end

return M
