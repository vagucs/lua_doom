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
-- Texto de fim de episodio, arte, coelho e elenco. Segue finale.py.

local info = require("info")
local sprites = require("sprites")
local v = require("v_video")
local wad = require("wad")

local M = {}

local TEXTSPEED = 3
local TEXTWAIT = 250
local STAGE_TEXT = 0
local STAGE_ART = 1
local STAGE_CAST = 2
local HU_FONTSTART = string.byte("!")
local HU_FONTEND = string.byte("_")
local SCREENWIDTH = 320
local SCREENHEIGHT = 200

local E1TEXT = "Once you beat the big badasses and\n"
  .. "clean out the moon base you're supposed\n"
  .. "to win, aren't you? Aren't you? Where's\n"
  .. "your fat reward and ticket home? What\n"
  .. "the hell is this? It's not supposed to\n"
  .. "end this way!\n"
  .. "\n"
  .. "It stinks like rotten meat, but looks\n"
  .. "like the lost Deimos base.  Looks like\n"
  .. "you're stuck on The Shores of Hell.\n"
  .. "The only way out is through.\n"
  .. "\n"
  .. "To continue the DOOM experience, play\n"
  .. "The Shores of Hell and its amazing\n"
  .. "sequel, Inferno!\n"

local E2TEXT = "You've done it! The hideous cyber-\n"
  .. "demon lord that ruled the lost Deimos\n"
  .. "moon base has been slain and you\n"
  .. "are triumphant! But ... where are\n"
  .. "you? You clamber to the edge of the\n"
  .. "moon and look down to see the awful\n"
  .. "truth.\n"
  .. "\n"
  .. "Deimos floats above Hell itself!\n"
  .. "You've never heard of anyone escaping\n"
  .. "from Hell, but you'll make the bastards\n"
  .. "sorry they ever heard of you! Quickly,\n"
  .. "you rappel down to  the surface of\n"
  .. "Hell.\n"
  .. "\n"
  .. "Now, it's on to the final chapter of\n"
  .. "DOOM! -- Inferno.\n"

local E3TEXT = "The loathsome spiderdemon that\n"
  .. "masterminded the invasion of the moon\n"
  .. "bases and caused so much death has had\n"
  .. "its ass kicked for all time.\n"
  .. "\n"
  .. "A hidden doorway opens and you enter.\n"
  .. "You've proven too tough for Hell to\n"
  .. "contain, and now Hell at last plays\n"
  .. "fair -- for you emerge from the door\n"
  .. "to see the green fields of Earth!\n"
  .. "Home at last.\n"
  .. "\n"
  .. "You wonder what's been happening on\n"
  .. "Earth while you were battling evil\n"
  .. "unleashed. It's good that no Hell-\n"
  .. "spawn could have come through that\n"
  .. "door with you ...\n"

local E4TEXT = "the spider mastermind must have sent forth\n"
  .. "its legions of hellspawn before your\n"
  .. "final confrontation with that terrible\n"
  .. "beast from hell.  but you stepped forward\n"
  .. "and brought forth eternal damnation and\n"
  .. "suffering upon the horde as a true hero\n"
  .. "would in the face of something so evil.\n"
  .. "\n"
  .. "besides, someone was gonna pay for what\n"
  .. "happened to daisy, your pet rabbit.\n"
  .. "\n"
  .. "but now, you see spread before you more\n"
  .. "potential pain and gibbitude as a nation\n"
  .. "of demons run amok among our cities.\n"
  .. "\n"
  .. "next stop, hell on earth!"

