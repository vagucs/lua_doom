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
-- Menu do titulo, a partir de menu.py. Escolher a skill nao abre o mapa.

local v = require("v_video")
local wad = require("wad")

local M = {}

local LINEHEIGHT = 16
local SKULLXOFF = -32
local HU_FONTSTART = string.byte("!")
local HU_FONTSIZE = string.byte("_") - HU_FONTSTART + 1
local SAVESTRINGSIZE = 24
local LOADSAVEEMPTY = "empty slot"

local has_episodes
local has
local patch

local function item(status, name, action, alpha)
  return { status = status, name = name or "", action = action or "", alpha = alpha or 0 }
end

local function menu_def(items, routine, x, y, last_on, prev)
  return { items = items, routine = routine, x = x, y = y, last_on = last_on or 0, prev = prev }
end

local function new(wad, sound, game)
  local self = {
    wad = wad,
    sound = sound,
    game = game,
    active = false,
    screen = "main",
    item_on = 0,
    which_skull = 0,
    skull_tics = 8,
    epi = 0,
    message = nil,
    message_confirm = false,
    message_action = nil,
    save_strings = {},
    save_slot_ok = {},
    save_string_enter = false,
    save_slot = 0,
    save_old_string = "",
    save_char_index = 0,
    menus = {},
  }
  for i = 1, 6 do
    self.save_strings[i] = LOADSAVEEMPTY
    self.save_slot_ok[i] = false
  end
  local slots = {}
  for i = 1, 6 do
    slots[i] = item(1, "", "loadslot")
  end
  local save_slots = {}
  for i = 1, 6 do
    save_slots[i] = item(1, "", "saveslot")
  end
  self.menus = {
    main = menu_def({
      item(1, "M_NGAME", "newgame", 110),
      item(1, "M_OPTION", "options", 111),
      item(1, "M_LOADG", "loadgame", 108),
      item(1, "M_SAVEG", "savegame", 115),
      item(1, "M_RDTHIS", "readthis", 114),
      item(1, "M_QUITG", "quit", 113),
    }, "main", 97, 64, 0, nil),
    episode = menu_def({
      item(1, "M_EPI1", "episode", 107),
      item(1, "M_EPI2", "episode", 116),
      item(1, "M_EPI3", "episode", 105),
      item(1, "M_EPI4", "episode", 116),
    }, "episode", 48, 63, 0, "main"),
    skill = menu_def({
      item(1, "M_JKILL", "skill", 105),
      item(1, "M_ROUGH", "skill", 104),
      item(1, "M_HURT", "skill", 104),
      item(1, "M_ULTRA", "skill", 117),
      item(1, "M_NMARE", "skill", 110),
    }, "skill", 48, 63, 2, "episode"),
    options = menu_def({
      item(1, "M_ENDGAM", "endgame", 101),
      item(1, "M_MESSG", "messages", 109),
      item(1, "M_DETAIL", "detail", 103),
      item(2, "M_SCRNSZ", "scrnsize", 115),
      item(-1, "", "", 0),
      item(2, "M_MSENS", "mousesens", 109),
      item(-1, "", "", 0),
      item(1, "M_SVOL", "sound", 115),
    }, "options", 60, 37, 0, "main"),
    sound = menu_def({
      item(2, "M_SFXVOL", "sfxvol", 115),
      item(-1, "", "", 0),
      item(2, "M_MUSVOL", "musvol", 109),
      item(-1, "", "", 0),
    }, "sound", 80, 64, 0, "options"),
    load = menu_def(slots, "load", 80, 54, 0, "main"),
    save = menu_def(save_slots, "save", 80, 54, 0, "main"),
    read1 = menu_def({ item(1, "", "read2", 0) }, "read1", 280, 185, 0, "main"),
    read2 = menu_def({ item(1, "", "finishread", 0) }, "read2", 330, 175, 0, "read1"),
  }
  if not has_episodes(self) then
    self.menus.skill.prev = "main"
  end
  return self
end

function has_episodes(self)
  return wad.check_num_for_name(self.wad, "MAP01") < 0
end

function has(self, name)
  return wad.check_num_for_name(self.wad, name) >= 0
end

function patch(self, name)
  local n = wad.check_num_for_name(self.wad, name)
  if n < 0 then
    return nil
  end
  return wad.cache_lump_num(self.wad, n)
end

function M.ticker(self)
  if not self.active then
    return false
  end
  self.skull_tics = self.skull_tics - 1
  if self.skull_tics <= 0 then
    self.which_skull = 1 - self.which_skull
    self.skull_tics = 8
    return true
  end
  return false
