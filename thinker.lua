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
-- Estado das coisas, a partir de thinker.py.

local compat = require("compat")
local collision = require("collision")
local info = require("info")
local rng = require("random")
local tables = require("tables")

local M = {}

local band, bor = compat.band, compat.bor
local as_u32 = compat.as_u32

local FRACUNIT = 65536
local MF_CORPSE = 1048576
local MF_COUNTKILL = 4194304
local MF_COUNTITEM = 8388608
local MF_MISSILE = 65536
local MF_SKULLFLY = 16777216
local MF_SPAWNCEILING = 256
local MF_AMBUSH = 32
local MTF_AMBUSH = 8
local SK_NIGHTMARE = 4
local TICRATE = 35
local S_NULL = 0

local ONFLOORZ = -2147483648
local ONCEILINGZ = 2147483647

M.ONFLOORZ = ONFLOORZ
M.ONCEILINGZ = ONCEILINGZ

local function skill_bit(skill)
  if skill <= 1 then
    return 1
  end
  if skill >= 3 then
    return 4
  end
  return 2
end

function M.spawn_mobj(world, x, y, z, typ, game)
  local row = info.MOBJINFO[typ]
  local sub = collision.point_in_subsector(world, x, y)
  local mo = {
    x = x,
    y = y,
    z = 0,
    angle = 0,
    momx = 0,
    momy = 0,
    momz = 0,
    radius = row[info.MI_RADIUS],
    height = row[info.MI_HEIGHT],
    floorz = sub.sector.floorheight,
    ceilingz = sub.sector.ceilingheight,
    flags = row[info.MI_FLAGS],
    health = row[info.MI_SPAWNHEALTH],
    type = typ,
    doomednum = row[info.MI_DOOMEDNUM],
    alive = true,
    damage = row[info.MI_DAMAGE],
    reactiontime = 0,
    lastlook = 0,
    target = nil,
    tracer = nil,
    player = nil,
    movedir = 8,
    movecount = 0,
    threshold = 0,
    sprite = "",
    frame = 0,
    tics = 0,
    istate = 0,
    spawnpoint = nil,
  }
  if game ~= nil and (game.skill or 2) ~= SK_NIGHTMARE then
    mo.reactiontime = row[info.MI_REACTIONTIME]
  end
  mo.lastlook = rng.p_random() % 4
  if z == ONCEILINGZ or (band(row[info.MI_FLAGS], MF_SPAWNCEILING) ~= 0 and z == ONFLOORZ) then
    mo.z = mo.ceilingz - mo.height
  elseif z == ONFLOORZ then
    mo.z = mo.floorz
  else
    mo.z = z
  end
  world.mobjs[#world.mobjs + 1] = mo
  collision.set_thing_position(world, mo)
  M.set_mobj_state(mo, row[info.MI_SPAWNSTATE], world, game)
  return mo
end

function M.remove_mobj(world, mo)
  collision.unset_thing_position(world, mo)
  mo.alive = false
  mo.istate = S_NULL
  mo.flags = 0
  mo.sprite = ""
  for i = 1, #world.mobjs do
    if world.mobjs[i] == mo then
      table.remove(world.mobjs, i)
      break
    end
  end
end

function M.set_mobj_state(mo, state, world, game)
  local enemy = require("enemy")
  local safety = 0
  while true do
    if state == S_NULL or mo == nil then
      if mo ~= nil and world ~= nil then
        M.remove_mobj(world, mo)
      end
      return false
    end
    local st = info.STATES[state]
    mo.istate = state
    mo.tics = st[2]
    mo.sprite = info.SPRNAMES[st[0]]
    mo.frame = st[1]
    local act = info.ACTIONS[st[3]]
    if act ~= nil and act ~= "" then
      enemy.call_action(act, mo, world, game)
      if mo.alive == false then
        return false
      end
    end
    state = st[4]
    if mo.tics ~= 0 then
      return true
    end
    safety = safety + 1
    if safety > 100 then
      return true
    end
  end
end

function M.mobj_thinker(world, mo, game)
  local enemy = require("enemy")
  if (mo.momx or 0) ~= 0 or (mo.momy or 0) ~= 0 or band(mo.flags or 0, MF_SKULLFLY) ~= 0 then
    enemy.p_xy_movement(world, mo, game)
    if mo.alive == false then
      return
    end
  end
  if mo.z ~= mo.floorz or (mo.momz or 0) ~= 0 then
    enemy.mobj_z(mo, world, game)
    if mo.alive == false then
      return
    end
  end
  if mo.tics ~= -1 then
    mo.tics = mo.tics - 1
    if mo.tics <= 0 then
      M.set_mobj_state(mo, info.STATES[mo.istate][4], world, game)
    end
    return
  end
  if band(mo.flags or 0, MF_COUNTKILL) == 0 then
    return
  end
  if not game.respawnmonsters then
    return
  end
  mo.movecount = (mo.movecount or 0) + 1
  if mo.movecount < 12 * TICRATE then
    return
  end
  if band(game.leveltime or 0, 31) ~= 0 then
    return
  end
  if enemy.p_random() > 4 then
    return
  end
  M.nightmare_respawn(world, mo, game)
end

function M.nightmare_respawn(world, mo, game)
  local sp = mo.spawnpoint
  if sp == nil then
    return
  end
  local x, y = sp.x * FRACUNIT, sp.y * FRACUNIT
  local chk = collision.check_position(world, mo, x, y)
  if chk.blocked then
    return
  end
  local row = info.MOBJINFO[mo.type]
  M.spawn_mobj(world, mo.x, mo.y, mo.floorz, info.MT_TFOG, game)
  if game and game.start_sound then
    game.start_sound("telept")
  end
  local sub = collision.point_in_subsector(world, x, y)
  M.spawn_mobj(world, x, y, sub.sector.floorheight, info.MT_TFOG, game)
  if game and game.start_sound then
    game.start_sound("telept")
  end
  local z = ONFLOORZ
  if band(row[info.MI_FLAGS], MF_SPAWNCEILING) ~= 0 then
    z = ONCEILINGZ
  end
  local spawned = M.spawn_mobj(world, x, y, z, mo.type, game)
  spawned.spawnpoint = sp
  spawned.angle = as_u32(math.floor(sp.angle / 45) * 536870912)
  if band(sp.options or 0, MTF_AMBUSH) ~= 0 then
    spawned.flags = bor(spawned.flags, MF_AMBUSH)
  end
  spawned.reactiontime = 18
  M.remove_mobj(world, mo)
end

function M.apply_fast(game)
  local want = game.fastparm == true or game.skill == SK_NIGHTMARE
  game.respawnmonsters = game.skill == SK_NIGHTMARE or game.respawnparm == true
  if game._fast_on == want then
    return
  end
  if game._sarg_tics == nil then
    game._sarg_tics = {}
    local n = 0
    for i = info.S_SARG_RUN1, info.S_SARG_PAIN2 do
      n = n + 1
      game._sarg_tics[n] = info.STATES[i][2]
    end
    game._shot_speed = {
      [info.MT_BRUISERSHOT] = info.MOBJINFO[info.MT_BRUISERSHOT][info.MI_SPEED],
      [info.MT_HEADSHOT] = info.MOBJINFO[info.MT_HEADSHOT][info.MI_SPEED],
      [info.MT_TROOPSHOT] = info.MOBJINFO[info.MT_TROOPSHOT][info.MI_SPEED],
    }
  end
  game._fast_on = want
  local n = 0
  for i = info.S_SARG_RUN1, info.S_SARG_PAIN2 do
    n = n + 1
    local tics = game._sarg_tics[n]
    if want then
      tics = math.max(1, math.floor(tics / 2))
    end
    info.STATES[i][2] = tics
  end
  local fast = 20 * FRACUNIT
  for mt, spd in pairs(game._shot_speed) do
    local speed = spd
    if want then
      speed = fast
    end
    info.MOBJINFO[mt][info.MI_SPEED] = speed
  end
end

function M.spawn_map(world, skill, game)
  tables.init()
  local bit = skill_bit(skill or 2)
  local kills, items = 0, 0
  world.mobjs = {}
  local nomonsters = game ~= nil and game.nomonsters == true
  for i = 1, #world.things do
    local mt = world.things[i]
    local typ = mt.type
    if typ ~= 11 then
      if typ == 1 or typ == 2 or typ == 3 or typ == 4 then
        if typ == 1 and game ~= nil and game.player == nil then
          local player_mod = require("player")
          game.player = player_mod.spawn(world, mt, 0)
        end
      elseif band(mt.options, bit) ~= 0 and band(mt.options, 16) == 0 then
        local mt_type = info.mobj_type_for_doomednum(typ)
        if mt_type >= 0 then
          local flags = info.MOBJINFO[mt_type][info.MI_FLAGS]
          local skip = nomonsters and (band(flags, MF_COUNTKILL) ~= 0 or mt_type == info.MT_SKULL)
          if not skip then
            local z = ONFLOORZ
            if band(flags, MF_SPAWNCEILING) ~= 0 then
              z = ONCEILINGZ
            end
            local mo = M.spawn_mobj(world, mt.x * FRACUNIT, mt.y * FRACUNIT, z, mt_type, game)
            if mo.tics > 0 then
              mo.tics = 1 + (rng.p_random() % mo.tics)
            end
            mo.angle = as_u32(math.floor(mt.angle / 45) * 536870912)
            mo.spawnpoint = mt
            if band(mt.options, MTF_AMBUSH) ~= 0 then
              mo.flags = bor(mo.flags, MF_AMBUSH)
            end
            if band(mo.flags, MF_COUNTKILL) ~= 0 then
              kills = kills + 1
            end
            if band(mo.flags, MF_COUNTITEM) ~= 0 then
              items = items + 1
            end
          end
        end
      end
    end
  end
  return kills, items
end

function M.tick(world, game)
  local player = game.player
  if player == nil or player.mo == nil then
    return
  end
  local list = {}
  for i = 1, #world.mobjs do
    list[i] = world.mobjs[i]
  end
  for i = 1, #list do
    local mo = list[i]
    if mo ~= player.mo and not mo.fx then
      M.mobj_thinker(world, mo, game)
    end
  end
end

return M
