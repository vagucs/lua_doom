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
-- Contagem da intermissao. Um jogador, a partir de wi_stuff.py.

local v = require("v_video")
local wad = require("wad")
local compat = require("compat")

local SCREENWIDTH = 320
local SCREENHEIGHT = 200
local TICRATE = 35
local WI_TITLEY = 2
local SP_STATSX = 50
local SP_STATSY = 50
local SP_TIMEX = 16
local SP_TIMEY = SCREENHEIGHT - 32
local SHOWNEXTLOCDELAY = 4
local NO_STATE = -1
local STAT_COUNT = 0
local SHOW_NEXT_LOC = 1
local ANIM_ALWAYS = 0
local ANIM_LEVEL = 2

local PARS = {
  [0] = { [0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  { [0] = 0, 30, 75, 120, 90, 165, 180, 180, 30, 165 },
  { [0] = 0, 90, 90, 90, 120, 90, 360, 240, 30, 170 },
  { [0] = 0, 90, 45, 90, 150, 90, 90, 165, 30, 135 },
}
local CPARS = {
  [0] = 30, 90, 120, 120, 90, 150, 120, 120, 270, 90,
  210, 150, 150, 150, 210, 150, 420, 150, 210, 150,
  240, 150, 180, 150, 150, 300, 330, 420, 300, 180,
  120, 30,
}

local LNODES = {
  { { 185, 164 }, { 148, 143 }, { 69, 122 }, { 209, 102 }, { 116, 89 }, { 166, 55 }, { 71, 56 }, { 135, 29 }, { 71, 24 } },
  { { 254, 25 }, { 97, 50 }, { 188, 64 }, { 128, 78 }, { 214, 92 }, { 133, 130 }, { 208, 136 }, { 148, 140 }, { 235, 158 } },
  { { 156, 168 }, { 48, 154 }, { 174, 95 }, { 265, 75 }, { 130, 48 }, { 279, 23 }, { 198, 48 }, { 140, 25 }, { 281, 136 } },
}

local ANIMS = {
  {
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 224, 104, 0 },
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 184, 160, 0 },
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 112, 136, 0 },
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 72, 112, 0 },
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 88, 96, 0 },
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 64, 48, 0 },
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 192, 40, 0 },
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 136, 16, 0 },
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 80, 16, 0 },
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 64, 24, 0 },
  },
  {
    { ANIM_LEVEL, math.floor(TICRATE / 3), 1, 128, 136, 1 },
    { ANIM_LEVEL, math.floor(TICRATE / 3), 1, 128, 136, 2 },
    { ANIM_LEVEL, math.floor(TICRATE / 3), 1, 128, 136, 3 },
    { ANIM_LEVEL, math.floor(TICRATE / 3), 1, 128, 136, 4 },
    { ANIM_LEVEL, math.floor(TICRATE / 3), 1, 128, 136, 5 },
    { ANIM_LEVEL, math.floor(TICRATE / 3), 1, 128, 136, 6 },
    { ANIM_LEVEL, math.floor(TICRATE / 3), 1, 128, 136, 7 },
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 192, 144, 8 },
    { ANIM_LEVEL, math.floor(TICRATE / 3), 1, 128, 136, 8 },
  },
  {
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 104, 168, 0 },
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 40, 136, 0 },
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 160, 96, 0 },
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 104, 80, 0 },
    { ANIM_ALWAYS, math.floor(TICRATE / 3), 3, 120, 32, 0 },
    { ANIM_ALWAYS, math.floor(TICRATE / 4), 3, 40, 0, 0 },
  },
}

local M = {}

function M.partime(episode, mapn, commercial)
  if commercial then
    local i = mapn - 1
    if i < 0 then
      i = 0
    elseif i > #CPARS then
      i = #CPARS
    end
    return TICRATE * CPARS[i]
  end
  if episode >= 1 and episode <= 3 and mapn >= 1 and mapn <= 9 then
    return TICRATE * PARS[episode][mapn]
  end
  if mapn >= 1 and mapn <= 9 then
    local i = mapn
    if i > #CPARS then
      i = #CPARS
    end
    return TICRATE * CPARS[i]
  end
  return TICRATE * 30
end

