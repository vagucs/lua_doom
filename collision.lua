-- DOOM generic portado do python_doom para Lua com SDL3.
--
-- Por Wagner Nunes da Silva
--
-- vagucs@bol.com.br
-- vagucs@vagucs.com.br
-- vagucs@gmail.com
--
-- www.vagucs.com.br
--
-- Colisao, uso e tiro, a partir de collision.py.

local compat = require("compat")
local world_mod = require("world")
local tables = require("tables")
local rng = require("random")

local M = {}

local band, bor, bxor, bnot = compat.band, compat.bor, compat.bxor, compat.bnot
local shar = compat.shar
local as_i32, as_u32 = compat.as_i32, compat.as_u32
local fixed_mul, fixed_div = compat.fixed_mul, compat.fixed_div

local FRACBITS = 16
local FRACUNIT = 65536
local ANG90 = 1073741824
local ANG180 = 2147483648
local BOXLEFT, BOXRIGHT, BOXBOTTOM, BOXTOP = 1, 2, 3, 4
local MAXMOVE = 30 * FRACUNIT
local MAPBLOCKSHIFT = 23
local MAPBLOCKSIZE = 128 * FRACUNIT
local MAPBTOFRAC = MAPBLOCKSHIFT - FRACBITS
local MAXRADIUS = 32 * FRACUNIT
local USERANGE = 64 * FRACUNIT
local MELEERANGE = 64 * FRACUNIT
local MAXSTEP = 24 * FRACUNIT
local PT_ADDLINES = 1
local PT_ADDTHINGS = 2
local PT_EARLYOUT = 4
local MF_SPECIAL = 1
local MF_SOLID = 2
local MF_SHOOTABLE = 4
local MF_NOBLOCKMAP = 16
local MF_MISSILE = 65536
local MF_NOBLOOD = 524288
local MF_SKULLFLY = 16777216
local MF_FLOAT = 16384
local MF_DROPOFF = 1024
local MF_PICKUP = 2048
local MF_NOCLIP = 4096
local MF_TELEPORT = 32768
local ML_BLOCKING = 1
local ML_BLOCKMONSTERS = 2
local ML_TWOSIDED = 4
local INT_MAX = 2147483647
local MT_PLAYER = 0
local MT_BRUISER = 15
local MT_KNIGHT = 17

local function has(flags, bit)
  return band(flags or 0, bit) ~= 0
end

local function abs32(n)
  n = as_i32(n)
  if n < 0 then
    return -n
  end
  return n
end

function M.point_in_subsector(world, x, y)
  return world_mod.point_in_subsector(world, x, y)
end

function M.point_on_line_side(x, y, line)
  if line.dx == 0 then
    if x <= line.v1.x then
      if line.dy > 0 then
        return 1
      end
      return 0
    end
    if line.dy < 0 then
      return 1
    end
    return 0
  end
  if line.dy == 0 then
    if y <= line.v1.y then
      if line.dx < 0 then
        return 1
      end
      return 0
    end
    if line.dx > 0 then
      return 1
    end
    return 0
  end
  local dx = as_i32(x - line.v1.x)
  local dy = as_i32(y - line.v1.y)
  local left = fixed_mul(shar(line.dy, FRACBITS), dx)
  local right = fixed_mul(dy, shar(line.dx, FRACBITS))
  if right < left then
    return 0
  end
  return 1
end

local function box_on_line_side(bbox, line)
  local p1, p2
  if line.dx == 0 then
    p1 = 0
    if bbox[BOXRIGHT] < line.v1.x then
      p1 = 1
    end
    p2 = 0
    if bbox[BOXLEFT] < line.v1.x then
      p2 = 1
    end
    if line.dy < 0 then
      p1 = bxor(p1, 1)
      p2 = bxor(p2, 1)
    end
  elseif line.dy == 0 then
    p1 = 0
    if bbox[BOXTOP] > line.v1.y then
      p1 = 1
    end
    p2 = 0
    if bbox[BOXBOTTOM] > line.v1.y then
      p2 = 1
    end
    if line.dx < 0 then
      p1 = bxor(p1, 1)
      p2 = bxor(p2, 1)
    end
  else
    local slope = 1
    if (line.dy > 0) == (line.dx > 0) then
      slope = 0
    end
    if slope == 0 then
      p1 = M.point_on_line_side(bbox[BOXLEFT], bbox[BOXTOP], line)
      p2 = M.point_on_line_side(bbox[BOXRIGHT], bbox[BOXBOTTOM], line)
    else
      p1 = M.point_on_line_side(bbox[BOXRIGHT], bbox[BOXTOP], line)
      p2 = M.point_on_line_side(bbox[BOXLEFT], bbox[BOXBOTTOM], line)
    end
  end
  if p1 == p2 then
    return p1
  end
  return -1
end

function M.line_opening(line)
  if line.backsector == nil then
    return 0, 0, 0
  end
  local front, back = line.frontsector, line.backsector
  local opentop = front.ceilingheight
  if back.ceilingheight < opentop then
    opentop = back.ceilingheight
  end
  if front.floorheight > back.floorheight then
    return opentop, front.floorheight, back.floorheight
  end
  return opentop, back.floorheight, front.floorheight
end

function M.approx_distance(dx, dy)
  dx, dy = math.abs(as_i32(dx)), math.abs(as_i32(dy))
  if dx < dy then
    return dx + dy - math.floor(dx / 2)
  end
  return dx + dy - math.floor(dy / 2)
end

function M.angle_to(x1, y1, x2, y2)
  tables.init()
  local x = as_i32(x2 - x1)
  local y = as_i32(y2 - y1)
  if x == 0 and y == 0 then
    return 0
  end
  if x >= 0 then
    if y >= 0 then
      if x > y then
        return tables.tantoangle[tables.slope_div(y, x)]
      end
      return as_u32(ANG90 - 1 - tables.tantoangle[tables.slope_div(x, y)])
    end
    y = -y
    if x > y then
      return as_u32(-tables.tantoangle[tables.slope_div(y, x)])
    end
    return as_u32(3221225472 + tables.tantoangle[tables.slope_div(x, y)])
  end
  x = -x
  if y >= 0 then
    if x > y then
      return as_u32(ANG180 - 1 - tables.tantoangle[tables.slope_div(y, x)])
    end
    return as_u32(ANG90 + tables.tantoangle[tables.slope_div(x, y)])
  end
  y = -y
  if x > y then
    return as_u32(ANG180 + tables.tantoangle[tables.slope_div(y, x)])
  end
  return as_u32(3221225472 - 1 - tables.tantoangle[tables.slope_div(x, y)])
end