local C1TEXT = "YOU HAVE ENTERED DEEPLY INTO THE INFESTED\n"
  .. "STARPORT. BUT SOMETHING IS WRONG. THE\n"
  .. "MONSTERS HAVE BROUGHT THEIR OWN REALITY\n"
  .. "WITH THEM, AND THE STARPORT'S TECHNOLOGY\n"
  .. "IS BEING SUBVERTED BY THEIR PRESENCE.\n"
  .. "\n"
  .. "AHEAD, YOU SEE AN OUTPOST OF HELL, A\n"
  .. "FORTIFIED ZONE. IF YOU CAN GET PAST IT,\n"
  .. "YOU CAN PENETRATE INTO THE HAUNTED HEART\n"
  .. "OF THE STARBASE AND FIND THE CONTROLLING\n"
  .. "SWITCH WHICH HOLDS EARTH'S POPULATION\n"
  .. "HOSTAGE."

local TEXTS = { [1] = E1TEXT, [2] = E2TEXT, [3] = E3TEXT, [4] = E4TEXT }
local FLATS = { [1] = "FLOOR4_8", [2] = "SFLR6_1", [3] = "MFLR8_4", [4] = "MFLR8_3" }
local D2_FLAT = {
  [6] = "SLIME16",
  [11] = "RROCK14",
  [20] = "RROCK07",
  [30] = "RROCK17",
  [15] = "RROCK13",
  [31] = "RROCK19",
}

local CASTORDER = {
  { "ZOMBIEMAN", info.MT_POSSESSED },
  { "SHOTGUN GUY", info.MT_SHOTGUY },
  { "HEAVY WEAPON DUDE", info.MT_CHAINGUY },
  { "IMP", info.MT_TROOP },
  { "DEMON", info.MT_SERGEANT },
  { "LOST SOUL", info.MT_SKULL },
  { "CACODEMON", info.MT_HEAD },
  { "HELL KNIGHT", info.MT_KNIGHT },
  { "BARON OF HELL", info.MT_BRUISER },
  { "ARACHNOTRON", info.MT_BABY },
  { "PAIN ELEMENTAL", info.MT_PAIN },
  { "REVENANT", info.MT_UNDEAD },
  { "MANCUBUS", info.MT_FATSO },
  { "ARCH-VILE", info.MT_VILE },
  { "THE SPIDER MASTERMIND", info.MT_SPIDER },
  { "THE CYBERDEMON", info.MT_CYBORG },
  { "OUR HERO", info.MT_PLAYER },
}

local CAST_SFX = {
  [info.S_PLAY_ATK1] = "dshtgn",
  [info.S_POSS_ATK2] = "pistol",
  [info.S_SPOS_ATK2] = "shotgn",
  [info.S_VILE_ATK2] = "vilatk",
  [info.S_SKEL_FIST2] = "skeswg",
  [info.S_SKEL_FIST4] = "skepch",
  [info.S_SKEL_MISS2] = "skeatk",
  [info.S_FATT_ATK8] = "firsht",
  [info.S_FATT_ATK5] = "firsht",
  [info.S_FATT_ATK2] = "firsht",
  [info.S_CPOS_ATK2] = "shotgn",
  [info.S_CPOS_ATK3] = "shotgn",
  [info.S_CPOS_ATK4] = "shotgn",
  [info.S_TROO_ATK3] = "claw",
  [info.S_SARG_ATK2] = "sgtatk",
  [info.S_BOSS_ATK2] = "firsht",
  [info.S_BOS2_ATK2] = "firsht",
  [info.S_HEAD_ATK2] = "firsht",
  [info.S_SKULL_ATK2] = "sklatk",
  [info.S_SPID_ATK2] = "shotgn",
  [info.S_SPID_ATK3] = "shotgn",
  [info.S_BSPI_ATK2] = "plasma",
  [info.S_CYBER_ATK2] = "rlaunc",
  [info.S_CYBER_ATK4] = "rlaunc",
  [info.S_CYBER_ATK6] = "rlaunc",
}

function M.commercial_map(mapn, secret)
  if mapn == 6 or mapn == 11 or mapn == 20 or mapn == 30 then
    return true
  end
  return secret and (mapn == 15 or mapn == 31)
end

local function lump(wadfile, name)
  local n = wad.check_num_for_name(wadfile, name)
  if n < 0 then
    return nil
  end
  return wad.cache_lump_num(wadfile, n)
