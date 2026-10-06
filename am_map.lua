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
-- Automapa. Tab liga. As paredes usam ML_MAPPED, como no Python.

local compat = require("compat")
local player_mod = require("player")
local tables = require("tables")
local v = require("v_video")
local wad = require("wad")

local M = {}

local FRACUNIT = 65536
local ANGLETOFINESHIFT = 19
local PLAYER_RADIUS = 16 * FRACUNIT
local SCREENWIDTH = 320
local SCREENHEIGHT = 200
local SBARHEIGHT = 32
local ML_DONTDRAW = 128
local ML_MAPPED = 256
local ML_SECRET = 32
local PW_ALLMAP = 4

local REDS = 256 - 5 * 16
local REDRANGE = 16
local GREENS = 7 * 16
local GRAYS = 6 * 16
local BROWNS = 4 * 16
local YELLOWS = 256 - 32 + 7
local WHITE = 256 - 47
local BACKGROUND = 0
local WALLCOLORS = REDS
local WALLRANGE = REDRANGE
local TSWALLCOLORS = GRAYS
local FDWALLCOLORS = BROWNS
local CDWALLCOLORS = YELLOWS
local THINGCOLORS = GREENS
local GRIDCOLORS = 104
local XHAIRCOLORS = GRAYS

local INITSCALEMTOF = 13107
local F_PANINC = 4
local M_ZOOMIN = 66846
local M_ZOOMOUT = 64250
local AM_NUMMARKPOINTS = 10
local MAPBLOCKUNITS = 128
local INT_MAX = 2147483647

local OC_LEFT = 1
local OC_RIGHT = 2
local OC_BOTTOM = 4
local OC_TOP = 8

local band = compat.band
local bor = compat.bor

local function idiv(a, b)
  return math.floor(a / b)
end

local function trunc_div(num, den)
  if den == 0 then
    return 0
  end
  local q = num / den
  if q >= 0 then
    return math.floor(q)
  end
  return math.ceil(q)
end

local function trunc(n)
  if n >= 0 then
    return math.floor(n)
  end
  return math.ceil(n)
end

local function line(ax, ay, bx, by)
  return { ax, ay, bx, by }
end

local function player_arrow()
  local n_r = trunc((8 * PLAYER_RADIUS) / 7)
  local q = idiv(n_r, 4)
  local e = idiv(n_r, 8)
  return {
    line(-n_r + e, 0, n_r, 0),
    line(n_r, 0, n_r - idiv(n_r, 2), q),
    line(n_r, 0, n_r - idiv(n_r, 2), -q),
    line(-n_r + e, 0, -n_r - e, q),
    line(-n_r + e, 0, -n_r - e, -q),
    line(-n_r + 3 * e, 0, -n_r + e, q),
    line(-n_r + 3 * e, 0, -n_r + e, -q),
  }
end

local function thin_triangle()
  return {
    line(trunc(-0.5 * FRACUNIT), trunc(-0.7 * FRACUNIT), FRACUNIT, 0),
    line(FRACUNIT, 0, trunc(-0.5 * FRACUNIT), trunc(0.7 * FRACUNIT)),
    line(trunc(-0.5 * FRACUNIT), trunc(0.7 * FRACUNIT), trunc(-0.5 * FRACUNIT), trunc(-0.7 * FRACUNIT)),
  }
end

local function cosine_at(i)
  return tables.finesine[band(i + 2048, 8191)]
end