local function pct(value, maximum)
  if maximum < 1 then
    maximum = 1
  end
  return math.floor(value * 100 / maximum)
end

local function lump(w, name)
  local n = wad.check_num_for_name(w, name)
  if n < 0 then
    return nil
  end
  return wad.cache_lump_num(w, n)
end

local function pw(patch)
  if not patch then
    return 8
  end
  local w = v.patch_size(patch)
  return w
end

local function ph(patch)
  if not patch then
    return 16
  end
  local _, h = v.patch_size(patch)
  return h
end

local function init_animated(self)
  if self.wbs.commercial or self.wbs.epsd > 2 then
    return
  end
  for i = 1, #self.anims do
    local a = self.anims[i]
    a.ctr = -1
    if a.type == ANIM_ALWAYS then
      local span = a.period
      if span < 1 then
        span = 1
      end
      a.nexttic = self.bcnt + 1 + math.random(0, span - 1)
    else
      a.nexttic = self.bcnt + 1
    end
  end
end

function M.new(game, wbs)
  local self = {
    game = game,
    wbs = wbs,
    state = STAT_COUNT,
    accelerate = 0,
    sp_state = 1,
    cnt_kills = -1,
    cnt_items = -1,
    cnt_secret = -1,
    cnt_time = -1,
    cnt_par = -1,
    cnt_pause = TICRATE,
    cnt = 0,
    bcnt = 0,
    snl_pointeron = false,
    done = false,
    anims = {},
    p = {},
    num = {},
    lnames = {},
  }
  local w = game.wad
  local names = {
    finished = "WIF",
    entering = "WIENTER",
    kills = "WIOSTK",
    items = "WIOSTI",
    sp_secret = "WISCRT2",
    percent = "WIPCNT",
    colon = "WICOLON",
    time = "WITIME",
    par = "WIPAR",
    sucks = "WISUCKS",
    minus = "WIMINUS",
    splat = "WISPLAT",
    yah0 = "WIURH0",
    yah1 = "WIURH1",
  }
  for k, lumpname in pairs(names) do
    self.p[k] = lump(w, lumpname)
  end
  for i = 0, 9 do
    self.num[i] = lump(w, "WINUM" .. tostring(i))
  end
  local bg
  if wbs.commercial or wbs.epsd == 3 then
    bg = "INTERPIC"
  else
    bg = "WIMAP" .. tostring(wbs.epsd)
  end
  self.background = lump(w, bg) or lump(w, "INTERPIC")
  local nmaps = 9
  if wbs.commercial then
    nmaps = 32
  end
  for i = 0, nmaps - 1 do
    local name
    if wbs.commercial then
      name = string.format("CWILV%02d", i)
    else
      name = "WILV" .. tostring(wbs.epsd) .. tostring(i)
    end
    self.lnames[i] = lump(w, name)
  end
  if not wbs.commercial and wbs.epsd < 3 then
    local specs = ANIMS[wbs.epsd + 1]
    for j = 1, #specs do
      local spec = specs[j]
      local a = {
        type = spec[1],
        period = spec[2],
        nanims = spec[3],
        x = spec[4],
        y = spec[5],
        data1 = spec[6],
        patches = {},
        ctr = -1,
        nexttic = 0,
      }
      for i = 0, a.nanims - 1 do
        if wbs.epsd == 1 and j == 9 then
          local src = self.anims[5]
          a.patches[i + 1] = src and src.patches[i + 1] or nil
        else
          a.patches[i + 1] = lump(w, string.format("WIA%d%02d%02d", wbs.epsd, j - 1, i))
        end
      end
      self.anims[j] = a
    end
  end
  init_animated(self)
  return self
end

local function update_animated(self)
  if self.wbs.commercial or self.wbs.epsd > 2 then
    return
  end
  for i = 1, #self.anims do
    local a = self.anims[i]
    if self.bcnt == a.nexttic then
      if a.type == ANIM_ALWAYS then
        a.ctr = a.ctr + 1
        if a.ctr >= a.nanims then
          a.ctr = 0
        end
        a.nexttic = self.bcnt + a.period
      elseif a.type == ANIM_LEVEL then
        if not (self.state == STAT_COUNT and i == 8) and self.wbs.next == a.data1 then
          a.ctr = a.ctr + 1
          if a.ctr == a.nanims then
            a.ctr = a.ctr - 1
          end
          a.nexttic = self.bcnt + a.period
        end
      end
    end
  end