end

local function play_music(game, name, looping)
  if game.sound and game.sound.change_music then
    game.sound.change_music(name, looping)
  end
end

local function play_sfx(game, name)
  if game.sound and game.sound.play then
    game.sound.play(name)
  end
end

function M.new(game)
  local commercial = wad.check_num_for_name(game.wad, "MAP01") >= 0
  local text, flat
  if commercial then
    flat = D2_FLAT[game.mapn] or "SLIME16"
    text = C1TEXT
    play_music(game, "read_m", true)
  else
    text = TEXTS[game.episode] or E1TEXT
    flat = FLATS[game.episode] or "FLOOR4_8"
    play_music(game, "victor", true)
  end
  local art_name
  if commercial then
    if wad.check_num_for_name(game.wad, "CREDIT") >= 0 then
      art_name = "CREDIT"
    else
      art_name = "HELP2"
    end
  elseif game.episode == 2 then
    art_name = "VICTORY2"
  elseif game.episode == 4 then
    art_name = "ENDPIC"
  elseif wad.check_num_for_name(game.wad, "CREDIT") >= 0 then
    art_name = "CREDIT"
  else
    art_name = "HELP2"
  end
  local self = {
    game = game,
    stage = STAGE_TEXT,
    count = 0,
    done = false,
    action = "",
    commercial = commercial,
    text = text,
    flat = flat,
    flat_lump = lump(game.wad, flat),
    art = lump(game.wad, art_name) or lump(game.wad, "HELP1"),
    pfub1 = nil,
    pfub2 = nil,
    bossback = lump(game.wad, "BOSSBACK"),
    last_bunny = -1,
    castnum = 0,
    caststate = info.S_NULL,
    casttics = 0,
    castdeath = false,
    castframes = 0,
    castonmelee = 0,
    castattacking = false,
  }
  if game.episode == 3 and not commercial then
    self.pfub1 = lump(game.wad, "PFUB1")
    self.pfub2 = lump(game.wad, "PFUB2")
  end
  return self
end

local function want_skip(self)
  local game = self.game
  if game.menu and game.menu.active then
    return false
  end
  if game.mouse_fire then
    return true
  end
  local held = game.held or {}
  return held.ctrl or held.space or held["return"] or held.e
end

local function cast_info(self)
  return info.MOBJINFO[CASTORDER[self.castnum + 1][2]]
end

local function stop_attack(self)
  self.castattacking = false
  self.castframes = 0
  self.caststate = cast_info(self)[info.MI_SEESTATE]
end

local function cast_ticker(self)
  self.casttics = self.casttics - 1
  if self.casttics > 0 then
    return
  end
  local st = info.STATES[self.caststate]
  if st[2] == -1 or st[4] == info.S_NULL then
    self.castnum = self.castnum + 1
    self.castdeath = false
    if self.castnum >= #CASTORDER then
      self.castnum = 0
    end
    self.caststate = cast_info(self)[info.MI_SEESTATE]
    self.castframes = 0
  else
    if self.caststate == info.S_PLAY_ATK1 then
      stop_attack(self)
    else
      local nxt = st[4]
      self.caststate = nxt
      self.castframes = self.castframes + 1
      local sfx = CAST_SFX[nxt]
      if sfx then
        play_sfx(self.game, sfx)
      end
    end
  end
  if self.castframes == 12 then
    self.castattacking = true
    local row = cast_info(self)
    if self.castonmelee ~= 0 then
      self.caststate = row[info.MI_MELEESTATE]
    else
      self.caststate = row[info.MI_MISSILESTATE]
    end
    if self.castonmelee ~= 0 then
      self.castonmelee = 0
    else
      self.castonmelee = 1
    end
    if self.caststate == info.S_NULL then
      if self.castonmelee ~= 0 then
        self.caststate = row[info.MI_MELEESTATE]
      else
        self.caststate = row[info.MI_MISSILESTATE]
      end
    end
  end
  if self.castattacking then
    if self.castframes == 24 or self.caststate == cast_info(self)[info.MI_SEESTATE] then
      stop_attack(self)
    end
  end
  self.casttics = info.STATES[self.caststate][2]
  if self.casttics == -1 then
    self.casttics = 15
  end
