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
-- Barra, contagem e derretimento. Sem janela.

local wad = require("wad")
local v = require("v_video")
local status_mod = require("status")
local wi_mod = require("wi_stuff")
local wipe_mod = require("wipe")

local function sig(fb)
  local sum, roll = 0, 0
  for i = 1, #fb do
    sum = sum + fb[i]
    roll = (roll * 33 + fb[i]) % 4294967296
  end
  return sum, roll
end

assert(wi_mod.partime(1, 1, false) == 1050, "par E1M1")
assert(wi_mod.partime(1, 2, false) == 75 * 35, "par E1M2")

local wipe = wipe_mod.new()
local fb = v.new_fb()
local start, endfb = {}, {}
for i = 1, v.PIXELS do
  start[i] = 1
  endfb[i] = 2
end
wipe.start = start
wipe.endfb = endfb
wipe.y = {}
for i = 0, 159 do
  wipe.y[i] = 200
end
wipe.y[0] = 0
assert(wipe_mod.tick(wipe, 1, fb) == false, "melt segue")
assert(fb[1] == 2 and fb[2] == 2, "topo novo")
assert(fb[321] == 1, "resto velho")
assert(wipe.y[0] == 1, "coluna andou")
wipe.y[0] = -2
assert(wipe_mod.tick(wipe, 1, fb) == false, "atraso")
assert(wipe.y[0] == -1 and fb[1] == 1, "coluna parada no quadro velho")

local w = wad.new()
wad.add_file(w, wad.find_iwad())
local bar = status_mod.new(w)
local player = {
  health = 100,
  armorpoints = 0,
  readyweapon = 1,
  ammo = { [0] = 50, 0, 0, 0 },
  maxammo = { [0] = 200, 50, 300, 50 },
  weaponowned = { [0] = true, true, false, false, false, false, false, false, false },
  cards = { [0] = false, false, false, false, false, false },
  message = "",
  bonuscount = 0,
  damagecount = 0,
  attackdown = false,
  cheats = 0,
  powers = { [0] = 0, 0, 0, 0, 0, 0 },
  attacker = nil,
  mo = nil,
}
v.fill(fb, 0)
status_mod.draw(bar, fb, player, true)
local sum, roll = sig(fb)
status_mod.ticker(bar, player)
assert(bar.face_index == 0 and bar.face_count == 16 and bar.rnd == 1103527590, "rosto")
v.fill(fb, 0)
status_mod.draw(bar, fb, player, true)
local sum2, roll2 = sig(fb)
assert(sum == 1083692 and roll == 2753326764, "barra")
assert(sum2 == sum and roll2 == roll, "barra depois do tic")

local game = {
  wad = w,
  menu = nil,
  player = nil,
  held = {},
  start_sound = function() end,
  sound = { change_music = function() end },
}
local wi = wi_mod.new(game, {
  epsd = 0,
  last = 0,
  next = 1,
  maxkills = 10,
  maxitems = 5,
  maxsecret = 1,
  partime = 1050,
  skills = 0,
  sitems = 0,
  ssecret = 0,
  stime = 350,
  didsecret = false,
  commercial = false,
})
v.fill(fb, 0)
wi_mod.draw(wi, fb)
local wsum, wroll = sig(fb)
assert(wsum == 8593360 and wroll == 1838591568, "contagem")
game.held = { ["return"] = true }
wi_mod.ticker(wi)
assert(wi.sp_state == 10, "atalho")
assert(wi.cnt_kills == 0 and wi.cnt_items == 0 and wi.cnt_secret == 0, "porcentagem")
assert(wi.cnt_time == 10 and wi.cnt_par == 30, "tempo")

print("hud ok barra 1083692 contagem 8593360")