function M.new()
  tables.init()
  local marks = {}
  for i = 1, AM_NUMMARKPOINTS do
    marks[i] = { x = -1, y = -1 }
  end
  return {
    active = false,
    cheating = 0,
    grid = 0,
    followplayer = 1,
    stopped = true,
    lastlevel = -1,
    lastepisode = -1,
    bigstate = 0,
    lightlev = 0,
    amclock = 0,
    f_x = 0,
    f_y = 0,
    f_w = SCREENWIDTH,
    f_h = SCREENHEIGHT - SBARHEIGHT,
    m_x = 0,
    m_y = 0,
    m_x2 = 0,
    m_y2 = 0,
    m_w = 0,
    m_h = 0,
    min_x = 0,
    min_y = 0,
    max_x = 0,
    max_y = 0,
    min_scale_mtof = FRACUNIT,
    max_scale_mtof = FRACUNIT,
    scale_mtof = INITSCALEMTOF,
    scale_ftom = FRACUNIT,
    old_m_x = 0,
    old_m_y = 0,
    old_m_w = 0,
    old_m_h = 0,
    f_oldloc_x = INT_MAX,
    f_oldloc_y = 0,
    m_paninc_x = 0,
    m_paninc_y = 0,
    mtof_zoommul = FRACUNIT,
    ftom_zoommul = FRACUNIT,
    player_arrow = player_arrow(),
    thintriangle_guy = thin_triangle(),
    marknums = {},
    markpoints = marks,
    markpointnum = 0,
    fb = nil,
    clip = { 0, 0, 0, 0 },
  }
end

function M.ftom(self, x)
  return compat.fixed_mul(x * FRACUNIT, self.scale_ftom)
end

function M.mtof(self, x)
  return compat.shar(compat.fixed_mul(x, self.scale_mtof), 16)
end

function M.cxmtof(self, x)
  return self.f_x + M.mtof(self, x - self.m_x)
end

function M.cymtof(self, y)
  return self.f_y + (self.f_h - M.mtof(self, y - self.m_y))
end

local function clear_marks(self)
  for i = 1, AM_NUMMARKPOINTS do
    self.markpoints[i].x = -1
    self.markpoints[i].y = -1
  end
  self.markpointnum = 0
end

local function find_min_max(self, world)
  self.min_x = INT_MAX
  self.min_y = INT_MAX
  self.max_x = -INT_MAX
  self.max_y = -INT_MAX
  for i = 1, #world.vertexes do
    local vx = world.vertexes[i].x
    local vy = world.vertexes[i].y
    if vx < self.min_x then
      self.min_x = vx
    elseif vx > self.max_x then
      self.max_x = vx
    end
    if vy < self.min_y then
      self.min_y = vy
    elseif vy > self.max_y then
      self.max_y = vy
    end
  end
  local max_w = self.max_x - self.min_x
  local max_h = self.max_y - self.min_y
  if max_w <= 0 then
    max_w = FRACUNIT
  end
  if max_h <= 0 then
    max_h = FRACUNIT
  end
  local a = compat.fixed_div(self.f_w * FRACUNIT, max_w)
  local b = compat.fixed_div(self.f_h * FRACUNIT, max_h)
  if a < b then
    self.min_scale_mtof = a
  else
    self.min_scale_mtof = b
  end
  self.max_scale_mtof = compat.fixed_div(self.f_h * FRACUNIT, 2 * PLAYER_RADIUS)
end

local function activate_new_scale(self)
  self.m_x = self.m_x + idiv(self.m_w, 2)
  self.m_y = self.m_y + idiv(self.m_h, 2)
  self.m_w = M.ftom(self, self.f_w)
  self.m_h = M.ftom(self, self.f_h)
  self.m_x = self.m_x - idiv(self.m_w, 2)
  self.m_y = self.m_y - idiv(self.m_h, 2)
  self.m_x2 = self.m_x + self.m_w
  self.m_y2 = self.m_y + self.m_h
end

local function min_out(self)
  self.scale_mtof = self.min_scale_mtof
  self.scale_ftom = compat.fixed_div(FRACUNIT, self.scale_mtof)
  activate_new_scale(self)
end

local function max_out(self)
  self.scale_mtof = self.max_scale_mtof
  self.scale_ftom = compat.fixed_div(FRACUNIT, self.scale_mtof)
  activate_new_scale(self)
end