end

local function start_cast(self)
  self.game.force_wipe = true
  self.castnum = 0
  self.caststate = info.MOBJINFO[CASTORDER[1][2]][info.MI_SEESTATE]
  self.casttics = info.STATES[self.caststate][2]
  self.castdeath = false
  self.stage = STAGE_CAST
  self.castframes = 0
  self.castonmelee = 0
  self.castattacking = false
  play_music(self.game, "evil", true)
end

function M.ticker(self)
  if self.commercial and self.stage == STAGE_TEXT and self.count > 50 and want_skip(self) then
    if self.game.mapn == 30 then
      start_cast(self)
    else
      self.action = "worlddone"
      self.done = true
      return
    end
  end
  self.count = self.count + 1
  if self.stage == STAGE_CAST then
    cast_ticker(self)
    return
  end
  if self.commercial then
    return
  end
  if self.stage == STAGE_TEXT then
    if self.count > #self.text * TEXTSPEED + TEXTWAIT then
      self.stage = STAGE_ART
      self.count = 0
      self.game.force_wipe = true
      if self.game.episode == 3 then
        play_music(self.game, "bunny", true)
      end
    end
  elseif self.stage == STAGE_ART then
    local skip_after = 10
    if self.pfub1 and self.pfub2 then
      skip_after = 1130
    end
    if want_skip(self) and self.count > skip_after then
      self.done = true
      self.action = "title"
    end
  end
end

function M.responder(self)
  if self.stage ~= STAGE_CAST or self.castdeath then
    return false
  end
  if not want_skip(self) then
    return false
  end
  local row = cast_info(self)
  self.castdeath = true
  self.caststate = row[info.MI_DEATHSTATE]
  self.casttics = info.STATES[self.caststate][2]
  if self.casttics == -1 then
    self.casttics = 15
  end
  self.castframes = 0
  self.castattacking = false
  return true
end

local function font(self, code)
  if code < HU_FONTSTART or code > HU_FONTEND then
    return nil
  end
  return lump(self.game.wad, string.format("STCFN%03d", code))
end

local function flat_row(y)
  return (y % 64) * 64
end

local function fill_flat(self, fb)
  local data = self.flat_lump
  if data == nil or #data < 4096 then
    v.fill(fb, 0)
    return
  end
  for y = 0, 199 do
    local row = flat_row(y)
    local dest = y * SCREENWIDTH
    local x = 0
    while x < SCREENWIDTH do
      local n = 64
      if n > SCREENWIDTH - x then
        n = SCREENWIDTH - x
      end
      for i = 0, n - 1 do
        fb[dest + x + i + 1] = data:byte(row + i + 1)
      end
      x = x + 64
    end
  end
end

local function draw_text(self, fb)
  fill_flat(self, fb)
  local nshow = math.floor(self.count / TEXTSPEED)
  local cx, cy = 10, 10
  for i = 1, #self.text do
    if i > nshow then
      break
    end
    local ch = self.text:sub(i, i)
    if ch == "\n" then
      cx = 10
      cy = cy + 11
    else
      local code = string.byte(ch:upper())
      local patch = nil
      if ch ~= " " and code >= HU_FONTSTART and code <= HU_FONTEND then
        patch = font(self, code)
      end
      if patch == nil then
        cx = cx + 4
      else
        local w = v.patch_size(patch)
        if cx + w > SCREENWIDTH then
          break
        end
        v.draw_patch(fb, cx, cy, patch)
        cx = cx + w
      end
    end
  end
end