end

function M.start(self)
  if self.active then
    return
  end
  self.active = true
  self.screen = "main"
  self.item_on = self.menus.main.last_on
  self.message = nil
  self.save_string_enter = false
  self.sound.play("swtchn")
end

function M.clear(self)
  self.active = false
  self.message = nil
  self.save_string_enter = false
end

local function goto_menu(self, name)
  self.menus[self.screen].last_on = self.item_on
  self.screen = name
  self.item_on = self.menus[name].last_on
end

local function refresh_saves(self)
  if self.game.slot_desc == nil then
    return
  end
  for i = 0, 5 do
    self.save_strings[i + 1] = self.game.slot_desc(self.game, i)
  end
end

local function do_action(self, action, choice)
  if action == "newgame" then
    if wad.check_num_for_name(self.wad, "MAP01") >= 0 or not has_episodes(self) then
      self.epi = 0
      goto_menu(self, "skill")
    else
      goto_menu(self, "episode")
    end
  elseif action == "options" then
    goto_menu(self, "options")
  elseif action == "loadgame" then
    self.save_string_enter = false
    self.message = nil
    refresh_saves(self)
    goto_menu(self, "load")
    self.sound.play("swtchn")
  elseif action == "savegame" then
    if self.game.gamestate ~= "view" or self.game.save_game == nil then
      self.sound.play("oof")
    else
      self.save_string_enter = false
      self.message = nil
      refresh_saves(self)
      goto_menu(self, "save")
      self.sound.play("swtchn")
    end
  elseif action == "loadslot" then
    if self.game.load_game and self.game.load_game(self.game, choice) then
      M.clear(self)
      self.sound.play("swtchx")
    else
      self.sound.play("oof")
    end
  elseif action == "saveslot" then
    local name = "save"
    if self.game.world and self.game.world.mapname then
      name = self.game.world.mapname
    end
    if self.game.save_game and self.game.save_game(self.game, choice, name) then
      refresh_saves(self)
      M.clear(self)
      self.sound.play("swtchx")
    else
      self.sound.play("oof")
    end
  elseif action == "readthis" then
    goto_menu(self, "read1")
  elseif action == "read2" then
    if has(self, "HELP1") and self.screen == "read1" then
      goto_menu(self, "read2")
    else
      goto_menu(self, "main")
    end
  elseif action == "finishread" then
    goto_menu(self, "main")
  elseif action == "quit" then
    self.message = "ARE YOU SURE YOU WANT TO QUIT?"
    self.message_confirm = true
    self.message_action = "quit"
  elseif action == "endgame" then
    if self.game.gamestate == "title" or self.game.end_game == nil then
      self.sound.play("oof")
    else
      self.message = "ARE YOU SURE YOU WANT TO END THE GAME?"
      self.message_confirm = true
      self.message_action = "endgame"
    end
  elseif action == "sound" then
    goto_menu(self, "sound")
  elseif action == "messages" then
    self.game.show_messages = not self.game.show_messages
  elseif action == "detail" then
    if self.game.detail_level == 0 then
      self.game.detail_level = 1
    else
      self.game.detail_level = 0
    end
  elseif action == "scrnsize" then
    if choice ~= 0 then
      if self.game.screen_size < 8 then
        self.game.screen_size = self.game.screen_size + 1
      end
    elseif self.game.screen_size > 0 then
      self.game.screen_size = self.game.screen_size - 1
    end
  elseif action == "mousesens" then
    if choice ~= 0 then
      if self.game.mouse_sensitivity < 9 then
        self.game.mouse_sensitivity = self.game.mouse_sensitivity + 1
      end
    elseif self.game.mouse_sensitivity > 0 then
      self.game.mouse_sensitivity = self.game.mouse_sensitivity - 1
    end
  elseif action == "sfxvol" then
    local vol = self.sound.sfx_volume
    if choice ~= 0 then
      vol = math.min(15, vol + 1)
    else
      vol = math.max(0, vol - 1)
    end
    self.sound.sfx_volume = vol
  elseif action == "musvol" then
    local vol = self.sound.music_volume
    if choice ~= 0 then
      vol = math.min(15, vol + 1)
    else
      vol = math.max(0, vol - 1)
    end
    self.sound.music_volume = vol
  elseif action == "episode" then
    if not has(self, "E2M1") and choice ~= 0 then
      self.message = "ONLY AVAILABLE IN THE REGISTERED VERSION."
      self.message_confirm = false
      self.message_action = nil
      goto_menu(self, "read1")
      return
    end
    self.epi = choice
    goto_menu(self, "skill")
  elseif action == "skill" then
    self.game.skill = choice
    self.game.episode = self.epi + 1
    self.game.mapn = 1
    if self.game.start_level then
      self.game.start_level(self.game)
      M.clear(self)
    else
      self.message = "EPISODIO " .. tostring(self.epi + 1) .. " SKILL " .. tostring(choice)
      self.message_confirm = false
      self.message_action = nil
    end
  end
