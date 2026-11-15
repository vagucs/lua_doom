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
-- Porta, luz e saida do E1M1, iguais ao Python.

local wad = require("wad")
local rdata = require("r_data")
local world_mod = require("world")
local specials_mod = require("specials")
local rng = require("random")

local function eq(name, got, want)
  if got ~= want then
    error(name .. " lua " .. tostring(got) .. " py " .. tostring(want))
  end
end

local w = wad.new()
wad.add_file(w, wad.find_iwad())
local res = rdata.new(w)
rdata.init(res)
local world = world_mod.new()
world_mod.setup_level(world, w, res, 1, 1)
rng.clear()
local spec = specials_mod.new(world, res, { play = function() end })
for _ = 1, 20 do
  specials_mod.tick(spec)
end

local door
for i = 1, #world.lines do
  if world.lines[i].special == 1 then
    door = world.lines[i]
    break
  end
end
eq("fechada", door.sides[2].sector.ceilingheight, 0)
specials_mod.use_special(spec, door, { player = nil }, 0)
for _ = 1, 30 do
  specials_mod.tick(spec)
end
eq("aberta", door.sides[2].sector.ceilingheight, 3932160)

local sum = 0
for i = 1, #world.sectors do
  local s = world.sectors[i]
  sum = (sum + s.floorheight + s.ceilingheight * 3 + s.lightlevel * 5 + s.special * 7 + i) % 1000000007
end
eq("setores", sum, 919240412)

local exit_line
for i = 1, #world.lines do
  if world.lines[i].special == 11 then
    exit_line = world.lines[i]
    break
  end
end
specials_mod.use_special(spec, exit_line, { player = nil }, 0)
eq("textura", exit_line.sides[1].midtexture, 119)
eq("saida", spec.exit_requested, true)
print("setores ok porta 0 -> 3932160 saida true")