local function level_init(self, game)
  self.f_x = 0
  self.f_y = 0
  self.f_w = SCREENWIDTH
  self.f_h = SCREENHEIGHT - SBARHEIGHT
  clear_marks(self)
  find_min_max(self, game.world)
  self.scale_mtof = compat.fixed_div(self.min_scale_mtof, trunc(0.7 * FRACUNIT))
  if self.scale_mtof > self.max_scale_mtof then
    self.scale_mtof = self.min_scale_mtof
  end
  self.scale_ftom = compat.fixed_div(FRACUNIT, self.scale_mtof)
end

local function change_window_loc(self)
  if self.m_paninc_x ~= 0 or self.m_paninc_y ~= 0 then
    self.followplayer = 0
    self.f_oldloc_x = INT_MAX
  end
  self.m_x = self.m_x + self.m_paninc_x
  self.m_y = self.m_y + self.m_paninc_y
  if self.m_x + idiv(self.m_w, 2) > self.max_x then
    self.m_x = self.max_x - idiv(self.m_w, 2)
  elseif self.m_x + idiv(self.m_w, 2) < self.min_x then
    self.m_x = self.min_x - idiv(self.m_w, 2)
  end
  if self.m_y + idiv(self.m_h, 2) > self.max_y then
    self.m_y = self.max_y - idiv(self.m_h, 2)
  elseif self.m_y + idiv(self.m_h, 2) < self.min_y then
    self.m_y = self.min_y - idiv(self.m_h, 2)
  end
  self.m_x2 = self.m_x + self.m_w
  self.m_y2 = self.m_y + self.m_h
end

local function init_variables(self, game)
  self.active = true
  self.f_oldloc_x = INT_MAX
  self.amclock = 0
  self.lightlev = 0
  self.m_paninc_x = 0
  self.m_paninc_y = 0
  self.ftom_zoommul = FRACUNIT
  self.mtof_zoommul = FRACUNIT
  self.m_w = M.ftom(self, self.f_w)
  self.m_h = M.ftom(self, self.f_h)
  local mo = game.player.mo
  self.m_x = mo.x - idiv(self.m_w, 2)
  self.m_y = mo.y - idiv(self.m_h, 2)
  change_window_loc(self)
  self.old_m_x = self.m_x
  self.old_m_y = self.m_y
  self.old_m_w = self.m_w
  self.old_m_h = self.m_h
end

local function load_pics(self, wadfile)
  self.marknums = {}
  for i = 0, 9 do
    local n = wad.check_num_for_name(wadfile, "AMMNUM" .. tostring(i))
    if n >= 0 then
      self.marknums[i + 1] = wad.cache_lump_num(wadfile, n)
    else
      self.marknums[i + 1] = nil
    end
  end
end

function M.start(self, game)
  if not self.stopped then
    M.stop(self)
  end
  self.stopped = false
  if self.lastlevel ~= game.mapn or self.lastepisode ~= game.episode then
    level_init(self, game)
    self.lastlevel = game.mapn
    self.lastepisode = game.episode
  end
  init_variables(self, game)
  load_pics(self, game.wad)
  self.active = true
end

function M.stop(self)
  self.active = false
  self.stopped = true
  self.m_paninc_x = 0
  self.m_paninc_y = 0
  self.mtof_zoommul = FRACUNIT
  self.ftom_zoommul = FRACUNIT
  self.bigstate = 0
end

function M.reset_level(self)
  if self.active then
    M.stop(self)
  end
  self.lastlevel = -1
  self.lastepisode = -1
  self.cheating = 0
end

local function do_follow(self, game)
  local mo = game.player.mo
  if self.f_oldloc_x ~= mo.x or self.f_oldloc_y ~= mo.y then
    self.m_x = M.ftom(self, M.mtof(self, mo.x)) - idiv(self.m_w, 2)
    self.m_y = M.ftom(self, M.mtof(self, mo.y)) - idiv(self.m_h, 2)
    self.m_x2 = self.m_x + self.m_w
    self.m_y2 = self.m_y + self.m_h
    self.f_oldloc_x = mo.x
    self.f_oldloc_y = mo.y
  end
end

