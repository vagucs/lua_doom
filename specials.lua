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
-- Portas, plataformas, pisos, tetos e interruptores, a partir de specials.py.

local collision = require("collision")
local rdata = require("r_data")
local rng = require("random")
local compat = require("compat")

local M = {}

local band = compat.band
local FRACUNIT = 65536
local TICRATE = 35
local VDOORSPEED = 2 * FRACUNIT
local VDOORWAIT = 150
local PLATSPEED = FRACUNIT
local PLATWAIT = 3
local FLOORSPEED = FRACUNIT
local CEILSPEED = FRACUNIT
local GLOWSPEED = 8
local STROBEBRIGHT = 5
local FASTDARK = 15
local SLOWDARK = 35
local BUTTONTIME = 35
local CEIL_LOWERTOFLOOR = 0
local CEIL_RAISETOHIGHEST = 1
local CEIL_LOWERANDCRUSH = 2
local CEIL_CRUSHANDRAISE = 3
local CEIL_FASTCRUSH = 4
local CEIL_SILENTCRUSH = 5
local RESULT_CRUSHED = 1
local RESULT_PASTDEST = 2
local PLAT_DOWN = 0
local PLAT_UP = 1
local PLAT_WAITING = 2
local PLAT_DWUS = 0
local PLAT_PERPETUAL = 1
local PLAT_BLAZEDWUS = 2
local VLD_NORMAL = 0
local VLD_CLOSE30 = 1
local VLD_CLOSE = 2
local VLD_OPEN = 3
local VLD_RAISEIN5 = 4
local VLD_BLAZERAISE = 5
local VLD_BLAZEOPEN = 6
local VLD_BLAZECLOSE = 7
local ML_TWOSIDED = 4
local MF_MISSILE = 65536
local IT_BLUECARD = 0
local IT_YELLOWCARD = 1
local IT_REDCARD = 2
local IT_BLUESKULL = 3
local IT_YELLOWSKULL = 4
local IT_REDSKULL = 5

local SWITCH_PAIRS = {
  { "SW1BRCOM", "SW2BRCOM" }, { "SW1BRN1", "SW2BRN1" }, { "SW1BRN2", "SW2BRN2" },
  { "SW1BRNGN", "SW2BRNGN" }, { "SW1BROWN", "SW2BROWN" }, { "SW1COMM", "SW2COMM" },
  { "SW1COMP", "SW2COMP" }, { "SW1DIRT", "SW2DIRT" }, { "SW1EXIT", "SW2EXIT" },
  { "SW1GRAY", "SW2GRAY" }, { "SW1GRAY1", "SW2GRAY1" }, { "SW1METAL", "SW2METAL" },
  { "SW1PIPE", "SW2PIPE" }, { "SW1SLAD", "SW2SLAD" }, { "SW1STARG", "SW2STARG" },
  { "SW1STON1", "SW2STON1" }, { "SW1STON2", "SW2STON2" }, { "SW1STONE", "SW2STONE" },
  { "SW1STRTN", "SW2STRTN" }, { "SW1BLUE", "SW2BLUE" }, { "SW1CMT", "SW2CMT" },
  { "SW1GARG", "SW2GARG" }, { "SW1GSTON", "SW2GSTON" }, { "SW1HOT", "SW2HOT" },
  { "SW1LION", "SW2LION" }, { "SW1SATYR", "SW2SATYR" }, { "SW1SKIN", "SW2SKIN" },
  { "SW1VINE", "SW2VINE" }, { "SW1WOOD", "SW2WOOD" }, { "SW1PANEL", "SW2PANEL" },
  { "SW1ROCK", "SW2ROCK" }, { "SW1MET2", "SW2MET2" }, { "SW1WDMET", "SW2WDMET" },
  { "SW1BRIK", "SW2BRIK" }, { "SW1MOD1", "SW2MOD1" }, { "SW1ZIM", "SW2ZIM" },
  { "SW1STON6", "SW2STON6" }, { "SW1TEK", "SW2TEK" }, { "SW1MARB", "SW2MARB" },
  { "SW1SKULL", "SW2SKULL" },
}

local function has(flags, bit)
  return band(flags or 0, bit) ~= 0
end

local function mark(self)
  self.stamp = self.stamp + 1
end

local function play(self, name)
  if self.sound and self.sound.play then
    self.sound.play(name)
  end
end

function M.move_plane(world, sector, speed, dest, floor_or_ceiling, direction, crush)
  local last = sector.floorheight
  if floor_or_ceiling ~= 0 then
    last = sector.ceilingheight
  end
  local past = false
  local next_h
  if direction == -1 then
    if last - speed < dest then
      next_h = dest
      past = true
    else
      next_h = last - speed
    end
  elseif last + speed > dest then
    next_h = dest
    past = true
  else
    next_h = last + speed
  end
  if floor_or_ceiling == 0 then
    sector.floorheight = next_h
  else
    sector.ceilingheight = next_h
  end
  local nofit = collision.change_sector(world, sector, crush and true or false)
  if nofit then
    if not crush or past then
      if floor_or_ceiling == 0 then
        sector.floorheight = last
      else
        sector.ceilingheight = last
      end
      collision.change_sector(world, sector, crush and true or false)
    end
    if past then
      return RESULT_PASTDEST
    end
    return RESULT_CRUSHED
  end
  if past then
    return RESULT_PASTDEST
  end
  return 0
end

local function surrounding_sectors(sector)
  local seen = {}
  local n = 0
  for i = 1, #sector.lines do
    local ln = sector.lines[i]
    local other = ln.backsector
    if ln.frontsector ~= sector then
      other = ln.frontsector
    end
    if other and other ~= sector then
      local known = false
      for j = 1, n do
        if seen[j] == other then
          known = true
          break
        end
      end
      if not known then
        n = n + 1
        seen[n] = other
      end
    end
  end
  return seen
end

local function lowest_ceiling(sector)
  local h = 2147483647
  local around = surrounding_sectors(sector)
  for i = 1, #around do
    if around[i].ceilingheight < h then
      h = around[i].ceilingheight
    end
  end
  if h == 2147483647 then
    return sector.ceilingheight
  end
  return h