end

function M.responder(self, key)
  if self.message then
    if self.message_confirm then
      if key == "y" or key == "return" then
        local action = self.message_action
        self.message = nil
        if action == "quit" then
          self.game.running = false
        elseif action == "endgame" and self.game.end_game then
          self.game.end_game(self.game)
          M.clear(self)
        end
        return true
      end
      if key == "n" or key == "escape" then
        self.message = nil
        return true
      end
      return true
    end
    if key ~= "" then
      self.message = nil
      return true
    end
  end
  if key == "f1" then
    self.active = true
    self.message = nil
    self.menus.read1.last_on = 0
    self.screen = "read1"
    self.item_on = 0
    self.sound.play("swtchn")
    return true
  end
  if not self.active then
    if key == "escape" or key == "return" then
      M.start(self)
      return true
    end
    return false
  end
  local menu = self.menus[self.screen]
  if key == "escape" then
    menu.last_on = self.item_on
    M.clear(self)
    self.sound.play("swtchx")
    return true
  end
  if key == "backspace" then
    menu.last_on = self.item_on
    if menu.prev then
      self.screen = menu.prev
      self.item_on = self.menus[self.screen].last_on
    else
      M.clear(self)
    end
    self.sound.play("swtchx")
    return true
  end
  if key == "down" then
    local n = #menu.items
    repeat
      self.item_on = (self.item_on + 1) % n
      self.sound.play("pstop")
    until menu.items[self.item_on + 1].status ~= -1
    return true
  end
  if key == "up" then
    local n = #menu.items
    repeat
      self.item_on = (self.item_on - 1) % n
      self.sound.play("pstop")
    until menu.items[self.item_on + 1].status ~= -1
    return true
  end
  if key == "left" or key == "right" then
    local it = menu.items[self.item_on + 1]
    if it.status == 2 and it.action ~= "" then
      self.sound.play("stnmov")
      do_action(self, it.action, key == "left" and 0 or 1)
    end
    return true
  end
  if key == "return" then
    local it = menu.items[self.item_on + 1]
    if it.status ~= 0 then
      menu.last_on = self.item_on
      self.sound.play("pistol")
      local choice = self.item_on
      if it.status == 2 then
        choice = 1
      end
      do_action(self, it.action, choice)
    end
    return true
  end
  return true
end

local function write_text(self, fb, x, y, text)
  local xx = x
  for i = 1, #text do
    local ch = text:sub(i, i):upper()
    if ch == " " then
      xx = xx + 4
    else
      local p = patch(self, string.format("STCFN%03d", string.byte(ch)))
      if p then
        v.draw_patch(fb, xx, y, p)
        local pw = v.patch_size(p)
        xx = xx + math.max(4, pw)
      else
        xx = xx + 8
      end
    end
  end
  return xx
end

local function draw_thermo(self, fb, x, y, width, dot)
  local left = patch(self, "M_THERML")
  local mid = patch(self, "M_THERMM")
  local right = patch(self, "M_THERMR")
  local knob = patch(self, "M_THERMO")
  local xx = x
  if left then
    v.draw_patch(fb, xx, y, left)
  end
  xx = xx + 8
  for _ = 1, width do
    if mid then
      v.draw_patch(fb, xx, y, mid)
    end
    xx = xx + 8
  end
  if right then
    v.draw_patch(fb, xx, y, right)
  end
  if knob then
    local at = dot
    if at < 0 then
      at = 0
    end
    if at > width - 1 then
      at = width - 1
    end
    v.draw_patch(fb, x + 8 + at * 8, y, knob)
  end
end

local function draw_message(self, fb)
  local text = self.message or ""
  if self.message_confirm then
    text = text .. "  (Y/N)"
  end
  local x, y = 10, 80
  for i = 1, #text do
    local ch = text:sub(i, i)
    if ch == " " then
      x = x + 8
    else
      local p = patch(self, string.format("STCFN%03d", string.byte(ch)))
      if p then
        v.draw_patch(fb, x, y, p)
        local pw = v.patch_size(p)
        x = x + math.max(4, pw)
      else
        x = x + 8
      end
    end
    if x > 300 then
      x = 10
      y = y + 10
    end
  end