end

local function check_accelerate(self)
  local menu = self.game.menu
  if menu and menu.active then
    return
  end
  local held = self.game.held or {}
  local attack = held.ctrl and true or false
  local use = (held.space or held.e) and true or false
  local enter = held["return"] and true or false
  local p = self.game.player
  if p == nil then
    if attack or use or enter then
      self.accelerate = 1
    end
    return
  end
  if attack then
    if not p.attackdown then
      self.accelerate = 1
    end
    p.attackdown = true
  else
    p.attackdown = false
  end
  if use or enter then
    if not p.usedown then
      self.accelerate = 1
    end
    p.usedown = true
  else
    if not use then
      p.usedown = false
    end
  end
end

local function init_show_next(self)
  self.state = SHOW_NEXT_LOC
  self.accelerate = 0
  self.cnt = SHOWNEXTLOCDELAY * TICRATE
  init_animated(self)
end

local function init_no_state(self)
  self.state = NO_STATE
  self.accelerate = 0
  self.cnt = 10
end

local function update_stats(self)
  local w = self.wbs
  update_animated(self)
  if self.accelerate ~= 0 and self.sp_state ~= 10 then
    self.accelerate = 0
    self.cnt_kills = pct(w.skills, w.maxkills)
    self.cnt_items = pct(w.sitems, w.maxitems)
    self.cnt_secret = pct(w.ssecret, w.maxsecret)
    self.cnt_time = math.floor(w.stime / TICRATE)
    self.cnt_par = math.floor(w.partime / TICRATE)
    if self.game.start_sound then
      self.game.start_sound("barexp")
    end
    self.sp_state = 10
  end
  if self.sp_state == 2 then
    self.cnt_kills = self.cnt_kills + 2
    if compat.band(self.bcnt, 3) == 0 and self.game.start_sound then
      self.game.start_sound("pistol")
    end
    local target = pct(w.skills, w.maxkills)
    if self.cnt_kills >= target then
      self.cnt_kills = target
      if self.game.start_sound then
        self.game.start_sound("barexp")
      end
      self.sp_state = self.sp_state + 1
    end
  elseif self.sp_state == 4 then
    self.cnt_items = self.cnt_items + 2
    if compat.band(self.bcnt, 3) == 0 and self.game.start_sound then
      self.game.start_sound("pistol")
    end
    local target = pct(w.sitems, w.maxitems)
    if self.cnt_items >= target then
      self.cnt_items = target
      if self.game.start_sound then
        self.game.start_sound("barexp")
      end
      self.sp_state = self.sp_state + 1
    end
  elseif self.sp_state == 6 then
    self.cnt_secret = self.cnt_secret + 2
    if compat.band(self.bcnt, 3) == 0 and self.game.start_sound then
      self.game.start_sound("pistol")
    end
    local target = pct(w.ssecret, w.maxsecret)
    if self.cnt_secret >= target then
      self.cnt_secret = target
      if self.game.start_sound then
        self.game.start_sound("barexp")
      end
      self.sp_state = self.sp_state + 1
    end
  elseif self.sp_state == 8 then
    if compat.band(self.bcnt, 3) == 0 and self.game.start_sound then
      self.game.start_sound("pistol")
    end
    self.cnt_time = self.cnt_time + 3
    local ttime = math.floor(w.stime / TICRATE)
    if self.cnt_time >= ttime then
      self.cnt_time = ttime
    end
    self.cnt_par = self.cnt_par + 3
    local ptime = math.floor(w.partime / TICRATE)
    if self.cnt_par >= ptime then
      self.cnt_par = ptime
      if self.cnt_time >= ttime then
        if self.game.start_sound then
          self.game.start_sound("barexp")
        end
        self.sp_state = self.sp_state + 1
      end
    end
  elseif self.sp_state == 10 then
    if self.accelerate ~= 0 then
      if self.game.start_sound then
        self.game.start_sound("wpnup")
      end
      if self.wbs.commercial then
        init_no_state(self)
      else
        init_show_next(self)
      end
    end
  elseif compat.band(self.sp_state, 1) ~= 0 then
    self.cnt_pause = self.cnt_pause - 1
    if self.cnt_pause == 0 then
      self.sp_state = self.sp_state + 1
      self.cnt_pause = TICRATE
      if self.sp_state == 2 then
        self.cnt_kills = 0
      elseif self.sp_state == 4 then
        self.cnt_items = 0
      elseif self.sp_state == 6 then
        self.cnt_secret = 0
      elseif self.sp_state == 8 then
        self.cnt_time = 0
        self.cnt_par = 0
      end
    end
  end