end

local function lowest_floor(sector)
  local h = sector.floorheight
  local around = surrounding_sectors(sector)
  for i = 1, #around do
    if around[i].floorheight < h then
      h = around[i].floorheight
    end
  end
  return h
end

local function highest_floor(sector)
  local h = -500 * FRACUNIT
  local around = surrounding_sectors(sector)
  for i = 1, #around do
    if around[i].floorheight > h then
      h = around[i].floorheight
    end
  end
  return h
end

local function next_highest_floor(sector, current)
  local min_h = 2147483647
  local found = false
  local around = surrounding_sectors(sector)
  for i = 1, #around do
    local fh = around[i].floorheight
    if fh > current and fh < min_h then
      min_h = fh
      found = true
    end
  end
  if found then
    return min_h
  end
  return current
end

local function highest_ceiling(sector)
  local h = sector.ceilingheight
  local around = surrounding_sectors(sector)
  for i = 1, #around do
    if around[i].ceilingheight > h then
      h = around[i].ceilingheight
    end
  end
  return h
end

local function raise_floor_dest(sector)
  local dest = lowest_ceiling(sector)
  if dest <= sector.ceilingheight then
    return dest
  end
  return sector.ceilingheight
end

local function raise_floor_crush_dest(sector)
  return raise_floor_dest(sector) - 8 * FRACUNIT
end

local function min_surrounding_light(sector, maxlight)
  local low = maxlight
  local around = surrounding_sectors(sector)
  for i = 1, #around do
    if around[i].lightlevel < low then
      low = around[i].lightlevel
    end
  end
  return low
end

local function max_surrounding_light(sector)
  local high = sector.lightlevel
  local around = surrounding_sectors(sector)
  for i = 1, #around do
    if around[i].lightlevel > high then
      high = around[i].lightlevel
    end
  end
  return high
end

