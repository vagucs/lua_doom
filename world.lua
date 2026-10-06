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
-- Mapa a partir de world.py. Nomes de textura ficam no setor e no lado.
-- O numero da textura entra na fase 7, quando r_data existir.

local compat = require("compat")
local wad = require("wad")
local v = require("v_video")
local rdata = require("r_data")

local M = {}

local FRACUNIT = compat.FRACUNIT
M.ML_TWOSIDED = 4
M.NF_SUBSECTOR = 32768
M.BOXLEFT = 0
M.BOXRIGHT = 1
M.BOXBOTTOM = 2
M.BOXTOP = 3

local MAPVERTEX_SIZE = 4
local MAPSEG_SIZE = 12
local MAPSUBSECTOR_SIZE = 4
local MAPSECTOR_SIZE = 26
local MAPNODE_SIZE = 28
local MAPTHING_SIZE = 10
local MAPLINEDEF_SIZE = 14
local MAPSIDEDEF_SIZE = 30

local function i16(data, off)
  local b1, b2 = data:byte(off + 1, off + 2)
  local n = b1 + b2 * 256
  if n >= 32768 then
    n = n - 65536
  end
  return n
end

local function u16(data, off)
  local b1, b2 = data:byte(off + 1, off + 2)
  return b1 + b2 * 256
end

local function name8(data, off)
  local raw = data:sub(off + 1, off + 8)
  local zero = raw:find("\0", 1, true)
  if zero then
    raw = raw:sub(1, zero - 1)
  end
  return (raw:gsub("%s+$", "")):upper()
end

local function new()
  return {
    vertexes = {},
    sectors = {},
    sides = {},
    lines = {},
    segs = {},
    subsectors = {},
    nodes = {},
    things = {},
    numnodes = 0,
    blockmap = {},
    bmaporgx = 0,
    bmaporgy = 0,
    bmapwidth = 0,
    bmapheight = 0,
    blockmaplump = {},
    blocklinks = {},
    validcount = 0,
    mobjs = {},
    rejectmatrix = "",
    mapname = "",
  }
end