local function u32(data, off)
  local b1, b2, b3, b4 = data:byte(off + 1, off + 4)
  if b1 == nil then
    return 0
  end
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function draw_patch_column(fb, x, patch, column)
  if column < 0 then
    return
  end
  local offset_pos = 8 + column * 4
  if offset_pos + 4 > #patch then
    return
  end
  local offset = u32(patch, offset_pos)
  while offset < #patch and patch:byte(offset + 1) ~= 255 do
    local top = patch:byte(offset + 1)
    local length = patch:byte(offset + 2)
    local source = offset + 3
    for i = 0, length - 1 do
      if top + i >= SCREENHEIGHT then
        break
      end
      fb[(top + i) * SCREENWIDTH + x + 1] = patch:byte(source + i + 1)
    end
    offset = offset + length + 4
  end
end

local function draw_bunny(self, fb)
  v.fill(fb, 0)
  local scroll = 320 - math.floor((self.count - 230) / 2)
  if scroll < 0 then
    scroll = 0
  end
  if scroll > 320 then
    scroll = 320
  end
  for x = 0, SCREENWIDTH - 1 do
    local column = x + scroll
    local patch = self.pfub1
    local src = column - 320
    if column < 320 then
      patch = self.pfub2
      src = column
    end
    if patch then
      draw_patch_column(fb, x, patch, src)
    end
  end
  if self.count < 1130 then
    return
  end
  local stage = 0
  if self.count >= 1180 then
    stage = math.floor((self.count - 1180) / 5)
    if stage > 6 then
      stage = 6
    end
  end
  if stage > self.last_bunny then
    play_sfx(self.game, "pistol")
    self.last_bunny = stage
  end
  local patch = lump(self.game.wad, "END" .. tostring(stage))
  if patch then
    v.draw_patch(fb, math.floor((320 - 104) / 2), math.floor((200 - 64) / 2), patch)
  end
end

local function cast_print(self, fb, text)
  local width = 0
  for i = 1, #text do
    local ch = text:sub(i, i)
    local code = string.byte(ch:upper())
    if ch == " " or code < HU_FONTSTART or code > HU_FONTEND then
      width = width + 4
    else
      local patch = font(self, code)
      if patch == nil then
        width = width + 4
      else
        local w = v.patch_size(patch)
        width = width + w
      end
    end
  end
  local cx = 160 - math.floor(width / 2)
  for i = 1, #text do
    local ch = text:sub(i, i)
    local code = string.byte(ch:upper())
    if ch == " " or code < HU_FONTSTART or code > HU_FONTEND then
      cx = cx + 4
    else
      local patch = font(self, code)
      if patch == nil then
        cx = cx + 4
      else
        local w = v.patch_size(patch)
        v.draw_patch(fb, cx, 180, patch)
        cx = cx + w
      end
    end
  end
end

local function draw_cast(self, fb)
  v.fill(fb, 0)
  if self.bossback then
    v.draw_patch(fb, 0, 0, self.bossback)
  end
  cast_print(self, fb, CASTORDER[self.castnum + 1][1])
  local st = info.STATES[self.caststate]
  local spr = info.SPRNAMES[st[0]] or ""
  if self.game.res == nil or spr == "" then
    return
  end
  local frame = st[1] % 32768
  local lumpnum, flip = sprites.lookup(self.game.res, spr, 0, 0, frame)
  if lumpnum == nil then
    return
  end
  local patch = wad.cache_lump_num(self.game.wad, lumpnum)
  v.draw_patch(fb, 160, 170, patch, flip and true or false)
end

function M.draw(self, fb)
  if self.stage == STAGE_CAST then
    draw_cast(self, fb)
    return
  end
  if self.stage == STAGE_ART then
    if self.game.episode == 3 and self.pfub1 and self.pfub2 then
      draw_bunny(self, fb)
    elseif self.art then
      v.fill(fb, 0)
      v.draw_patch(fb, 0, 0, self.art)
    end
    return
  end
  draw_text(self, fb)
end

M.E1TEXT = E1TEXT
return M
