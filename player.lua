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
-- Jogador, gravidade e armas, a partir de player.py.

local compat = require("compat")
local tables = require("tables")
local collision = require("collision")
local rng = require("random")

local M = {}

local band, bnot = compat.band, compat.bnot
local shar = compat.shar
local as_u32 = compat.as_u32
local fixed_mul = compat.fixed_mul

local FRACUNIT = 65536
local ANG90 = 1073741824
local ANG180 = 2147483648
local FINEMASK = 8191
local FINEANGLES = 8192
local FRICTION = 59392
local GRAVITY = FRACUNIT
local STOPSPEED = 4096
local MAXMOVE = 30 * FRACUNIT
local MAXBOB = 1048576
local VIEWHEIGHT = 41 * FRACUNIT
local PLAYER_RADIUS = 16 * FRACUNIT
local PLAYER_HEIGHT = 56 * FRACUNIT
local MELEERANGE = 64 * FRACUNIT
local MISSILERANGE = 32 * 64 * FRACUNIT
local MF_SOLID = 2
local MF_SHOOTABLE = 4
local MF_DROPOFF = 1024
local MF_PICKUP = 2048
local MF_NOCLIP = 4096
local MF_NOGRAVITY = 512
local MF_MISSILE = 65536
local MF_CORPSE = 1048576
local MF_SKULLFLY = 16777216
local MF_SHADOW = 262144
local CF_NOCLIP = 1
local CF_GODMODE = 2
local CF_NOMOMENTUM = 4
local PST_LIVE = 0
local PST_DEAD = 1
local PST_REBORN = 2
local PW_INVULNERABILITY = 0
local PW_STRENGTH = 1
local PW_INVISIBILITY = 2
local PW_IRONFEET = 3
local PW_INFRARED = 5
local BT_ATTACK = 1
local BT_USE = 2
local BT_CHANGE = 4
local BT_WEAPONMASK = 56
local BT_WEAPONSHIFT = 3
local WP_FIST = 0
local WP_PISTOL = 1
local WP_SHOTGUN = 2
local WP_CHAINGUN = 3
local WP_MISSILE = 4
local WP_PLASMA = 5
local WP_BFG = 6
local WP_CHAINSAW = 7
local WP_SUPERSHOTGUN = 8
local WP_NOCHANGE = 10
local AM_CLIP = 0
local AM_SHELL = 1
local AM_CELL = 2
local AM_MISL = 3
local INVERSECOLORMAP = 32
local WEAPONTOP = 32 * FRACUNIT
local WEAPONBOTTOM = 128 * FRACUNIT
local LOWERSPEED = 6 * FRACUNIT
local RAISESPEED = 6 * FRACUNIT
local TICRATE = 35
local MAXHEALTH = 100

local FORWARDMOVE = { [0] = 25, 50 }
local SIDEMOVE = { [0] = 24, 40 }
local ANGLETURN = { [0] = 640, 1280, 320 }

local function has(flags, bit)
  return band(flags or 0, bit) ~= 0
end

local function empty_cmd()
  return { forwardmove = 0, sidemove = 0, angleturn = 0, buttons = 0 }
end

local function trunc2(n)
  n = compat.as_i32(n)
  if n < 0 then
    return -math.floor((-n) / 2)
  end
  return math.floor(n / 2)
end

local WEAPON_AMMO = {
  [WP_PISTOL] = AM_CLIP,
  [WP_SHOTGUN] = AM_SHELL,
  [WP_SUPERSHOTGUN] = AM_SHELL,
  [WP_CHAINGUN] = AM_CLIP,
  [WP_MISSILE] = AM_MISL,
  [WP_PLASMA] = AM_CELL,
  [WP_BFG] = AM_CELL,
}

local WEAPON_PATCH = {
  [WP_FIST] = "PUNGA0",
  [WP_PISTOL] = "PISGA0",
  [WP_SHOTGUN] = "SHTGA0",
  [WP_CHAINGUN] = "CHGGA0",
  [WP_MISSILE] = "MISGA0",
  [WP_PLASMA] = "PLSGA0",
  [WP_BFG] = "BFGGA0",
  [WP_CHAINSAW] = "SAWGC0",
  [WP_SUPERSHOTGUN] = "SHT2A0",
}

local WEAPON_FIRE_BODY = {
  [WP_FIST] = "PUNGC0",
  [WP_PISTOL] = "PISGB0",
  [WP_SHOTGUN] = "SHTGA0",
  [WP_CHAINGUN] = "CHGGB0",
  [WP_MISSILE] = "MISGB0",
  [WP_PLASMA] = "PLSGA0",
  [WP_BFG] = "BFGGB0",
  [WP_CHAINSAW] = "SAWGA0",
  [WP_SUPERSHOTGUN] = "SHT2A0",
}

