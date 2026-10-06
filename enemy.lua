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
-- Olhar, perseguir, atacar e cair, a partir de enemy.py.

local compat = require("compat")
local collision = require("collision")
local info = require("info")
local rng = require("random")
local tables = require("tables")

local M = {}

local band, bor, bnot = compat.band, compat.bor, compat.bnot
local shar = compat.shar
local as_i32, as_u32 = compat.as_i32, compat.as_u32
local fixed_mul = compat.fixed_mul

local FRACUNIT = 65536
local ANG45 = 536870912
local ANG90 = 1073741824
local ANG180 = 2147483648
local ANG270 = 3221225472
local FRICTION = 59392
local GRAVITY = FRACUNIT
local MAXMOVE = 30 * FRACUNIT
local MELEERANGE = 64 * FRACUNIT
local MISSILERANGE = 32 * 64 * FRACUNIT
local SKULLSPEED = 20 * FRACUNIT
local STOPSPEED = 4096
local FLOATSPEED = 4 * FRACUNIT
local TRACEANGLE = 201326592
local FATSPREAD = math.floor(ANG90 / 8)
local MAX_SKULLS = 21
local VIEWHEIGHT = 41 * FRACUNIT

local MF_AMBUSH = 32
local MF_CORPSE = 1048576
local MF_COUNTKILL = 4194304
local MF_DROPOFF = 1024
local MF_DROPPED = 131072
local MF_FLOAT = 16384
local MF_INFLOAT = 2097152
local MF_JUSTHIT = 64
local MF_JUSTATTACKED = 128
local MF_MISSILE = 65536
local MF_NOCLIP = 4096
local MF_NOGRAVITY = 512
local MF_SHADOW = 262144
local MF_SHOOTABLE = 4
local MF_SKULLFLY = 16777216
local MF_SOLID = 2
local ML_SOUNDBLOCK = 64
local ML_TWOSIDED = 4
local SK_EASY = 1
local SK_NIGHTMARE = 4
local CF_NOMOMENTUM = 4
local VLD_BLAZEOPEN = 6
local WP_CHAINSAW = 7

local DI_EAST, DI_NE, DI_NORTH, DI_NW = 0, 1, 2, 3
local DI_WEST, DI_SW, DI_SOUTH, DI_SE = 4, 5, 6, 7
local DI_NODIR = 8
local XSPEED = { [0] = FRACUNIT, 47000, 0, -47000, -FRACUNIT, -47000, 0, 47000 }
local YSPEED = { [0] = 0, 47000, FRACUNIT, 47000, 0, -47000, -FRACUNIT, -47000 }
local OPPOSITE = { [0] = 4, 5, 6, 7, 0, 1, 2, 3, 8 }
local DIAGS = { [0] = DI_NW, DI_NE, DI_SW, DI_SE }

local brain_target_on = 0
local brain_targets = {}

M.p_random = rng.p_random

local function mi(mo)
  return info.MOBJINFO[mo.type]
end

local function play(game, name)
  if game and game.start_sound and name ~= nil and name ~= "" then
    game.start_sound(name)
  end
end

local function trunc(n)
  if n >= 0 then
    return math.floor(n)
  end
  return math.ceil(n)
end

local function has(flags, bit)
  return band(flags or 0, bit) ~= 0
end

function M.kill_monster(mo, game, source)
  local thinker = require("thinker")
  local row = mi(mo)
  mo.flags = band(mo.flags, bnot(MF_SHOOTABLE + MF_FLOAT + MF_SKULLFLY))
  mo.flags = bor(mo.flags, MF_CORPSE + MF_DROPOFF)
  mo.height = math.floor(mo.height / 4)
  if source ~= nil and source.player ~= nil and has(mo.flags, MF_COUNTKILL) then
    source.player.killcount = (source.player.killcount or 0) + 1
  end
  local st = row[info.MI_DEATHSTATE]
  local xds = row[info.MI_XDEATHSTATE]
  if mo.health < -row[info.MI_SPAWNHEALTH] and xds ~= 0 then
    st = xds
  end
  thinker.set_mobj_state(mo, st, game.world, game)
  if mo.alive == false then
    return
  end
  mo.tics = mo.tics - band(rng.p_random(), 3)
  if mo.tics < 1 then
    mo.tics = 1
  end
  local drop = nil
  if mo.type == info.MT_POSSESSED then
    drop = info.MT_CLIP
  elseif mo.type == info.MT_SHOTGUY then
    drop = info.MT_SHOTGUN
  elseif mo.type == info.MT_CHAINGUY then
    drop = info.MT_CHAINGUN
  end
  if drop ~= nil then
    local item = thinker.spawn_mobj(game.world, mo.x, mo.y, thinker.ONFLOORZ, drop, game)
    item.flags = bor(item.flags, MF_DROPPED)
  end
end

function M.pain_or_wake(game, target, source)
  local thinker = require("thinker")
  local row = info.MOBJINFO[target.type]
  if rng.p_random() < row[info.MI_PAINCHANCE] and not has(target.flags, MF_SKULLFLY) then
    target.flags = bor(target.flags, MF_JUSTHIT)
    if row[info.MI_PAINSTATE] ~= 0 then
      thinker.set_mobj_state(target, row[info.MI_PAINSTATE], game.world, game)
    end
  end
  target.reactiontime = 0
  if source ~= nil and source ~= target and target.player == nil then
    target.target = source
    if target.istate == row[info.MI_SPAWNSTATE] and row[info.MI_SEESTATE] ~= 0 then
      thinker.set_mobj_state(target, row[info.MI_SEESTATE], game.world, game)
    end
  end
end