end

local function update_show_next(self)
  update_animated(self)
  self.cnt = self.cnt - 1
  if self.cnt == 0 or self.accelerate ~= 0 then
    init_no_state(self)
  else
    self.snl_pointeron = compat.band(self.cnt, 31) < 20
  end
end

local function update_no_state(self)
  update_animated(self)
  self.cnt = self.cnt - 1
  if self.cnt == 0 then
    self.done = true
  end
end

function M.ticker(self)
  self.bcnt = self.bcnt + 1
  if self.bcnt == 1 and self.game.sound and self.game.sound.change_music then
    if self.wbs.commercial then
      self.game.sound.change_music("dm2int", true)
    else
      self.game.sound.change_music("inter", true)
    end
  end
  check_accelerate(self)
  if self.state == STAT_COUNT then
    update_stats(self)
  elseif self.state == SHOW_NEXT_LOC then
    update_show_next(self)
  elseif self.state == NO_STATE then
    update_no_state(self)
  end
end

local function draw_num(self, fb, x, y, n, digits)
  local fontw = 8
  if self.num[0] then
    fontw = pw(self.num[0])
  end
  if digits < 0 then
    if n == 0 then
      digits = 1
    else
      digits = 0
      local temp = math.abs(n)
      while temp ~= 0 do
        temp = math.floor(temp / 10)
        digits = digits + 1
      end
    end
  end
  local neg = n < 0
  if neg then
    n = -n
  end
  while digits > 0 do
    digits = digits - 1
    x = x - fontw
    local d = n % 10
    if self.num[d] then
      v.draw_patch(fb, x, y, self.num[d])
    end
    n = math.floor(n / 10)
  end
  if neg and self.p.minus then
    x = x - 8
    v.draw_patch(fb, x, y, self.p.minus)
  end
  return x
end

local function draw_percent(self, fb, x, y, value)
  if value < 0 then
    return
  end
  if self.p.percent then
    v.draw_patch(fb, x, y, self.p.percent)
  end
  draw_num(self, fb, x, y, value, -1)
end

local function draw_time(self, fb, x, y, t)
  if t < 0 then
    return
  end
  if t > 61 * 59 then
    if self.p.sucks then
      v.draw_patch(fb, x - pw(self.p.sucks), y, self.p.sucks)
    end
    return
  end
  local colon = self.p.colon
  local div = 1
  while true do
    local n = math.floor(t / div) % 60
    local colonw = 0
    if colon then
      colonw = pw(colon)
    end
    x = draw_num(self, fb, x, y, n, 2) - colonw
    div = div * 60
    if div == 60 or math.floor(t / div) ~= 0 then
      if colon then
        v.draw_patch(fb, x, y, colon)
      end
    end
    if math.floor(t / div) == 0 then
      break
    end
  end
end

local function draw_animated(self, fb)
  if self.wbs.commercial or self.wbs.epsd > 2 then
    return
  end
  for i = 1, #self.anims do
    local a = self.anims[i]
    if a.ctr >= 0 and a.ctr < #a.patches and a.patches[a.ctr + 1] then
      v.draw_patch(fb, a.x, a.y, a.patches[a.ctr + 1])
    end
  end
end

local function draw_bg(self, fb)
  if self.background then
    v.draw_patch(fb, 0, 0, self.background)
  end
  draw_animated(self, fb)
end

