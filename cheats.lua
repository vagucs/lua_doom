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
-- Cheats de st_stuff / deh.py. Letras minusculas, um caractere por tecla.

local am_map = require("am_map")
local compat = require("compat")
local player_mod = require("player")
local sound_mod = require("sound")
local wad = require("wad")

local M = {}

local CF_NOCLIP = 1
local CF_GODMODE = 2
local MF_NOCLIP = 4096
local WP_FIST = 0
local WP_CHAINSAW = 7

local function seq(action, text, params)
  return {
    action = action,
    sequence = text,
    param_chars = params or 0,
    chars_read = 0,
    param_buf = "",
  }
end

function M.new()
  return {
    seqs = {
      seq("god", "iddqd"),
      seq("kfa", "idkfa"),
      seq("fa", "idfa"),
      seq("noclip2", "idclip"),
      seq("noclip", "idspispopd"),
      seq("iddt", "iddt"),
      seq("beholdv", "idbeholdv"),
      seq("beholds", "idbeholds"),
      seq("beholdi", "idbeholdi"),
      seq("beholdr", "idbeholdr"),
      seq("beholda", "idbeholda"),
      seq("beholdl", "idbeholdl"),
      seq("behold", "idbehold"),
      seq("choppers", "idchoppers"),
      seq("mypos", "idmypos"),
      seq("clev", "idclev", 2),
      seq("mus", "idmus", 2),
    },
  }
end

local function feed_one(self, ch)
  local text = self.sequence
  local n = #text
  if n == 0 then
    return nil
  end
  if self.chars_read < n then
    if ch == text:sub(self.chars_read + 1, self.chars_read + 1) then
      self.chars_read = self.chars_read + 1
    elseif ch == text:sub(1, 1) then
      self.chars_read = 1
    else
      self.chars_read = 0
    end
    if self.chars_read < n then
      return nil
    end
    if self.param_chars <= 0 then
      self.chars_read = 0
      return ""
    end
    return nil
  end
  if #self.param_buf < self.param_chars then
    self.param_buf = self.param_buf .. ch
  end
  if #self.param_buf >= self.param_chars then
    local buf = self.param_buf
    self.chars_read = 0
    self.param_buf = ""
    return buf
  end
  return nil
end

local function commercial(game)
  return wad.check_num_for_name(game.wad, "MAP01") >= 0
end

local function cheat_ammo(player, keys)
  if keys then
    player.armorpoints = 200
    player.armortype = 2
  else
    player.armorpoints = 200
    player.armortype = 2
  end
  for i = 0, 8 do
    player.weaponowned[i] = true
  end
  player.maxammo = { [0] = 200, 50, 300, 50 }
  for i = 0, 3 do
    player.ammo[i] = player.maxammo[i]
  end
  if keys then
    player.cards = { [0] = true, true, true, true, true, true }
  end
  if keys then
    player_mod.set_message(player, "Very Happy Ammo Added")
  else
    player_mod.set_message(player, "Ammo Added")
  end
end

local function cheat_behold(player, pw)
  if pw < 0 then
    return
  end
  if (player.powers[pw] or 0) == 0 then
    player_mod.give_power(player, pw)
    if pw == 1 and player.readyweapon ~= WP_FIST then
      player.pendingweapon = WP_FIST
    end
  elseif pw == 1 then
    player.powers[pw] = 0
  else
    player.powers[pw] = 1
  end
  player_mod.set_message(player, "Power-up Toggled")
end

local BEHOLD = { v = 0, s = 1, i = 2, r = 3, a = 4, l = 5 }

