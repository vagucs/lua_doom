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
-- Inimigos do E1M1 depois de 20 tics parados, iguais ao Python.

local wad = require("wad")
local rdata = require("r_data")
local world_mod = require("world")
local sprites = require("sprites")
local player_mod = require("player")
local specials_mod = require("specials")
local thinker = require("thinker")
local enemy = require("enemy")
local rng = require("random")

local function sig(world)
  local n = 0
  for i = 1, #world.mobjs do
    local mo = world.mobjs[i]
    if not mo.player and not mo.fx then
      n = (n + (mo.type or 0) + (mo.x or 0) + (mo.y or 0) * 3 + (mo.z or 0) * 5
        + (mo.health or 0) * 7 + (mo.frame or 0) * 11 + (mo.flags or 0) * 13
        + (mo.istate or 0) * 17 + (mo.height or 0) + i) % 1000000007
      if mo.sprite then
        n = (n + #mo.sprite * 19) % 1000000007
      end
    end
  end
  return n
end

local w = wad.new()
wad.add_file(w, wad.find_iwad())
local res = rdata.new(w)
rdata.init(res)
res.sprites = sprites.init_defs(w)
rng.clear()
local world = world_mod.new()
world_mod.setup_level(world, w, res, 1, 1)
local game = {
  skill = 2,
  episode = 1,
  mapn = 1,
  wad = w,
  res = res,
  world = world,
  leveltime = 0,
  player = nil,
  fastparm = false,
  start_sound = function() end,
}
game.specials = specials_mod.new(world, res, { play = function() end })
function game.damage_mobj(target, source, damage, inflictor)
  enemy.damage_mobj(game, target, source, damage, inflictor)
end
function game.use_special(line, thing, side)
  return specials_mod.use_special(game.specials, line, thing, side)
end
thinker.spawn_map(world, 2, game)
thinker.apply_fast(game)
for _ = 1, 20 do
  game.player.cmd = player_mod.empty_cmd()
  player_mod.think(world, game.player, game, game.leveltime)
  thinker.tick(world, game)
  specials_mod.tick(game.specials)
  game.leveltime = game.leveltime + 1
end
local idle = sig(world)
local victim = nil
for i = 1, #world.mobjs do
  local mo = world.mobjs[i]
  if mo.sprite == "POSS" and (mo.health or 0) > 0 then
    victim = mo
    break
  end
end
game.damage_mobj(victim, game.player.mo, 10000, game.player.mo)
local dead = victim.sprite .. "," .. tostring(victim.frame) .. "," .. tostring(victim.health) .. "," .. tostring(victim.height) .. "," .. tostring(victim.flags)
if idle ~= 357442092 then
  error("posicao lua " .. tostring(idle) .. " py 357442092")
end
if dead ~= "POSS,12,-9980,917504,5243938" then
  error("corpo lua " .. dead)
end
print("inimigos ok corpo POSS")
