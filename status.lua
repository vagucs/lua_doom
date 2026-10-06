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
-- Barra de status. Vida, municao, armas, chaves e o rosto.

local v = require("v_video")
local wad = require("wad")
local collision = require("collision")
local compat = require("compat")

local ST_AMMOX, ST_AMMOY = 44, 171
local ST_HEALTHX, ST_HEALTHY = 90, 171
local ST_ARMORX, ST_ARMORY = 221, 171
local ST_FACESX, ST_FACESY = 143, 168
local ST_ARMSX, ST_ARMSY = 111, 172
local ST_ARMSXSPACE, ST_ARMSYSPACE = 12, 10
local ST_KEY0X, ST_KEY0Y = 239, 171
local ST_AMMO_POS = { { 288, 173 }, { 288, 179 }, { 288, 191 }, { 288, 185 } }
local ST_MAX_POS = { { 314, 173 }, { 314, 179 }, { 314, 191 }, { 314, 185 } }

local ST_NUMPAINFACES = 5
local ST_NUMSTRAIGHTFACES = 3
local ST_NUMTURNFACES = 2
local ST_NUMSPECIALFACES = 3
local ST_FACESTRIDE = ST_NUMSTRAIGHTFACES + ST_NUMTURNFACES + ST_NUMSPECIALFACES
local ST_TURNOFFSET = ST_NUMSTRAIGHTFACES
local ST_OUCHOFFSET = ST_TURNOFFSET + ST_NUMTURNFACES
local ST_EVILGRINOFFSET = ST_OUCHOFFSET + 1
local ST_RAMPAGEOFFSET = ST_EVILGRINOFFSET + 1
local ST_GODFACE = ST_NUMPAINFACES * ST_FACESTRIDE
local ST_DEADFACE = ST_GODFACE + 1
local ST_EVILGRINCOUNT = 2 * 35
local ST_STRAIGHTFACECOUNT = 17
local ST_TURNCOUNT = 35
local ST_RAMPAGEDELAY = 2 * 35
local ST_MUCHPAIN = 20

local HU_FONTSTART = string.byte("!")
local HU_FONTEND = string.byte("_")
local ANG45 = 536870912
local ANG180 = 2147483648
local CF_GODMODE = 2
local PW_INVULNERABILITY = 0
local IT_BLUECARD, IT_BLUESKULL = 0, 3
local IT_YELLOWCARD, IT_YELLOWSKULL = 1, 4
local IT_REDCARD, IT_REDSKULL = 2, 5
local AM_CLIP, AM_SHELL, AM_CELL, AM_MISL = 0, 1, 2, 3
local WP_SHOTGUN, WP_CHAINGUN = 2, 3
local WP_MISSILE, WP_PLASMA, WP_BFG, WP_SUPERSHOTGUN = 4, 5, 6, 8
local WP_PISTOL = 1

local WEAPON_AMMO = {
  [WP_PISTOL] = AM_CLIP,
  [WP_SHOTGUN] = AM_SHELL,
  [WP_SUPERSHOTGUN] = AM_SHELL,
  [WP_CHAINGUN] = AM_CLIP,
  [WP_MISSILE] = AM_MISL,
  [WP_PLASMA] = AM_CELL,
  [WP_BFG] = AM_CELL,
}

local M = {}

local function u32_lcg(rnd)
  local lo = rnd % 65536
  local hi = math.floor(rnd / 65536)
  local prod = lo * 20077
  prod = prod + (lo * 16838) * 65536
  prod = prod + (hi * 20077) * 65536
  prod = (prod + 12345) % 4294967296
  return prod
end

local function lump(w, name)
  local n = wad.check_num_for_name(w, name)
  if n < 0 then
    return nil
  end
  return wad.cache_lump_num(w, n)
end

local function copy_owned(player)
  local out = {}
  for i = 0, 8 do
    out[i] = false
    if player and player.weaponowned then
      out[i] = player.weaponowned[i] and true or false
    end
  end
  return out