function M.damage_mobj(game, target, source, damage, inflictor)
  if target == nil or target.alive == false or not has(target.flags, MF_SHOOTABLE) then
    return
  end
  if target.player and game.skill == 0 then
    damage = math.floor(damage / 2)
  end
  local src = inflictor or source
  local skip_saw = source ~= nil and source.player ~= nil and source.player.readyweapon == WP_CHAINSAW
  if src ~= nil and not has(target.flags, MF_NOCLIP) and not skip_saw then
    local ang = collision.angle_to(src.x, src.y, target.x, target.y)
    local row = info.MOBJINFO[target.type or 0]
    local mass = 100
    if row ~= nil and row[info.MI_MASS] ~= 0 then
      mass = row[info.MI_MASS]
    end
    local thrust = math.floor(damage * 8192 * 100 / mass)
    if damage < 40 and damage > (target.health or 0) and target.z - src.z > 64 * FRACUNIT and band(rng.p_random(), 1) ~= 0 then
      ang = as_u32(ang + ANG180)
      thrust = thrust * 4
    end
    target.momx = (target.momx or 0) + fixed_mul(thrust, tables.fine_cos(ang))
    target.momy = (target.momy or 0) + fixed_mul(thrust, tables.fine_sin(ang))
  end
  if target.player then
    local player_mod = require("player")
    player_mod.damage_mobj(target, source, damage, inflictor)
    return
  end
  target.health = (target.health or 0) - damage
  if target.health <= 0 then
    M.kill_monster(target, game, source)
    return
  end
  M.pain_or_wake(game, target, source)
end

local function recursive_sound(world, sec, soundblocks, target)
  if sec.validcount == world.validcount and (sec.soundtraversed or 0) <= soundblocks + 1 then
    return
  end
  sec.validcount = world.validcount
  sec.soundtraversed = soundblocks + 1
  sec.soundtarget = target
  for i = 1, #sec.lines do
    local check = sec.lines[i]
    if has(check.flags, ML_TWOSIDED) then
      local opentop, openbottom = collision.line_opening(check)
      if opentop - openbottom > 0 then
        local other = check.backsector
        if check.frontsector ~= sec then
          other = check.frontsector
        end
        if other ~= nil then
          if has(check.flags, ML_SOUNDBLOCK) then
            if soundblocks == 0 then
              recursive_sound(world, other, 1, target)
            end
          else
            recursive_sound(world, other, soundblocks, target)
          end
        end
      end
    end
  end
end

function M.noise_alert(world, emitter, game)
  if emitter == nil then
    return
  end
  local sec = collision.point_in_subsector(world, emitter.x, emitter.y).sector
  world.validcount = (world.validcount or 0) + 1
  recursive_sound(world, sec, 0, emitter)
end

local function play_see_sound(mo, game)
  local s = mi(mo)[info.MI_SEESOUND]
  if s == nil or s == "" then
    return
  end
  if s == "posit1" then
    local names = { [0] = "posit1", "posit2", "posit3" }
    s = names[rng.p_random() % 3]
  elseif s == "bgsit1" then
    local names = { [0] = "bgsit1", "bgsit2" }
    s = names[rng.p_random() % 2]
  end
  play(game, s)
end

local function play_death_sound(mo, game)
  local s = mi(mo)[info.MI_DEATHSOUND]
  if s == nil or s == "" then
    return
  end
  if s == "podth1" then
    local names = { [0] = "podth1", "podth2", "podth3" }
    s = names[rng.p_random() % 3]
  elseif s == "bgdth1" then
    local names = { [0] = "bgdth1", "bgdth2" }
    s = names[rng.p_random() % 2]
  end
  play(game, s)
end

local function look_for_players(world, mo, player_mo, allaround)
  if player_mo == nil then
    return false
  end
  local c = 0
  local stop = band(mo.lastlook - 1, 3)
  while true do
    if mo.lastlook ~= 0 then
      mo.lastlook = band(mo.lastlook + 1, 3)
    else
      if c == 2 or mo.lastlook == stop then
        return false
      end
      c = c + 1
      local skip = false
      if (player_mo.health or 0) <= 0 or not has(player_mo.flags, MF_SHOOTABLE) then
        mo.lastlook = band(mo.lastlook + 1, 3)
        skip = true
      elseif not collision.check_sight(world, mo, player_mo) then
        mo.lastlook = band(mo.lastlook + 1, 3)
        skip = true
      elseif not allaround then
        local an = as_u32(collision.angle_to(mo.x, mo.y, player_mo.x, player_mo.y) - mo.angle)
        if an > ANG90 and an < ANG270 then
          local dist = collision.approx_distance(player_mo.x - mo.x, player_mo.y - mo.y)
          if dist > MELEERANGE then
            mo.lastlook = band(mo.lastlook + 1, 3)
            skip = true
          end
        end
      end
      if not skip then
        mo.target = player_mo
        return true
      end
    end
  end
end

local function face_target(mo, target)
  mo.angle = collision.angle_to(mo.x, mo.y, target.x, target.y)
  if has(target.flags, MF_SHADOW) then
    mo.angle = as_u32(mo.angle + (rng.p_random() - rng.p_random()) * 2097152)
  end
end

local function face_movedir(mo)
  if mo.movedir < 0 or mo.movedir >= 8 then
    return
  end
  mo.angle = as_u32(band(mo.angle, 3758096384))
  local delta = as_i32(mo.angle - mo.movedir * ANG45)
  if delta > 0 then
    mo.angle = as_u32(mo.angle - ANG45)
  elseif delta < 0 then
    mo.angle = as_u32(mo.angle + ANG45)
  end
end