local function sectors_from_tag(world, tag)
  local out = {}
  if tag == 0 then
    return out
  end
  for i = 1, #world.sectors do
    if world.sectors[i].tag == tag then
      out[#out + 1] = world.sectors[i]
    end
  end
  return out
end

local function tag_line(tag)
  return { tag = tag }
end

function M.new(world, res, sound)
  local self = {
    world = world,
    res = res,
    sound = sound,
    thinkers = {},
    lights = {},
    scroll_lines = {},
    buttons = {},
    exit_requested = false,
    secret_exit = false,
    switch_map = {},
    stamp = 0,
  }
  for i = 1, #SWITCH_PAIRS do
    local ia = rdata.texture_num_for_name(res, SWITCH_PAIRS[i][1])
    local ib = rdata.texture_num_for_name(res, SWITCH_PAIRS[i][2])
    if ia ~= 0 or ib ~= 0 then
      self.switch_map[ia] = ib
      self.switch_map[ib] = ia
    end
  end
  M.spawn_specials(self)
  return self
end

local function spawn_light_flash(self, sector)
  sector.special = 0
  local flash = {
    sector = sector,
    kind = "flash",
    maxlight = sector.lightlevel,
    minlight = min_surrounding_light(sector, sector.lightlevel),
    maxtime = 64,
    mintime = 7,
    count = 0,
  }
  flash.count = band(rng.p_random(), flash.maxtime) + 1
  self.lights[#self.lights + 1] = flash
  mark(self)
end

local function spawn_strobe(self, sector, darktime, synced)
  sector.special = 0
  local minl = min_surrounding_light(sector, sector.lightlevel)
  if minl == sector.lightlevel then
    minl = 0
  end
  local count = 1
  if not synced then
    count = band(rng.p_random(), 7) + 1
  end
  self.lights[#self.lights + 1] = {
    sector = sector,
    kind = "strobe",
    maxlight = sector.lightlevel,
    minlight = minl,
    darktime = darktime,
    brighttime = STROBEBRIGHT,
    count = count,
  }
  mark(self)
end

local function spawn_glow(self, sector)
  sector.special = 0
  self.lights[#self.lights + 1] = {
    sector = sector,
    kind = "glow",
    maxlight = sector.lightlevel,
    minlight = min_surrounding_light(sector, sector.lightlevel),
    direction = -1,
  }
  mark(self)
end

local function spawn_fire(self, sector)
  sector.special = 0
  self.lights[#self.lights + 1] = {
    sector = sector,
    kind = "fire",
    maxlight = sector.lightlevel,
    minlight = min_surrounding_light(sector, sector.lightlevel) + 16,
    count = 4,
  }
  mark(self)
end

local function spawn_door(self, sector, dtype, reverse)
  if sector.specialdata ~= nil then
    local door = sector.specialdata
    if door.kind == "door" and (dtype == VLD_NORMAL or dtype == VLD_BLAZERAISE) then
      if door.direction == -1 then
        door.direction = 1
      else
        door.direction = -1
      end
      return true
    end
    return false
  end
  local direction = 1
  if reverse or dtype == VLD_CLOSE or dtype == VLD_BLAZECLOSE or dtype == VLD_CLOSE30 then
    direction = -1
  end
  local speed = VDOORSPEED
  if dtype >= VLD_BLAZERAISE then
    speed = VDOORSPEED * 4
  end
  local door = {
    kind = "door",
    sector = sector,
    type = dtype,
    direction = direction,
    topheight = lowest_ceiling(sector) - 4 * FRACUNIT,
    speed = speed,
    topwait = VDOORWAIT,
    topcountdown = 0,
    dead = false,
  }
  if dtype == VLD_CLOSE30 then
    door.topheight = sector.ceilingheight
  end
  sector.specialdata = door
  self.thinkers[#self.thinkers + 1] = door
  if door.direction == 1 then
    if dtype < VLD_BLAZERAISE then
      play(self, "doropn")
    else
      play(self, "bdopn")
    end
  else
    if dtype < VLD_BLAZERAISE then
      play(self, "dorcls")
    else
      play(self, "bdcls")
    end
  end
  return true
end

local function spawn_door_close_in_30(self, sector)
  if sector.specialdata ~= nil then
    return
  end
  sector.special = 0
  local door = {
    kind = "door",
    sector = sector,
    type = VLD_CLOSE,
    direction = 0,
    topheight = sector.ceilingheight,
    speed = VDOORSPEED,
    topwait = VDOORWAIT,
    topcountdown = 30 * TICRATE,
    dead = false,
  }
  sector.specialdata = door
  self.thinkers[#self.thinkers + 1] = door
end

local function spawn_door_raise_in_5(self, sector)
  if sector.specialdata ~= nil then
    return
  end
  sector.special = 0
  local door = {
    kind = "door",
    sector = sector,
    type = VLD_RAISEIN5,
    direction = 0,
    topheight = lowest_ceiling(sector) - 4 * FRACUNIT,
    speed = VDOORSPEED,
    topwait = VDOORWAIT,
    topcountdown = 5 * 60 * TICRATE,
    dead = false,
  }
  sector.specialdata = door
  self.thinkers[#self.thinkers + 1] = door
end

function M.spawn_specials(self)
  for i = 1, #self.world.sectors do
    local sector = self.world.sectors[i]
    local spec = sector.special
    if spec == 1 then
      spawn_light_flash(self, sector)
    elseif spec == 2 then
      spawn_strobe(self, sector, FASTDARK, false)
    elseif spec == 4 then
      spawn_strobe(self, sector, FASTDARK, false)
      sector.special = 4
    elseif spec == 3 then
      spawn_strobe(self, sector, SLOWDARK, false)
    elseif spec == 8 then
      spawn_glow(self, sector)
    elseif spec == 10 then
      spawn_door_close_in_30(self, sector)
    elseif spec == 12 then
      spawn_strobe(self, sector, SLOWDARK, true)
    elseif spec == 13 then
      spawn_strobe(self, sector, FASTDARK, true)
    elseif spec == 14 then
      spawn_door_raise_in_5(self, sector)
    elseif spec == 17 then
      spawn_fire(self, sector)
    end
  end
  for i = 1, #self.world.lines do
    local ln = self.world.lines[i]
    if ln.special == 48 then
      self.scroll_lines[#self.scroll_lines + 1] = ln
    end
  end
end

local function tick_lights(self)
  for i = 1, #self.lights do
    local light = self.lights[i]
    if light.kind == "glow" then
      if light.direction == -1 then
        light.sector.lightlevel = light.sector.lightlevel - GLOWSPEED
        if light.sector.lightlevel <= light.minlight then
          light.sector.lightlevel = light.sector.lightlevel + GLOWSPEED
          light.direction = 1
        end
      else
        light.sector.lightlevel = light.sector.lightlevel + GLOWSPEED
        if light.sector.lightlevel >= light.maxlight then
          light.sector.lightlevel = light.sector.lightlevel - GLOWSPEED
          light.direction = -1
        end
      end
      mark(self)
    else
      light.count = light.count - 1
      if light.count == 0 then
        if light.kind == "flash" then
          if light.sector.lightlevel == light.maxlight then
            light.sector.lightlevel = light.minlight
            light.count = band(rng.p_random(), light.mintime) + 1
          else
            light.sector.lightlevel = light.maxlight
            light.count = band(rng.p_random(), light.maxtime) + 1
          end
        elseif light.kind == "strobe" then
          if light.sector.lightlevel == light.minlight then
            light.sector.lightlevel = light.maxlight
            light.count = light.brighttime
          else
            light.sector.lightlevel = light.minlight
            light.count = light.darktime
          end
        elseif light.kind == "fire" then
          local amount = band(rng.p_random(), 3) * 16
          if light.sector.lightlevel - amount < light.minlight then
            light.sector.lightlevel = light.minlight
          else
            light.sector.lightlevel = light.maxlight - amount
          end
          light.count = 4
        end
        mark(self)
      end
    end
  end
end

local function tick_door(self, door)
  if door.direction == 0 then
    door.topcountdown = door.topcountdown - 1
    if door.topcountdown <= 0 then
      local dtype = door.type
      if dtype == VLD_NORMAL or dtype == VLD_BLAZERAISE or dtype == VLD_CLOSE then
        door.direction = -1
        if dtype == VLD_BLAZERAISE then
          play(self, "bdcls")
        else
          play(self, "dorcls")
        end
      elseif dtype == VLD_CLOSE30 or dtype == VLD_RAISEIN5 then
        door.direction = 1
        play(self, "doropn")
      end
    end
    return
  end
  local dest = door.sector.floorheight
  if door.direction == 1 then
    dest = door.topheight
  end
  local res = M.move_plane(self.world, door.sector, door.speed, dest, 1, door.direction, false)
  mark(self)
  if res ~= RESULT_PASTDEST then
    return
  end
  if door.direction == 1 then
    if door.type == VLD_NORMAL or door.type == VLD_BLAZERAISE then
      door.direction = 0
      door.topcountdown = door.topwait
    else
      door.sector.specialdata = nil
      door.dead = true
    end
  else
    if door.type == VLD_CLOSE30 then
      door.direction = 0
      door.topcountdown = TICRATE * 30
    else
      door.sector.specialdata = nil
      door.dead = true
    end
  end
end

local function tick_plat(self, plat)
  if plat.status == PLAT_WAITING then
    plat.count = plat.count - 1
    if plat.count <= 0 then
      if plat.sector.floorheight <= plat.low then
        plat.status = PLAT_UP
      else
        plat.status = PLAT_DOWN
      end
      play(self, "pstart")
    end
    return
  end
  local dest = plat.low
  local direction = -1
  if plat.status == PLAT_UP then
    dest = plat.high
    direction = 1
  end
  local res = M.move_plane(self.world, plat.sector, plat.speed, dest, 0, direction, false)
  mark(self)
  if res == RESULT_PASTDEST then
    if plat.status == PLAT_DOWN or plat.type == PLAT_PERPETUAL then
      plat.status = PLAT_WAITING
      plat.count = plat.wait
      play(self, "pstop")
    else
      plat.sector.specialdata = nil
      plat.dead = true
      play(self, "pstop")
    end
  end
end

local function tick_floor(self, floor)
  local res = M.move_plane(self.world, floor.sector, floor.speed, floor.dest, 0, floor.direction, floor.crush)
  mark(self)
  if res == RESULT_PASTDEST then
    if floor.floorpic ~= nil then
      floor.sector.floorpic = floor.floorpic
    end
    floor.sector.specialdata = nil
    floor.dead = true
  end
end

local function tick_ceiling(self, ceil)
  local dest = ceil.dest
  if ceil.ctype ~= 0 then
    if ceil.direction == 1 then
      dest = ceil.topheight
    else
      dest = ceil.bottomheight
    end
  end
  local res = M.move_plane(self.world, ceil.sector, ceil.speed, dest, 1, ceil.direction, ceil.crush)
  mark(self)
  local bounce = ceil.ctype == CEIL_CRUSHANDRAISE or ceil.ctype == CEIL_FASTCRUSH or ceil.ctype == CEIL_SILENTCRUSH
  if res == RESULT_PASTDEST then
    if bounce then
      if ceil.direction == -1 then
        ceil.direction = 1
        ceil.speed = CEILSPEED
        if ceil.ctype == CEIL_FASTCRUSH then
          ceil.speed = CEILSPEED * 2
        end
        if ceil.ctype == CEIL_SILENTCRUSH then
          play(self, "pstop")
        end
      else
        ceil.direction = -1
        if ceil.ctype == CEIL_SILENTCRUSH then
          play(self, "pstop")
        end
      end
    else
      ceil.sector.specialdata = nil
      ceil.dead = true
    end
  elseif res == RESULT_CRUSHED and bounce then
    local slow = math.floor(CEILSPEED / 8)
    if slow < 1 then
      slow = 1
    end
    ceil.speed = slow
  end
end

function M.tick(self)
  local before = self.stamp
  tick_lights(self)
  for i = 1, #self.scroll_lines do
    local side = self.scroll_lines[i].sides[1]
    if side then
      side.textureoffset = side.textureoffset + FRACUNIT
      mark(self)
    end
  end
  local alive = {}
  for i = 1, #self.thinkers do
    local th = self.thinkers[i]
    if not th.dead then
      if th.kind == "door" then
        tick_door(self, th)
      elseif th.kind == "plat" then
        tick_plat(self, th)
      elseif th.kind == "floor" then
        tick_floor(self, th)
      elseif th.kind == "ceiling" then
        tick_ceiling(self, th)
      end
      if not th.dead then
        alive[#alive + 1] = th
      end
    end
  end
  self.thinkers = alive
  local keep = {}
  for i = 1, #self.buttons do
    local btn = self.buttons[i]
    btn.timer = btn.timer - 1
    if btn.timer <= 0 then
      local side = btn.line.sides[1]
      if side then
        side[btn.attr] = btn.texture
        mark(self)
      end
    else
      keep[#keep + 1] = btn
    end
  end
  self.buttons = keep
  return self.stamp ~= before
end

function M.do_door(self, line, dtype, reverse)
  local ok = false
  local secs = sectors_from_tag(self.world, line.tag)
  for i = 1, #secs do
    if spawn_door(self, secs[i], dtype, reverse) then
      ok = true
    end
  end
  return ok
end

function M.vertical_door(self, line, thing)
  local player = thing and thing.player
  local spec = line.special
  if (spec == 26 or spec == 32) and player then
    if not player.cards[IT_BLUECARD] and not player.cards[IT_BLUESKULL] then
      player.message = "You need a blue key to open this door"
      play(self, "oof")
      return
    end
  end
  if (spec == 27 or spec == 34) and player then
    if not player.cards[IT_YELLOWCARD] and not player.cards[IT_YELLOWSKULL] then
      player.message = "You need a yellow key to open this door"
      play(self, "oof")
      return
    end
  end
  if (spec == 28 or spec == 33) and player then
    if not player.cards[IT_REDCARD] and not player.cards[IT_REDSKULL] then
      player.message = "You need a red key to open this door"
      play(self, "oof")
      return
    end
  end
  local side = line.sides[2]
  if not side or not side.sector then
    return
  end
  local dtype = VLD_NORMAL
  if spec == 31 or spec == 32 or spec == 33 or spec == 34 then
    dtype = VLD_OPEN
    line.special = 0
  elseif spec == 117 then
    dtype = VLD_BLAZERAISE
  elseif spec == 118 then
    dtype = VLD_BLAZEOPEN
    line.special = 0
  end
  spawn_door(self, side.sector, dtype, false)
end

function M.locked_blaze_door(self, line, thing, spec)
  local player = thing and thing.player
  if not player then
    return
  end
  if (spec == 99 or spec == 133) and not player.cards[IT_BLUECARD] and not player.cards[IT_BLUESKULL] then
    player.message = "You need a blue key to open this door"
    play(self, "oof")
    return
  end
  if (spec == 136 or spec == 137) and not player.cards[IT_YELLOWCARD] and not player.cards[IT_YELLOWSKULL] then
    player.message = "You need a yellow key to open this door"
    play(self, "oof")
    return
  end
  if (spec == 134 or spec == 135) and not player.cards[IT_REDCARD] and not player.cards[IT_REDSKULL] then
    player.message = "You need a red key to open this door"
    play(self, "oof")
    return
  end
  if M.do_door(self, line, VLD_BLAZEOPEN, false) then
    M.change_switch(self, line, spec == 99 or spec == 134 or spec == 136)
  end
end

function M.do_plat_dwus(self, line, blaze)
  local ok = false
  local speed = PLATSPEED
  if blaze then
    speed = PLATSPEED * 8
  end
  local secs = sectors_from_tag(self.world, line.tag)
  for i = 1, #secs do
    local sec = secs[i]
    if sec.specialdata == nil then
      local ptype = PLAT_DWUS
      if blaze then
        ptype = PLAT_BLAZEDWUS
      end
      local plat = {
        kind = "plat",
        sector = sec,
        type = ptype,
        status = PLAT_DOWN,
        speed = speed,
        low = lowest_floor(sec),
        high = sec.floorheight,
        wait = PLATWAIT * TICRATE,
        count = 0,
        dead = false,
      }
      if plat.low == plat.high then
        plat.low = plat.high - 8 * FRACUNIT
      end
      sec.specialdata = plat
      self.thinkers[#self.thinkers + 1] = plat
      play(self, "pstart")
      ok = true
    end
  end
  return ok
end

function M.do_floor(self, line, dest_fn, direction, speed, crush)
  local ok = false
  local spd = speed
  if spd == nil then
    spd = FLOORSPEED
  end
  local secs = sectors_from_tag(self.world, line.tag)
  for i = 1, #secs do
    local sec = secs[i]
    if sec.specialdata == nil then
      local floor = {
        kind = "floor",
        sector = sec,
        direction = direction,
        dest = dest_fn(sec),
        speed = spd,
        crush = crush and true or false,
        floorpic = nil,
        dead = false,
      }
      sec.specialdata = floor
      self.thinkers[#self.thinkers + 1] = floor
      ok = true
    end
  end
  return ok
end

function M.do_stairs(self, line, step, speed)
  local ok = false
  local secs = sectors_from_tag(self.world, line.tag)
  for i = 1, #secs do
    local sec = secs[i]
    if sec.specialdata == nil then
      local height = sec.floorheight + step
      sec.specialdata = {
        kind = "floor",
        sector = sec,
        direction = 1,
        dest = height,
        speed = speed,
        crush = false,
        floorpic = nil,
        dead = false,
      }
      self.thinkers[#self.thinkers + 1] = sec.specialdata
      ok = true
      local texture = sec.floorpic
      local cur = sec
      while true do
        local nxt = nil
        for n = 1, #cur.lines do
          local ln = cur.lines[n]
          if has(ln.flags, ML_TWOSIDED) then
            local other = ln.backsector
            if ln.frontsector ~= cur then
              other = ln.frontsector
            end
            if other and other ~= cur and other.floorpic == texture and other.specialdata == nil then
              nxt = other
              break
            end
          end
        end
        if not nxt then
          break
        end
        height = height + step
        nxt.specialdata = {
          kind = "floor",
          sector = nxt,
          direction = 1,
          dest = height,
          speed = speed,
          crush = false,
          floorpic = nil,
          dead = false,
        }
        self.thinkers[#self.thinkers + 1] = nxt.specialdata
        cur = nxt
      end
    end
  end
  return ok
end

local function start_floor(self, sec, dest, direction, speed, crush, floorpic)
  if sec.specialdata ~= nil then
    return false
  end
  local floor = {
    kind = "floor",
    sector = sec,
    direction = direction,
    dest = dest,
    speed = speed,
    crush = crush and true or false,
    floorpic = floorpic,
    dead = false,
  }
  sec.specialdata = floor
  self.thinkers[#self.thinkers + 1] = floor
  return true
end

function M.do_crusher(self, line, ctype)
  local ok = false
  local secs = sectors_from_tag(self.world, line.tag)
  for i = 1, #secs do
    local sec = secs[i]
    if sec.specialdata == nil then
      local top = sec.ceilingheight
      local bottom = sec.floorheight
      local crush = ctype ~= CEIL_RAISETOHIGHEST
      local speed = CEILSPEED
      if ctype == CEIL_FASTCRUSH then
        speed = CEILSPEED * 2
      end
      local direction = -1
      local dest = bottom
      if ctype == CEIL_RAISETOHIGHEST then
        dest = highest_ceiling(sec)
        direction = 1
        crush = false
      elseif ctype ~= CEIL_LOWERTOFLOOR then
        bottom = bottom + 8 * FRACUNIT
        dest = bottom
      end
      local ceil = {
        kind = "ceiling",
        sector = sec,
        direction = direction,
        dest = dest,
        speed = speed,
        crush = crush,
        ctype = ctype,
        topheight = top,
        bottomheight = bottom,
        dead = false,
      }
      sec.specialdata = ceil
      self.thinkers[#self.thinkers + 1] = ceil
      ok = true
    end
  end
  return ok
end

function M.do_donut(self, line)
  local ok = false
  local secs = sectors_from_tag(self.world, line.tag)
  for i = 1, #secs do
    local s1 = secs[i]
    if s1.specialdata == nil and #s1.lines > 0 then
      local first = s1.lines[1]
      local s2 = first.backsector
      if first.frontsector ~= s1 then
        s2 = first.frontsector
      end
      if s2 then
        local s3 = nil
        for n = 1, #s2.lines do
          local other = s2.lines[n].backsector
          if other and other ~= s1 then
            s3 = other
            break
          end
        end
        if s3 then
          if start_floor(self, s2, s3.floorheight, 1, math.floor(FLOORSPEED / 2), false, s3.floorpic) then
            ok = true
          end
          if start_floor(self, s1, s3.floorheight, -1, math.floor(FLOORSPEED / 2), false, nil) then
            ok = true
          end
        end
      end
    end
  end
  return ok
end

function M.do_plat_perpetual(self, line)
  local ok = false
  local secs = sectors_from_tag(self.world, line.tag)
  for i = 1, #secs do
    local sec = secs[i]
    if sec.specialdata == nil then
      local low = lowest_floor(sec)
      local high = highest_floor(sec)
      if low > sec.floorheight then
        low = sec.floorheight
      end
      if high < sec.floorheight then
        high = sec.floorheight
      end
      local plat = {
        kind = "plat",
        sector = sec,
        type = PLAT_PERPETUAL,
        status = band(rng.p_random(), 1),
        speed = PLATSPEED,
        low = low,
        high = high,
        wait = PLATWAIT * TICRATE,
        count = 0,
        dead = false,
      }
      sec.specialdata = plat
      self.thinkers[#self.thinkers + 1] = plat
      play(self, "pstart")
      ok = true
    end
  end
  return ok
end

function M.do_plat_raise(self, line, amount, change)
  if change == nil then
    change = true
  end
  local ok = false
  local pic = nil
  if change and line.sides and line.sides[1] and line.sides[1].sector then
    pic = line.sides[1].sector.floorpic
  end
  local secs = sectors_from_tag(self.world, line.tag)
  for i = 1, #secs do
    local sec = secs[i]
    if sec.specialdata == nil then
      local high = next_highest_floor(sec, sec.floorheight)
      if amount ~= 0 then
        high = sec.floorheight + amount
      end
      if pic ~= nil then
        sec.floorpic = pic
        mark(self)
      end
      local plat = {
        kind = "plat",
        sector = sec,
        type = PLAT_DWUS,
        status = PLAT_UP,
        speed = math.floor(PLATSPEED / 2),
        low = sec.floorheight,
        high = high,
        wait = 0,
        count = 0,
        dead = false,
      }
      sec.specialdata = plat
      self.thinkers[#self.thinkers + 1] = plat
      play(self, "pstart")
      ok = true
    end
  end
  return ok
end

function M.stop_plat(self, line)
  local ok = false
  for i = 1, #self.thinkers do
    local th = self.thinkers[i]
    if th.kind == "plat" and not th.dead and th.sector.tag == line.tag then
      th.status = PLAT_WAITING
      th.count = 2147483647
      ok = true
    end
  end
  return ok
end

function M.raise_to_texture(self, line)
  local ok = false
  local secs = sectors_from_tag(self.world, line.tag)
  for i = 1, #secs do
    local sec = secs[i]
    if sec.specialdata == nil then
      local minsize = 2147483647
      for n = 1, #sec.lines do
        local ln = sec.lines[n]
        if has(ln.flags, ML_TWOSIDED) then
          for s = 1, 2 do
            local side = ln.sides[s]
            if side and side.bottomtexture > 0 then
              local h = rdata.texture_height(self.res, side.bottomtexture)
              if h > 0 and h < minsize then
                minsize = h
              end
            end
          end
        end
      end
      if minsize == 2147483647 then
        minsize = 64 * FRACUNIT
      end
      if start_floor(self, sec, sec.floorheight + minsize, 1, FLOORSPEED, false, nil) then
        ok = true
      end
    end
  end
  return ok
end

function M.lower_and_change(self, line)
  local ok = false
  local secs = sectors_from_tag(self.world, line.tag)
  for i = 1, #secs do
    local sec = secs[i]
    if sec.specialdata == nil then
      local dest = lowest_floor(sec)
      local pic = sec.floorpic
      local around = surrounding_sectors(sec)
      for n = 1, #around do
        if around[n].floorheight == dest then
          pic = around[n].floorpic
          break
        end
      end
      if start_floor(self, sec, dest, -1, FLOORSPEED, false, pic) then
        ok = true
      end
    end
  end
  return ok
end

function M.light_turn_on(self, line, bright)
  local ok = false
  local secs = sectors_from_tag(self.world, line.tag)
  for i = 1, #secs do
    local sec = secs[i]
    if bright ~= 0 then
      sec.lightlevel = bright
    else
      sec.lightlevel = max_surrounding_light(sec)
    end
    mark(self)
    ok = true
  end
  return ok
end

function M.turn_tag_lights_off(self, line)
  local ok = false
  local secs = sectors_from_tag(self.world, line.tag)
  for i = 1, #secs do
    local sec = secs[i]
    sec.lightlevel = min_surrounding_light(sec, sec.lightlevel)
    mark(self)
    ok = true
  end
  return ok
end

function M.start_light_strobing(self, line)
  local ok = false
  local secs = sectors_from_tag(self.world, line.tag)
  for i = 1, #secs do
    if secs[i].specialdata == nil then
      spawn_strobe(self, secs[i], SLOWDARK, false)
      ok = true
    end
  end
  return ok
end

function M.change_switch(self, line, use_again)
  local side = line.sides[1]
  if not side then
    return
  end
  if not use_again then
    line.special = 0
  end
  local sound = "swtchn"
  if line.special == 11 then
    sound = "swtchx"
  end
  local fields = { "toptexture", "midtexture", "bottomtexture" }
  for i = 1, 3 do
    local attr = fields[i]
    local tex = side[attr]
    local new = self.switch_map[tex]
    if new ~= nil then
      if use_again then
        self.buttons[#self.buttons + 1] = {
          line = line,
          attr = attr,
          texture = tex,
          timer = BUTTONTIME,
        }
      end
      side[attr] = new
      mark(self)
      play(self, sound)
      return
    end
  end
  play(self, sound)
end

function M.use_special(self, line, thing, side)
  if side ~= 0 then
    return false
  end
  local spec = line.special
  if spec == 1 or spec == 26 or spec == 27 or spec == 28 or spec == 31 or spec == 32
    or spec == 33 or spec == 34 or spec == 117 or spec == 118 then
    M.vertical_door(self, line, thing)
    return true
  end
  if spec == 99 or spec == 133 or spec == 134 or spec == 135 or spec == 136 or spec == 137 then
    M.locked_blaze_door(self, line, thing, spec)
    return true
  end
  if spec == 11 then
    M.change_switch(self, line, false)
    self.exit_requested = true
    return true
  end
  if spec == 51 then
    M.change_switch(self, line, false)
    self.exit_requested = true
    self.secret_exit = true
    return true
  end
  local function door(dtype)
    return M.do_door(self, line, dtype, false)
  end
  local tagged = {
    [29] = function() return door(VLD_NORMAL) end,
    [50] = function() return door(VLD_CLOSE) end,
    [103] = function() return door(VLD_OPEN) end,
    [111] = function() return door(VLD_BLAZERAISE) end,
    [112] = function() return door(VLD_BLAZEOPEN) end,
    [113] = function() return door(VLD_BLAZECLOSE) end,
    [21] = function() return M.do_plat_dwus(self, line, false) end,
    [122] = function() return M.do_plat_dwus(self, line, true) end,
    [18] = function() return M.do_floor(self, line, function(s) return next_highest_floor(s, s.floorheight) end, 1) end,
    [23] = function() return M.do_floor(self, line, lowest_floor, -1) end,
    [71] = function() return M.do_floor(self, line, highest_floor, -1) end,
    [101] = function() return M.do_floor(self, line, raise_floor_dest, 1) end,
    [102] = function() return M.do_floor(self, line, highest_floor, -1) end,
    [7] = function() return M.do_stairs(self, line, 8 * FRACUNIT, math.floor(FLOORSPEED / 4)) end,
    [127] = function() return M.do_stairs(self, line, 16 * FRACUNIT, FLOORSPEED * 4) end,
    [41] = function() return M.do_crusher(self, line, CEIL_LOWERTOFLOOR) end,
    [49] = function() return M.do_crusher(self, line, CEIL_CRUSHANDRAISE) end,
    [9] = function() return M.do_donut(self, line) end,
    [14] = function() return M.do_plat_raise(self, line, 32 * FRACUNIT, true) end,
    [15] = function() return M.do_plat_raise(self, line, 24 * FRACUNIT, true) end,
    [20] = function() return M.do_plat_raise(self, line, 0, true) end,
    [55] = function() return M.do_floor(self, line, raise_floor_crush_dest, 1, nil, true) end,
    [131] = function() return M.do_floor(self, line, function(s) return next_highest_floor(s, s.floorheight) end, 1, FLOORSPEED * 4) end,
    [140] = function() return M.do_floor(self, line, function(s) return s.floorheight + 512 * FRACUNIT end, 1) end,
  }
  local retrigger = {
    [42] = function() return door(VLD_CLOSE) end,
    [61] = function() return door(VLD_OPEN) end,
    [63] = function() return door(VLD_NORMAL) end,
    [62] = function() return M.do_plat_dwus(self, line, false) end,
    [114] = function() return door(VLD_BLAZERAISE) end,
    [115] = function() return door(VLD_BLAZEOPEN) end,
    [116] = function() return door(VLD_BLAZECLOSE) end,
    [120] = function() return M.do_plat_dwus(self, line, true) end,
    [123] = function() return M.do_plat_dwus(self, line, true) end,
    [45] = function() return M.do_floor(self, line, highest_floor, -1) end,
    [60] = function() return M.do_floor(self, line, lowest_floor, -1) end,
    [64] = function() return M.do_floor(self, line, raise_floor_dest, 1) end,
    [70] = function() return M.do_floor(self, line, highest_floor, -1, FLOORSPEED * 4) end,
    [43] = function() return M.do_crusher(self, line, CEIL_LOWERTOFLOOR) end,
    [65] = function() return M.do_floor(self, line, raise_floor_crush_dest, 1, nil, true) end,
    [66] = function() return M.do_plat_raise(self, line, 24 * FRACUNIT, true) end,
    [67] = function() return M.do_plat_raise(self, line, 32 * FRACUNIT, true) end,
    [68] = function() return M.do_plat_raise(self, line, 0, true) end,
    [69] = function() return M.do_floor(self, line, function(s) return next_highest_floor(s, s.floorheight) end, 1) end,
    [132] = function() return M.do_floor(self, line, function(s) return next_highest_floor(s, s.floorheight) end, 1, FLOORSPEED * 4) end,
    [138] = function() return M.light_turn_on(self, line, 255) end,
    [139] = function() return M.light_turn_on(self, line, 35) end,
  }
  local fn = tagged[spec]
  if fn then
    local ok = fn() and true or false
    if ok then
      M.change_switch(self, line, false)
    end
    return ok
  end
  fn = retrigger[spec]
  if fn then
    local ok = fn() and true or false
    if ok then
      M.change_switch(self, line, true)
    end
    return ok
  end
  return false
end

function M.shoot_special(self, line, thing)
  local spec = line.special
  if spec == 24 then
    if M.do_floor(self, line, raise_floor_dest, 1) then
      M.change_switch(self, line, false)
    end
  elseif spec == 46 then
    M.do_door(self, line, VLD_OPEN, false)
    M.change_switch(self, line, true)
  elseif spec == 47 then
    if M.do_plat_raise(self, line, 0, true) then
      M.change_switch(self, line, false)
    end
  end
end

function M.teleport(self, line, side, thing)
  if side == 1 or has(thing.flags, MF_MISSILE) then
    return false
  end
  local tag = line.tag
  for i = 1, #self.world.sectors do
    local sector = self.world.sectors[i]
    if sector.tag == tag then
      for n = 1, #self.world.mobjs do
        local dest = self.world.mobjs[n]
        if dest.doomednum == 14 then
          local dest_sector = collision.point_in_subsector(self.world, dest.x, dest.y).sector
          if dest_sector == sector or dest_sector.i_sector == i - 1 then
            thing.momx, thing.momy, thing.momz = 0, 0, 0
            collision.unset_thing_position(self.world, thing)
            thing.x = dest.x
            thing.y = dest.y
            local ss = collision.point_in_subsector(self.world, thing.x, thing.y)
            thing.floorz = ss.sector.floorheight
            thing.ceilingz = ss.sector.ceilingheight
            thing.z = thing.floorz
            thing.angle = dest.angle
            collision.set_thing_position(self.world, thing)
            if thing.player then
              thing.player.viewz = thing.z + thing.player.viewheight
              thing.reactiontime = 18
            end
            play(self, "telept")
            mark(self)
            return true
          end
        end
      end
    end
  end
  return false
end

function M.cross_special(self, line, side, thing)
  local spec = line.special
  if spec == 52 then
    self.exit_requested = true
    return
  end
  if spec == 124 then
    self.exit_requested = true
    self.secret_exit = true
    return
  end
  local function door(dtype, reverse)
    return M.do_door(self, line, dtype, reverse)
  end
  local function floor_up24()
    return M.do_floor(self, line, function(s) return s.floorheight + 24 * FRACUNIT end, 1)
  end
  local function floor_next(speed)
    return M.do_floor(self, line, function(s) return next_highest_floor(s, s.floorheight) end, 1, speed)
  end
  local once = {
    [2] = function() return door(VLD_OPEN, false) end,
    [3] = function() return door(VLD_CLOSE, false) end,
    [4] = function() return door(VLD_NORMAL, false) end,
    [5] = function() return M.do_floor(self, line, raise_floor_dest, 1) end,
    [6] = function() return M.do_crusher(self, line, CEIL_FASTCRUSH) end,
    [8] = function() return M.do_stairs(self, line, 8 * FRACUNIT, math.floor(FLOORSPEED / 4)) end,
    [10] = function() return M.do_plat_dwus(self, line, false) end,
    [12] = function() return M.light_turn_on(self, line, 0) end,
    [13] = function() return M.light_turn_on(self, line, 255) end,
    [16] = function() return door(VLD_CLOSE30, true) end,
    [17] = function() return M.start_light_strobing(self, line) end,
    [19] = function() return M.do_floor(self, line, highest_floor, -1) end,
    [22] = function() return M.do_plat_raise(self, line, 0, true) end,
    [25] = function() return M.do_crusher(self, line, CEIL_CRUSHANDRAISE) end,
    [30] = function() return M.raise_to_texture(self, line) end,
    [35] = function() return M.light_turn_on(self, line, 35) end,
    [36] = function() return M.do_floor(self, line, highest_floor, -1, FLOORSPEED * 4) end,
    [37] = function() return M.lower_and_change(self, line) end,
    [38] = function() return M.do_floor(self, line, lowest_floor, -1) end,
    [39] = function()
      M.teleport(self, line, side, thing)
      return true
    end,
    [40] = function()
      M.do_crusher(self, line, CEIL_RAISETOHIGHEST)
      M.do_floor(self, line, lowest_floor, -1)
      return true
    end,
    [44] = function() return M.do_crusher(self, line, CEIL_LOWERANDCRUSH) end,
    [53] = function() return M.do_plat_perpetual(self, line) end,
    [54] = function() return M.stop_plat(self, line) end,
    [56] = function() return M.do_floor(self, line, raise_floor_crush_dest, 1, nil, true) end,
    [57] = function() return M.stop_plat(self, line) end,
    [58] = function() return floor_up24() end,
    [59] = function() return floor_up24() end,
    [100] = function() return M.do_stairs(self, line, 16 * FRACUNIT, FLOORSPEED * 4) end,
    [104] = function() return M.turn_tag_lights_off(self, line) end,
    [108] = function() return door(VLD_BLAZERAISE, false) end,
    [109] = function() return door(VLD_BLAZEOPEN, false) end,
    [110] = function() return door(VLD_BLAZECLOSE, false) end,
    [119] = function() return floor_next(nil) end,
    [121] = function() return M.do_plat_dwus(self, line, true) end,
    [125] = function()
      if thing.player == nil then
        M.teleport(self, line, side, thing)
      end
      return true
    end,
    [130] = function() return floor_next(FLOORSPEED * 4) end,
    [141] = function() return M.do_crusher(self, line, CEIL_SILENTCRUSH) end,
  }
  local again = {
    [72] = function() return M.do_crusher(self, line, CEIL_LOWERANDCRUSH) end,
    [73] = function() return M.do_crusher(self, line, CEIL_CRUSHANDRAISE) end,
    [74] = function() return M.stop_plat(self, line) end,
    [75] = function() return door(VLD_CLOSE, false) end,
    [76] = function() return door(VLD_CLOSE30, true) end,
    [77] = function() return M.do_crusher(self, line, CEIL_FASTCRUSH) end,
    [79] = function() return M.light_turn_on(self, line, 35) end,
    [80] = function() return M.light_turn_on(self, line, 0) end,
    [81] = function() return M.light_turn_on(self, line, 255) end,
    [82] = function() return M.do_floor(self, line, lowest_floor, -1) end,
    [83] = function() return M.do_floor(self, line, highest_floor, -1) end,
    [84] = function() return M.lower_and_change(self, line) end,
    [86] = function() return door(VLD_OPEN, false) end,
    [87] = function() return M.do_plat_perpetual(self, line) end,
    [88] = function() return M.do_plat_dwus(self, line, false) end,
    [89] = function() return M.stop_plat(self, line) end,
    [90] = function() return door(VLD_NORMAL, false) end,
    [91] = function() return M.do_floor(self, line, raise_floor_dest, 1) end,
    [92] = function() return floor_up24() end,
    [93] = function() return floor_up24() end,
    [94] = function() return M.do_floor(self, line, raise_floor_crush_dest, 1, nil, true) end,
    [95] = function() return M.do_plat_raise(self, line, 0, true) end,
    [96] = function() return M.raise_to_texture(self, line) end,
    [97] = function() return M.teleport(self, line, side, thing) end,
    [98] = function() return M.do_floor(self, line, highest_floor, -1, FLOORSPEED * 4) end,
    [105] = function() return door(VLD_BLAZERAISE, false) end,
    [106] = function() return door(VLD_BLAZEOPEN, false) end,
    [107] = function() return door(VLD_BLAZECLOSE, false) end,
    [120] = function() return M.do_plat_dwus(self, line, true) end,
    [126] = function()
      if thing.player == nil then
        return M.teleport(self, line, side, thing)
      end
      return false
    end,
    [128] = function() return floor_next(nil) end,
    [129] = function() return floor_next(FLOORSPEED * 4) end,
  }
  local fn = once[spec]
  if fn then
    fn()
    line.special = 0
  else
    fn = again[spec]
    if fn then
      fn()
    end
  end
end

function M.do_floor_tag(self, tag, dest_fn, direction, speed, crush)
  return M.do_floor(self, tag_line(tag), dest_fn, direction, speed, crush)
end

function M.do_door_tag(self, tag, dtype)
  return M.do_door(self, tag_line(tag), dtype)
end

function M.raise_to_texture_tag(self, tag)
  return M.raise_to_texture(self, tag_line(tag))
end

M.lowest_floor = lowest_floor

return M