end

function M.new(w)
  local self = { wad = w }
  self.sbar = lump(w, "STBAR")
  self.tallnum = {}
  self.shortnum = {}
  for i = 0, 9 do
    self.tallnum[i] = lump(w, "STTNUM" .. tostring(i))
    self.shortnum[i] = lump(w, "STYSNUM" .. tostring(i))
  end
  self.tallpercent = lump(w, "STTPRCNT")
  self.keys = {}
  for i = 0, 5 do
    self.keys[i] = lump(w, "STKEYS" .. tostring(i))
  end
  self.armsbg = lump(w, "STARMS")
  self.arms_off = {}
  for i = 2, 7 do
    self.arms_off[#self.arms_off + 1] = lump(w, "STGNUM" .. tostring(i))
  end
  self.fallback_face = lump(w, "STFST00")
  self.faces = {}
  for pain = 0, ST_NUMPAINFACES - 1 do
    for look = 0, ST_NUMSTRAIGHTFACES - 1 do
      self.faces[#self.faces + 1] = lump(w, "STFST" .. tostring(pain) .. tostring(look))
    end
    self.faces[#self.faces + 1] = lump(w, "STFTR" .. tostring(pain) .. "0")
    self.faces[#self.faces + 1] = lump(w, "STFTL" .. tostring(pain) .. "0")
    self.faces[#self.faces + 1] = lump(w, "STFOUCH" .. tostring(pain))
    self.faces[#self.faces + 1] = lump(w, "STFEVL" .. tostring(pain))
    self.faces[#self.faces + 1] = lump(w, "STFKILL" .. tostring(pain))
  end
  self.faces[#self.faces + 1] = lump(w, "STFGOD0")
  self.faces[#self.faces + 1] = lump(w, "STFDEAD0")
  self.font = {}
  for ch = HU_FONTSTART, HU_FONTEND do
    local name = string.format("STCFN%03d", ch)
    self.font[#self.font + 1] = lump(w, name)
  end
  M.reset(self, nil)
  return self
end

function M.reset(self, player)
  self.face_index = 0
  self.face_count = 0
  self.face_priority = 0
  self.old_health = -1
  self.pain_old_health = -1
  self.last_calc = 0
  self.last_attackdown = -1
  self.old_weapons_owned = copy_owned(player)
  self.rnd = 1
end

local function face_patch(self, index)
  local patch = self.faces[index + 1]
  if patch == nil then
    return self.fallback_face
  end
  return patch
end

local function calc_pain_offset(self, player)
  local health = math.floor(player.health or 0)
  if health > 100 then
    health = 100
  elseif health < 0 then
    health = 0
  end
  if health ~= self.pain_old_health then
    self.last_calc = math.floor(ST_FACESTRIDE * ((100 - health) * ST_NUMPAINFACES) / 101)
    self.pain_old_health = health
  end
  return self.last_calc
end

local function update_face(self, player, st_random)
  if self.face_priority < 10 and (player.health or 0) <= 0 then
    self.face_priority = 9
    self.face_index = ST_DEADFACE
    self.face_count = 1
  end
  if self.face_priority < 9 and (player.bonuscount or 0) ~= 0 then
    local grin = false
    for i = 0, 8 do
      local now = player.weaponowned[i] and true or false
      if self.old_weapons_owned[i] ~= now then
        grin = true
        self.old_weapons_owned[i] = now
      end
    end
    if grin then
      self.face_priority = 8
      self.face_count = ST_EVILGRINCOUNT
      self.face_index = calc_pain_offset(self, player) + ST_EVILGRINOFFSET
    end
  end
  if self.face_priority < 8 and (player.damagecount or 0) ~= 0 and player.attacker ~= nil and player.mo ~= nil and player.attacker ~= player.mo then
    self.face_priority = 7
    if (player.health or 0) - self.old_health > ST_MUCHPAIN then
      self.face_count = ST_TURNCOUNT
      self.face_index = calc_pain_offset(self, player) + ST_OUCHOFFSET
    else
      local bad = collision.angle_to(player.mo.x, player.mo.y, player.attacker.x, player.attacker.y)
      local diffang
      local turn_right
      if compat.as_u32(bad) > compat.as_u32(player.mo.angle) then
        diffang = compat.as_u32(bad - player.mo.angle)
        turn_right = diffang > compat.as_u32(ANG180)
      else
        diffang = compat.as_u32(player.mo.angle - bad)
        turn_right = diffang <= compat.as_u32(ANG180)
      end
      self.face_count = ST_TURNCOUNT
      self.face_index = calc_pain_offset(self, player)
      if diffang < compat.as_u32(ANG45) then
        self.face_index = self.face_index + ST_RAMPAGEOFFSET
      elseif turn_right then
        self.face_index = self.face_index + ST_TURNOFFSET
      else
        self.face_index = self.face_index + ST_TURNOFFSET + 1
      end
    end
  end
  if self.face_priority < 7 and (player.damagecount or 0) ~= 0 then
    if (player.health or 0) - self.old_health > ST_MUCHPAIN then
      self.face_priority = 7
      self.face_count = ST_TURNCOUNT
      self.face_index = calc_pain_offset(self, player) + ST_OUCHOFFSET
    else
      self.face_priority = 6
      self.face_count = ST_TURNCOUNT
      self.face_index = calc_pain_offset(self, player) + ST_RAMPAGEOFFSET
    end
  end
  if self.face_priority < 6 then
    if player.attackdown then
      if self.last_attackdown == -1 then
        self.last_attackdown = ST_RAMPAGEDELAY
      else
        self.last_attackdown = self.last_attackdown - 1
        if self.last_attackdown == 0 then
          self.face_priority = 5
          self.face_index = calc_pain_offset(self, player) + ST_RAMPAGEOFFSET
          self.face_count = 1
          self.last_attackdown = 1
        end
      end
    else
      self.last_attackdown = -1
    end
  end
  local inv = 0
  if player.powers then
    inv = player.powers[PW_INVULNERABILITY] or 0
  end
  if self.face_priority < 5 and (compat.band(player.cheats or 0, CF_GODMODE) ~= 0 or inv ~= 0) then
    self.face_priority = 4
    self.face_index = ST_GODFACE
    self.face_count = 1
  end
  if self.face_count == 0 then
    self.face_index = calc_pain_offset(self, player) + (st_random % 3)
    self.face_count = ST_STRAIGHTFACECOUNT
    self.face_priority = 0
  end
  self.face_count = self.face_count - 1
end

function M.ticker(self, player)
  if player == nil then
    return
  end
  self.rnd = u32_lcg(self.rnd)
  local st_random = math.floor(self.rnd / 65536) % 256
  update_face(self, player, st_random)
  self.old_health = player.health
end

local function draw_digit(fb, x, y, n, font)
  if n < 0 then
    n = 0
  elseif n > 9 then
    n = 9
  end
  local patch = font[n]
  if patch then
    v.draw_patch(fb, x, y, patch)
  end
end

local function draw_num(fb, x, y, value, digits, font)
  local w = 8
  if font[0] then
    w = v.patch_size(font[0])
  end
  x = x - w
  value = math.abs(math.floor(value or 0))
  for _ = 1, digits do
    draw_digit(fb, x, y, value % 10, font)
    x = x - w
    value = math.floor(value / 10)
    if value == 0 then
      break
    end
  end
end

function M.text_width(self, text)
  local x = 0
  for i = 1, #(text or "") do
    local ch = string.byte(string.upper(text:sub(i, i)))
    local idx = ch - HU_FONTSTART
    local patch = self.font[idx + 1]
    if idx >= 0 and patch then
      local w = v.patch_size(patch)
      x = x + w
    else
      x = x + 4
    end
  end
  return x
end

function M.draw_text(self, fb, x, y, text)
  for i = 1, #text do
    local ch = string.byte(string.upper(text:sub(i, i)))
    local idx = ch - HU_FONTSTART
    local patch = self.font[idx + 1]
    if idx >= 0 and patch then
      v.draw_patch(fb, x, y, patch)
      local w = v.patch_size(patch)
      x = x + w
    else
      x = x + 4
    end
  end
end

function M.draw(self, fb, player, show_messages)
  if self.sbar then
    v.draw_patch(fb, 0, 168, self.sbar)
  end
  if self.armsbg then
    v.draw_patch(fb, 104, 168, self.armsbg)
  end
  local ammo = 0
  local at = WEAPON_AMMO[player.readyweapon]
  if at ~= nil then
    ammo = player.ammo[at] or 0
  end
  draw_num(fb, ST_AMMOX, ST_AMMOY, ammo, 3, self.tallnum)
  draw_num(fb, ST_HEALTHX, ST_HEALTHY, player.health or 0, 3, self.tallnum)
  if self.tallpercent then
    v.draw_patch(fb, ST_HEALTHX, ST_HEALTHY, self.tallpercent)
  end
  draw_num(fb, ST_ARMORX, ST_ARMORY, player.armorpoints or 0, 3, self.tallnum)
  if self.tallpercent then
    v.draw_patch(fb, ST_ARMORX, ST_ARMORY, self.tallpercent)
  end
  local owned = {
    (player.weaponowned[WP_SHOTGUN] or player.weaponowned[WP_SUPERSHOTGUN]) and true or false,
    player.weaponowned[WP_CHAINGUN] and true or false,
    player.weaponowned[WP_MISSILE] and true or false,
    player.weaponowned[WP_PLASMA] and true or false,
    player.weaponowned[WP_BFG] and true or false,
    false,
  }
  for i = 0, 5 do
    local x = ST_ARMSX + (i % 3) * ST_ARMSXSPACE
    local y = ST_ARMSY + math.floor(i / 3) * ST_ARMSYSPACE
    if owned[i + 1] then
      draw_digit(fb, x, y, i + 2, self.shortnum)
    elseif self.arms_off[i + 1] then
      v.draw_patch(fb, x, y, self.arms_off[i + 1])
    end
  end
  local face = face_patch(self, self.face_index)
  if face then
    v.draw_patch(fb, ST_FACESX, ST_FACESY, face)
  end
  local slots = {
    { IT_BLUECARD, IT_BLUESKULL, 0 },
    { IT_YELLOWCARD, IT_YELLOWSKULL, 1 },
    { IT_REDCARD, IT_REDSKULL, 2 },
  }
  for s = 1, 3 do
    local card, skull, slot = slots[s][1], slots[s][2], slots[s][3]
    local y = ST_KEY0Y + slot * 10
    local idx = card
    if player.cards[skull] then
      idx = skull
    end
    if player.cards[card] or player.cards[skull] then
      local patch = self.keys[idx]
      if patch then
        v.draw_patch(fb, ST_KEY0X, y, patch)
      end
    end
  end
  local order = { AM_CLIP, AM_SHELL, AM_CELL, AM_MISL }
  for i = 1, 4 do
    local am = order[i]
    local pos = ST_AMMO_POS[i]
    local mx = ST_MAX_POS[i]
    draw_num(fb, pos[1], pos[2], player.ammo[am] or 0, 3, self.shortnum)
    draw_num(fb, mx[1], mx[2], player.maxammo[am] or 0, 3, self.shortnum)
  end
  if show_messages ~= false and player.message ~= nil and player.message ~= "" then
    M.draw_text(self, fb, 0, 0, player.message)
  end
end

return M