local function move_step(world, mo, speed, game)
  if mo.movedir < 0 or mo.movedir >= 8 then
    return false
  end
  local nx = mo.x + speed * XSPEED[mo.movedir]
  local ny = mo.y + speed * YSPEED[mo.movedir]
  if not collision.try_move(world, mo, nx, ny, game) then
    if has(mo.flags, MF_FLOAT) and collision.floatok then
      if mo.z < collision.tmfloorz then
        mo.z = mo.z + FLOATSPEED
      else
        mo.z = mo.z - FLOATSPEED
      end
      mo.flags = bor(mo.flags, MF_INFLOAT)
      return true
    end
    local hits = collision.last_spechit
    if hits == nil or #hits == 0 then
      return false
    end
    mo.movedir = DI_NODIR
    local good = false
    for i = #hits, 1, -1 do
      local ln = hits[i]
      if (ln.special or 0) ~= 0 and game ~= nil and game.use_special and game.use_special(ln, mo, 0) then
        good = true
      end
    end
    return good
  end
  mo.flags = band(mo.flags, bnot(MF_INFLOAT))
  if not has(mo.flags, MF_FLOAT) then
    mo.z = mo.floorz
  end
  return true
end

local function new_chase_dir(world, mo, game)
  local target = mo.target
  if target == nil then
    return
  end
  local old = mo.movedir
  local turn = DI_NODIR
  if old >= 0 and old < 8 then
    turn = OPPOSITE[old]
  end
  local dx = target.x - mo.x
  local dy = target.y - mo.y
  local d2 = DI_NODIR
  local d3 = DI_NODIR
  if dx > 10 * FRACUNIT then
    d2 = DI_EAST
  elseif dx < -10 * FRACUNIT then
    d2 = DI_WEST
  end
  if dy < -10 * FRACUNIT then
    d3 = DI_SOUTH
  elseif dy > 10 * FRACUNIT then
    d3 = DI_NORTH
  end
  local speed = mi(mo)[info.MI_SPEED]
  if d2 ~= DI_NODIR and d3 ~= DI_NODIR then
    mo.movedir = DIAGS[(dy < 0 and 2 or 0) + (dx > 0 and 1 or 0)]
    if mo.movedir ~= turn and move_step(world, mo, speed, game) then
      mo.movecount = band(rng.p_random(), 15)
      return
    end
  end
  if rng.p_random() > 200 or math.abs(dy) > math.abs(dx) then
    d2, d3 = d3, d2
  end
  if d2 == turn then
    d2 = DI_NODIR
  end
  if d3 == turn then
    d3 = DI_NODIR
  end
  if d2 ~= DI_NODIR then
    mo.movedir = d2
    if move_step(world, mo, speed, game) then
      mo.movecount = band(rng.p_random(), 15)
      return
    end
  end
  if d3 ~= DI_NODIR then
    mo.movedir = d3
    if move_step(world, mo, speed, game) then
      mo.movecount = band(rng.p_random(), 15)
      return
    end
  end
  if old ~= DI_NODIR then
    mo.movedir = old
    if move_step(world, mo, speed, game) then
      mo.movecount = band(rng.p_random(), 15)
      return
    end
  end
  local start = band(rng.p_random(), 1)
  local dirs = {}
  if start ~= 0 then
    for t = 0, 7 do
      dirs[#dirs + 1] = t
    end
  else
    for t = 7, 0, -1 do
      dirs[#dirs + 1] = t
    end
  end
  for i = 1, #dirs do
    local tdir = dirs[i]
    if tdir ~= turn then
      mo.movedir = tdir
      if move_step(world, mo, speed, game) then
        mo.movecount = band(rng.p_random(), 15)
        return
      end
    end
  end
  if turn ~= DI_NODIR then
    mo.movedir = turn
    if move_step(world, mo, speed, game) then
      mo.movecount = band(rng.p_random(), 15)
      return
    end
  end
  mo.movedir = DI_NODIR
  mo.movecount = band(rng.p_random(), 15)
end

local function missile_ok(world, mo, target, dist, has_melee)
  if not collision.check_sight(world, mo, target) then
    return false
  end
  if has(mo.flags, MF_JUSTHIT) then
    mo.flags = band(mo.flags, bnot(MF_JUSTHIT))
    return true
  end
  if (mo.reactiontime or 0) ~= 0 then
    return false
  end
  local d = dist - 64 * FRACUNIT
  if not has_melee then
    d = d - 128 * FRACUNIT
  end
  d = shar(d, 16)
  if mo.type == info.MT_VILE and d > 14 * 64 then
    return false
  end
  if mo.type == info.MT_UNDEAD then
    if d < 196 then
      return false
    end
    d = shar(d, 1)
  end
  if mo.type == info.MT_CYBORG or mo.type == info.MT_SPIDER or mo.type == info.MT_SKULL then
    d = shar(d, 1)
  end
  if d > 200 then
    d = 200
  end
  if mo.type == info.MT_CYBORG and d > 160 then
    d = 160
  end
  return rng.p_random() >= d
end

local function look(world, mo, player_mo, game)
  local thinker = require("thinker")
  mo.threshold = 0
  local see = false
  local sec = collision.point_in_subsector(world, mo.x, mo.y).sector
  local targ = sec.soundtarget
  if targ ~= nil and has(targ.flags, MF_SHOOTABLE) then
    mo.target = targ
    if has(mo.flags, MF_AMBUSH) then
      see = collision.check_sight(world, mo, targ)
    else
      see = true
    end
  end
  if not see then
    if not look_for_players(world, mo, player_mo, false) then
      return
    end
  end
  mo.movedir = DI_NODIR
  mo.movecount = 0
  play_see_sound(mo, game)
  thinker.set_mobj_state(mo, mi(mo)[info.MI_SEESTATE], world, game)
end

local function chase(world, mo, player_mo, game)
  local thinker = require("thinker")
  local row = mi(mo)
  if (mo.reactiontime or 0) ~= 0 then
    mo.reactiontime = mo.reactiontime - 1
  end
  if (mo.threshold or 0) ~= 0 then
    local target = mo.target
    if target == nil or (target.health or 0) <= 0 then
      mo.threshold = 0
    else
      mo.threshold = mo.threshold - 1
    end
  end
  if mo.movedir < 8 then
    face_movedir(mo)
  end
  local target = mo.target
  if target == nil or not has(target.flags, MF_SHOOTABLE) then
    if look_for_players(world, mo, player_mo, true) then
      return
    end
    thinker.set_mobj_state(mo, row[info.MI_SPAWNSTATE], world, game)
    return
  end
  if has(mo.flags, MF_JUSTATTACKED) then
    mo.flags = band(mo.flags, bnot(MF_JUSTATTACKED))
    if game.skill ~= SK_NIGHTMARE and game.fastparm ~= true then
      new_chase_dir(world, mo, game)
    end
    return
  end
  local melee_st = row[info.MI_MELEESTATE]
  local miss_st = row[info.MI_MISSILESTATE]
  local dist = collision.approx_distance(target.x - mo.x, target.y - mo.y)
  local melee_range = MELEERANGE - 20 * FRACUNIT + (target.radius or 0)
  if melee_st ~= 0 and dist < melee_range and collision.check_sight(world, mo, target) then
    local atk = row[info.MI_ATTACKSOUND]
    if atk ~= nil and atk ~= "" then
      play(game, atk)
    end
    thinker.set_mobj_state(mo, melee_st, world, game)
    return
  end
  if miss_st ~= 0 then
    local skip = game.skill < SK_NIGHTMARE and game.fastparm ~= true and (mo.movecount or 0) ~= 0
    if not skip and missile_ok(world, mo, target, dist, melee_st ~= 0) then
      thinker.set_mobj_state(mo, miss_st, world, game)
      mo.flags = bor(mo.flags, MF_JUSTATTACKED)
      return
    end
  end
  mo.movecount = (mo.movecount or 0) - 1
  if mo.movecount < 0 or not move_step(world, mo, row[info.MI_SPEED], game) then
    new_chase_dir(world, mo, game)
  end
  local active = row[info.MI_ACTIVESOUND]
  if active ~= nil and active ~= "" and rng.p_random() < 3 then
    play(game, active)
  end
end

local function check_missile_spawn(mo)
  mo.tics = mo.tics - band(rng.p_random(), 3)
  if mo.tics < 1 then
    mo.tics = 1
  end
  mo.x = mo.x + shar(mo.momx, 1)
  mo.y = mo.y + shar(mo.momy, 1)
  mo.z = mo.z + shar(mo.momz, 1)
end

function M.spawn_missile_mt(world, source, dest, typ, game, ang)
  local thinker = require("thinker")
  local row = info.MOBJINFO[typ]
  local speed = row[info.MI_SPEED]
  if dest == nil then
    dest = source
  end
  if ang == nil then
    ang = collision.angle_to(source.x, source.y, dest.x, dest.y)
    if has(dest.flags, MF_SHADOW) then
      ang = as_u32(ang + (rng.p_random() - rng.p_random()) * 1048576)
    end
  end
  local dist = collision.approx_distance(dest.x - source.x, dest.y - source.y)
  local steps = 1
  if speed ~= 0 then
    steps = math.floor(dist / speed)
  end
  if steps < 1 then
    steps = 1
  end
  local mo = thinker.spawn_mobj(world, source.x, source.y, source.z + 32 * FRACUNIT, typ, game)
  mo.target = source
  mo.angle = ang
  mo.momx = fixed_mul(speed, tables.fine_cos(ang))
  mo.momy = fixed_mul(speed, tables.fine_sin(ang))
  mo.momz = trunc((dest.z - source.z) / steps)
  check_missile_spawn(mo)
  return mo
end

function M.spawn_player_missile(world, source, kind)
  local thinker = require("thinker")
  local typ = info.MT_BFG
  if kind == "rocket" then
    typ = info.MT_ROCKET
  elseif kind == "plasma" then
    typ = info.MT_PLASMA
  end
  local ang = source.angle
  local row = info.MOBJINFO[typ]
  local spd = row[info.MI_SPEED]
  local mo = thinker.spawn_mobj(world, source.x, source.y, source.z + 32 * FRACUNIT, typ, nil)
  mo.target = source
  mo.angle = ang
  mo.momx = fixed_mul(spd, tables.fine_cos(ang))
  mo.momy = fixed_mul(spd, tables.fine_sin(ang))
  mo.momz = 0
  check_missile_spawn(mo)
  return mo
end

local function radius_attack(world, spot, source, damage, game)
  local list = {}
  for i = 1, #world.mobjs do
    list[i] = world.mobjs[i]
  end
  for i = 1, #list do
    local other = list[i]
    if other ~= spot and has(other.flags, MF_SHOOTABLE) and other.type ~= info.MT_CYBORG and other.type ~= info.MT_SPIDER then
      local dx = math.abs(other.x - spot.x)
      local dy = math.abs(other.y - spot.y)
      local dist = dx
      if dy > dx then
        dist = dy
      end
      dist = dist - (other.radius or 0)
      if dist < 0 then
        dist = 0
      end
      dist = shar(dist, 16)
      if dist < damage and collision.check_sight(world, other, spot) then
        local src = source or spot
        game.damage_mobj(other, src, damage - dist, spot)
      end
    end
  end
end

function M.explode_missile(world, mo, game, hit)
  local thinker = require("thinker")
  if hit ~= nil then
    local src = mo.target or mo
    local dmg = mo.damage or mi(mo)[info.MI_DAMAGE]
    game.damage_mobj(hit, src, dmg * ((rng.p_random() % 8) + 1), mo)
  end
  mo.momx, mo.momy, mo.momz = 0, 0, 0
  mo.flags = band(mo.flags, bnot(MF_MISSILE))
  thinker.set_mobj_state(mo, mi(mo)[info.MI_DEATHSTATE], world, game)
end

function M.p_xy_movement(world, mo, game)
  local thinker = require("thinker")
  if (mo.momx or 0) == 0 and (mo.momy or 0) == 0 then
    if has(mo.flags, MF_SKULLFLY) then
      mo.flags = band(mo.flags, bnot(MF_SKULLFLY))
      mo.momx, mo.momy, mo.momz = 0, 0, 0
      thinker.set_mobj_state(mo, mi(mo)[info.MI_SPAWNSTATE], world, game)
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
      ptryx = mo.x + trunc(xmove / 2)
      ptryy = mo.y + trunc(ymove / 2)
      xmove = trunc(xmove / 2)
      ymove = trunc(ymove / 2)
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
    elseif mo.player ~= nil then
      collision.slide_move(world, mo, mo.momx, mo.momy, game)
    elseif has(mo.flags, MF_MISSILE) then
      local line = collision.ceilingline
      local sky = -1
      if game and game.res then
        sky = game.res.skyflatnum or -1
      end
      if line ~= nil and line.backsector ~= nil and line.backsector.ceilingpic == sky then
        thinker.remove_mobj(world, mo)
        return
      end
      M.explode_missile(world, mo, game, nil)
      return
    else
      mo.momx, mo.momy = 0, 0
    end
  end
  local player = mo.player
  if player ~= nil and has(player.cheats, CF_NOMOMENTUM) then
    mo.momx, mo.momy = 0, 0
    return
  end
  if has(mo.flags, MF_MISSILE) or has(mo.flags, MF_SKULLFLY) then
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
  if -STOPSPEED < mo.momx and mo.momx < STOPSPEED and -STOPSPEED < mo.momy and mo.momy < STOPSPEED
    and (player == nil or ((player.cmd.forwardmove or 0) == 0 and (player.cmd.sidemove or 0) == 0)) then
    if player ~= nil then
      local n = mo.istate - info.S_PLAY_RUN1
      if n >= 0 and n < 4 then
        thinker.set_mobj_state(mo, info.S_PLAY, world, game)
      end
    end
    mo.momx, mo.momy = 0, 0
  else
    mo.momx = fixed_mul(mo.momx, FRICTION)
    mo.momy = fixed_mul(mo.momy, FRICTION)
  end
end

function M.mobj_z(mo, world, game)
  local player = mo.player
  if player ~= nil and mo.z < mo.floorz then
    player.viewheight = player.viewheight - (mo.floorz - mo.z)
    player.deltaviewheight = shar(VIEWHEIGHT - player.viewheight, 3)
  end
  mo.z = mo.z + (mo.momz or 0)
  if has(mo.flags, MF_FLOAT) and mo.target ~= nil and not has(mo.flags, MF_SKULLFLY) and not has(mo.flags, MF_INFLOAT) then
    local dist = collision.approx_distance(mo.x - mo.target.x, mo.y - mo.target.y)
    local delta = (mo.target.z + shar(mo.height, 1)) - mo.z
    if delta < 0 and dist < -(delta * 3) then
      mo.z = mo.z - FLOATSPEED
    elseif delta > 0 and dist < (delta * 3) then
      mo.z = mo.z + FLOATSPEED
    end
  end
  if mo.z <= mo.floorz then
    if (mo.momz or 0) < 0 then
      if player ~= nil and mo.momz < -GRAVITY * 8 then
        player.deltaviewheight = shar(mo.momz, 3)
        play(game, "oof")
      end
      mo.momz = 0
    end
    mo.z = mo.floorz
    if has(mo.flags, MF_SKULLFLY) and not has(mo.flags, MF_MISSILE) then
      mo.momz = -mo.momz
    end
    if has(mo.flags, MF_MISSILE) and not has(mo.flags, MF_NOCLIP) then
      M.explode_missile(world, mo, game, nil)
      return
    end
  elseif not has(mo.flags, MF_NOGRAVITY) then
    if (mo.momz or 0) == 0 then
      mo.momz = -GRAVITY * 2
    else
      mo.momz = mo.momz - GRAVITY
    end
  end
  if mo.z + mo.height > mo.ceilingz then
    if (mo.momz or 0) > 0 then
      mo.momz = 0
    end
    mo.z = mo.ceilingz - mo.height
    if has(mo.flags, MF_SKULLFLY) then
      mo.momz = -mo.momz
    end
    if has(mo.flags, MF_MISSILE) and not has(mo.flags, MF_NOCLIP) then
      M.explode_missile(world, mo, game, nil)
    end
  end
end

local function skull_attack(mo, game)
  local dest = mo.target
  if dest == nil then
    return
  end
  mo.flags = bor(mo.flags, MF_SKULLFLY)
  play(game, "sklatk")
  face_target(mo, dest)
  mo.momx = fixed_mul(SKULLSPEED, tables.fine_cos(mo.angle))
  mo.momy = fixed_mul(SKULLSPEED, tables.fine_sin(mo.angle))
  local dist = collision.approx_distance(dest.x - mo.x, dest.y - mo.y)
  local steps = 1
  if SKULLSPEED ~= 0 then
    steps = math.floor(dist / SKULLSPEED)
  end
  if steps < 1 then
    steps = 1
  end
  mo.momz = trunc((dest.z + math.floor(dest.height / 2) - mo.z) / steps)
end

local function tracer_home(mo)
  local dest = mo.tracer
  if dest == nil or (dest.health or 0) <= 0 then
    return
  end
  local exact = collision.angle_to(mo.x, mo.y, dest.x, dest.y)
  local diff = as_u32(exact - mo.angle)
  if diff > 2147483648 then
    mo.angle = as_u32(mo.angle - TRACEANGLE)
    if as_u32(exact - mo.angle) < 2147483648 then
      mo.angle = exact
    end
  else
    mo.angle = as_u32(mo.angle + TRACEANGLE)
    if as_u32(exact - mo.angle) > 2147483648 then
      mo.angle = exact
    end
  end
  local speed = mi(mo)[info.MI_SPEED]
  mo.momx = fixed_mul(speed, tables.fine_cos(mo.angle))
  mo.momy = fixed_mul(speed, tables.fine_sin(mo.angle))
  local dist = collision.approx_distance(dest.x - mo.x, dest.y - mo.y)
  local steps = 1
  if speed ~= 0 then
    steps = math.floor(dist / speed)
  end
  if steps < 1 then
    steps = 1
  end
  mo.momz = trunc((dest.z + 40 * FRACUNIT - mo.z) / steps)
end

local function vile_chase(world, mo, game)
  local thinker = require("thinker")
  for i = 1, #world.mobjs do
    local other = world.mobjs[i]
    if other ~= mo and has(other.flags, MF_CORPSE) and (other.health or 0) <= 0 then
      local row = info.MOBJINFO[other.type]
      if row[info.MI_RAISESTATE] ~= 0 then
        local maxdist = mo.radius + other.radius
        if math.abs(other.x - mo.x) <= maxdist and math.abs(other.y - mo.y) <= maxdist then
          thinker.set_mobj_state(mo, info.S_VILE_HEAL1, world, game)
          play(game, "slop")
          thinker.set_mobj_state(other, row[info.MI_RAISESTATE], world, game)
          other.flags = row[info.MI_FLAGS]
          other.health = row[info.MI_SPAWNHEALTH]
          other.height = row[info.MI_HEIGHT]
          other.radius = row[info.MI_RADIUS]
          other.target = nil
          other.alive = true
          other.z = other.floorz
          return true
        end
      end
    end
  end
  return false
end

local function pain_shoot_skull(world, actor, game, ang)
  local thinker = require("thinker")
  local n = 0
  for i = 1, #world.mobjs do
    local other = world.mobjs[i]
    if other.type == info.MT_SKULL and (other.health or 0) > 0 then
      n = n + 1
    end
  end
  if n >= MAX_SKULLS then
    return
  end
  local pre = 4 * FRACUNIT + math.floor(3 * actor.radius / 2)
  local x = actor.x + fixed_mul(pre, tables.fine_cos(ang))
  local y = actor.y + fixed_mul(pre, tables.fine_sin(ang))
  local skull = thinker.spawn_mobj(world, x, y, actor.z, info.MT_SKULL, game)
  skull.angle = ang
  local chk = collision.check_position(world, skull, skull.x, skull.y)
  if chk.blocked then
    game.damage_mobj(skull, actor, 10000, actor)
    return
  end
  skull.target = actor.target
  skull_attack(skull, game)
end

local function alive_of_type(world, typ)
  for i = 1, #world.mobjs do
    local other = world.mobjs[i]
    if other.type == typ and (other.health or 0) > 0 then
      return true
    end
  end
  return false
end

local function boss_death(world, mo, game)
  if alive_of_type(world, mo.type) then
    return
  end
  local specials = require("specials")
  local spec = game.specials
  if spec == nil then
    return
  end
  local commercial = false
  if game.wad ~= nil then
    local wad = require("wad")
    commercial = wad.check_num_for_name(game.wad, "MAP01") >= 0
  end
  if commercial and game.mapn == 7 then
    if mo.type == info.MT_FATSO then
      specials.do_floor_tag(spec, 666, specials.lowest_floor, -1)
    elseif mo.type == info.MT_BABY then
      specials.raise_to_texture_tag(spec, 667)
    end
    return
  end
  if commercial then
    return
  end
  if game.episode == 1 and game.mapn == 8 and mo.type == info.MT_BRUISER then
    specials.do_floor_tag(spec, 666, specials.lowest_floor, -1)
  elseif game.episode == 2 and game.mapn == 8 and mo.type == info.MT_CYBORG then
    spec.exit_requested = true
  elseif game.episode == 3 and game.mapn == 8 and mo.type == info.MT_SPIDER then
    spec.exit_requested = true
  elseif game.episode == 4 and game.mapn == 6 and mo.type == info.MT_CYBORG then
    specials.do_floor_tag(spec, 666, specials.lowest_floor, -1)
  elseif game.episode == 4 and game.mapn == 8 and mo.type == info.MT_BRUISER then
    specials.do_floor_tag(spec, 666, specials.lowest_floor, -1)
  end
end

local function spawn_fly(world, cube, game)
  local thinker = require("thinker")
  local dest = cube.target or cube
  local r = rng.p_random()
  local typ = info.MT_BRUISER
  if r < 50 then
    typ = info.MT_TROOP
  elseif r < 90 then
    typ = info.MT_SERGEANT
  elseif r < 120 then
    typ = info.MT_SHADOWS
  elseif r < 130 then
    typ = info.MT_PAIN
  elseif r < 160 then
    typ = info.MT_HEAD
  elseif r < 162 then
    typ = info.MT_VILE
  elseif r < 172 then
    typ = info.MT_UNDEAD
  elseif r < 192 then
    typ = info.MT_BABY
  elseif r < 222 then
    typ = info.MT_FATSO
  elseif r < 246 then
    typ = info.MT_KNIGHT
  end
  play(game, "telept")
  local spawned = thinker.spawn_mobj(world, dest.x, dest.y, dest.z, typ, game)
  spawned.angle = dest.angle
  thinker.remove_mobj(world, cube)
end

local function bfg_spray(world, ball, game)
  local shooter = ball.target
  if shooter == nil then
    return
  end
  for i = 0, 39 do
    local an = as_u32(shooter.angle - math.floor(ANG90 / 2) + math.floor(ANG90 / 40) * i)
    local target = collision.aim_line_attack(world, shooter, an, 16 * 64 * FRACUNIT)
    if target ~= nil then
      local damage = 0
      for _ = 1, 15 do
        damage = damage + band(rng.p_random(), 7) + 1
      end
      game.damage_mobj(target, shooter, damage, ball)
    end
  end
end

function M.call_action(name, mo, world, game)
  local thinker = require("thinker")
  local pl = nil
  if game ~= nil and game.player ~= nil then
    pl = game.player.mo
  end
  if name == "Look" then
    look(world, mo, pl, game)
  elseif name == "Chase" then
    chase(world, mo, pl, game)
  elseif name == "FaceTarget" then
    if mo.target ~= nil then
      face_target(mo, mo.target)
    end
  elseif name == "Fall" then
    mo.flags = band(mo.flags, bnot(MF_SOLID))
  elseif name == "Scream" then
    play_death_sound(mo, game)
  elseif name == "XScream" then
    play(game, "slop")
  elseif name == "Pain" then
    local s = mi(mo)[info.MI_PAINSOUND]
    if s ~= nil and s ~= "" then
      play(game, s)
    end
  elseif name == "Explode" then
    radius_attack(world, mo, mo.target, 128, game)
  elseif name == "PosAttack" or name == "CPosAttack" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    local slope = collision.aim_slope(world, mo, mo.angle, MISSILERANGE)
    if name == "PosAttack" then
      play(game, "pistol")
    else
      play(game, "shotgn")
    end
    local saved = mo.angle
    mo.angle = as_u32(saved + (rng.p_random() - rng.p_random()) * 1048576)
    collision.line_attack(world, mo, ((rng.p_random() % 5) + 1) * 3, game, MISSILERANGE, mo.angle, slope)
    mo.angle = saved
  elseif name == "SPosAttack" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    local slope = collision.aim_slope(world, mo, mo.angle, MISSILERANGE)
    play(game, "shotgn")
    local saved = mo.angle
    for _ = 1, 3 do
      mo.angle = as_u32(saved + (rng.p_random() - rng.p_random()) * 1048576)
      collision.line_attack(world, mo, ((rng.p_random() % 5) + 1) * 3, game, MISSILERANGE, mo.angle, slope)
    end
    mo.angle = saved
  elseif name == "CPosRefire" or name == "SpidRefire" then
    if mo.target ~= nil then
      face_target(mo, mo.target)
    end
    local keep = 40
    if name == "SpidRefire" then
      keep = 10
    end
    if rng.p_random() < keep then
      return
    end
    if mo.target == nil or (mo.target.health or 0) <= 0 or not collision.check_sight(world, mo, mo.target) then
      thinker.set_mobj_state(mo, mi(mo)[info.MI_SEESTATE], world, game)
    end
  elseif name == "TroopAttack" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    local dist = collision.approx_distance(mo.target.x - mo.x, mo.target.y - mo.y)
    if dist < MELEERANGE + mo.radius then
      play(game, "claw")
      game.damage_mobj(mo.target, mo, ((rng.p_random() % 8) + 1) * 3)
    else
      M.spawn_missile_mt(world, mo, mo.target, info.MT_TROOPSHOT, game)
    end
  elseif name == "SargAttack" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    local dist = collision.approx_distance(mo.target.x - mo.x, mo.target.y - mo.y)
    if dist < MELEERANGE + mo.radius then
      game.damage_mobj(mo.target, mo, ((rng.p_random() % 8) + 1) * 4)
    end
  elseif name == "HeadAttack" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    local dist = collision.approx_distance(mo.target.x - mo.x, mo.target.y - mo.y)
    if dist < MELEERANGE + mo.radius then
      game.damage_mobj(mo.target, mo, ((rng.p_random() % 8) + 1) * 10)
    else
      M.spawn_missile_mt(world, mo, mo.target, info.MT_HEADSHOT, game)
    end
  elseif name == "BruisAttack" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    local dist = collision.approx_distance(mo.target.x - mo.x, mo.target.y - mo.y)
    if dist < MELEERANGE + mo.radius then
      game.damage_mobj(mo.target, mo, ((rng.p_random() % 8) + 1) * 10)
    else
      M.spawn_missile_mt(world, mo, mo.target, info.MT_BRUISERSHOT, game)
    end
  elseif name == "SkullAttack" then
    skull_attack(mo, game)
  elseif name == "CyberAttack" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    M.spawn_missile_mt(world, mo, mo.target, info.MT_ROCKET, game)
  elseif name == "BspiAttack" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    M.spawn_missile_mt(world, mo, mo.target, info.MT_ARACHPLAZ, game)
  elseif name == "Metal" then
    play(game, "metal")
    chase(world, mo, pl, game)
  elseif name == "BabyMetal" then
    play(game, "bspwlk")
    chase(world, mo, pl, game)
  elseif name == "Hoof" then
    play(game, "hoof")
    chase(world, mo, pl, game)
  elseif name == "PainAttack" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    pain_shoot_skull(world, mo, game, mo.angle)
  elseif name == "PainDie" then
    mo.flags = band(mo.flags, bnot(MF_SOLID))
    pain_shoot_skull(world, mo, game, as_u32(mo.angle + ANG90))
    pain_shoot_skull(world, mo, game, as_u32(mo.angle + ANG90 * 2))
    pain_shoot_skull(world, mo, game, as_u32(mo.angle + ANG270))
  elseif name == "KeenDie" then
    mo.flags = band(mo.flags, bnot(MF_SOLID))
    if not alive_of_type(world, info.MT_KEEN) and game.specials then
      local specials = require("specials")
      specials.do_door_tag(game.specials, 666, VLD_BLAZEOPEN)
    end
  elseif name == "BossDeath" then
    boss_death(world, mo, game)
  elseif name == "VileChase" then
    if not vile_chase(world, mo, game) then
      chase(world, mo, pl, game)
    end
  elseif name == "VileStart" then
    play(game, "vilatk")
  elseif name == "VileTarget" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    local fog = thinker.spawn_mobj(world, mo.target.x, mo.target.y, mo.target.z, info.MT_FIRE, game)
    mo.tracer = fog
    fog.target = mo
    fog.tracer = mo.target
  elseif name == "VileAttack" then
    local dest = mo.target
    if dest == nil or not collision.check_sight(world, mo, dest) then
      return
    end
    play(game, "vilatk")
    game.damage_mobj(dest, mo, 20)
    radius_attack(world, dest, mo, 70, game)
  elseif name == "StartFire" or name == "Fire" or name == "FireCrackle" then
    if name == "StartFire" then
      play(game, "flamst")
    elseif name == "FireCrackle" then
      play(game, "flame")
    end
    local dest = mo.tracer
    if dest == nil or mo.target == nil then
      return
    end
    mo.x, mo.y, mo.z = dest.x, dest.y, dest.z
  elseif name == "Tracer" then
    if band(game.leveltime or 0, 3) ~= 0 then
      return
    end
    tracer_home(mo)
  elseif name == "SkelWhoosh" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    play(game, "skeswg")
  elseif name == "SkelFist" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    local dist = collision.approx_distance(mo.target.x - mo.x, mo.target.y - mo.y)
    if dist < MELEERANGE + mo.radius then
      play(game, "skepch")
      game.damage_mobj(mo.target, mo, ((rng.p_random() % 8) + 1) * 6)
    end
  elseif name == "SkelMissile" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    local miss = M.spawn_missile_mt(world, mo, mo.target, info.MT_TRACER, game)
    miss.tracer = mo.target
    miss.z = miss.z + 16 * FRACUNIT
  elseif name == "FatRaise" then
    if mo.target ~= nil then
      face_target(mo, mo.target)
    end
    play(game, "manatk")
  elseif name == "FatAttack1" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    mo.angle = as_u32(mo.angle + FATSPREAD)
    M.spawn_missile_mt(world, mo, mo.target, info.MT_FATSHOT, game)
    local miss = M.spawn_missile_mt(world, mo, mo.target, info.MT_FATSHOT, game)
    miss.angle = as_u32(miss.angle + FATSPREAD)
    miss.momx = fixed_mul(mi(miss)[info.MI_SPEED], tables.fine_cos(miss.angle))
    miss.momy = fixed_mul(mi(miss)[info.MI_SPEED], tables.fine_sin(miss.angle))
  elseif name == "FatAttack2" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    mo.angle = as_u32(mo.angle - FATSPREAD)
    M.spawn_missile_mt(world, mo, mo.target, info.MT_FATSHOT, game)
    local miss = M.spawn_missile_mt(world, mo, mo.target, info.MT_FATSHOT, game)
    miss.angle = as_u32(miss.angle - FATSPREAD * 2)
    miss.momx = fixed_mul(mi(miss)[info.MI_SPEED], tables.fine_cos(miss.angle))
    miss.momy = fixed_mul(mi(miss)[info.MI_SPEED], tables.fine_sin(miss.angle))
  elseif name == "FatAttack3" then
    if mo.target == nil then
      return
    end
    face_target(mo, mo.target)
    local miss = M.spawn_missile_mt(world, mo, mo.target, info.MT_FATSHOT, game)
    miss.angle = as_u32(mo.angle - math.floor(FATSPREAD / 2))
    miss.momx = fixed_mul(mi(miss)[info.MI_SPEED], tables.fine_cos(miss.angle))
    miss.momy = fixed_mul(mi(miss)[info.MI_SPEED], tables.fine_sin(miss.angle))
    miss = M.spawn_missile_mt(world, mo, mo.target, info.MT_FATSHOT, game)
    miss.angle = as_u32(mo.angle + math.floor(FATSPREAD / 2))
    miss.momx = fixed_mul(mi(miss)[info.MI_SPEED], tables.fine_cos(miss.angle))
    miss.momy = fixed_mul(mi(miss)[info.MI_SPEED], tables.fine_sin(miss.angle))
  elseif name == "BrainPain" then
    play(game, "bospn")
  elseif name == "BrainScream" then
    play(game, "bosdth")
  elseif name == "BrainDie" then
    if game.specials then
      game.specials.exit_requested = true
    end
  elseif name == "BrainAwake" then
    brain_targets = {}
    for i = 1, #world.mobjs do
      if world.mobjs[i].type == info.MT_BOSSTARGET then
        brain_targets[#brain_targets + 1] = world.mobjs[i]
      end
    end
    brain_target_on = 0
    play(game, "bossit")
  elseif name == "BrainSpit" then
    if (game.skill or 2) <= SK_EASY then
      mo._easy_skip = not mo._easy_skip
      if mo._easy_skip then
        return
      end
    end
    local targs = brain_targets
    if #targs == 0 then
      for i = 1, #world.mobjs do
        if world.mobjs[i].type == info.MT_BOSSTARGET then
          targs[#targs + 1] = world.mobjs[i]
        end
      end
    end
    if #targs == 0 then
      return
    end
    local dest = targs[(brain_target_on % #targs) + 1]
    brain_target_on = brain_target_on + 1
    play(game, "bospit")
    local miss = M.spawn_missile_mt(world, mo, dest, info.MT_SPAWNSHOT, game)
    miss.target = dest
    local st = miss.tics
    if st == 0 then
      st = 1
    end
    if miss.momy ~= 0 then
      miss.reactiontime = math.floor(math.floor((dest.y - mo.y) / miss.momy) / st)
    end
  elseif name == "SpawnSound" then
    play(game, "boscub")
    mo.reactiontime = (mo.reactiontime or 0) - 1
    if mo.reactiontime == 0 then
      spawn_fly(world, mo, game)
    end
  elseif name == "SpawnFly" then
    mo.reactiontime = (mo.reactiontime or 0) - 1
    if mo.reactiontime == 0 then
      spawn_fly(world, mo, game)
    end
  elseif name == "BFGSpray" then
    bfg_spray(world, mo, game)
  elseif name == "PlayerScream" then
    play(game, "pldeth")
  end
end

return M