function M.unset_thing_position(world, thing)
  if not thing.blocklinked then
    return
  end
  local nxt = thing.bnext
  local prev = thing.bprev
  if nxt then
    nxt.bprev = prev
  end
  if prev then
    prev.bnext = nxt
  else
    local i = thing._bindex or 0
    local links = world.blocklinks
    if i >= 1 and links[i] == thing then
      links[i] = nxt
    end
  end
  thing.bnext = nil
  thing.bprev = nil
  thing.blocklinked = false
end

function M.set_thing_position(world, thing)
  thing.subsector = M.point_in_subsector(world, thing.x, thing.y)
  if thing.blocklinked then
    M.unset_thing_position(world, thing)
  end
  local links = world.blocklinks
  thing.bnext = nil
  thing.bprev = nil
  thing.blocklinked = false
  if has(thing.flags, MF_NOBLOCKMAP) or not world.bmapwidth or world.bmapwidth == 0 then
    return
  end
  local bx = shar(thing.x - world.bmaporgx, MAPBLOCKSHIFT)
  local by = shar(thing.y - world.bmaporgy, MAPBLOCKSHIFT)
  if bx < 0 or by < 0 or bx >= world.bmapwidth or by >= world.bmapheight then
    return
  end
  local i = by * world.bmapwidth + bx + 1
  local head = links[i]
  thing.bnext = head
  if head then
    head.bprev = thing
  end
  links[i] = thing
  thing._bindex = i
  thing.blocklinked = true
end

function M.link_mobjs(world)
  for i = 1, #(world.mobjs or {}) do
    M.set_thing_position(world, world.mobjs[i])
  end
end

local function block_things(world, x, y, func)
  if x < 0 or y < 0 or x >= world.bmapwidth or y >= world.bmapheight then
    return true
  end
  local mo = world.blocklinks[y * world.bmapwidth + x + 1]
  while mo do
    local nxt = mo.bnext
    if not func(mo) then
      return false
    end
    mo = nxt
  end
  return true
end

local function pit_stomp_thing(tm, other, game)
  if not has(other.flags, MF_SHOOTABLE) then
    return true
  end
  local blockdist = (other.radius or 0) + (tm.radius or 0)
  if math.abs(other.x - tm._tmx) >= blockdist or math.abs(other.y - tm._tmy) >= blockdist then
    return true
  end
  if other == tm then
    return true
  end
  local mapn = 0
  if game ~= nil then
    mapn = game.mapn or 0
  end
  if tm.player == nil and mapn ~= 30 then
    return false
  end
  if game and game.damage_mobj then
    game.damage_mobj(other, tm, 10000, tm)
  end
  return true
end

function M.teleport_move(world, thing, x, y, game)
  thing._tmx = x
  thing._tmy = y
  local r = thing.radius or 0
  local bbox = {
    [BOXLEFT] = x - r,
    [BOXRIGHT] = x + r,
    [BOXBOTTOM] = y - r,
    [BOXTOP] = y + r,
  }
  local sub = M.point_in_subsector(world, x, y)
  local tmfloorz = sub.sector.floorheight
  local tmceilingz = sub.sector.ceilingheight
  world.validcount = (world.validcount or 0) + 1
  local links = world.blocklinks
  if links and world.bmapwidth and world.bmapwidth > 0 then
    local orgx = world.bmaporgx
    local orgy = world.bmaporgy
    local xl = shar(bbox[BOXLEFT] - orgx - MAXRADIUS, MAPBLOCKSHIFT)
    local xh = shar(bbox[BOXRIGHT] - orgx + MAXRADIUS, MAPBLOCKSHIFT)
    local yl = shar(bbox[BOXBOTTOM] - orgy - MAXRADIUS, MAPBLOCKSHIFT)
    local yh = shar(bbox[BOXTOP] - orgy + MAXRADIUS, MAPBLOCKSHIFT)
    for bx = xl, xh do
      for by = yl, yh do
        if not block_things(world, bx, by, function(th)
          return pit_stomp_thing(thing, th, game)
        end) then
          return false
        end
      end
    end
  end
  M.unset_thing_position(world, thing)
  thing.floorz = tmfloorz
  thing.ceilingz = tmceilingz
  thing.x = x
  thing.y = y
  M.set_thing_position(world, thing)
  return true
end

local function block_lines(world, x, y, func)
  if x < 0 or y < 0 or x >= world.bmapwidth or y >= world.bmapheight then
    return true
  end
  local lump = world.blockmaplump
  local offset = world.blockmap[y * world.bmapwidth + x + 1]
  while offset and offset >= 0 and offset < #lump do
    local n = lump[offset + 1]
    offset = offset + 1
    if n == 65535 then
      return true
    end
    if n < #world.lines then
      local ld = world.lines[n + 1]
      if ld.validcount ~= world.validcount then
        ld.validcount = world.validcount
        if not func(ld) then
          return false
        end
      end
    end
  end
  return true
end

local function same_species(target, other)
  if target.type == other.type then
    return true
  end
  if target.type == MT_KNIGHT and other.type == MT_BRUISER then
    return true
  end
  return target.type == MT_BRUISER and other.type == MT_KNIGHT
end

function M.missile_reaches(mo, other, x, y, z)
  if other == mo or other == mo.target then
    return false
  end
  if (other.health or 0) <= 0 or not has(other.flags, MF_SHOOTABLE) then
    return false
  end
  local reach = (other.radius or 0) + (mo.radius or 0)
  if math.abs(other.x - x) >= reach or math.abs(other.y - y) >= reach then
    return false
  end
  local slack = 64 * FRACUNIT
  local z1 = z + (mo.momz or 0)
  local low = math.min(z, z1) - slack
  local high = math.max(z, z1) + (mo.height or 0) + slack
  if mo.floorz ~= nil and z <= mo.floorz then
    low = math.min(low, mo.floorz - slack)
    high = math.max(high, mo.floorz + slack)
  end
  return low <= other.z + (other.height or 0) and high >= other.z
end

