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
-- Vista do E1M1 igual ao Python. Sem janela.

local wad = require("wad")
local v = require("v_video")
local world_mod = require("world")
local rdata = require("r_data")
local render = require("render")
local sprites = require("sprites")

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
local ps = world_mod.player_start(world)
local x = ps.x * 65536
local y = ps.y * 65536
local ang = math.floor(ps.angle * 536870912 / 45)
local sub = world_mod.point_in_subsector(world, x, y)
local z = sub.sector.floorheight + 41 * 65536
eq("sec", sub.sector.i_sector, 38)
eq("z", z, 2686976)
eq("ang", ang, 1073741824)

local r = render.new(res)
render.set_view_size(r, 10, 0)
render.setup_frame(r, x, y, z, ang, 0, 0)
local fb = v.new_fb()
render.render(r, world, fb)

local f = assert(io.open("_view.bin", "rb"))
local bin = f:read("*a")
f:close()
local bad = 0
local first = nil
local ink = 0
for i = 1, 64000 do
  if fb[i] ~= 0 then
    ink = ink + 1
  end
  if fb[i] ~= bin:byte(i) then
    bad = bad + 1
    if not first then
      first = i
    end
  end
end
if bad ~= 0 then
  local y = math.floor((first - 1) / 320)
  local xpix = (first - 1) % 320
  error(string.format(
    "vista diferente em %d pixels, primeiro %d (%d,%d) lua %d py %d tinta %d",
    bad, first, xpix, y, fb[first], bin:byte(first), ink
  ))
end
print("view ok tinta " .. ink .. " segs " .. #r.drawsegs .. " planos " .. #r.visplanes)

res.sprites = sprites.init_defs(w)
sprites.spawn_things(world, 2)
eq("mobs", #world.mobjs, 91)
sprites.draw(r, world, fb)
render.draw_masked(r)
local fs = assert(io.open("_view_spr.bin", "rb"))
local sprbin = fs:read("*a")
fs:close()
bad = 0
first = nil
ink = 0
for i = 1, 64000 do
  if fb[i] ~= 0 then
    ink = ink + 1
  end
  if fb[i] ~= sprbin:byte(i) then
    bad = bad + 1
    if not first then
      first = i
    end
  end
end
if bad ~= 0 then
  local y = math.floor((first - 1) / 320)
  local xpix = (first - 1) % 320
  error(string.format(
    "sprite diferente em %d pixels, primeiro %d (%d,%d) lua %d py %d tinta %d",
    bad, first, xpix, y, fb[first], sprbin:byte(first), ink
  ))
end
print("sprites ok tinta " .. ink .. " coisas " .. #world.mobjs)