local function change_window_scale(self)
  self.scale_mtof = compat.fixed_mul(self.scale_mtof, self.mtof_zoommul)
  self.scale_ftom = compat.fixed_div(FRACUNIT, self.scale_mtof)
  if self.scale_mtof < self.min_scale_mtof then
    min_out(self)
  elseif self.scale_mtof > self.max_scale_mtof then
    max_out(self)
  else
    activate_new_scale(self)
  end
end

function M.ticker(self, game)
  if not self.active then
    return
  end
  self.amclock = self.amclock + 1
  if self.followplayer ~= 0 then
    do_follow(self, game)
  end
  if self.ftom_zoommul ~= FRACUNIT then
    change_window_scale(self)
  end
  if self.m_paninc_x ~= 0 or self.m_paninc_y ~= 0 then
    change_window_loc(self)
  end
end

local function clear_fb(self)
  local fb = self.fb
  local color = BACKGROUND
  for y = 0, self.f_h - 1 do
    local row = y * self.f_w
    for x = 0, self.f_w - 1 do
      fb[row + x + 1] = color
    end
  end
end

local function put_dot(self, xx, yy, cc)
  if xx >= 0 and xx < self.f_w and yy >= 0 and yy < self.f_h then
    self.fb[yy * self.f_w + xx + 1] = band(cc, 255)
  end
end

local function draw_fline(self, x0, y0, x1, y1, color)
  if not (x0 >= 0 and x0 < self.f_w and y0 >= 0 and y0 < self.f_h and x1 >= 0 and x1 < self.f_w and y1 >= 0 and y1 < self.f_h) then
    return
  end
  local dx = x1 - x0
  local ax = dx
  if ax < 0 then
    ax = -ax
  end
  ax = ax * 2
  local sx = 1
  if dx < 0 then
    sx = -1
  end
  local dy = y1 - y0
  local ay = dy
  if ay < 0 then
    ay = -ay
  end
  ay = ay * 2
  local sy = 1
  if dy < 0 then
    sy = -1
  end
  local x, y = x0, y0
  if ax > ay then
    local d = ay - idiv(ax, 2)
    while true do
      put_dot(self, x, y, color)
      if x == x1 then
        return
      end
      if d >= 0 then
        y = y + sy
        d = d - ax
      end
      x = x + sx
      d = d + ay
    end
  else
    local d = ax - idiv(ay, 2)
    while true do
      put_dot(self, x, y, color)
      if y == y1 then
        return
      end
      if d >= 0 then
        x = x + sx
        d = d - ay
      end
      y = y + sy
      d = d + ax
    end
  end
end

local function outcode(self, mx, my)
  local oc = 0
  if my < 0 then
    oc = bor(oc, OC_TOP)
  elseif my >= self.f_h then
    oc = bor(oc, OC_BOTTOM)
  end
  if mx < 0 then
    oc = bor(oc, OC_LEFT)
  elseif mx >= self.f_w then
    oc = bor(oc, OC_RIGHT)
  end
  return oc
end

