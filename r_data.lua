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
-- Texturas, flats e COLORMAP, a partir de r_data.py.
-- Sprites ficam para a vista.

local compat = require("compat")
local wad = require("wad")

local M = {}

local FRACUNIT = compat.FRACUNIT
local unpack = unpack or table.unpack

local function i16(data, off)
  local b1, b2 = data:byte(off + 1, off + 2)
  local n = b1 + b2 * 256
  if n >= 32768 then
    n = n - 65536
  end
  return n
end

local function i32(data, off)
  local b1, b2, b3, b4 = data:byte(off + 1, off + 4)
  return compat.as_i32(b1 + b2 * 256 + b3 * 65536 + b4 * 16777216)
end

local function u32(data, off)
  local b1, b2, b3, b4 = data:byte(off + 1, off + 4)
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function name8(data, off)
  local raw = data:sub(off + 1, off + 8)
  local zero = raw:find("\0", 1, true)
  if zero then
    raw = raw:sub(1, zero - 1)
  end
  return (raw:gsub("%s+$", "")):upper()
end

local function bytes_of(buf)
  if #buf == 0 then
    return ""
  end
  local parts = {}
  local n = 0
  local i = 1
  while i <= #buf do
    local last = i + 4095
    if last > #buf then
      last = #buf
    end
    n = n + 1
    parts[n] = string.char(unpack(buf, i, last))
    i = last + 1
  end
  return table.concat(parts)
end

local function zeros(n)
  local buf = {}
  for i = 1, n do
    buf[i] = 0
  end
  return buf
end

function M.new(wadfile)
  return {
    wad = wadfile,
    textures = {},
    tex_index = {},
    flats_first = 0,
    flats_last = 0,
    flattranslation = {},
    texturetranslation = {},
    colormaps = "",
    skytexture = 0,
    skyflatnum = 0,
    sprites = {},
  }
end

function M.colormap(self, level)
  if level < 0 then
    level = 0
  end
  if level > 32 then
    level = 32
  end
  local cache = self.cmap_cache
  if not cache then
    cache = {}
    self.cmap_cache = cache
  end
  local hit = cache[level]
  if hit then
    return hit
  end
  local off = level * 256
  hit = self.colormaps:sub(off + 1, off + 256)
  cache[level] = hit
  return hit
end

local function init_flats(self)
  self.flats_first = wad.get_num_for_name(self.wad, "F_START") + 1
  self.flats_last = wad.get_num_for_name(self.wad, "F_END") - 1
  local n = self.flats_last - self.flats_first + 1
  self.flattranslation = {}
  for i = 0, n - 1 do
    self.flattranslation[i + 1] = i
  end
end

function M.flat_num_for_name(self, name)
  local i = wad.check_num_for_name(self.wad, name)
  if i < 0 then
    return 0
  end
  return i - self.flats_first
end

function M.flat_lump(self, flatnum)
  local n = self.flats_last - self.flats_first + 1
  if flatnum < 0 or flatnum >= n then
    flatnum = 0
  end
  return self.flats_first + self.flattranslation[flatnum + 1]
end