local WEAPON_ATK = {
  [WP_FIST] = {
    { "PUNGB0", 4, false, "", 0, 0 },
    { "PUNGC0", 4, true, "", 0, 0 },
    { "PUNGD0", 5, false, "", 0, 0 },
    { "PUNGC0", 4, false, "", 0, 0 },
    { "PUNGB0", 5, false, "", 0, 0 },
  },
  [WP_PISTOL] = {
    { "PISGA0", 4, false, "", 0, 0 },
    { "PISGB0", 6, true, "PISFA0", 7, 1 },
    { "PISGC0", 4, false, "", 0, 0 },
    { "PISGB0", 5, false, "", 0, 0 },
  },
  [WP_SHOTGUN] = {
    { "SHTGA0", 3, false, "", 0, 0 },
    { "SHTGA0", 7, true, "SHTFA0", 7, 1 },
    { "SHTGB0", 5, false, "", 0, 0 },
    { "SHTGC0", 5, false, "", 0, 0 },
    { "SHTGD0", 4, false, "", 0, 0 },
    { "SHTGC0", 5, false, "", 0, 0 },
    { "SHTGB0", 5, false, "", 0, 0 },
    { "SHTGA0", 3, false, "", 0, 0 },
    { "SHTGA0", 7, false, "", 0, 0 },
  },
  [WP_CHAINGUN] = {
    { "CHGGA0", 4, true, "CHGFA0", 5, 1 },
    { "CHGGB0", 4, true, "CHGFB0", 5, 2 },
  },
  [WP_MISSILE] = {
    { "MISGB0", 8, false, "MISFA0", 15, 1 },
    { "MISGB0", 12, true, "", 0, 2 },
  },
  [WP_PLASMA] = {
    { "PLSGA0", 3, true, "PLSFA0", 4, 1 },
    { "PLSGB0", 20, false, "", 0, 0, true },
  },
  [WP_BFG] = {
    { "BFGGA0", 20, false, "", 0, 0 },
    { "BFGGB0", 10, false, "BFGFA0", 17, 1 },
    { "BFGGB0", 10, true, "", 0, 2 },
    { "BFGGB0", 20, false, "", 0, 0 },
  },
  [WP_CHAINSAW] = {
    { "SAWGA0", 4, true, "", 0, 0 },
    { "SAWGB0", 4, true, "", 0, 0 },
  },
  [WP_SUPERSHOTGUN] = {
    { "SHT2A0", 3, false, "", 0, 0 },
    { "SHT2A0", 7, true, "SHT2I0", 9, 1 },
    { "SHT2B0", 7, false, "", 0, 0 },
    { "SHT2C0", 7, false, "", 0, 0 },
    { "SHT2D0", 7, false, "", 0, 0 },
    { "SHT2E0", 7, false, "", 0, 0 },
    { "SHT2F0", 7, false, "", 0, 0 },
    { "SHT2G0", 6, false, "", 0, 0 },
    { "SHT2H0", 6, false, "", 0, 0 },
    { "SHT2A0", 5, false, "", 0, 0 },
  },
}

local WEAPON_READY = {
  [WP_CHAINSAW] = {
    { "SAWGC0", 4, "sawidl" },
    { "SAWGD0", 4, "" },
  },
}

function M.damage_mobj(target, source, damage, inflictor)
  if target == nil or target.alive == false or not has(target.flags, MF_SHOOTABLE) then
    return
  end
  if target.player then
    local player = target.player
    if (has(player.cheats, CF_GODMODE) or (player.powers[PW_INVULNERABILITY] or 0) ~= 0) and damage < 1000 then
      return
    end
    local saved = 0
    if (player.armortype or 0) ~= 0 then
      local div = 2
      if player.armortype == 1 then
        div = 3
      end
      saved = math.floor(damage / div)
      if player.armorpoints <= saved then
        saved = player.armorpoints
        player.armortype = 0
      end
      player.armorpoints = player.armorpoints - saved
    end
    damage = damage - saved
    player.health = player.health - damage
    target.health = player.health
    player.damagecount = (player.damagecount or 0) + damage
    if player.damagecount > 100 then
      player.damagecount = 100
    end
    player.attacker = source
    if player.health <= 0 then
      player.health = 0
      target.health = 0
      player.playerstate = PST_DEAD
      target.alive = false
      target.flags = band(target.flags, bnot(MF_SOLID + MF_SHOOTABLE))
    end
    return
  end
  target.health = (target.health or 0) - damage
  if target.health <= 0 then
    target.health = 0
    target.alive = false
    target.flags = band(target.flags, bnot(MF_SOLID + MF_SHOOTABLE))
  end
end