local function clip_mline(self, ax, ay, bx, by)
  local out1 = 0
  local out2 = 0
  if ay > self.m_y2 then
    out1 = OC_TOP
  elseif ay < self.m_y then
    out1 = OC_BOTTOM
  end
  if by > self.m_y2 then
    out2 = OC_TOP
  elseif by < self.m_y then
    out2 = OC_BOTTOM
  end
  if band(out1, out2) ~= 0 then
    return false
  end
  if ax < self.m_x then
    out1 = bor(out1, OC_LEFT)
  elseif ax > self.m_x2 then
    out1 = bor(out1, OC_RIGHT)
  end
  if bx < self.m_x then
    out2 = bor(out2, OC_LEFT)
  elseif bx > self.m_x2 then
    out2 = bor(out2, OC_RIGHT)
  end
  if band(out1, out2) ~= 0 then
    return false
  end
  local fx0 = M.cxmtof(self, ax)
  local fy0 = M.cymtof(self, ay)
  local fx1 = M.cxmtof(self, bx)
  local fy1 = M.cymtof(self, by)
  out1 = outcode(self, fx0, fy0)
  out2 = outcode(self, fx1, fy1)
  if band(out1, out2) ~= 0 then
    return false
  end
  local f_w = self.f_w
  local f_h = self.f_h
  local clipped = false
  for _ = 1, 8 do
    if bor(out1, out2) == 0 then
      clipped = true
      break
    end
    local outside
    if out1 ~= 0 then
      outside = out1
    else
      outside = out2
    end
    local tmpx, tmpy
    if band(outside, OC_TOP) ~= 0 then
      local dy = fy0 - fy1
      local dx = fx1 - fx0
      if dy ~= 0 then
        tmpx = fx0 + trunc_div(dx * fy0, dy)
      else
        tmpx = fx0
      end
      tmpy = 0
    elseif band(outside, OC_BOTTOM) ~= 0 then
      local dy = fy0 - fy1
      local dx = fx1 - fx0
      if dy ~= 0 then
        tmpx = fx0 + trunc_div(dx * (fy0 - f_h), dy)
      else
        tmpx = fx0
      end
      tmpy = f_h - 1
    elseif band(outside, OC_RIGHT) ~= 0 then
      local dy = fy1 - fy0
      local dx = fx1 - fx0
      if dx ~= 0 then
        tmpy = fy0 + trunc_div(dy * (f_w - 1 - fx0), dx)
      else
        tmpy = fy0
      end
      tmpx = f_w - 1
    else
      local dy = fy1 - fy0
      local dx = fx1 - fx0
      if dx ~= 0 then
        tmpy = fy0 + trunc_div(dy * (-fx0), dx)
      else
        tmpy = fy0
      end
      tmpx = 0
    end
    if outside == out1 then
      fx0, fy0 = tmpx, tmpy
      out1 = outcode(self, fx0, fy0)
    else
      fx1, fy1 = tmpx, tmpy
      out2 = outcode(self, fx1, fy1)
    end
    if band(out1, out2) ~= 0 then
      return false
    end
  end
  if not clipped then
    return false
  end
  self.clip[1] = fx0
  self.clip[2] = fy0
  self.clip[3] = fx1
  self.clip[4] = fy1
  return true
end

local function draw_mline(self, ax, ay, bx, by, color)
  if clip_mline(self, ax, ay, bx, by) then
    draw_fline(self, self.clip[1], self.clip[2], self.clip[3], self.clip[4], color)
  end
end

local function draw_grid(self, game)
  local block = MAPBLOCKUNITS * FRACUNIT
  local orgx = game.world.bmaporgx
  local orgy = game.world.bmaporgy
  local start = self.m_x
  local rem = (start - orgx) % block
  if rem ~= 0 then
    start = start + block - rem
  end
  local endx = self.m_x + self.m_w
  local y0 = self.m_y
  local y1 = self.m_y + self.m_h
  local x = start
  while x < endx do
    draw_mline(self, x, y0, x, y1, GRIDCOLORS)
    x = x + block
  end
  start = self.m_y
  rem = (start - orgy) % block
  if rem ~= 0 then
    start = start + block - rem
  end
  local endy = self.m_y + self.m_h
  local x0 = self.m_x
  local x1 = self.m_x + self.m_w
  local y = start
  while y < endy do
    draw_mline(self, x0, y, x1, y, GRIDCOLORS)
    y = y + block
  end
end