local function load_vertexes(self, data)
  local n = math.floor(#data / MAPVERTEX_SIZE)
  self.vertexes = {}
  for i = 0, n - 1 do
    self.vertexes[i + 1] = {
      x = i16(data, i * 4) * FRACUNIT,
      y = i16(data, i * 4 + 2) * FRACUNIT,
    }
  end
end

local function load_sectors(self, data)
  local n = math.floor(#data / MAPSECTOR_SIZE)
  self.sectors = {}
  for i = 0, n - 1 do
    local o = i * MAPSECTOR_SIZE
    self.sectors[i + 1] = {
      floorheight = i16(data, o) * FRACUNIT,
      ceilingheight = i16(data, o + 2) * FRACUNIT,
      floorflat = name8(data, o + 4),
      ceilingflat = name8(data, o + 12),
      floorpic = self.res and rdata.flat_num_for_name(self.res, name8(data, o + 4)) or 0,
      ceilingpic = self.res and rdata.flat_num_for_name(self.res, name8(data, o + 12)) or 0,
      lightlevel = i16(data, o + 20),
      special = i16(data, o + 22),
      tag = i16(data, o + 24),
      lines = {},
      specialdata = nil,
      soundorg = nil,
      i_sector = i,
      validcount = 0,
      soundtraversed = 0,
      soundtarget = nil,
    }
  end
end

local function load_sides(self, data)
  local n = math.floor(#data / MAPSIDEDEF_SIZE)
  self.sides = {}
  local nsec = #self.sectors
  for i = 0, n - 1 do
    local o = i * MAPSIDEDEF_SIZE
    local sec = i16(data, o + 28)
    local sector = self.sectors[1]
    if sec >= 0 and sec < nsec then
      sector = self.sectors[sec + 1]
    end
    self.sides[i + 1] = {
      textureoffset = i16(data, o) * FRACUNIT,
      rowoffset = i16(data, o + 2) * FRACUNIT,
      topname = name8(data, o + 4),
      bottomname = name8(data, o + 12),
      midname = name8(data, o + 20),
      toptexture = self.res and rdata.texture_num_for_name(self.res, name8(data, o + 4)) or 0,
      bottomtexture = self.res and rdata.texture_num_for_name(self.res, name8(data, o + 12)) or 0,
      midtexture = self.res and rdata.texture_num_for_name(self.res, name8(data, o + 20)) or 0,
      sector = sector,
    }
  end
end

local function load_lines(self, data)
  local n = math.floor(#data / MAPLINEDEF_SIZE)
  self.lines = {}
  for i = 0, n - 1 do
    local o = i * MAPLINEDEF_SIZE
    local v1 = i16(data, o)
    local v2 = i16(data, o + 2)
    local ln = {
      v1 = self.vertexes[v1 + 1],
      v2 = self.vertexes[v2 + 1],
      flags = i16(data, o + 4),
      special = i16(data, o + 6),
      tag = i16(data, o + 8),
      sidenum = { i16(data, o + 10), i16(data, o + 12) },
      bbox = { 0, 0, 0, 0 },
      slopetype = 0,
      frontsector = nil,
      backsector = nil,
      sides = { nil, nil },
      i_line = i,
      validcount = 0,
    }
    ln.dx = ln.v2.x - ln.v1.x
    ln.dy = ln.v2.y - ln.v1.y
    local s0, s1 = ln.sidenum[1], ln.sidenum[2]
    if s0 >= 0 then
      ln.sides[1] = self.sides[s0 + 1]
      ln.frontsector = ln.sides[1].sector
    end
    if s1 >= 0 then
      ln.sides[2] = self.sides[s1 + 1]
      ln.backsector = ln.sides[2].sector
    end
    if ln.v1.x < ln.v2.x then
      ln.bbox[1] = ln.v1.x
      ln.bbox[2] = ln.v2.x
    else
      ln.bbox[1] = ln.v2.x
      ln.bbox[2] = ln.v1.x
    end
    if ln.v1.y < ln.v2.y then
      ln.bbox[3] = ln.v1.y
      ln.bbox[4] = ln.v2.y
    else
      ln.bbox[3] = ln.v2.y
      ln.bbox[4] = ln.v1.y
    end
    if ln.frontsector then
      local lines = ln.frontsector.lines
      lines[#lines + 1] = ln
    end
    if ln.backsector and ln.backsector ~= ln.frontsector then
      local lines = ln.backsector.lines
      lines[#lines + 1] = ln
    end
    self.lines[i + 1] = ln
  end
end

local function load_segs(self, data)
  local n = math.floor(#data / MAPSEG_SIZE)
  self.segs = {}
  for i = 0, n - 1 do
    local o = i * MAPSEG_SIZE
    local ln = self.lines[i16(data, o + 6) + 1]
    local side = i16(data, o + 8)
    local sg = {
      v1 = self.vertexes[i16(data, o) + 1],
      v2 = self.vertexes[i16(data, o + 2) + 1],
      angle = compat.as_u32(i16(data, o + 4) * 65536),
      linedef = ln,
      offset = i16(data, o + 10) * FRACUNIT,
      sidedef = nil,
      frontsector = nil,
      backsector = nil,
    }
    local sd = ln.sides[side + 1]
    if not sd then
      sd = ln.sides[1]
    end
    sg.sidedef = sd
    if sd then
      sg.frontsector = sd.sector
    end
    if compat.band(ln.flags, M.ML_TWOSIDED) ~= 0 then
      local other = ln.sides[compat.bxor(side, 1) + 1]
      if other then
        sg.backsector = other.sector
      end
    end
    self.segs[i + 1] = sg
  end
end

local function load_subsectors(self, data)
  local n = math.floor(#data / MAPSUBSECTOR_SIZE)
  self.subsectors = {}
  for i = 0, n - 1 do
    local o = i * MAPSUBSECTOR_SIZE
    self.subsectors[i + 1] = {
      numlines = u16(data, o),
      firstline = u16(data, o + 2),
      sector = nil,
    }
  end
end

local function load_nodes(self, data)
  local n = math.floor(#data / MAPNODE_SIZE)
  self.nodes = {}
  for i = 0, n - 1 do
    local o = i * MAPNODE_SIZE
    local bbox = {}
    local p = o + 8
    for child = 1, 2 do
      bbox[child] = {
        i16(data, p) * FRACUNIT,
        i16(data, p + 2) * FRACUNIT,
        i16(data, p + 4) * FRACUNIT,
        i16(data, p + 6) * FRACUNIT,
      }
      p = p + 8
    end
    self.nodes[i + 1] = {
      x = i16(data, o) * FRACUNIT,
      y = i16(data, o + 2) * FRACUNIT,
      dx = i16(data, o + 4) * FRACUNIT,
      dy = i16(data, o + 6) * FRACUNIT,
      bbox = bbox,
      children = { u16(data, p), u16(data, p + 2) },
    }
  end
end

local function load_things(self, data)
  local n = math.floor(#data / MAPTHING_SIZE)
  self.things = {}
  for i = 0, n - 1 do
    local o = i * MAPTHING_SIZE
    self.things[i + 1] = {
      x = i16(data, o),
      y = i16(data, o + 2),
      angle = i16(data, o + 4),
      type = i16(data, o + 6),
      options = i16(data, o + 8),
    }
  end
end

local function load_blockmap(self, data)
  local n = math.floor(#data / 2)
  local lump = {}
  for i = 0, n - 1 do
    lump[i + 1] = u16(data, i * 2)
  end
  self.blockmaplump = lump
  self.blockmap = {}
  self.blocklinks = {}
  if n < 4 then
    return
  end
  self.bmaporgx = i16(data, 0) * FRACUNIT
  self.bmaporgy = i16(data, 2) * FRACUNIT
  self.bmapwidth = i16(data, 4)
  self.bmapheight = i16(data, 6)
  local count = self.bmapwidth * self.bmapheight
  for i = 1, count do
    self.blockmap[i] = lump[4 + i]
  end
end

local function load_reject(self, data)
  self.rejectmatrix = data or ""
end

function M.setup_level(self, wadfile, res, episode, mapn)
  self.res = res
  local lumpname
  if wad.check_num_for_name(wadfile, string.format("MAP%02d", mapn)) >= 0 then
    lumpname = string.format("MAP%02d", mapn)
  else
    lumpname = string.format("E%dM%d", episode, mapn)
  end
  local lumpnum = wad.get_num_for_name(wadfile, lumpname)
  load_vertexes(self, wad.cache_lump_num(wadfile, lumpnum + 4))
  load_sectors(self, wad.cache_lump_num(wadfile, lumpnum + 8))
  load_sides(self, wad.cache_lump_num(wadfile, lumpnum + 3))
  load_lines(self, wad.cache_lump_num(wadfile, lumpnum + 2))
  load_segs(self, wad.cache_lump_num(wadfile, lumpnum + 5))
  load_subsectors(self, wad.cache_lump_num(wadfile, lumpnum + 6))
  load_nodes(self, wad.cache_lump_num(wadfile, lumpnum + 7))
  load_things(self, wad.cache_lump_num(wadfile, lumpnum + 1))
  load_blockmap(self, wad.cache_lump_num(wadfile, lumpnum + 10))
  load_reject(self, wad.cache_lump_num(wadfile, lumpnum + 9))
  self.numnodes = #self.nodes
  self.mapname = lumpname
  for i = 1, #self.subsectors do
    local ss = self.subsectors[i]
    local seg = self.segs[ss.firstline + 1]
    if seg then
      ss.sector = seg.frontsector
    end
  end
end

function M.point_in_subsector(self, x, y)
  local nodenum = self.numnodes - 1
  if nodenum < 0 then
    return self.subsectors[1]
  end
  while compat.band(nodenum, M.NF_SUBSECTOR) == 0 do
    local node = self.nodes[nodenum + 1]
    local dx = compat.as_i32(x - node.x)
    local dy = compat.as_i32(y - node.y)
    local left = compat.as_i32(compat.shar(node.dy, 16)) * dx
    local right = dy * compat.as_i32(compat.shar(node.dx, 16))
    local side = 0
    if right >= left then
      side = 1
    end
    nodenum = node.children[side + 1]
  end
  return self.subsectors[compat.band(nodenum, 32767) + 1]
end

function M.player_start(self)
  for i = 1, #self.things do
    if self.things[i].type == 1 then
      return self.things[i]
    end
  end
  return self.things[1]
end

local wall_color, open_color, arrow_color

local function pick_colors(pal)
  local wall, open, arrow = 4, 4, 4
  local best, mid, red = -1, 1000000000, -1
  for i = 0, 255 do
    local r, g, b = pal:byte(i * 3 + 1, i * 3 + 3)
    local sum = r + g + b
    if sum > best then
      best = sum
      wall = i
    end
    local spread = math.abs(r - g) + math.abs(g - b) + math.abs(r - b)
    if spread < 24 and sum > 180 and sum < 520 then
      local dist = math.abs(sum - 320)
      if dist < mid then
        mid = dist
        open = i
      end
    end
    if r > red and r > g + 80 and r > b + 80 then
      red = r
      arrow = i
    end
  end
  if mid == 1000000000 then
    open = wall
  end
  return wall, open, arrow
end

local function map_scale(self)
  local minx, maxx, miny, maxy
  for i = 1, #self.vertexes do
    local x = self.vertexes[i].x / FRACUNIT
    local y = self.vertexes[i].y / FRACUNIT
    if not minx or x < minx then
      minx = x
    end
    if not maxx or x > maxx then
      maxx = x
    end
    if not miny or y < miny then
      miny = y
    end
    if not maxy or y > maxy then
      maxy = y
    end
  end
  local spanx = (maxx or 1) - (minx or 0)
  local spany = (maxy or 1) - (miny or 0)
  if spanx < 1 then
    spanx = 1
  end
  if spany < 1 then
    spany = 1
  end
  local margin = 8
  local scale = (v.SCREENWIDTH - margin * 2) / spanx
  local sy = (v.SCREENHEIGHT - margin * 2) / spany
  if sy < scale then
    scale = sy
  end
  local ox = (v.SCREENWIDTH - spanx * scale) / 2
  local oy = (v.SCREENHEIGHT - spany * scale) / 2
  return minx, maxy, scale, ox, oy
end

local function dominant(pixels)
  local counts = {}
  local best, bestn = 0, 0
  for i = 1, #pixels do
    local c = pixels:byte(i)
    if c ~= 0 then
      local n = (counts[c] or 0) + 1
      counts[c] = n
      if n > bestn then
        bestn = n
        best = c
      end
    end
  end
  if bestn == 0 then
    return pixels:byte(1) or 4
  end
  return best
end

local function swatch(res, kind, num)
  res.swatch = res.swatch or {}
  local key = kind .. tostring(num)
  local hit = res.swatch[key]
  if hit then
    return hit
  end
  local pixels
  if kind == "t" then
    pixels = rdata.get_column(res, num, 0)
  else
    pixels = rdata.flat_pixels(res, num)
  end
  hit = dominant(pixels)
  res.swatch[key] = hit
  return hit
end

local function line_color(self, ln, plain, open)
  if not self.res then
    if ln.backsector then
      return open
    end
    return plain
  end
  local side = ln.sides[1]
  local num = 0
  if side then
    num = side.midtexture
    if num <= 0 then
      num = side.toptexture
    end
    if num <= 0 then
      num = side.bottomtexture
    end
    if num > 0 then
      return swatch(self.res, "t", num)
    end
    if side.sector then
      return swatch(self.res, "f", side.sector.floorpic)
    end
  end
  return open
end

function M.draw_overhead(self, fb, pal)
  if pal and not wall_color then
    wall_color, open_color, arrow_color = pick_colors(pal)
  end
  local plain = wall_color or 176
  local open = open_color or 96
  local arrow = arrow_color or 32
  local minx, maxy, scale, ox, oy = map_scale(self)
  local function to_screen(x, y)
    return ox + (x - minx) * scale, oy + (maxy - y) * scale
  end
  for i = 1, #self.lines do
    local ln = self.lines[i]
    local color = line_color(self, ln, plain, open)
    local x0, y0 = to_screen(ln.v1.x / FRACUNIT, ln.v1.y / FRACUNIT)
    local x1, y1 = to_screen(ln.v2.x / FRACUNIT, ln.v2.y / FRACUNIT)
    v.draw_line(fb, x0, y0, x1, y1, color)
  end
  local ps = M.player_start(self)
  if ps then
    local rad = ps.angle * math.pi / 180
    local x0, y0 = to_screen(ps.x, ps.y)
    local x1, y1 = to_screen(ps.x + math.cos(rad) * 128, ps.y + math.sin(rad) * 128)
    v.draw_line(fb, x0, y0, x1, y1, arrow)
    v.plot(fb, x0, y0, arrow)
  end
end

function M.new()
  return new()
end

return M
