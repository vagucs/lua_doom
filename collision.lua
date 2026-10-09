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
    if bbox[BOXRIGHT] >= line.v1.x then
      p1 = 1
    end
    p2 = 0
    if bbox[BOXLEFT] >= line.v1.x then
      p2 = 1
    end
    if line.dy > 0 then
      p1 = bxor(p1, 1)
      p2 = bxor(p2, 1)
    end
  elseif line.dy == 0 then
    p1 = 0
    if bbox[BOXTOP] <= line.v1.y then
      p1 = 1
    end
    p2 = 0
    if bbox[BOXBOTTOM] <= line.v1.y then
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
  dx, dy = math.abs(dx), math.abs(dy)
  if dx < dy then
    dx, dy = dy, dx
  end
  return dx + math.floor(dy / 2)
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
    local dmg = ((rng.p_random() % 8) + 1) * (tm.damage or 0)
    if game and game.damage_mobj then
      game.damage_mobj(other, tm, dmg, tm)
    end
    tm.flags = band(tm.flags, bnot(MF_SKULLFLY))
    tm.momx, tm.momy, tm.momz = 0, 0, 0
    return false
  end
  if has(tm.flags, MF_MISSILE) then
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
    if not M.missile_reaches(tm, other, tm._tmx, tm._tmy, tm.z) then
      return true
    end
    tm.struck = other
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
  intercepts[#intercepts + 1] = { frac = frac, isaline = true, line = ld, thing = nil }
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
  intercepts[#intercepts + 1] = { frac = frac, isaline = false, line = nil, thing = thing }
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

local function slide_blocks(thing, li)
  if not has(li.flags, ML_TWOSIDED) or li.backsector == nil then
    return M.point_on_line_side(thing.x, thing.y, li) == 0
  end
  local opentop, openbottom = M.line_opening(li)
  if opentop - openbottom < thing.height then
    return true
  end
  if opentop - thing.z < thing.height then
    return true
  end
  if openbottom - thing.z > 24 * FRACUNIT then
    return true
  end
  return has(li.flags, ML_BLOCKING)
end

local function intercept_frac(x1, y1, x2, y2, line)
  local u = FRACUNIT
  local ax, ay = x1 / u, y1 / u
  local bx, by = x2 / u, y2 / u
  local cx, cy = line.v1.x / u, line.v1.y / u
  local dx, dy = line.v2.x / u, line.v2.y / u
  local den = (bx - ax) * (dy - cy) - (by - ay) * (dx - cx)
  if math.abs(den) < 1e-8 then
    return -1
  end
  local t = ((cx - ax) * (dy - cy) - (cy - ay) * (dx - cx)) / den
  local v = ((cx - ax) * (by - ay) - (cy - ay) * (bx - ax)) / den
  if t < 0 or t > 1 or v < 0 or v > 1 then
    return -1
  end
  return math.floor(t * u)
end

local function trace_slide_corner(world, thing, x1, y1, x2, y2, best)
  local lines = world.lines
  for i = 1, #lines do
    local ln = lines[i]
    local frac = intercept_frac(x1, y1, x2, y2, ln)
    if frac >= 0 and frac <= FRACUNIT and slide_blocks(thing, ln) and frac < best[1] then
      best[1] = frac
      best[2] = ln
    end
  end
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
      return slope
    end
  end
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

function M.check_sight(world, t1, t2)
  local s1 = M.point_in_subsector(world, t1.x, t1.y).sector
  local s2 = M.point_in_subsector(world, t2.x, t2.y).sector
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
  if s1 == s2 then
    return true
  end
  local x1, y1, x2, y2 = t1.x, t1.y, t2.x, t2.y
  local margin = math.floor(FRACUNIT / 64)
  for i = 1, #world.lines do
    local ln = world.lines[i]
    local open = false
    if ln.backsector ~= nil then
      local opentop, openbottom = M.line_opening(ln)
      open = opentop - openbottom > 0
    end
    if not open then
      local frac = intercept_frac(x1, y1, x2, y2, ln)
      if frac ~= nil and margin < frac and frac < FRACUNIT - margin then
        return false
      end
    end
  end
  return true
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

function M.change_sector(world, sector, crush)
  local nofit = false
  local mobjs = world.mobjs or {}
  for i = 1, #mobjs do
    local thing = mobjs[i]
    if M.point_in_subsector(world, thing.x, thing.y).sector == sector then
      if not M.thing_height_clip(world, thing) then
        if (thing.health or 0) <= 0 then
          thing.flags = band(thing.flags or 0, bnot(MF_SOLID))
          thing.height = 0
        elseif has(thing.flags, MF_SHOOTABLE) then
          nofit = true
          if crush then
            thing.health = thing.health - 10
            if thing.player then
              thing.player.health = thing.health
            end
            if thing.health <= 0 then
              thing.health = 0
              if thing.player then
                thing.player.health = 0
              end
              thing.flags = band(thing.flags or 0, bnot(MF_SOLID))
              thing.height = 0
            end
          end
        end
      end
    end
  end
  return nofit
end

M.MF_SOLID = MF_SOLID
M.MF_SHOOTABLE = MF_SHOOTABLE
M.MELEERANGE = MELEERANGE
M.USERANGE = USERANGE

return M
