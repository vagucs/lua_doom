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
-- Cheats, automapa, finale e save. Sem janela.

local am_map = require("am_map")
local cheats = require("cheats")
local finale_mod = require("finale")
local player_mod = require("player")
local rdata = require("r_data")
local saveg = require("saveg")
local v = require("v_video")
local wad = require("wad")
local world_mod = require("world")

local function eq(name, got, want)
  if got ~= want then
    error(name .. " got " .. tostring(got) .. " want " .. tostring(want))
  end
end

local function feed(box, text, game)
  for i = 1, #text do
    cheats.feed(box, text:sub(i, i), game)
  end
end

local function fresh_player()
  return {
    cheats = 0,
    health = 50,
    armorpoints = 0,
    armortype = 0,
    mo = { health = 50, flags = 0, angle = 90, x = 16, y = 32 },
    powers = { [0] = 0, 0, 0, 0, 0, 0 },
    weaponowned = { [0] = true, true, false, false, false, false, false, false, false },
    ammo = { [0] = 10, 0, 0, 0 },
    maxammo = { [0] = 200, 50, 300, 50 },
    cards = { [0] = false, false, false, false, false, false },
    message = "",
    message_tics = 0,
    readyweapon = 1,
    pendingweapon = 10,
  }
end

local w = wad.new()
wad.add_file(w, wad.find_iwad())
local game = {
  gamestate = "view",
  skill = 2,
  wad = w,
  sound = { change_music = function() end, play = function() end },
}
local p = fresh_player()
game.player = p
local box = cheats.new()
feed(box, "iddqd", game)
eq("god", p.cheats, 2)
eq("godmsg", p.message, "Degreelessness Mode On")
eq("godhp", p.health, 100)

p = fresh_player()
game.player = p
game.skill = 4
box = cheats.new()
feed(box, "iddqd", game)
eq("nightmare", p.cheats, 0)
game.skill = 2

p = fresh_player()
game.player = p
box = cheats.new()
feed(box, "idkfa", game)
eq("ammo", p.ammo[0], 200)
eq("card", p.cards[0], true)
eq("saw", p.weaponowned[7], true)

local text = saveg.encode({
  { "episode", 1 },
  { "name", "E1M1" },
  { "ok", true },
  { "ammo", (function()
    local a = { 50, 0 }
    a._json = "array"
    return a
  end)() },
})
local decoded = saveg.decode(text)
eq("json ep", decoded.episode, 1)
eq("json name", decoded.name, "E1M1")
eq("json ok", decoded.ok, true)
eq("json ammo", decoded.ammo[1], 50)

local res = rdata.new(w)
rdata.init(res)
local world = world_mod.new()
world_mod.setup_level(world, w, res, 1, 1)
local start = world_mod.player_start(world)
local player = player_mod.spawn(world, start)
game.world = world
game.player = player
game.mapn = 1
game.episode = 1
game.res = res
local am = am_map.new()
am_map.start(am, game)
am.cheating = 1
local fb = v.new_fb()
am_map.drawer(am, fb, game)
local ink = 0
for i = 1, 320 * 168 do
  if fb[i] ~= 0 then
    ink = ink + 1
  end
end
if ink < 1000 then
  error("automapa tinta " .. tostring(ink))
end

local fin = finale_mod.new(game)
eq("texto", fin.text:sub(1, 8), "Once you")
eq("flat", fin.flat, "FLOOR4_8")
for _ = 1, 3 do
  finale_mod.ticker(fin)
end
eq("count", fin.count, 3)
v.fill(fb, 0)
finale_mod.draw(fin, fb)
local letters = 0
for i = 1, 320 * 40 do
  if fb[i] ~= 0 then
    letters = letters + 1
  end
end
if letters < 10 then
  error("finale sem letras " .. tostring(letters))
end

local dir = (os.getenv("TEMP") or ".") .. "\\doomphase14"
os.execute('mkdir "' .. dir .. '" >nul 2>&1')
game.iwad_path = dir .. "\\DOOM1.WAD"
game.leveltime = 35
local wrote = saveg.write(game, 0, "E1M1")
eq("gravou", wrote, true)
local desc, ok = saveg.description(game, 0)
eq("desc", desc, "E1M1")
eq("slot", ok, true)
local data = saveg.read(game, 0)
eq("save ep", data.episode, 1)
eq("save map", data.mapn, 1)
eq("save hp", data.player.health, 100)
eq("save time", data.leveltime, 35)
os.remove(saveg.path(game, 0))

print(string.format("fase14 ok cheats mapa %d finale %d", ink, letters))
