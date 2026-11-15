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
-- Andar, atirar e a pistola na frente da vista, iguais ao Python.

local wad = require("wad")
local rdata = require("r_data")
local world_mod = require("world")
local sprites = require("sprites")
local collision = require("collision")
local player_mod = require("player")
local rng = require("random")
local render = require("render")
local v = require("v_video")

local function eq(name, got, want)
  if got ~= want then
    error(name .. " lua " .. tostring(got) .. " py " .. tostring(want))
  end
end

local w = wad.new()
wad.add_file(w, wad.find_iwad())
local res = rdata.new(w)
rdata.init(res)
res.sprites = sprites.init_defs(w)

local function boot()
  local world = world_mod.new()
  world_mod.setup_level(world, w, res, 1, 1)
  sprites.spawn_things(world, 2)
  collision.link_mobjs(world)
  rng.clear()
  local ps = world_mod.player_start(world)
  local player = player_mod.spawn(world, ps, 0)
  local game = {
    world = world,
    res = res,
    skill = 2,
    start_sound = function() end,
    damage_mobj = player_mod.damage_mobj,
  }
  return world, player, game
end

local world, player, game = boot()
for tic = 0, 34 do
  player.cmd = { forwardmove = 25, sidemove = 0, angleturn = 0, buttons = 0 }
  player_mod.think(world, player, game, tic)
end
local mo = player.mo
eq("x", mo.x, 69200415)
eq("y", mo.y, -222974830)
eq("z", mo.z, 0)
eq("momx", mo.momx, -193)
eq("momy", mo.momy, 479135)
eq("ang", mo.angle, 1073741824)
eq("viewz", player.viewz, 2272651)
eq("arma", player.psprite_state, "ready")
print("andar ok " .. mo.x .. " " .. mo.y)

world, player, game = boot()
for tic = 0, 19 do
  player.cmd = { forwardmove = 0, sidemove = 0, angleturn = 0, buttons = 0 }
  player_mod.think(world, player, game, tic)
end
local r = render.new(res)
render.set_view_size(r, 10, 0)
render.setup_frame(r, player.mo.x, player.mo.y, player.viewz, player.mo.angle, 0, 0)
local fb = v.new_fb()
render.render(r, world, fb)
sprites.draw(r, world, fb)
render.draw_masked(r)
sprites.draw_weapon(r, fb, player, 20)
local f = assert(io.open("_player.bin", "rb"))
local bin = f:read("*a")
f:close()
local bad, ink = 0, 0
for i = 1, 64000 do
  if fb[i] ~= 0 then
    ink = ink + 1
  end
  if fb[i] ~= bin:byte(i) then
    bad = bad + 1
  end
end
if bad ~= 0 then
  error("arma diferente em " .. bad .. " pixels tinta " .. ink)
end
print("arma ok tinta " .. ink)

world, player, game = boot()
for tic = 0, 39 do
  local buttons = 0
  if tic >= 20 then
    buttons = 1
  end
  player.cmd = { forwardmove = 0, sidemove = 0, angleturn = 0, buttons = buttons }
  player_mod.think(world, player, game, tic)
  player_mod.tick_fx(world)
end
local health = 0
for i = 1, #world.mobjs do
  local th = world.mobjs[i]
  if not th.fx and th ~= player.mo then
    health = health + (th.health or 0)
  end
end
eq("municao", player.ammo[0], 49)
eq("vida", health, 79320)
eq("tiro", player.psprite_state, "atk")
print("tiro ok municao " .. player.ammo[0] .. " vida " .. health)