local function draw_walls(self, game)
  local color = WALLCOLORS + self.lightlev
  local powers = game.player.powers
  local allmap = powers and (powers[PW_ALLMAP] or 0) ~= 0
  for i = 1, #game.world.lines do
    local lineobj = game.world.lines[i]
    local ax, ay = lineobj.v1.x, lineobj.v1.y
    local bx, by = lineobj.v2.x, lineobj.v2.y
    local mapped = band(lineobj.flags, ML_MAPPED) ~= 0
    if self.cheating ~= 0 or mapped then
      if band(lineobj.flags, ML_DONTDRAW) ~= 0 and self.cheating == 0 then
        -- linha que o mapa nao mostra
      elseif lineobj.backsector == nil then
        draw_mline(self, ax, ay, bx, by, color)
      elseif lineobj.frontsector == nil then
        -- sem frente
      elseif lineobj.special == 39 then
        draw_mline(self, ax, ay, bx, by, WALLCOLORS + idiv(WALLRANGE, 2))
      elseif band(lineobj.flags, ML_SECRET) ~= 0 then
        draw_mline(self, ax, ay, bx, by, color)
      elseif lineobj.backsector.floorheight ~= lineobj.frontsector.floorheight then
        draw_mline(self, ax, ay, bx, by, FDWALLCOLORS + self.lightlev)
      elseif lineobj.backsector.ceilingheight ~= lineobj.frontsector.ceilingheight then
        draw_mline(self, ax, ay, bx, by, CDWALLCOLORS + self.lightlev)
      elseif self.cheating ~= 0 then
        draw_mline(self, ax, ay, bx, by, TSWALLCOLORS + self.lightlev)
      end
    elseif allmap and band(lineobj.flags, ML_DONTDRAW) == 0 then
      draw_mline(self, ax, ay, bx, by, GRAYS + 3)
    end
  end
end

local function rotate(x, y, a)
  local n_fine = compat.ushr(compat.as_u32(a), ANGLETOFINESHIFT)
  local cs = cosine_at(n_fine)
  local sn = tables.finesine[n_fine]
  local rx = compat.fixed_mul(x, cs) - compat.fixed_mul(y, sn)
  local ry = compat.fixed_mul(x, sn) + compat.fixed_mul(y, cs)
  return rx, ry
end

local function draw_line_character(self, lines, scale, angle, color, x, y)
  for i = 1, #lines do
    local ln = lines[i]
    local nax, nay, nbx, nby = ln[1], ln[2], ln[3], ln[4]
    if scale ~= 0 then
      nax = compat.fixed_mul(scale, nax)
      nay = compat.fixed_mul(scale, nay)
      nbx = compat.fixed_mul(scale, nbx)
      nby = compat.fixed_mul(scale, nby)
    end
    if angle ~= 0 then
      nax, nay = rotate(nax, nay, angle)
      nbx, nby = rotate(nbx, nby, angle)
    end
    draw_mline(self, nax + x, nay + y, nbx + x, nby + y, color)
  end
end

local function draw_marks(self)
  for i = 1, AM_NUMMARKPOINTS do
    local pt = self.markpoints[i]
    local patch = self.marknums[i]
    if pt.x ~= -1 and patch ~= nil then
      local fx = M.cxmtof(self, pt.x)
      local fy = M.cymtof(self, pt.y)
      if self.f_x <= fx and fx <= self.f_w - 5 and self.f_y <= fy and fy <= self.f_h - 6 then
        v.draw_patch(self.fb, fx, fy, patch)
      end
    end
  end
end

function M.drawer(self, fb, game)
  if not self.active then
    return
  end
  self.fb = fb
  clear_fb(self)
  if self.grid ~= 0 then
    draw_grid(self, game)
  end
  draw_walls(self, game)
  local mo = game.player.mo
  draw_line_character(self, self.player_arrow, 0, mo.angle, WHITE, mo.x, mo.y)
  if self.cheating == 2 then
    local scale = 16 * FRACUNIT
    local color = THINGCOLORS + self.lightlev
    for i = 1, #game.world.mobjs do
      local thing = game.world.mobjs[i]
      draw_line_character(self, self.thintriangle_guy, scale, thing.angle or 0, color, thing.x, thing.y)
    end
  end
  put_dot(self, idiv(self.f_w, 2), idiv(self.f_h, 2), XHAIRCOLORS)
  draw_marks(self)
  self.fb = nil
end

local function save_scale(self)
  self.old_m_x = self.m_x
  self.old_m_y = self.m_y
  self.old_m_w = self.m_w
  self.old_m_h = self.m_h
