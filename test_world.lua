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
-- Teste do mapa E1M1. Sem janela.

local wad = require("wad")
local v = require("v_video")
local world_mod = require("world")
local rdata = require("r_data")

local function eq(name, got, want)
  if got ~= want then
    error(name .. " got " .. tostring(got) .. " want " .. tostring(want))
  end
end

local w = wad.new()
wad.add_file(w, wad.find_iwad())
local res = rdata.new(w)
rdata.init(res)
local world = world_mod.new()
world_mod.setup_level(world, w, res, 1, 1)

eq("map", world.mapname, "E1M1")
eq("vertexes", #world.vertexes, 467)
eq("sectors", #world.sectors, 85)
eq("sides", #world.sides, 648)
eq("lines", #world.lines, 475)
eq("segs", #world.segs, 732)
eq("subsectors", #world.subsectors, 237)
eq("nodes", #world.nodes, 236)
eq("things", #world.things, 138)
eq("numnodes", world.numnodes, 236)

local v0 = world.vertexes[1]
eq("v0x", v0.x, 71303168)
eq("v0y", v0.y, -241172480)

local sec = world.sectors[1]
eq("floor", sec.floorheight, 0)
eq("ceil", sec.ceilingheight, 4718592)
eq("light", sec.lightlevel, 160)
eq("seclines", #sec.lines, 4)

local marker = wad.get_num_for_name(w, "E1M1")
local secdata = wad.cache_lump_num(w, marker + 8)
local function name8(data, off)
  local raw = data:sub(off + 1, off + 8)
  local zero = raw:find("\0", 1, true)
  if zero then
    raw = raw:sub(1, zero - 1)
  end
  return (raw:gsub("%s+$", "")):upper()
end
eq("floorflat", sec.floorflat, name8(secdata, 4))
eq("ceilflat", sec.ceilingflat, name8(secdata, 12))

local ln = world.lines[1]
eq("flags", ln.flags, 1)
eq("dx", ln.dx, -4194304)
eq("dy", ln.dy, 0)
eq("s0", ln.sidenum[1], 0)
eq("s1", ln.sidenum[2], -1)
eq("bleft", ln.bbox[1], 67108864)
eq("bright", ln.bbox[2], 71303168)
eq("bbot", ln.bbox[3], -241172480)
eq("btop", ln.bbox[4], -241172480)
eq("front", ln.frontsector.i_sector, 40)
if ln.backsector then
  error("linha 0 tem fundo")
end

local sg = world.segs[1]
eq("angle", sg.angle, 1073741824)
eq("offset", sg.offset, 0)
eq("segfront", sg.frontsector.i_sector, 0)
eq("segback", sg.backsector.i_sector, 4)

local nd = world.nodes[1]
eq("nx", nd.x, 101711872)
eq("ny", nd.y, -159383552)
eq("ndx", nd.dx, 7340032)
eq("ndy", nd.dy, 0)
eq("c0", nd.children[1], 32768)
eq("c1", nd.children[2], 32769)
eq("ntop", nd.bbox[1][1], -159383552)
eq("nbot", nd.bbox[1][2], -167772160)
eq("nleft", nd.bbox[1][3], 101711872)
eq("nright", nd.bbox[1][4], 109051904)

local th = world.things[1]
eq("tx", th.x, 1056)
eq("ty", th.y, -3616)
eq("ta", th.angle, 90)
eq("tt", th.type, 1)
eq("to", th.options, 7)
local ps = world_mod.player_start(world)
eq("px", ps.x, 1056)
eq("py", ps.y, -3616)

eq("bmapx", world.bmaporgx, -50855936)
eq("bmapy", world.bmaporgy, -319291392)
eq("bmapw", world.bmapwidth, 36)
eq("bmaph", world.bmapheight, 23)
eq("bmapn", #world.blockmap, 828)
eq("blump", #world.blockmaplump, 3461)
eq("boff", world.blockmap[1], 832)
eq("reject", #world.rejectmatrix, 904)
eq("r0", world.rejectmatrix:byte(1), 32)
eq("ssn", world.subsectors[1].numlines, 4)
eq("ssf", world.subsectors[1].firstline, 0)
eq("sss", world.subsectors[1].sector.i_sector, 0)
eq("side0", world.sides[1].sector.i_sector, 40)
eq("floorpic", world.sectors[1].floorpic, 10)
eq("ceilpic", world.sectors[1].ceilingpic, 32)
eq("midtex", world.sides[1].midtexture, 30)
eq("door", res.textures[world.sides[1].midtexture + 1].name, "DOOR3")

local fb = v.new_fb()
local pal = wad.cache_lump_name(w, "PLAYPAL")
world_mod.draw_overhead(world, fb, pal)
local ink = 0
for i = 1, #fb do
  if fb[i] ~= 0 then
    ink = ink + 1
  end
end
if ink < 1000 then
  error("planta quase vazia: " .. tostring(ink))
end
local seen = {}
local kinds = 0
for i = 1, #fb do
  local c = fb[i]
  if c ~= 0 and not seen[c] then
    seen[c] = true
    kinds = kinds + 1
  end
end
if kinds < 4 then
  error("planta com poucas cores: " .. tostring(kinds))
end
print("world ok E1M1 linhas " .. #world.lines .. " tinta " .. ink .. " cores " .. kinds)