local function pit_thing(world, tm, other, game)
  if not has(other.flags, MF_SOLID + MF_SPECIAL + MF_SHOOTABLE) then
    return true
  end
  local blockdist = (other.radius or 0) + (tm.radius or 0)
  if math.abs(other.x - tm._tmx) >= blockdist or math.abs(other.y - tm._tmy) >= blockdist then
    return true
  end
  if other == tm then
    return true
  end
  if has(tm.flags, MF_SKULLFLY) then
    local info = require("info")
    local thinker = require("thinker")
    local base = info.MOBJINFO[tm.type or 0][info.MI_DAMAGE] or 0
    local dmg = ((rng.p_random() % 8) + 1) * base
    if game and game.damage_mobj then
      game.damage_mobj(other, tm, dmg, tm)
    end
    tm.flags = band(tm.flags, bnot(MF_SKULLFLY))
    tm.momx, tm.momy, tm.momz = 0, 0, 0
    thinker.set_mobj_state(tm, info.MOBJINFO[tm.type or 0][info.MI_SPAWNSTATE], world, game)
    return false
  end
  if has(tm.flags, MF_MISSILE) then
    if tm.z > other.z + (other.height or 0) then
      return true
    end
    if tm.z + (tm.height or 0) < other.z then
      return true
    end
    local target = tm.target
    if target and same_species(target, other) then
      if other == target then
        return true
      end
      if other.type ~= MT_PLAYER then
        return false
      end
    end
    if not has(other.flags, MF_SHOOTABLE) then
      return not has(other.flags, MF_SOLID)
    end
    if game and game.damage_mobj then
      local info = require("info")
      local base = tm.damage or info.MOBJINFO[tm.type or 0][info.MI_DAMAGE] or 0
      game.damage_mobj(other, tm.target, ((rng.p_random() % 8) + 1) * base, tm)
    end
    return false
  end
  if has(other.flags, MF_SPECIAL) then
    local solid = has(other.flags, MF_SOLID)
    if has(tm.flags, MF_PICKUP) and game and game.touch_special then
      game.touch_special(other, tm)
    end
    return not solid
  end
  return not has(other.flags, MF_SOLID)
end