end

local function restore_scale(self, game)
  self.m_w = self.old_m_w
  self.m_h = self.old_m_h
  if self.followplayer == 0 then
    self.m_x = self.old_m_x
    self.m_y = self.old_m_y
  else
    local mo = game.player.mo
    self.m_x = mo.x - idiv(self.m_w, 2)
    self.m_y = mo.y - idiv(self.m_h, 2)
  end
  self.m_x2 = self.m_x + self.m_w
  self.m_y2 = self.m_y + self.m_h
  self.scale_mtof = compat.fixed_div(self.f_w * FRACUNIT, self.m_w)
  self.scale_ftom = compat.fixed_div(FRACUNIT, self.scale_mtof)
end

local function add_mark(self)
  local i = self.markpointnum + 1
  self.markpoints[i].x = self.m_x + idiv(self.m_w, 2)
  self.markpoints[i].y = self.m_y + idiv(self.m_h, 2)
  self.markpointnum = (self.markpointnum + 1) % AM_NUMMARKPOINTS
end

function M.responder(self, key, down, game)
  if game.gamestate ~= "view" or game.player == nil or game.world == nil then
    return false
  end
  if down then
    if not self.active then
      if key == "tab" then
        M.start(self, game)
        return true
      end
      return false
    end
    if key == "right" or key == "left" or key == "up" or key == "down" then
      if self.followplayer ~= 0 then
        return false
      end
      if key == "right" then
        self.m_paninc_x = M.ftom(self, F_PANINC)
      elseif key == "left" then
        self.m_paninc_x = -M.ftom(self, F_PANINC)
      elseif key == "up" then
        self.m_paninc_y = M.ftom(self, F_PANINC)
      else
        self.m_paninc_y = -M.ftom(self, F_PANINC)
      end
      return true
    end
    if key == "minus" then
      self.mtof_zoommul = M_ZOOMOUT
      self.ftom_zoommul = M_ZOOMIN
      return true
    end
    if key == "equals" then
      self.mtof_zoommul = M_ZOOMIN
      self.ftom_zoommul = M_ZOOMOUT
      return true
    end
    if key == "tab" then
      M.stop(self)
      return true
    end
    if key == "0" then
      if self.bigstate ~= 0 then
        self.bigstate = 0
      else
        self.bigstate = 1
      end
      if self.bigstate ~= 0 then
        save_scale(self)
        min_out(self)
      else
        restore_scale(self, game)
      end
      return true
    end
    if key == "f" then
      if self.followplayer ~= 0 then
        self.followplayer = 0
      else
        self.followplayer = 1
      end
      self.f_oldloc_x = INT_MAX
      if self.followplayer ~= 0 then
        player_mod.set_message(game.player, "Follow Mode ON")
      else
        player_mod.set_message(game.player, "Follow Mode OFF")
      end
      return true
    end
    if key == "g" then
      if self.grid ~= 0 then
        self.grid = 0
      else
        self.grid = 1
      end
      if self.grid ~= 0 then
        player_mod.set_message(game.player, "Grid ON")
      else
        player_mod.set_message(game.player, "Grid OFF")
      end
      return true
    end
    if key == "m" then
      player_mod.set_message(game.player, "Marked Spot " .. tostring(self.markpointnum))
      add_mark(self)
      return true
    end
    if key == "c" then
      clear_marks(self)
      player_mod.set_message(game.player, "All Marks Cleared")
      return true
    end
    return false
  end
  if self.active then
    if (key == "right" or key == "left") and self.followplayer == 0 then
      self.m_paninc_x = 0
    elseif (key == "up" or key == "down") and self.followplayer == 0 then
      self.m_paninc_y = 0
    elseif key == "minus" or key == "equals" then
      self.mtof_zoommul = FRACUNIT
      self.ftom_zoommul = FRACUNIT
    end
  end
  return false
end

function M.cycle_iddt(self)
  self.cheating = (self.cheating + 1) % 3
end

return M