local function draw_lf(self, fb)
  local y = WI_TITLEY
  local patch = self.lnames[self.wbs.last]
  if patch then
    v.draw_patch(fb, math.floor((SCREENWIDTH - pw(patch)) / 2), y, patch)
    y = y + math.floor(5 * ph(patch) / 4)
  end
  if self.p.finished then
    v.draw_patch(fb, math.floor((SCREENWIDTH - pw(self.p.finished)) / 2), y, self.p.finished)
  end
end

local function draw_el(self, fb)
  local y = WI_TITLEY
  if self.p.entering then
    v.draw_patch(fb, math.floor((SCREENWIDTH - pw(self.p.entering)) / 2), y, self.p.entering)
    y = y + math.floor(5 * ph(self.p.entering) / 4)
  end
  local patch = self.lnames[self.wbs.next]
  if patch then
    v.draw_patch(fb, math.floor((SCREENWIDTH - pw(patch)) / 2), y, patch)
  end
end

local function draw_on_lnode(self, fb, n, patches)
  local nodes = LNODES[self.wbs.epsd + 1]
  if nodes == nil or nodes[n + 1] == nil then
    return
  end
  local node = nodes[n + 1]
  for i = 1, #patches do
    local patch = patches[i]
    if patch then
      local w, h, left, top = v.patch_size(patch)
      local left_x = node[1] - left
      local top_y = node[2] - top
      if left_x >= 0 and left_x + w < SCREENWIDTH and top_y >= 0 and top_y + h < SCREENHEIGHT then
        v.draw_patch(fb, node[1], node[2], patch)
        return
      end
    end
  end
end

local function draw_stats(self, fb)
  draw_bg(self, fb)
  draw_lf(self, fb)
  local lh = 24
  if self.num[0] then
    lh = math.floor(3 * ph(self.num[0]) / 2)
  end
  if self.p.kills then
    v.draw_patch(fb, SP_STATSX, SP_STATSY, self.p.kills)
  end
  draw_percent(self, fb, SCREENWIDTH - SP_STATSX, SP_STATSY, self.cnt_kills)
  if self.p.items then
    v.draw_patch(fb, SP_STATSX, SP_STATSY + lh, self.p.items)
  end
  draw_percent(self, fb, SCREENWIDTH - SP_STATSX, SP_STATSY + lh, self.cnt_items)
  if self.p.sp_secret then
    v.draw_patch(fb, SP_STATSX, SP_STATSY + 2 * lh, self.p.sp_secret)
  end
  draw_percent(self, fb, SCREENWIDTH - SP_STATSX, SP_STATSY + 2 * lh, self.cnt_secret)
  if self.p.time then
    v.draw_patch(fb, SP_TIMEX, SP_TIMEY, self.p.time)
  end
  draw_time(self, fb, math.floor(SCREENWIDTH / 2) - SP_TIMEX, SP_TIMEY, self.cnt_time)
  if self.wbs.epsd < 3 then
    if self.p.par then
      v.draw_patch(fb, math.floor(SCREENWIDTH / 2) + SP_TIMEX, SP_TIMEY, self.p.par)
    end
    draw_time(self, fb, SCREENWIDTH - SP_TIMEX, SP_TIMEY, self.cnt_par)
  end
end

local function draw_show_next(self, fb)
  draw_bg(self, fb)
  if self.state == NO_STATE then
    self.snl_pointeron = true
  end
  if not self.wbs.commercial then
    if self.wbs.epsd > 2 then
      draw_el(self, fb)
      return
    end
    local last = self.wbs.last
    if self.wbs.last == 8 then
      last = self.wbs.next - 1
    end
    local splat = { self.p.splat }
    local yah = { self.p.yah0, self.p.yah1 }
    for i = 0, math.max(0, last + 1) - 1 do
      draw_on_lnode(self, fb, i, splat)
    end
    if self.wbs.didsecret then
      draw_on_lnode(self, fb, 8, splat)
    end
    if self.snl_pointeron then
      draw_on_lnode(self, fb, self.wbs.next, yah)
    end
  end
  if not self.wbs.commercial or self.wbs.next ~= 30 then
    draw_el(self, fb)
  end
end

function M.draw(self, fb)
  if self.state == STAT_COUNT then
    draw_stats(self, fb)
  else
    draw_show_next(self, fb)
  end
end

return M