local function do_cheat(game, action, param)
  local p = game.player
  if p == nil then
    return
  end
  if action == "god" then
    p.cheats = compat.bxor(p.cheats or 0, CF_GODMODE)
    if compat.band(p.cheats, CF_GODMODE) ~= 0 then
      p.health = 100
      if p.mo then
        p.mo.health = 100
      end
      player_mod.set_message(p, "Degreelessness Mode On")
    else
      player_mod.set_message(p, "Degreelessness Mode Off")
    end
  elseif action == "kfa" then
    cheat_ammo(p, true)
  elseif action == "fa" then
    cheat_ammo(p, false)
  elseif action == "noclip" or action == "noclip2" then
    p.cheats = compat.bxor(p.cheats or 0, CF_NOCLIP)
    if p.mo then
      if compat.band(p.cheats, CF_NOCLIP) ~= 0 then
        p.mo.flags = compat.bor(p.mo.flags, MF_NOCLIP)
      else
        p.mo.flags = compat.band(p.mo.flags, compat.bnot(MF_NOCLIP))
      end
    end
    if compat.band(p.cheats, CF_NOCLIP) ~= 0 then
      player_mod.set_message(p, "No Clipping Mode ON")
    else
      player_mod.set_message(p, "No Clipping Mode OFF")
    end
  elseif action == "iddt" then
    if game.automap and game.automap.active then
      am_map.cycle_iddt(game.automap)
    end
  elseif action == "behold" then
    player_mod.set_message(p, "invin visis rad allmap lite amp")
  elseif action:sub(1, 6) == "behold" and #action == 7 then
    local pw = BEHOLD[action:sub(7, 7)]
    if pw ~= nil then
      cheat_behold(p, pw)
    end
  elseif action == "choppers" then
    p.weaponowned[WP_CHAINSAW] = true
    p.pendingweapon = WP_CHAINSAW
    p.powers[0] = 1
    player_mod.set_message(p, "... doesn't suck - GM")
  elseif action == "mypos" then
    local mo = p.mo
    if mo then
      player_mod.set_message(p, string.format(
        "ang=0x%x;x,y=(0x%x,0x%x)",
        compat.as_u32(mo.angle), compat.as_u32(mo.x), compat.as_u32(mo.y)
      ))
    end
  elseif action == "clev" then
    if #param < 2 or param:match("^%d%d$") == nil then
      return
    end
    local a = tonumber(param:sub(1, 1))
    local b = tonumber(param:sub(2, 2))
    local episode, mapn, lump
    if commercial(game) then
      episode = 1
      mapn = a * 10 + b
      lump = string.format("MAP%02d", mapn)
    else
      episode = a
      mapn = b
      lump = string.format("E%dM%d", episode, mapn)
    end
    if episode < 1 or mapn < 1 or wad.check_num_for_name(game.wad, lump) < 0 then
      return
    end
    player_mod.set_message(p, "Changing Level...")
    game.episode = episode
    game.mapn = mapn
    if game.start_level then
      game.start_level(game)
    end
  elseif action == "mus" then
    if #param < 2 or param:match("^%d%d$") == nil then
      return
    end
    local a = tonumber(param:sub(1, 1))
    local b = tonumber(param:sub(2, 2))
    local name
    if commercial(game) then
      local mapn = a * 10 + b
      local music = sound_mod.DOOM2_MUSIC
      if mapn < 1 or mapn > #music then
        player_mod.set_message(p, "IMPOSSIBLE SELECTION")
        return
      end
      name = music[mapn]
    else
      if a < 1 or b < 1 or b > 9 then
        player_mod.set_message(p, "IMPOSSIBLE SELECTION")
        return
      end
      name = string.format("e%dm%d", a, b)
    end
    if game.sound == nil or not sound_mod.has_music(game.sound, name) then
      player_mod.set_message(p, "IMPOSSIBLE SELECTION")
      return
    end
    sound_mod.change_music(game.sound, name, true)
    player_mod.set_message(p, "Music Change")
  end
end

function M.feed(self, ch, game)
  if game.nocheats or game.gamestate ~= "view" or game.player == nil then
    return
  end
  if ch == nil or #ch ~= 1 then
    return
  end
  local code = ch:byte()
  local letter = (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
  if not letter then
    return
  end
  local nightmare = game.skill == 4
  for i = 1, #self.seqs do
    local cheat = self.seqs[i]
    local param = feed_one(cheat, ch)
    if param ~= nil then
      if not (nightmare and cheat.action ~= "clev" and cheat.action ~= "iddt") then
        do_cheat(game, cheat.action, param)
      end
    end
  end
end

return M