end

local function draw_slots(self, fb, menu)
  for i = 0, 5 do
    local y = menu.y + LINEHEIGHT * i
    write_text(self, fb, menu.x, y, self.save_strings[i + 1])
  end
end

function M.draw(self, fb)
  if not self.active then
    return
  end
  if self.message then
    draw_message(self, fb)
    return
  end
  local menu = self.menus[self.screen]
  if menu.routine == "main" then
    local p = patch(self, "M_DOOM")
    if p then
      v.draw_patch(fb, 94, 2, p)
    end
  elseif menu.routine == "skill" then
    local p = patch(self, "M_NEWG")
    if p then
      v.draw_patch(fb, 96, 14, p)
    end
    p = patch(self, "M_SKILL")
    if p then
      v.draw_patch(fb, 54, 38, p)
    end
  elseif menu.routine == "episode" then
    local p = patch(self, "M_EPISOD")
    if p then
      v.draw_patch(fb, 54, 38, p)
    end
  elseif menu.routine == "options" then
    local p = patch(self, "M_OPTTTL")
    if p then
      v.draw_patch(fb, 108, 15, p)
    end
    local msg = "M_MSGOFF"
    if self.game.show_messages then
      msg = "M_MSGON"
    end
    p = patch(self, msg)
    if p then
      v.draw_patch(fb, menu.x + 120, menu.y + LINEHEIGHT, p)
    end
    local det = "M_GDLOW"
    if self.game.detail_level == 0 then
      det = "M_GDHIGH"
    end
    p = patch(self, det)
    if p then
      v.draw_patch(fb, menu.x + 175, menu.y + LINEHEIGHT * 2, p)
    end
  elseif menu.routine == "sound" then
    local p = patch(self, "M_SVOL")
    if p then
      v.draw_patch(fb, 60, 38, p)
    end
  elseif menu.routine == "read1" then
    local lump = "CREDIT"
    if has(self, "HELP2") then
      lump = "HELP2"
    elseif has(self, "HELP1") then
      lump = "HELP1"
    elseif has(self, "HELP") then
      lump = "HELP"
    end
    local p = patch(self, lump)
    if p then
      v.draw_patch(fb, 0, 0, p)
    end
  elseif menu.routine == "read2" then
    local p = patch(self, "HELP1") or patch(self, "CREDIT")
    if p then
      v.draw_patch(fb, 0, 0, p)
    end
  elseif menu.routine == "load" then
    local p = patch(self, "M_LOADG")
    if p then
      v.draw_patch(fb, 72, 28, p)
    end
    draw_slots(self, fb, menu)
  elseif menu.routine == "save" then
    local p = patch(self, "M_SAVEG")
    if p then
      v.draw_patch(fb, 72, 28, p)
    end
    draw_slots(self, fb, menu)
  end
  if menu.routine ~= "read1" and menu.routine ~= "read2" and menu.routine ~= "load" and menu.routine ~= "save" then
    local y = menu.y
    for i = 1, #menu.items do
      local it = menu.items[i]
      if it.name ~= "" then
        local p = patch(self, it.name)
        if p then
          v.draw_patch(fb, menu.x, y, p)
        end
      end
      y = y + LINEHEIGHT
    end
  end
  if menu.routine == "options" then
    draw_thermo(self, fb, menu.x, menu.y + LINEHEIGHT * 4, 9, self.game.screen_size)
    draw_thermo(self, fb, menu.x, menu.y + LINEHEIGHT * 6, 10, self.game.mouse_sensitivity)
  elseif menu.routine == "sound" then
    draw_thermo(self, fb, menu.x, menu.y + LINEHEIGHT, 16, self.sound.sfx_volume)
    draw_thermo(self, fb, menu.x, menu.y + LINEHEIGHT * 3, 16, self.sound.music_volume)
  end
  local skull = "M_SKULL1"
  if self.which_skull ~= 0 then
    skull = "M_SKULL2"
  end
  local p = patch(self, skull)
  if p and menu.routine ~= "read1" and menu.routine ~= "read2" then
    v.draw_patch(fb, menu.x + SKULLXOFF, menu.y - 5 + self.item_on * LINEHEIGHT, p)
  end
end

function M.new(wad, sound, game)
  return new(wad, sound, game)
end

M.HU_FONTSTART = HU_FONTSTART
M.HU_FONTSIZE = HU_FONTSIZE
M.LOADSAVEEMPTY = LOADSAVEEMPTY

return M