local function pit_line(tm, chk, ld)
  local bbox = chk.bbox
  local lb = ld.bbox
  if bbox[BOXRIGHT] <= lb[BOXLEFT] or bbox[BOXLEFT] >= lb[BOXRIGHT]
    or bbox[BOXTOP] <= lb[BOXBOTTOM] or bbox[BOXBOTTOM] >= lb[BOXTOP] then
    return true
  end
  if box_on_line_side(bbox, ld) ~= -1 then
    return true
  end
  if ld.backsector == nil then
    return false
  end
  if not has(tm.flags, MF_MISSILE) then
    if has(ld.flags, ML_BLOCKING) then
      return false
    end
    if tm.player == nil and has(ld.flags, ML_BLOCKMONSTERS) then
      return false
    end
  end
  local opentop, openbottom, lowfloor = M.line_opening(ld)
  if opentop < chk.ceilingz then
    chk.ceilingz = opentop
    chk.ceilingline = ld
  end
  if openbottom > chk.floorz then
    chk.floorz = openbottom
  end
  if lowfloor < chk.dropoffz then
    chk.dropoffz = lowfloor
  end
  if ld.special ~= 0 then
    chk.spechit[#chk.spechit + 1] = ld
  end
  return true
end

function M.check_position(world, thing, x, y, game)
  local chk = {
    floorz = 0,
    ceilingz = 0,
    dropoffz = 0,
    spechit = {},
    blocked = false,
    ceilingline = nil,
    bbox = { 0, 0, 0, 0 },
  }
  thing._tmx, thing._tmy = x, y
  local radius = thing.radius or 0
  local bbox = chk.bbox
  bbox[BOXTOP] = y + radius
  bbox[BOXBOTTOM] = y - radius
  bbox[BOXRIGHT] = x + radius
  bbox[BOXLEFT] = x - radius
  local sub = M.point_in_subsector(world, x, y)
  chk.floorz = sub.sector.floorheight
  chk.dropoffz = chk.floorz
  chk.ceilingz = sub.sector.ceilingheight
  world.validcount = (world.validcount or 0) + 1
  if has(thing.flags, MF_NOCLIP) then
    return chk
  end
  if not world.bmapwidth or world.bmapwidth == 0 then
    return chk
  end
  local orgx, orgy = world.bmaporgx, world.bmaporgy
  local xl = shar(bbox[BOXLEFT] - orgx - MAXRADIUS, MAPBLOCKSHIFT)
  local xh = shar(bbox[BOXRIGHT] - orgx + MAXRADIUS, MAPBLOCKSHIFT)
  local yl = shar(bbox[BOXBOTTOM] - orgy - MAXRADIUS, MAPBLOCKSHIFT)
  local yh = shar(bbox[BOXTOP] - orgy + MAXRADIUS, MAPBLOCKSHIFT)
  for bx = xl, xh do
    for by = yl, yh do
      if not block_things(world, bx, by, function(th)
        return pit_thing(world, thing, th, game)
      end) then
        chk.blocked = true
        return chk
      end
    end
  end
  xl = shar(bbox[BOXLEFT] - orgx, MAPBLOCKSHIFT)
  xh = shar(bbox[BOXRIGHT] - orgx, MAPBLOCKSHIFT)
  yl = shar(bbox[BOXBOTTOM] - orgy, MAPBLOCKSHIFT)
  yh = shar(bbox[BOXTOP] - orgy, MAPBLOCKSHIFT)
  for bx = xl, xh do
    for by = yl, yh do
      if not block_lines(world, bx, by, function(ld)
        return pit_line(thing, chk, ld)
      end) then
        chk.blocked = true
        return chk
      end
    end
  end
  return chk
end

M.floatok = false
M.tmfloorz = 0
M.last_spechit = {}
M.ceilingline = nil

function M.try_move(world, thing, x, y, game)
  M.floatok = false
  M.ceilingline = nil
  local chk = M.check_position(world, thing, x, y, game)
  M.last_spechit = chk.spechit
  M.tmfloorz = chk.floorz
  M.ceilingline = chk.ceilingline
  if chk.blocked then
    return false
  end
  if not has(thing.flags, MF_NOCLIP) then
    if chk.ceilingz - chk.floorz < (thing.height or 0) then
      return false
    end
    M.floatok = true
    if not has(thing.flags, MF_TELEPORT) and chk.ceilingz - thing.z < (thing.height or 0) then
      return false
    end
    if not has(thing.flags, MF_TELEPORT) and chk.floorz - thing.z > MAXSTEP then
      return false
    end
    if not has(thing.flags, MF_DROPOFF + MF_FLOAT) and chk.floorz - chk.dropoffz > MAXSTEP then
      return false
    end
  end
  M.unset_thing_position(world, thing)
  local oldx, oldy = thing.x, thing.y
  thing.floorz = chk.floorz
  thing.ceilingz = chk.ceilingz
  thing.x = x
  thing.y = y
  M.set_thing_position(world, thing)
  if game and not has(thing.flags, MF_TELEPORT + MF_NOCLIP) and game.cross_special then
    for i = #chk.spechit, 1, -1 do
      local ln = chk.spechit[i]
      local side = M.point_on_line_side(thing.x, thing.y, ln)
      local oldside = M.point_on_line_side(oldx, oldy, ln)
      if side ~= oldside and ln.special ~= 0 then
        game.cross_special(ln, oldside, thing)
      end
    end
  end
  return true
end

local earlyout = false
local intercepts = {}
local trace = { x = 0, y = 0, dx = 0, dy = 0 }
local MAXINTERCEPTS_ORIGINAL = 128
M.bulletslope = 0
local open_top, open_bottom, open_range, low_floor = 0, 0, 0, 0
local overrun_world = nil
local playerstarts = {}
for _psi = 1, 8 do
  playerstarts[_psi] = { 0, 0, 0, 0, 0 }
end
local OVERRUN_TABLE = {
  { 4, nil, false }, { 4, nil, false }, { 4, nil, false },
  { 4, "lowfloor", false }, { 4, "openbottom", false }, { 4, "opentop", false },
  { 4, "openrange", false }, { 4, nil, false }, { 120, nil, false }, { 8, nil, false },
  { 4, "bulletslope", false }, { 4, nil, false }, { 4, nil, false }, { 4, nil, false },
  { 40, "playerstarts", true }, { 4, nil, false }, { 4, "bmapwidth", false },
  { 4, nil, false }, { 4, "bmaporgx", false }, { 4, "bmaporgy", false },
  { 4, nil, false }, { 4, "bmapheight", false },
}

local function as_i16(n)
  n = band(n, 65535)
  if n >= 32768 then
    return n - 65536
  end
  return n
end

local function overrun_set_player_start(index, value)
  local thing = math.floor(index / 5)
  local field = index % 5
  local row = playerstarts[thing + 1]
  if row == nil then
    return
  end
  row[field + 1] = as_i16(value)
end

local function intercepts_memory_overrun(location, value)
  local offset = 0
  for i = 1, #OVERRUN_TABLE do
    local length, name, int16_array = OVERRUN_TABLE[i][1], OVERRUN_TABLE[i][2], OVERRUN_TABLE[i][3]
    if offset + length > location then
      if name == nil then
        return
      end
      if int16_array then
        local index = math.floor((location - offset) / 2)
        overrun_set_player_start(index, band(value, 65535))
        overrun_set_player_start(index + 1, band(math.floor(value / 65536), 65535))
      elseif name == "lowfloor" then
        low_floor = value
      elseif name == "openbottom" then
        open_bottom = value
      elseif name == "opentop" then
        open_top = value
      elseif name == "openrange" then
        open_range = value
      elseif name == "bulletslope" then
        M.bulletslope = value
      elseif overrun_world ~= nil then
        if name == "bmapwidth" then
          overrun_world.bmapwidth = value
        elseif name == "bmaporgx" then
          overrun_world.bmaporgx = value
        elseif name == "bmaporgy" then
          overrun_world.bmaporgy = value
        elseif name == "bmapheight" then
          overrun_world.bmapheight = value
        end
      end
      return
    end
    offset = offset + length
  end
end

local function intercepts_overrun(inn)
  local num = #intercepts - 1
  if num <= MAXINTERCEPTS_ORIGINAL then
    return
  end
  local location = (num - MAXINTERCEPTS_ORIGINAL - 1) * 12
  intercepts_memory_overrun(location, inn.frac)
  intercepts_memory_overrun(location + 4, inn.isaline and 1 or 0)
  intercepts_memory_overrun(location + 8, 0)
end

local function div_trace()
  return { x = trace.x, y = trace.y, dx = trace.dx, dy = trace.dy }
end

local function point_on_divline_side(x, y, line)
  if line.dx == 0 then
    if x <= line.x then
      if line.dy > 0 then
        return 1
      end
      return 0
    end
    if line.dy < 0 then
      return 1
    end
    return 0
  end
  if line.dy == 0 then
    if y <= line.y then
      if line.dx < 0 then
        return 1
      end
      return 0
    end
    if line.dx > 0 then
      return 1
    end
    return 0
  end
  local dx = x - line.x
  local dy = y - line.y
  local xorv = bxor(bxor(bxor(as_u32(line.dy), as_u32(line.dx)), as_u32(dx)), as_u32(dy))
  if band(xorv, 2147483648) ~= 0 then
    if band(bxor(as_u32(line.dy), as_u32(dx)), 2147483648) ~= 0 then
      return 1
    end
    return 0
  end
  local left = fixed_mul(shar(line.dy, 8), shar(dx, 8))
  local right = fixed_mul(shar(dy, 8), shar(line.dx, 8))
  if right < left then
    return 0
  end
  return 1
end

local function intercept_vector(v2, v1)
  local den = as_i32(fixed_mul(shar(v1.dy, 8), v2.dx) - fixed_mul(shar(v1.dx, 8), v2.dy))
  if den == 0 then
    return 0
  end
  local num = as_i32(fixed_mul(shar(v1.x - v2.x, 8), v1.dy) + fixed_mul(shar(v2.y - v1.y, 8), v1.dx))
  return fixed_div(num, den)
end

local function add_line_intercept(ld)
  local big = 16 * FRACUNIT
  local dx, dy = trace.dx, trace.dy
  local s1, s2
  if dx > big or dy > big or dx < -big or dy < -big then
    local tr = div_trace()
    s1 = point_on_divline_side(ld.v1.x, ld.v1.y, tr)
    s2 = point_on_divline_side(ld.v2.x, ld.v2.y, tr)
  else
    s1 = M.point_on_line_side(trace.x, trace.y, ld)
    s2 = M.point_on_line_side(trace.x + dx, trace.y + dy, ld)
  end
  if s1 == s2 then
    return true
  end
  local frac = intercept_vector(div_trace(), { x = ld.v1.x, y = ld.v1.y, dx = ld.dx, dy = ld.dy })
  if frac < 0 then
    return true
  end
  if earlyout and frac < FRACUNIT and ld.backsector == nil then
    return false
  end
  local inn = { frac = frac, isaline = true, line = ld, thing = nil }
  intercepts[#intercepts + 1] = inn
  intercepts_overrun(inn)
  return true
end

local function add_thing_intercept(thing)
  local tr = div_trace()
  local positive = as_i32(bxor(as_u32(tr.dx), as_u32(tr.dy))) > 0
  local x1, y1, x2, y2
  local radius = thing.radius or 0
  if positive then
    x1, y1 = thing.x - radius, thing.y + radius
    x2, y2 = thing.x + radius, thing.y - radius
  else
    x1, y1 = thing.x - radius, thing.y - radius
    x2, y2 = thing.x + radius, thing.y + radius
  end
  if point_on_divline_side(x1, y1, tr) == point_on_divline_side(x2, y2, tr) then
    return true
  end
  local frac = intercept_vector(tr, { x = x1, y = y1, dx = x2 - x1, dy = y2 - y1 })
  if frac < 0 then
    return true
  end
  local inn = { frac = frac, isaline = false, line = nil, thing = thing }
  intercepts[#intercepts + 1] = inn
  intercepts_overrun(inn)
  return true
end

local function traverse_intercepts(func, maxfrac)
  local count = #intercepts
  while count > 0 do
    count = count - 1
    local dist = INT_MAX
    local chosen = nil
    for i = 1, #intercepts do
      local scan = intercepts[i]
      if scan.frac < dist then
        dist = scan.frac
        chosen = scan
      end
    end
    if dist > maxfrac then
      return true
    end
    if chosen == nil or not func(chosen) then
      return false
    end
    chosen.frac = INT_MAX
  end
  return true
end

function M.path_traverse(world, x1, y1, x2, y2, flags, trav)
  overrun_world = world
  earlyout = band(flags, PT_EARLYOUT) ~= 0
  world.validcount = (world.validcount or 0) + 1
  intercepts = {}
  local orgx, orgy = world.bmaporgx, world.bmaporgy
  if band(as_i32(x1 - orgx), MAPBLOCKSIZE - 1) == 0 then
    x1 = x1 + FRACUNIT
  end
  if band(as_i32(y1 - orgy), MAPBLOCKSIZE - 1) == 0 then
    y1 = y1 + FRACUNIT
  end
  trace.x = x1
  trace.y = y1
  trace.dx = as_i32(x2 - x1)
  trace.dy = as_i32(y2 - y1)
  local x1m = as_i32(x1 - orgx)
  local y1m = as_i32(y1 - orgy)
  local xt1 = shar(x1m, MAPBLOCKSHIFT)
  local yt1 = shar(y1m, MAPBLOCKSHIFT)
  local x2m = as_i32(x2 - orgx)
  local y2m = as_i32(y2 - orgy)
  local xt2 = shar(x2m, MAPBLOCKSHIFT)
  local yt2 = shar(y2m, MAPBLOCKSHIFT)
  local mapxstep, mapystep, partial, ystep, xstep
  if xt2 > xt1 then
    mapxstep = 1
    partial = FRACUNIT - band(shar(x1m, MAPBTOFRAC), FRACUNIT - 1)
    ystep = fixed_div(as_i32(y2m - y1m), abs32(as_i32(x2m - x1m)))
  elseif xt2 < xt1 then
    mapxstep = -1
    partial = band(shar(x1m, MAPBTOFRAC), FRACUNIT - 1)
    ystep = fixed_div(as_i32(y2m - y1m), abs32(as_i32(x2m - x1m)))
  else
    mapxstep = 0
    partial = FRACUNIT
    ystep = 256 * FRACUNIT
  end
  local yintercept = as_i32(shar(y1m, MAPBTOFRAC) + fixed_mul(partial, ystep))
  if yt2 > yt1 then
    mapystep = 1
    partial = FRACUNIT - band(shar(y1m, MAPBTOFRAC), FRACUNIT - 1)
    xstep = fixed_div(as_i32(x2m - x1m), abs32(as_i32(y2m - y1m)))
  elseif yt2 < yt1 then
    mapystep = -1
    partial = band(shar(y1m, MAPBTOFRAC), FRACUNIT - 1)
    xstep = fixed_div(as_i32(x2m - x1m), abs32(as_i32(y2m - y1m)))
  else
    mapystep = 0
    partial = FRACUNIT
    xstep = 256 * FRACUNIT
  end
  local xintercept = as_i32(shar(x1m, MAPBTOFRAC) + fixed_mul(partial, xstep))
  local mapx, mapy = xt1, yt1
  for _ = 1, 64 do
    if band(flags, PT_ADDLINES) ~= 0 then
      if not block_lines(world, mapx, mapy, add_line_intercept) then
        return false
      end
    end
    if band(flags, PT_ADDTHINGS) ~= 0 then
      if not block_things(world, mapx, mapy, add_thing_intercept) then
        return false
      end
    end
    if mapx == xt2 and mapy == yt2 then
      break
    end
    if shar(yintercept, FRACBITS) == mapy then
      yintercept = as_i32(yintercept + ystep)
      mapx = mapx + mapxstep
    elseif shar(xintercept, FRACBITS) == mapx then
      xintercept = as_i32(xintercept + xstep)
      mapy = mapy + mapystep
    end
  end
  return traverse_intercepts(trav, FRACUNIT)
end

local function stairstep(world, thing, game)
  if not M.try_move(world, thing, thing.x, thing.y + thing.momy, game) then
    M.try_move(world, thing, thing.x + thing.momx, thing.y, game)
  end
end

local function hit_slide_line(thing, line, tmx, tmy)
  if line.dy == 0 then
    return tmx, 0
  end
  if line.dx == 0 then
    return 0, tmy
  end
  local side = M.point_on_line_side(thing.x, thing.y, line)
  local lineangle = M.angle_to(0, 0, line.dx, line.dy)
  if side == 1 then
    lineangle = as_u32(lineangle + ANG180)
  end
  local moveangle = M.angle_to(0, 0, tmx, tmy)
  local delta = as_u32(moveangle - lineangle)
  if delta > ANG180 then
    delta = as_u32(delta + ANG180)
  end
  local newlen = fixed_mul(M.approx_distance(tmx, tmy), tables.fine_cos(delta))
  return fixed_mul(newlen, tables.fine_cos(lineangle)), fixed_mul(newlen, tables.fine_sin(lineangle))
end

local function trace_slide_corner(world, thing, x1, y1, x2, y2, best)
  M.path_traverse(world, x1, y1, x2, y2, PT_ADDLINES, function(inn)
    local li = inn.line
    local blocking = false
    if not has(li.flags, ML_TWOSIDED) then
      if M.point_on_line_side(thing.x, thing.y, li) ~= 0 then
        return true
      end
      blocking = true
    else
      local opentop, openbottom = M.line_opening(li)
      if opentop - openbottom < (thing.height or 0) then
        blocking = true
      elseif opentop - thing.z < (thing.height or 0) then
        blocking = true
      elseif openbottom - thing.z > 24 * FRACUNIT then
        blocking = true
      end
    end
    if not blocking then
      return true
    end
    if inn.frac < best[1] then
      best[1] = inn.frac
      best[2] = li
    end
    return false
  end)
end

function M.slide_move(world, thing, momx, momy, game)
  if math.abs(momx) > MAXMOVE then
    if momx > 0 then
      momx = MAXMOVE
    else
      momx = -MAXMOVE
    end
  end
  if math.abs(momy) > MAXMOVE then
    if momy > 0 then
      momy = MAXMOVE
    else
      momy = -MAXMOVE
    end
  end
  thing.momx = momx
  thing.momy = momy
  local hitcount = 0
  while true do
    hitcount = hitcount + 1
    if hitcount == 3 then
      stairstep(world, thing, game)
      return
    end
    local leadx, trailx, leady, traily
    if thing.momx > 0 then
      leadx = thing.x + thing.radius
      trailx = thing.x - thing.radius
    else
      leadx = thing.x - thing.radius
      trailx = thing.x + thing.radius
    end
    if thing.momy > 0 then
      leady = thing.y + thing.radius
      traily = thing.y - thing.radius
    else
      leady = thing.y - thing.radius
      traily = thing.y + thing.radius
    end
    local best = { FRACUNIT + 1, nil }
    local mx, my = thing.momx, thing.momy
    trace_slide_corner(world, thing, leadx, leady, leadx + mx, leady + my, best)
    trace_slide_corner(world, thing, trailx, leady, trailx + mx, leady + my, best)
    trace_slide_corner(world, thing, leadx, traily, leadx + mx, traily + my, best)
    if best[1] == FRACUNIT + 1 or best[2] == nil then
      stairstep(world, thing, game)
      return
    end
    best[1] = best[1] - 2048
    if best[1] > 0 then
      local newx = fixed_mul(thing.momx, best[1])
      local newy = fixed_mul(thing.momy, best[1])
      if not M.try_move(world, thing, thing.x + newx, thing.y + newy, game) then
        stairstep(world, thing, game)
        return
      end
    end
    best[1] = FRACUNIT - (best[1] + 2048)
    if best[1] > FRACUNIT then
      best[1] = FRACUNIT
    end
    if best[1] <= 0 then
      return
    end
    local tmx = fixed_mul(thing.momx, best[1])
    local tmy = fixed_mul(thing.momy, best[1])
    tmx, tmy = hit_slide_line(thing, best[2], tmx, tmy)
    thing.momx = tmx
    thing.momy = tmy
    if M.try_move(world, thing, thing.x + tmx, thing.y + tmy, game) then
      return
    end
  end
end

function M.use_lines(world, player, game)
  local mo = player.mo
  local x1, y1 = mo.x, mo.y
  local x2 = x1 + shar(USERANGE, FRACBITS) * tables.fine_cos(mo.angle)
  local y2 = y1 + shar(USERANGE, FRACBITS) * tables.fine_sin(mo.angle)
  M.path_traverse(world, x1, y1, x2, y2, PT_ADDLINES, function(inn)
    local ln = inn.line
    if ln.special == 0 then
      local opentop, openbottom = M.line_opening(ln)
      if opentop - openbottom <= 0 then
        if game and game.start_sound then
          game.start_sound("noway")
        end
        return false
      end
      return true
    end
    local side = 0
    if M.point_on_line_side(mo.x, mo.y, ln) == 1 then
      side = 1
    end
    if game and game.use_special then
      game.use_special(ln, mo, side)
    end
    return false
  end)
end

local function shot_ends(source, angle, attackrange)
  local x2 = source.x + shar(attackrange, FRACBITS) * tables.fine_cos(angle)
  local y2 = source.y + shar(attackrange, FRACBITS) * tables.fine_sin(angle)
  local shootz = source.z + shar(source.height or 0, 1) + 8 * FRACUNIT
  return x2, y2, shootz
end

local function aim(world, source, angle, attackrange)
  local x2, y2, shootz = shot_ends(source, angle, attackrange)
  local window = math.floor((100 * FRACUNIT) / 160)
  local state = { top = window, bottom = -window, slope = 0, target = nil }
  M.path_traverse(world, source.x, source.y, x2, y2, PT_ADDLINES + PT_ADDTHINGS, function(inn)
    if inn.isaline then
      local li = inn.line
      if not has(li.flags, ML_TWOSIDED) then
        return false
      end
      local opentop, openbottom = M.line_opening(li)
      if openbottom >= opentop then
        return false
      end
      local dist = fixed_mul(attackrange, inn.frac)
      local front, back = li.frontsector, li.backsector
      if back == nil or front.floorheight ~= back.floorheight then
        local slope = fixed_div(openbottom - shootz, dist)
        if slope > state.bottom then
          state.bottom = slope
        end
      end
      if back == nil or front.ceilingheight ~= back.ceilingheight then
        local slope = fixed_div(opentop - shootz, dist)
        if slope < state.top then
          state.top = slope
        end
      end
      return state.top > state.bottom
    end
    local th = inn.thing
    if th == source or not has(th.flags, MF_SHOOTABLE) then
      return true
    end
    local dist = fixed_mul(attackrange, inn.frac)
    local thingtop = fixed_div(th.z + (th.height or 0) - shootz, dist)
    if thingtop < state.bottom then
      return true
    end
    local thingbot = fixed_div(th.z - shootz, dist)
    if thingbot > state.top then
      return true
    end
    if thingtop > state.top then
      thingtop = state.top
    end
    if thingbot < state.bottom then
      thingbot = state.bottom
    end
    state.slope = math.floor((thingtop + thingbot) / 2)
    state.target = th
    return false
  end)
  if state.target then
    return state.slope, state.target
  end
  return 0, nil
end

function M.aim_slope(world, source, angle, attackrange)
  local slope, target = aim(world, source, angle, attackrange)
  if target then
    return slope
  end
  return 0
end

function M.aim_line_attack(world, source, angle, attackrange)
  local _, target = aim(world, source, angle, attackrange)
  return target
end

function M.missile_aim(world, source, span)
  local base = source.angle
  span = span or (16 * 64 * FRACUNIT)
  local angles = { base, as_u32(base + 67108864), as_u32(base - 67108864) }
  for i = 1, 3 do
    local slope, target = aim(world, source, angles[i], span)
    if target then
      return angles[i], slope
    end
  end
  return base, 0
end

function M.bullet_slope(world, source)
  local base = source.angle
  local span = 16 * 64 * FRACUNIT
  local angles = { base, as_u32(base + 67108864), as_u32(base - 67108864) }
  for i = 1, 3 do
    local slope, target = aim(world, source, angles[i], span)
    if target then
      M.bulletslope = slope
      return slope
    end
  end
  M.bulletslope = 0
  return 0
end

local function spawn_fx(world, x, y, z, sprite, momz)
  local sub = M.point_in_subsector(world, x, y)
  local mo = {
    x = x,
    y = y,
    z = z,
    momx = 0,
    momy = 0,
    momz = momz,
    radius = 20 * FRACUNIT,
    height = 16 * FRACUNIT,
    floorz = sub.sector.floorheight,
    ceilingz = sub.sector.ceilingheight,
    flags = MF_NOBLOCKMAP,
    sprite = sprite,
    frame = 0,
    player = nil,
    fx = true,
    tics = 8,
    health = 0,
  }
  world.mobjs[#world.mobjs + 1] = mo
  return mo
end

local function spawn_puff(world, x, y, z, game, attackrange)
  z = z + (rng.p_random() - rng.p_random()) * 1024
  local th = spawn_fx(world, x, y, z, "PUFF", FRACUNIT)
  rng.p_random()
  th.tics = th.tics - band(rng.p_random(), 3)
  if th.tics < 1 then
    th.tics = 1
  end
  if attackrange == MELEERANGE then
    th.frame = 2
  end
  return th
end

local function spawn_blood(world, x, y, z, game, damage)
  z = z + (rng.p_random() - rng.p_random()) * 1024
  local th = spawn_fx(world, x, y, z, "BLUD", FRACUNIT * 2)
  rng.p_random()
  th.tics = th.tics - band(rng.p_random(), 3)
  if th.tics < 1 then
    th.tics = 1
  end
  if damage <= 12 and damage >= 9 then
    th.frame = 1
  elseif damage < 9 then
    th.frame = 2
  end
  return th
end

function M.line_attack(world, source, damage, game, attackrange, angle, slope)
  tables.init()
  local ang = source.angle
  if angle ~= nil then
    ang = angle
  end
  local aimslope = slope
  if aimslope == nil then
    aimslope = aim(world, source, ang, attackrange)
  end
  local x2, y2, shootz = shot_ends(source, ang, attackrange)
  local sky = -1
  if game and game.res then
    sky = game.res.skyflatnum or -1
  end
  local hit = false
  M.path_traverse(world, source.x, source.y, x2, y2, PT_ADDLINES + PT_ADDTHINGS, function(inn)
    if inn.isaline then
      local li = inn.line
      if li.special ~= 0 and game and game.shoot_special then
        game.shoot_special(li, source)
      end
      local hit_line = false
      if not has(li.flags, ML_TWOSIDED) then
        hit_line = true
      else
        local opentop, openbottom = M.line_opening(li)
        local dist = fixed_mul(attackrange, inn.frac)
        local front, back = li.frontsector, li.backsector
        if back == nil then
          if fixed_div(openbottom - shootz, dist) > aimslope then
            hit_line = true
          elseif fixed_div(opentop - shootz, dist) < aimslope then
            hit_line = true
          end
        else
          if front.floorheight ~= back.floorheight and fixed_div(openbottom - shootz, dist) > aimslope then
            hit_line = true
          end
          if not hit_line and front.ceilingheight ~= back.ceilingheight and fixed_div(opentop - shootz, dist) < aimslope then
            hit_line = true
          end
        end
      end
      if not hit_line then
        return true
      end
      local frac = inn.frac - fixed_div(4 * FRACUNIT, attackrange)
      local x = trace.x + fixed_mul(trace.dx, frac)
      local y = trace.y + fixed_mul(trace.dy, frac)
      local z = shootz + fixed_mul(aimslope, fixed_mul(frac, attackrange))
      local front = li.frontsector
      if front and front.ceilingpic == sky then
        if z > front.ceilingheight then
          return false
        end
        if li.backsector and li.backsector.ceilingpic == sky then
          return false
        end
      end
      spawn_puff(world, x, y, z, game, attackrange)
      return false
    end
    local th = inn.thing
    if th == source or not has(th.flags, MF_SHOOTABLE) then
      return true
    end
    local dist = fixed_mul(attackrange, inn.frac)
    if fixed_div(th.z + (th.height or 0) - shootz, dist) < aimslope then
      return true
    end
    if fixed_div(th.z - shootz, dist) > aimslope then
      return true
    end
    local frac = inn.frac - fixed_div(10 * FRACUNIT, attackrange)
    local x = trace.x + fixed_mul(trace.dx, frac)
    local y = trace.y + fixed_mul(trace.dy, frac)
    local z = shootz + fixed_mul(aimslope, fixed_mul(frac, attackrange))
    if has(th.flags, MF_NOBLOOD) then
      spawn_puff(world, x, y, z, game, attackrange)
    else
      spawn_blood(world, x, y, z, game, damage)
    end
    if game and game.damage_mobj and damage ~= 0 then
      game.damage_mobj(th, source, damage, source)
    end
    hit = true
    return false
  end)
  return hit
end

local function intercept_frac(x1, y1, x2, y2, line)
  local ax, ay = x1 / FRACUNIT, y1 / FRACUNIT
  local bx, by = x2 / FRACUNIT, y2 / FRACUNIT
  local cx, cy = line.v1.x / FRACUNIT, line.v1.y / FRACUNIT
  local dx, dy = line.v2.x / FRACUNIT, line.v2.y / FRACUNIT
  local den = (bx - ax) * (dy - cy) - (by - ay) * (dx - cx)
  if math.abs(den) < 1e-8 then
    return nil
  end
  local t = ((cx - ax) * (dy - cy) - (cy - ay) * (dx - cx)) / den
  local u = ((cx - ax) * (by - ay) - (cy - ay) * (bx - ax)) / den
  if t < 0 or t > 1 or u < 0 or u > 1 then
    return nil
  end
  return math.floor(t * FRACUNIT)
end

local NF_SUBSECTOR = 32768

local function shar64(n, bits)
  return math.floor(n / (2 ^ bits))
end

local function sight_side(x, y, lx, ly, ldx, ldy)
  if ldx == 0 then
    if x == lx then
      return 2
    end
    if x <= lx then
      return ldy > 0 and 1 or 0
    end
    return ldy < 0 and 1 or 0
  end
  if ldy == 0 then
    if x == ly then
      return 2
    end
    if y <= ly then
      return ldx < 0 and 1 or 0
    end
    return ldx > 0 and 1 or 0
  end
  local dx = shar64(x - lx, FRACBITS)
  local dy = shar64(y - ly, FRACBITS)
  local left = shar64(ldy, FRACBITS) * dx
  local right = dy * shar64(ldx, FRACBITS)
  if right < left then
    return 0
  end
  if left == right then
    return 2
  end
  return 1
end

local function intercept_vector(v2, v1)
  local den = as_i32(fixed_mul(shar(v1.dy, 8), v2.dx) - fixed_mul(shar(v1.dx, 8), v2.dy))
  if den == 0 then
    return 0
  end
  local num = as_i32(fixed_mul(shar(v1.x - v2.x, 8), v1.dy) + fixed_mul(shar(v2.y - v1.y, 8), v1.dx))
  return fixed_div(num, den)
end

local function cross_sight_subsector(world, num, st)
  if num < 0 or num >= #world.subsectors then
    num = 0
  end
  local sub = world.subsectors[num + 1]
  local n_seg = sub.firstline
  for _ = 1, sub.numlines do
    local seg = world.segs[n_seg + 1]
    n_seg = n_seg + 1
    local line = seg and seg.linedef
    if seg ~= nil and line ~= nil and line.v1 ~= nil and line.v2 ~= nil then
      if line.validcount ~= world.validcount then
        line.validcount = world.validcount
        local s1 = sight_side(line.v1.x, line.v1.y, st.x, st.y, st.dx, st.dy)
        local s2 = sight_side(line.v2.x, line.v2.y, st.x, st.y, st.dx, st.dy)
        if s1 ~= s2 then
          local ldx = as_i32(line.v2.x - line.v1.x)
          local ldy = as_i32(line.v2.y - line.v1.y)
          s1 = sight_side(st.x, st.y, line.v1.x, line.v1.y, ldx, ldy)
          s2 = sight_side(st.t2x, st.t2y, line.v1.x, line.v1.y, ldx, ldy)
          if s1 ~= s2 then
            if line.backsector == nil or band(line.flags, ML_TWOSIDED) == 0 then
              return false
            end
            local front = seg.frontsector
            local back = seg.backsector
            if front == nil or back == nil then
              return false
            end
            if not (front.floorheight == back.floorheight and front.ceilingheight == back.ceilingheight) then
              local opentop = math.min(front.ceilingheight, back.ceilingheight)
              local openbottom = math.max(front.floorheight, back.floorheight)
              if openbottom >= opentop then
                return false
              end
              local frac = intercept_vector(
                { x = st.x, y = st.y, dx = st.dx, dy = st.dy },
                { x = line.v1.x, y = line.v1.y, dx = ldx, dy = ldy }
              )
              if front.floorheight ~= back.floorheight then
                local slope = fixed_div(openbottom - st.z, frac)
                if slope > st.bottom then
                  st.bottom = slope
                end
              end
              if front.ceilingheight ~= back.ceilingheight then
                local slope = fixed_div(opentop - st.z, frac)
                if slope < st.top then
                  st.top = slope
                end
              end
              if st.top <= st.bottom then
                return false
              end
            end
          end
        end
      end
    end
  end
  return true
end

local function cross_sight_bsp(world, bspnum, st)
  if band(bspnum, NF_SUBSECTOR) ~= 0 or bspnum < 0 then
    if band(bspnum, 65535) == 65535 then
      return cross_sight_subsector(world, 0, st)
    end
    return cross_sight_subsector(world, band(bspnum, 32767), st)
  end
  if bspnum >= #world.nodes then
    return true
  end
  local node = world.nodes[bspnum + 1]
  local side = sight_side(st.x, st.y, node.x, node.y, node.dx, node.dy)
  if side == 2 then
    side = 0
  end
  if not cross_sight_bsp(world, node.children[side + 1], st) then
    return false
  end
  local other = sight_side(st.t2x, st.t2y, node.x, node.y, node.dx, node.dy)
  if side == other then
    return true
  end
  return cross_sight_bsp(world, node.children[bxor(side, 1) + 1], st)
end

function M.check_sight(world, t1, t2)
  local s1 = (t1.subsector or M.point_in_subsector(world, t1.x, t1.y)).sector
  local s2 = (t2.subsector or M.point_in_subsector(world, t2.x, t2.y)).sector
  local nsec = #world.sectors
  local rej = world.rejectmatrix or ""
  if nsec > 0 and #rej > 0 then
    local pnum = s1.i_sector * nsec + s2.i_sector
    local bytenum = math.floor(pnum / 8)
    local bitnum = 2 ^ (pnum % 8)
    if bytenum < #rej and band(rej:byte(bytenum + 1), bitnum) ~= 0 then
      return false
    end
  end
  local eye = t1.z + (t1.height or 0) - shar(t1.height or 0, 2)
  local st = {
    top = (t2.z + (t2.height or 0)) - eye,
    bottom = t2.z - eye,
    z = eye,
    x = t1.x,
    y = t1.y,
    dx = t2.x - t1.x,
    dy = t2.y - t1.y,
    t2x = t2.x,
    t2y = t2.y,
  }
  world.validcount = (world.validcount or 0) + 1
  if (world.numnodes or 0) == 0 then
    return cross_sight_subsector(world, 0, st)
  end
  return cross_sight_bsp(world, world.numnodes - 1, st)
end

function M.thing_height_clip(world, thing)
  local on_floor = thing.z == thing.floorz
  local chk = M.check_position(world, thing, thing.x, thing.y)
  thing.floorz = chk.floorz
  thing.ceilingz = chk.ceilingz
  if on_floor then
    thing.z = thing.floorz
  elseif thing.z + (thing.height or 0) > thing.ceilingz then
    thing.z = thing.ceilingz - (thing.height or 0)
  end
  if thing.player then
    thing.player.viewz = thing.z + thing.player.viewheight
  end
  return thing.ceilingz - thing.floorz >= (thing.height or 0)
end

local MF_DROPPED = 131072

function M.change_sector(world, sector, crush, game)
  local nofit = false
  local thinker = require("thinker")
  local info = require("info")
  local leveltime = 0
  if game then
    leveltime = game.leveltime or 0
  end
  local seen = {}
  local bb = sector.blockbox or { 0, 0, 0, 0 }
  local function pit(thing)
    if seen[thing] then
      return true
    end
    seen[thing] = true
    if M.thing_height_clip(world, thing) then
      return true
    end
    if (thing.health or 0) <= 0 then
      if game then
        thinker.set_mobj_state(thing, info.S_GIBS, world, game)
      end
      thing.flags = band(thing.flags or 0, bnot(MF_SOLID))
      thing.height = 0
      thing.radius = 0
      return true
    end
    if band(thing.flags or 0, MF_DROPPED) ~= 0 then
      thinker.remove_mobj(world, thing)
      return true
    end
    if not has(thing.flags, MF_SHOOTABLE) then
      return true
    end
    nofit = true
    if crush and game and band(leveltime, 3) == 0 then
      game.damage_mobj(thing, nil, 10)
      local blood = thinker.spawn_mobj(
        world, thing.x, thing.y, thing.z + math.floor((thing.height or 0) / 2), info.MT_BLOOD, game
      )
      blood.momx = (rng.p_random() - rng.p_random()) * 4096
      blood.momy = (rng.p_random() - rng.p_random()) * 4096
    end
    return true
  end
  local xl = bb[BOXLEFT] or 0
  local xh = bb[BOXRIGHT] or 0
  local yl = bb[BOXBOTTOM] or 0
  local yh = bb[BOXTOP] or 0
  for bx = xl, xh do
    for by = yl, yh do
      block_things(world, bx, by, pit)
    end
  end
  return nofit
end

M.MF_SOLID = MF_SOLID
M.MF_SHOOTABLE = MF_SHOOTABLE
M.MELEERANGE = MELEERANGE
M.USERANGE = USERANGE

return M