function M.spawn(world, start, cheats)
  tables.init()
  local x = start.x * FRACUNIT
  local y = start.y * FRACUNIT
  local sub = collision.point_in_subsector(world, x, y)
  local flags = MF_SOLID + MF_SHOOTABLE + MF_PICKUP + MF_DROPOFF
  cheats = cheats or 0
  if has(cheats, CF_NOCLIP) then
    flags = compat.bor(flags, MF_NOCLIP)
  end
  local mo = {
    x = x,
    y = y,
    z = sub.sector.floorheight,
    angle = as_u32(math.floor(start.angle / 45) * 536870912),
    momx = 0,
    momy = 0,
    momz = 0,
    radius = PLAYER_RADIUS,
    height = PLAYER_HEIGHT,
    floorz = sub.sector.floorheight,
    ceilingz = sub.sector.ceilingheight,
    flags = flags,
    health = 100,
    type = 0,
    sprite = "PLAY",
    frame = 0,
    alive = true,
    player = nil,
    damage = 0,
  }
  local player = {
    mo = mo,
    cmd = empty_cmd(),
    playerstate = PST_LIVE,
    viewz = mo.z + VIEWHEIGHT,
    viewheight = VIEWHEIGHT,
    deltaviewheight = 0,
    bob = 0,
    health = 100,
    armorpoints = 0,
    armortype = 0,
    ammo = { [0] = 50, 0, 0, 0 },
    maxammo = { [0] = 200, 50, 300, 50 },
    weaponowned = { [0] = true, true, false, false, false, false, false, false, false },
    pendingweapon = WP_NOCHANGE,
    readyweapon = WP_PISTOL,
    cards = { [0] = false, false, false, false, false, false },
    cheats = cheats,
    attackdown = false,
    usedown = false,
    damagecount = 0,
    bonuscount = 0,
    attacker = nil,
    extralight = 0,
    fixedcolormap = 0,
    refire = 0,
    killcount = 0,
    itemcount = 0,
    secretcount = 0,
    psprite_sy = WEAPONBOTTOM,
    psprite_state = "up",
    psprite_tics = 0,
    psprite_step = 0,
    psprite_body = "",
    psprite_flash = "",
    flash_tics = 0,
    powers = { [0] = 0, 0, 0, 0, 0, 0 },
    message = "",
    message_tics = 0,
  }
  mo.player = player
  mo.lastlook = rng.p_random() % 4
  world.mobjs[#world.mobjs + 1] = mo
  collision.set_thing_position(world, mo)
  return player
end

function M.thrust(mo, angle, move)
  mo.momx = mo.momx + fixed_mul(move, tables.fine_cos(angle))
  mo.momy = mo.momy + fixed_mul(move, tables.fine_sin(angle))
end

local function calc_height(player, leveltime)
  local mo = player.mo
  player.bob = math.floor((fixed_mul(mo.momx, mo.momx) + fixed_mul(mo.momy, mo.momy)) / 4)
  if player.bob > MAXBOB then
    player.bob = MAXBOB
  end
  local onground = mo.z <= mo.floorz
  if not onground then
    player.viewz = mo.z + player.viewheight
    if player.viewz > mo.ceilingz - 4 * FRACUNIT then
      player.viewz = mo.ceilingz - 4 * FRACUNIT
    end
    return
  end
  local angle = band(math.floor(FINEANGLES / 20) * leveltime, FINEMASK)
  local bob = fixed_mul(math.floor(player.bob / 2), tables.finesine[angle] or 0)
  if player.playerstate == PST_LIVE then
    player.viewheight = player.viewheight + player.deltaviewheight
    if player.viewheight > VIEWHEIGHT then
      player.viewheight = VIEWHEIGHT
      player.deltaviewheight = 0
    end
    if player.viewheight < math.floor(VIEWHEIGHT / 2) then
      player.viewheight = math.floor(VIEWHEIGHT / 2)
      if player.deltaviewheight <= 0 then
        player.deltaviewheight = 1
      end
    end
    if player.deltaviewheight ~= 0 then
      player.deltaviewheight = player.deltaviewheight + math.floor(FRACUNIT / 4)
    end
  end
  player.viewz = mo.z + player.viewheight + bob
  if player.viewz > mo.ceilingz - 4 * FRACUNIT then
    player.viewz = mo.ceilingz - 4 * FRACUNIT
  end
end

function M.xy_movement(world, mo, game)
  if mo.momx == 0 and mo.momy == 0 then
    if has(mo.flags, MF_SKULLFLY) then
      mo.flags = band(mo.flags, bnot(MF_SKULLFLY))
      mo.momx, mo.momy, mo.momz = 0, 0, 0
    end
    return
  end
  if mo.momx > MAXMOVE then
    mo.momx = MAXMOVE
  elseif mo.momx < -MAXMOVE then
    mo.momx = -MAXMOVE
  end
  if mo.momy > MAXMOVE then
    mo.momy = MAXMOVE
  elseif mo.momy < -MAXMOVE then
    mo.momy = -MAXMOVE
  end
  local xmove, ymove = mo.momx, mo.momy
  local half = math.floor(MAXMOVE / 2)
  while xmove ~= 0 or ymove ~= 0 do
    local ptryx, ptryy
    if xmove > half or ymove > half then
      ptryx = mo.x + trunc2(xmove)
      ptryy = mo.y + trunc2(ymove)
      xmove = trunc2(xmove)
      ymove = trunc2(ymove)
    else
      ptryx = mo.x + xmove
      ptryy = mo.y + ymove
      xmove, ymove = 0, 0
    end
    if has(mo.flags, MF_NOCLIP) then
      collision.unset_thing_position(world, mo)
      mo.x, mo.y = ptryx, ptryy
      collision.set_thing_position(world, mo)
    elseif collision.try_move(world, mo, ptryx, ptryy, game) then
    elseif mo.player then
      collision.slide_move(world, mo, mo.momx, mo.momy, game)
    else
      mo.momx, mo.momy = 0, 0
    end
  end
  local player = mo.player
  if player and has(player.cheats, CF_NOMOMENTUM) then
    mo.momx, mo.momy = 0, 0
    return
  end
  if has(mo.flags, MF_MISSILE + MF_SKULLFLY) then
    return
  end
  if mo.z > mo.floorz then
    return
  end
  if has(mo.flags, MF_CORPSE) then
    local lim = math.floor(FRACUNIT / 4)
    if mo.momx > lim or mo.momx < -lim or mo.momy > lim or mo.momy < -lim then
      local sec = collision.point_in_subsector(world, mo.x, mo.y).sector
      if mo.floorz ~= sec.floorheight then
        return
      end
    end
  end
  local cmd = player and player.cmd
  local idle = player == nil or (cmd.forwardmove == 0 and cmd.sidemove == 0)
  if mo.momx > -STOPSPEED and mo.momx < STOPSPEED and mo.momy > -STOPSPEED and mo.momy < STOPSPEED and idle then
    mo.momx, mo.momy = 0, 0
  else
    mo.momx = fixed_mul(mo.momx, FRICTION)
    mo.momy = fixed_mul(mo.momy, FRICTION)
  end
end

function M.z_movement(mo, world, game)
  local player = mo.player
  if player and mo.z < mo.floorz then
    player.viewheight = player.viewheight - (mo.floorz - mo.z)
    player.deltaviewheight = shar(VIEWHEIGHT - player.viewheight, 3)
  end
  mo.z = mo.z + mo.momz
  if mo.z <= mo.floorz then
    if mo.momz < 0 then
      if player and mo.momz < -GRAVITY * 8 then
        player.deltaviewheight = shar(mo.momz, 3)
        if game and game.start_sound then
          game.start_sound("oof")
        end
      end
      mo.momz = 0
    end
    mo.z = mo.floorz
    if has(mo.flags, MF_SKULLFLY) and not has(mo.flags, MF_MISSILE) then
      mo.momz = -mo.momz
    end
  elseif not has(mo.flags, MF_NOGRAVITY) then
    if mo.momz == 0 then
      mo.momz = -GRAVITY * 2
    else
      mo.momz = mo.momz - GRAVITY
    end
  end
  if mo.z + mo.height > mo.ceilingz then
    if mo.momz > 0 then
      mo.momz = 0
    end
    mo.z = mo.ceilingz - mo.height
    if has(mo.flags, MF_SKULLFLY) then
      mo.momz = -mo.momz
    end
  end
end

local function special_sector(world, player, game, leveltime)
  local mo = player.mo
  if mo == nil then
    return
  end
  local sector = collision.point_in_subsector(world, mo.x, mo.y).sector
  if mo.z ~= sector.floorheight or sector.special == 0 then
    return
  end
  local spec = sector.special
  if spec == 9 then
    player.secretcount = player.secretcount + 1
    sector.special = 0
    return
  end
  if spec == 5 or spec == 7 or spec == 4 or spec == 16 or spec == 11 then
    if (player.powers[PW_IRONFEET] or 0) ~= 0 then
      return
    end
    if band(leveltime, 31) ~= 0 then
      return
    end
    if game and game.damage_mobj then
      local dmg = 0
      if spec == 5 then
        dmg = 10
      elseif spec == 7 then
        dmg = 5
      else
        dmg = 20
      end
      game.damage_mobj(mo, nil, dmg)
    end
  end
end

local function ammo_needed(weapon)
  if weapon == WP_BFG then
    return 40
  end
  return 1
end

local function gun_shot(player, game, accurate)
  local mo = player.mo
  local slope = collision.bullet_slope(game.world, mo)
  local damage = 5 * ((rng.p_random() % 3) + 1)
  local angle = mo.angle
  if not accurate then
    angle = as_u32(angle + (rng.p_random() - rng.p_random()) * 262144)
  end
  return collision.line_attack(game.world, mo, damage, game, MISSILERANGE, angle, slope)
end

local function do_shot(player, game, ammo_type)
  local need = ammo_needed(player.readyweapon)
  if ammo_type ~= nil then
    if player.ammo[ammo_type] < need then
      return
    end
    player.ammo[ammo_type] = player.ammo[ammo_type] - need
  end
  local mo = player.mo
  local weapon = player.readyweapon
  if mo and (weapon == WP_MISSILE or weapon == WP_PLASMA or weapon == WP_BFG) then
    local enemy = require("enemy")
    if weapon == WP_PLASMA then
      if band(rng.p_random(), 1) ~= 0 then
        player.psprite_flash = "PLSFB0"
      else
        player.psprite_flash = "PLSFA0"
      end
      player.flash_tics = 4
    end
    if weapon == WP_MISSILE then
      enemy.spawn_player_missile(game.world, mo, "rocket")
      if game and game.start_sound then
        game.start_sound("rlaunc")
      end
    elseif weapon == WP_PLASMA then
      enemy.spawn_player_missile(game.world, mo, "plasma")
      if game and game.start_sound then
        game.start_sound("plasma")
      end
    else
      enemy.spawn_player_missile(game.world, mo, "bfg")
      if game and game.start_sound then
        game.start_sound("bfg")
      end
    end
    player.refire = player.refire + 1
    player.attackdown = true
    enemy.noise_alert(game.world, mo, game)
    return
  end
  if mo and weapon == WP_FIST then
    local damage = ((rng.p_random() % 10) + 1) * 2
    if (player.powers[PW_STRENGTH] or 0) ~= 0 then
      damage = damage * 10
    end
    local angle = as_u32(mo.angle + (rng.p_random() - rng.p_random()) * 262144)
    local hit = collision.line_attack(game.world, mo, damage, game, MELEERANGE, angle, nil)
    if hit and game and game.start_sound then
      game.start_sound("punch")
    end
  elseif mo and weapon == WP_CHAINSAW then
    local damage = 2 * ((rng.p_random() % 10) + 1)
    local angle = as_u32(mo.angle + (rng.p_random() - rng.p_random()) * 262144)
    local hit = collision.line_attack(game.world, mo, damage, game, MELEERANGE + 1, angle, nil)
    if game and game.start_sound then
      if hit then
        game.start_sound("sawhit")
      else
        game.start_sound("sawful")
      end
    end
  elseif mo and weapon == WP_SHOTGUN then
    if game and game.start_sound then
      game.start_sound("shotgn")
    end
    for _ = 1, 7 do
      gun_shot(player, game, false)
    end
  elseif mo and weapon == WP_SUPERSHOTGUN then
    if game and game.start_sound then
      game.start_sound("dshtgn")
    end
    local slope = collision.bullet_slope(game.world, mo)
    for _ = 1, 20 do
      local damage = 5 * ((rng.p_random() % 3) + 1)
      local angle = as_u32(mo.angle + (rng.p_random() - rng.p_random()) * 524288)
      local pellet = slope + (rng.p_random() - rng.p_random()) * 32
      collision.line_attack(game.world, mo, damage, game, MISSILERANGE, angle, pellet)
    end
  elseif mo then
    if game and game.start_sound then
      game.start_sound("pistol")
    end
    gun_shot(player, game, player.refire == 0)
  end
  player.refire = player.refire + 1
  player.attackdown = true
  if mo then
    local enemy = require("enemy")
    enemy.noise_alert(game.world, mo, game)
  end
end

local function start_ready(player, game)
  player.psprite_state = "ready"
  player.psprite_step = 0
  local seq = WEAPON_READY[player.readyweapon]
  if not seq then
    player.psprite_body = WEAPON_PATCH[player.readyweapon] or "PISGA0"
    player.psprite_tics = 0
    return
  end
  local body, tics, sfx = seq[1][1], seq[1][2], seq[1][3]
  player.psprite_body = body
  player.psprite_tics = tics
  if sfx ~= "" and game and game.start_sound then
    game.start_sound(sfx)
  end
end

local function tick_ready(player, game)
  local seq = WEAPON_READY[player.readyweapon]
  if not seq then
    player.psprite_body = WEAPON_PATCH[player.readyweapon] or "PISGA0"
    return
  end
  if player.psprite_tics > 0 then
    player.psprite_tics = player.psprite_tics - 1
    if player.psprite_tics > 0 then
      return
    end
    player.psprite_step = (player.psprite_step + 1) % #seq
  end
  local row = seq[player.psprite_step + 1]
  player.psprite_body = row[1]
  player.psprite_tics = row[2]
  if row[3] ~= "" and game and game.start_sound then
    game.start_sound(row[3])
  end
end

local function enter_atk_step(player, game, ammo_type, firing, can_fire)
  local seq = WEAPON_ATK[player.readyweapon] or WEAPON_ATK[WP_PISTOL]
  while true do
    if player.psprite_step >= #seq then
      if firing and can_fire and player.pendingweapon == WP_NOCHANGE then
        player.psprite_step = 0
      else
        start_ready(player, game)
        if not firing then
          player.attackdown = false
          player.refire = 0
        end
        return
      end
    else
      local row = seq[player.psprite_step + 1]
      if row[7] and firing and can_fire and player.pendingweapon == WP_NOCHANGE and (player.health or 0) > 0 then
        player.psprite_step = 0
      else
        player.psprite_body = row[1]
        player.psprite_tics = row[2]
        if row[5] ~= 0 then
          player.psprite_flash = row[4]
          player.flash_tics = row[5]
        end
        if row[6] ~= 0 then
          player.extralight = row[6]
        end
        if row[3] then
          do_shot(player, game, ammo_type)
        end
        if row[2] > 0 then
          return
        end
        player.psprite_step = player.psprite_step + 1
      end
    end
  end
end

local function lower_weapon(player, game)
  player.psprite_state = "down"
  if player.psprite_body == "" then
    player.psprite_body = WEAPON_PATCH[player.readyweapon] or "PISGA0"
  end
  player.psprite_sy = player.psprite_sy + LOWERSPEED
  if player.psprite_sy < WEAPONBOTTOM then
    return
  end
  player.psprite_sy = WEAPONBOTTOM
  if player.playerstate == PST_DEAD or player.health <= 0 then
    return
  end
  if player.pendingweapon ~= WP_NOCHANGE then
    player.readyweapon = player.pendingweapon
    player.pendingweapon = WP_NOCHANGE
  end
  if player.readyweapon == WP_CHAINSAW and game and game.start_sound then
    game.start_sound("sawup")
  end
  player.psprite_state = "up"
  player.psprite_body = WEAPON_PATCH[player.readyweapon] or "PISGA0"
end

local function raise_weapon(player, game)
  player.psprite_sy = player.psprite_sy - RAISESPEED
  if player.psprite_body == "" then
    player.psprite_body = WEAPON_PATCH[player.readyweapon] or "PISGA0"
  end
  if player.psprite_sy > WEAPONTOP then
    return
  end
  player.psprite_sy = WEAPONTOP
  start_ready(player, game)
end

local function weapon_think(player, game)
  if player.playerstate == PST_DEAD or player.health <= 0 then
    lower_weapon(player, game)
    return
  end
  local cmd = player.cmd
  local firing = band(cmd.buttons, BT_ATTACK) ~= 0
  local ammo_type = WEAPON_AMMO[player.readyweapon]
  local can_fire = true
  local need = ammo_needed(player.readyweapon)
  if ammo_type ~= nil and player.ammo[ammo_type] < need then
    can_fire = player.readyweapon == WP_FIST or player.readyweapon == WP_CHAINSAW
    if not can_fire then
      local order = { WP_PISTOL, WP_SHOTGUN, WP_CHAINGUN, WP_MISSILE, WP_PLASMA, WP_BFG, WP_FIST }
      for i = 1, #order do
        local w = order[i]
        local at = WEAPON_AMMO[w]
        if player.weaponowned[w] and (at == nil or player.ammo[at] >= ammo_needed(w)) then
          player.pendingweapon = w
          break
        end
      end
      ammo_type = WEAPON_AMMO[player.readyweapon]
      can_fire = ammo_type == nil or player.ammo[ammo_type] >= ammo_needed(player.readyweapon)
    end
  end
  if player.flash_tics > 0 then
    player.flash_tics = player.flash_tics - 1
    if player.flash_tics <= 0 then
      player.psprite_flash = ""
      player.extralight = 0
    end
  end
  if player.psprite_state == "fire" then
    player.psprite_state = "atk"
  end
  if player.psprite_state == "atk" then
    if firing then
      player.attackdown = true
    end
    if player.psprite_tics > 0 then
      player.psprite_tics = player.psprite_tics - 1
    end
    if player.psprite_tics > 0 then
      return
    end
    player.psprite_step = player.psprite_step + 1
    enter_atk_step(player, game, ammo_type, firing, can_fire)
    return
  end
  if player.pendingweapon ~= WP_NOCHANGE or player.psprite_state == "down" then
    lower_weapon(player, game)
    return
  end
  if player.psprite_state == "up" then
    raise_weapon(player, game)
    return
  end
  if firing and can_fire then
    local ready_gate = (not player.attackdown) or (player.readyweapon ~= WP_MISSILE and player.readyweapon ~= WP_BFG)
    if ready_gate then
      player.psprite_state = "atk"
      player.psprite_step = 0
      player.psprite_sy = WEAPONTOP
      player.attackdown = true
      enter_atk_step(player, game, ammo_type, firing, can_fire)
      return
    end
  end
  if player.psprite_state ~= "ready" then
    start_ready(player, game)
    return
  end
  tick_ready(player, game)
  if not firing then
    player.attackdown = false
    player.refire = 0
  end
end

local function death_think(world, player, game, leveltime)
  local mo = player.mo
  local cmd = player.cmd
  if player.viewheight > 6 * FRACUNIT then
    player.viewheight = player.viewheight - FRACUNIT
  end
  if player.viewheight < 6 * FRACUNIT then
    player.viewheight = 6 * FRACUNIT
  end
  player.deltaviewheight = 0
  M.xy_movement(world, mo, game)
  M.z_movement(mo, world, game)
  calc_height(player, leveltime)
  if player.attacker and player.attacker ~= mo then
    local angle = collision.angle_to(mo.x, mo.y, player.attacker.x, player.attacker.y)
    local delta = as_u32(angle - mo.angle)
    local ang5 = math.floor(ANG90 / 18)
    if delta < as_u32(ang5) or delta > as_u32(-ang5) then
      mo.angle = angle
      if player.damagecount ~= 0 then
        player.damagecount = player.damagecount - 1
      end
    elseif delta < as_u32(ANG180) then
      mo.angle = as_u32(mo.angle + ang5)
    else
      mo.angle = as_u32(mo.angle - ang5)
    end
  elseif player.damagecount ~= 0 then
    player.damagecount = player.damagecount - 1
  end
  weapon_think(player, game)
  if band(cmd.buttons, BT_USE) ~= 0 then
    player.playerstate = PST_REBORN
  end
end

function M.think(world, player, game, leveltime)
  local mo = player.mo
  local cmd = player.cmd
  if player.playerstate == PST_DEAD then
    death_think(world, player, game, leveltime)
    return
  end
  mo.angle = as_u32(mo.angle + cmd.angleturn * 65536)
  local onground = mo.z <= mo.floorz
  if cmd.forwardmove ~= 0 and onground then
    M.thrust(mo, mo.angle, cmd.forwardmove * 2048)
  end
  if cmd.sidemove ~= 0 and onground then
    M.thrust(mo, as_u32(mo.angle - ANG90), cmd.sidemove * 2048)
  end
  M.xy_movement(world, mo, game)
  M.z_movement(mo, world, game)
  calc_height(player, leveltime)
  special_sector(world, player, game, leveltime)
  if band(cmd.buttons, BT_USE) ~= 0 then
    if not player.usedown then
      collision.use_lines(world, player, game)
      player.usedown = true
    end
  else
    player.usedown = false
  end
  if band(cmd.buttons, BT_CHANGE) ~= 0 then
    local neww = math.floor(band(cmd.buttons, BT_WEAPONMASK) / (2 ^ BT_WEAPONSHIFT))
    if neww >= 0 and neww <= WP_SUPERSHOTGUN and player.weaponowned[neww] and neww ~= player.readyweapon then
      player.pendingweapon = neww
    end
  end
  weapon_think(player, game)
  if (player.powers[PW_STRENGTH] or 0) ~= 0 then
    player.powers[PW_STRENGTH] = player.powers[PW_STRENGTH] + 1
  end
  if (player.powers[PW_INVULNERABILITY] or 0) ~= 0 then
    player.powers[PW_INVULNERABILITY] = player.powers[PW_INVULNERABILITY] - 1
  end
  if (player.powers[PW_INVISIBILITY] or 0) ~= 0 then
    player.powers[PW_INVISIBILITY] = player.powers[PW_INVISIBILITY] - 1
    if player.powers[PW_INVISIBILITY] == 0 then
      mo.flags = band(mo.flags, bnot(MF_SHADOW))
    end
  end
  if (player.powers[PW_INFRARED] or 0) ~= 0 then
    player.powers[PW_INFRARED] = player.powers[PW_INFRARED] - 1
  end
  if (player.powers[PW_IRONFEET] or 0) ~= 0 then
    player.powers[PW_IRONFEET] = player.powers[PW_IRONFEET] - 1
  end
  local inv = player.powers[PW_INVULNERABILITY] or 0
  local ir = player.powers[PW_INFRARED] or 0
  if inv ~= 0 then
    if inv > 4 * 32 or band(inv, 8) ~= 0 then
      player.fixedcolormap = INVERSECOLORMAP
    else
      player.fixedcolormap = 0
    end
  elseif ir ~= 0 then
    if ir > 4 * 32 or band(ir, 8) ~= 0 then
      player.fixedcolormap = 1
    else
      player.fixedcolormap = 0
    end
  else
    player.fixedcolormap = 0
  end
  if player.damagecount ~= 0 then
    player.damagecount = player.damagecount - 1
  end
  if player.bonuscount ~= 0 then
    player.bonuscount = player.bonuscount - 1
  end
  if player.message_tics ~= 0 then
    player.message_tics = player.message_tics - 1
    if player.message_tics <= 0 then
      player.message = ""
    end
  end
end

function M.tick_fx(world)
  local src = world.mobjs or {}
  local keep = {}
  for i = 1, #src do
    local mo = src[i]
    if mo.fx then
      mo.tics = (mo.tics or 1) - 1
      if mo.tics > 0 then
        keep[#keep + 1] = mo
      end
    else
      keep[#keep + 1] = mo
    end
  end
  world.mobjs = keep
end

function M.set_message(player, text)
  if player == nil then
    return
  end
  player.message = text or ""
  player.message_tics = 4 * 35
end

function M.give_power(player, power)
  if player == nil then
    return false
  end
  if power == PW_INVULNERABILITY then
    player.powers[power] = 30 * 35
    return true
  end
  if power == PW_INVISIBILITY then
    player.powers[power] = 60 * 35
    if player.mo then
      player.mo.flags = compat.bor(player.mo.flags, MF_SHADOW)
    end
    return true
  end
  if power == PW_INFRARED then
    player.powers[power] = 120 * 35
    return true
  end
  if power == PW_IRONFEET then
    player.powers[power] = 60 * 35
    return true
  end
  if power == PW_STRENGTH then
    if player.health < 100 then
      player.health = math.min(100, player.health + 100)
      if player.mo then
        player.mo.health = player.health
      end
    end
    player.powers[power] = 1
    return true
  end
  if (player.powers[power] or 0) ~= 0 then
    return false
  end
  player.powers[power] = 1
  return true
end

function M.build_ticcmd(held, turnheld, player, mousex, mousey, sensitivity, mouse_fire)
  local cmd = empty_cmd()
  local speed = 0
  if held.shift then
    speed = 1
  end
  local strafe = held.alt and true or false
  local turning = held.right or held.left
  local held_count = 0
  if turning then
    held_count = turnheld + 1
  end
  local tspeed = speed
  if held_count < 6 then
    tspeed = 2
  end
  if strafe then
    if held.right then
      cmd.sidemove = cmd.sidemove + SIDEMOVE[speed]
    end
    if held.left then
      cmd.sidemove = cmd.sidemove - SIDEMOVE[speed]
    end
  else
    if held.right then
      cmd.angleturn = cmd.angleturn - ANGLETURN[tspeed]
    end
    if held.left then
      cmd.angleturn = cmd.angleturn + ANGLETURN[tspeed]
    end
  end
  if held.up then
    cmd.forwardmove = cmd.forwardmove + FORWARDMOVE[speed]
  end
  if held.down then
    cmd.forwardmove = cmd.forwardmove - FORWARDMOVE[speed]
  end
  if held.comma then
    cmd.sidemove = cmd.sidemove - SIDEMOVE[speed]
  end
  if held.period then
    cmd.sidemove = cmd.sidemove + SIDEMOVE[speed]
  end
  if held.ctrl then
    cmd.buttons = compat.bor(cmd.buttons, BT_ATTACK)
  end
  if held.space or held.e then
    cmd.buttons = compat.bor(cmd.buttons, BT_USE)
  end
  local picked = nil
  if held["1"] then
    if player and player.readyweapon == WP_CHAINSAW then
      picked = WP_FIST
    elseif player and player.weaponowned[WP_CHAINSAW] then
      picked = WP_CHAINSAW
    else
      picked = WP_FIST
    end
  elseif held["2"] then
    picked = WP_PISTOL
  elseif held["3"] then
    picked = WP_SHOTGUN
  elseif held["4"] then
    picked = WP_CHAINGUN
  elseif held["5"] then
    picked = WP_MISSILE
  elseif held["6"] then
    picked = WP_PLASMA
  elseif held["7"] then
    picked = WP_BFG
  end
  if picked ~= nil then
    cmd.buttons = compat.bor(cmd.buttons, BT_CHANGE + picked * (2 ^ BT_WEAPONSHIFT))
  end
  if mousex ~= nil or mousey ~= nil or mouse_fire then
    local sens = ((sensitivity or 5) + 5) / 10
    local function trunc(n)
      if n >= 0 then
        return math.floor(n)
      end
      return math.ceil(n)
    end
    local function clamp(n)
      if n > 127 then
        return 127
      end
      if n < -127 then
        return -127
      end
      return n
    end
    local mx = trunc((mousex or 0) * sens)
    local my = trunc((mousey or 0) * sens)
    cmd.forwardmove = clamp(cmd.forwardmove + my)
    if strafe then
      cmd.sidemove = clamp(cmd.sidemove + mx * 2)
    else
      cmd.angleturn = cmd.angleturn - mx * 8
    end
    if mouse_fire then
      cmd.buttons = compat.bor(cmd.buttons, BT_ATTACK)
    end
  end
  return cmd, held_count
end

function M.weapon_body(player)
  if player.psprite_body ~= "" then
    return player.psprite_body
  end
  if player.psprite_state == "atk" or player.psprite_state == "fire" then
    return WEAPON_FIRE_BODY[player.readyweapon] or WEAPON_PATCH[player.readyweapon] or "PISGA0"
  end
  return WEAPON_PATCH[player.readyweapon] or "PISGA0"
end

local KEY_CARD = {
  [5] = 0,
  [6] = 1,
  [13] = 2,
  [40] = 3,
  [39] = 4,
  [38] = 5,
}

function M.take_key(special, toucher)
  local player = toucher and toucher.player
  if not player or special.alive == false then
    return false
  end
  local card = KEY_CARD[special.doomednum]
  if card == nil then
    return false
  end
  player.cards[card] = true
  special.alive = false
  special.flags = 0
  special.sprite = ""
  return true
end

M.WEAPONBOTTOM = WEAPONBOTTOM
M.PST_DEAD = PST_DEAD
M.PST_REBORN = PST_REBORN
M.WP_FIST = WP_FIST
M.WP_CHAINSAW = WP_CHAINSAW
M.empty_cmd = empty_cmd

return M