function M.flat_pixels(self, flatnum)
  local lump = M.flat_lump(self, flatnum)
  local cache = self.flat_cache
  if not cache then
    cache = {}
    self.flat_cache = cache
  end
  local hit = cache[lump]
  if hit then
    return hit
  end
  local data = wad.cache_lump_num(self.wad, lump)
  if #data >= 4096 then
    hit = data:sub(1, 4096)
  else
    hit = data .. string.rep("\0", 4096 - #data)
  end
  cache[lump] = hit
  return hit
end

local function generate_lookup(self, tex)
  local width = tex.width
  local patchcount = zeros(width)
  for p = 1, #tex.patches do
    local mp = tex.patches[p]
    if mp.patch >= 0 then
      local pdata = wad.cache_lump_num(self.wad, mp.patch)
      local pw = i16(pdata, 0)
      local x1 = mp.originx
      local x2 = x1 + pw
      local x = x1
      if x < 0 then
        x = 0
      end
      if x2 > width then
        x2 = width
      end
      while x < x2 do
        local at = x + 1
        patchcount[at] = patchcount[at] + 1
        tex.col_lump[at] = mp.patch
        tex.col_ofs[at] = u32(pdata, 8 + (x - mp.originx) * 4)
        x = x + 1
      end
    end
  end
  for x = 0, width - 1 do
    if patchcount[x + 1] > 1 then
      tex.col_lump[x + 1] = -1
    end
  end
end

local function draw_column_in_cache(patch, column, cache, x, originy, tex)
  while column < #patch do
    local topdelta = patch:byte(column + 1)
    if topdelta == 255 then
      break
    end
    local length = patch:byte(column + 2)
    local source = column + 3
    local pos = originy + topdelta
    local count = length
    if pos < 0 then
      count = count + pos
      source = source - pos
      pos = 0
    end
    if pos + count > tex.height then
      count = tex.height - pos
    end
    local dest = x * tex.height + pos
    local i = 0
    while i < count do
      cache[dest + i + 1] = patch:byte(source + i + 1)
      i = i + 1
    end
    column = column + length + 4
  end
end

local function generate_composite(self, tex)
  if tex.composite then
    return
  end
  local buf = zeros(tex.width * tex.height)
  for p = 1, #tex.patches do
    local mp = tex.patches[p]
    if mp.patch >= 0 then
      local pdata = wad.cache_lump_num(self.wad, mp.patch)
      local pw = i16(pdata, 0)
      local x1 = mp.originx
      local x2 = x1 + pw
      if x2 > tex.width then
        x2 = tex.width
      end
      local x = x1
      if x < 0 then
        x = 0
      end
      while x < x2 do
        local colofs = u32(pdata, 8 + (x - mp.originx) * 4)
        draw_column_in_cache(pdata, colofs, buf, x, mp.originy, tex)
        x = x + 1
      end
    end
  end
  tex.composite = bytes_of(buf)
  for x = 0, tex.width - 1 do
    if tex.col_lump[x + 1] < 0 then
      tex.col_ofs[x + 1] = x * tex.height
    end
  end
end

local function init_textures(self)
  local pnames = wad.cache_lump_name(self.wad, "PNAMES")
  local nummappatches = i32(pnames, 0)
  local patchlookup = {}
  for i = 0, nummappatches - 1 do
    patchlookup[i + 1] = wad.check_num_for_name(self.wad, name8(pnames, 4 + i * 8))
  end
  local maptex1 = wad.cache_lump_name(self.wad, "TEXTURE1")
  local numtextures1 = i32(maptex1, 0)
  local maptex2 = ""
  local numtextures2 = 0
  if wad.check_num_for_name(self.wad, "TEXTURE2") >= 0 then
    maptex2 = wad.cache_lump_name(self.wad, "TEXTURE2")
    numtextures2 = i32(maptex2, 0)
  end
  for i = 0, numtextures1 + numtextures2 - 1 do
    local offset, src
    if i < numtextures1 then
      offset = i32(maptex1, 4 + i * 4)
      src = maptex1
    else
      offset = i32(maptex2, 4 + (i - numtextures1) * 4)
      src = maptex2
    end
    local name = name8(src, offset)
    local width = i16(src, offset + 12)
    local height = i16(src, offset + 14)
    local patchcount = i16(src, offset + 20)
    local tex = {
      name = name,
      width = width,
      height = height,
      patches = {},
      widthmask = 0,
      composite = nil,
      col_lump = {},
      col_ofs = {},
    }
    local poff = offset + 22
    for _ = 1, patchcount do
      local ox = i16(src, poff)
      local oy = i16(src, poff + 2)
      local pidx = i16(src, poff + 4)
      poff = poff + 10
      local lump = -1
      if pidx >= 0 and pidx < nummappatches then
        lump = patchlookup[pidx + 1]
      end
      tex.patches[#tex.patches + 1] = { originx = ox, originy = oy, patch = lump }
    end
    local j = 1
    while j * 2 <= width do
      j = j * 2
    end
    tex.widthmask = j - 1
    for x = 1, width do
      tex.col_lump[x] = -1
      tex.col_ofs[x] = 0
    end
    self.tex_index[name] = #self.textures
    self.textures[#self.textures + 1] = tex
    generate_lookup(self, tex)
  end
  self.texturetranslation = {}
  for i = 0, #self.textures - 1 do
    self.texturetranslation[i + 1] = i
  end
end

function M.texture_num_for_name(self, name)
  local key = name:upper():gsub("%s+$", "")
  if #key > 8 then
    key = key:sub(1, 8)
  end
  if key == "-" or key == "" then
    return 0
  end
  local n = self.tex_index[key]
  if n == nil then
    return 0
  end
  return n
end

function M.texture_height(self, texnum)
  return self.textures[texnum + 1].height * FRACUNIT
end

function M.texture_width(self, texnum)
  return self.textures[texnum + 1].width
end

function M.column_posts(self, texnum, col)
  if texnum <= 0 or texnum >= #self.textures then
    return {}
  end
  local tex = self.textures[texnum + 1]
  col = compat.band(col, tex.widthmask)
  local cached = tex.post_cache
  if not cached then
    cached = {}
    tex.post_cache = cached
  end
  local hit = cached[col]
  if hit then
    return hit
  end
  local lump = tex.col_lump[col + 1]
  local posts = {}
  if lump >= 0 then
    local patch = wad.cache_lump_num(self.wad, lump)
    local column = tex.col_ofs[col + 1]
    while column < #patch do
      local topdelta = patch:byte(column + 1)
      if topdelta == 255 then
        break
      end
      local length = patch:byte(column + 2)
      local source = column + 3
      posts[#posts + 1] = {
        topdelta = topdelta,
        pixels = patch:sub(source + 1, source + length),
      }
      column = column + length + 4
    end
    cached[col] = posts
    return posts
  end
  generate_composite(self, tex)
  local ofs = tex.col_ofs[col + 1]
  local colbytes = tex.composite:sub(ofs + 1, ofs + tex.height)
  if #colbytes > 0 then
    posts[1] = { topdelta = 0, pixels = colbytes }
  end
  cached[col] = posts
  return posts
end

local function column_to_source(patch, column)
  local buf = zeros(128)
  while column < #patch do
    local topdelta = patch:byte(column + 1)
    if topdelta == 255 then
      break
    end
    local length = patch:byte(column + 2)
    local source = column + 3
    for i = 0, length - 1 do
      local y = topdelta + i
      if y >= 0 and y < 128 then
        buf[y + 1] = patch:byte(source + i + 1)
      end
    end
    column = column + length + 4
  end
  return bytes_of(buf)
end

local function repeat_column(colbytes)
  local buf = zeros(128)
  local n = #colbytes
  if n > 0 then
    for i = 0, 127 do
      buf[i + 1] = colbytes:byte((i % n) + 1)
    end
  end
  return bytes_of(buf)
end

function M.get_column(self, texnum, col)
  local tex = self.textures[texnum + 1]
  col = compat.band(col, tex.widthmask)
  local cols = tex.col_cache
  if not cols then
    cols = {}
    tex.col_cache = cols
  end
  local hit = cols[col]
  if hit then
    return hit
  end
  local lump = tex.col_lump[col + 1]
  if lump >= 0 then
    local pdata = wad.cache_lump_num(self.wad, lump)
    hit = column_to_source(pdata, tex.col_ofs[col + 1])
  else
    generate_composite(self, tex)
    local ofs = tex.col_ofs[col + 1]
    hit = repeat_column(tex.composite:sub(ofs + 1, ofs + tex.height))
  end
  cols[col] = hit
  return hit
end

function M.init(self)
  init_textures(self)
  init_flats(self)
  self.colormaps = wad.cache_lump_name(self.wad, "COLORMAP")
  self.skyflatnum = M.flat_num_for_name(self, "F_SKY1")
  self.skytexture = M.texture_num_for_name(self, "SKY1")
  self.sprites = {}
end

return M
