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
-- Efeitos DS* e musica D_*. A mistura fica aqui. A ponte so enfileira o PCM e abre o MIDI.

local wad = require("wad")
local mus2mid = require("mus2mid")
local video = require("video")
local unpack = unpack or table.unpack

local MAX_VOICES = 8
local music_seq = 0

local DOOM2_MUSIC = {
  "runnin", "stalks", "countd", "betwee", "doom", "the_da",
  "shawn", "ddtblu", "in_cit", "dead", "stlks2", "theda2",
  "doom2", "ddtbl2", "runni2", "dead2", "stlks3", "romero",
  "shawn2", "messag", "count2", "ddtbl3", "ampie", "theda3",
  "adrian", "messg2", "romer2", "tense", "shawn3", "openin",
  "evil", "ultima",
}

local M = {}
M.DOOM2_MUSIC = DOOM2_MUSIC

local function bytes_to_string(bytes)
  local parts = {}
  local n = #bytes
  local i = 1
  while i <= n do
    local last = i + 4095
    if last > n then
      last = n
    end
    parts[#parts + 1] = string.char(unpack(bytes, i, last))
    i = last + 1
  end
  return table.concat(parts)
end

function M.decode(data, mix_rate, mix_ch)
  if #data < 8 or data:byte(1) ~= 3 or data:byte(2) ~= 0 then
    return nil
  end
  local rate = data:byte(3) + data:byte(4) * 256
  local length = data:byte(5) + data:byte(6) * 256 + data:byte(7) * 65536 + data:byte(8) * 16777216
  if length > #data - 8 or length <= 48 or rate <= 0 then
    return nil
  end
  length = length - 32
  if length <= 0 then
    return nil
  end
  local out_n = length
  if mix_rate ~= rate then
    out_n = math.max(1, math.floor(length * mix_rate / rate))
  end
  local samples = {}
  for i = 0, out_n - 1 do
    local src_i = i
    if mix_rate ~= rate then
      src_i = math.min(length - 1, math.floor(i * length / out_n))
    end
    local b = data:byte(17 + src_i)
    samples[i + 1] = (b - 128) * 256
  end
  if mix_ch >= 2 then
    local stereo = {}
    for i = 1, #samples do
      stereo[#stereo + 1] = samples[i]
      stereo[#stereo + 1] = samples[i]
    end
    samples = stereo
  end
  return samples
end

function M.new()
  local self = {
    wad = nil,
    cache = {},
    enabled = true,
    music_enabled = true,
    ready = false,
    freq = 11025,
    channels = 1,
    music_path = nil,
    music_name = "",
    music_loop = false,
    music_on = false,
    sfx_volume = 8,
    music_volume = 8,
    voices = {},
    last_ms = 0,
  }
  self.play = function(name)
    M.play(self, name)
  end
  self.change_music = function(name, looping)
    M.change_music(self, name, looping)
  end
  return self
end

function M.init(self, wadfile)
  self.wad = wadfile
  local freq, channels = video.audio_open()
  if freq then
    self.freq = freq
    self.channels = channels
    self.ready = true
    self.enabled = true
  else
    self.ready = false
    self.enabled = false
  end
  self.last_ms = video.ticks()
  M.set_music_volume(self, self.music_volume)
end

function M.play(self, name)
  if not self.enabled or not self.ready or not self.wad or name == nil or name == "" then
    return
  end
  local key = string.lower(name)
  local samples = self.cache[key]
  if samples == nil then
    local lump = "DS" .. string.upper(string.sub(key, 1, 6))
    local n = wad.check_num_for_name(self.wad, lump)
    if n < 0 then
      self.cache[key] = false
      return
    end
    samples = M.decode(wad.cache_lump_num(self.wad, n), self.freq, 1)
    if samples == nil then
      self.cache[key] = false
      return
    end
    self.cache[key] = samples
  end
  if samples == false then
    return
  end
  if #self.voices >= MAX_VOICES then
    table.remove(self.voices, 1)
  end
  self.voices[#self.voices + 1] = {
    samples = samples,
    pos = 0,
    n = #samples,
    vol = self.sfx_volume,
  }
end

function M.has_music(self, name)
  if not self.wad or name == nil or name == "" then
    return false
  end
  return wad.check_num_for_name(self.wad, "D_" .. string.upper(string.sub(name, 1, 6))) >= 0
end

function M.set_sfx_volume(self, vol)
  if vol < 0 then
    vol = 0
  elseif vol > 15 then
    vol = 15
  end
  self.sfx_volume = vol
end

function M.set_music_volume(self, vol)
  if vol < 0 then
    vol = 0
  elseif vol > 15 then
    vol = 15
  end
  self.music_volume = vol
  if self.music_on then
    video.music_volume(math.floor(vol / 15 * 1000))
  end
end

function M.stop_music(self)
  if self.music_on then
    video.music_close()
  end
  self.music_on = false
  self.music_name = ""
  self.music_loop = false
  if self.music_path then
    os.remove(self.music_path)
    self.music_path = nil
  end
end

function M.change_music(self, name, looping)
  if not self.music_enabled or not self.wad or name == nil or name == "" then
    return
  end
  if string.lower(name) == self.music_name then
    return
  end
  local lump = "D_" .. string.upper(string.sub(name, 1, 6))
  local n = wad.check_num_for_name(self.wad, lump)
  if n < 0 then
    return
  end
  local midi = mus2mid.mus2mid(wad.cache_lump_num(self.wad, n))
  if midi == nil or midi == "" then
    return
  end
  M.stop_music(self)
  local dir = os.getenv("TEMP") or os.getenv("TMP") or "."
  dir = string.gsub(dir, "[\\/]+$", "")
  music_seq = music_seq + 1
  local path = string.format("%s\\doommus_%d_%d.mid", dir, os.time(), music_seq)
  path = string.gsub(path, "/", "\\")
  local f = io.open(path, "wb")
  if not f then
    return
  end
  f:write(midi)
  f:close()
  self.music_path = path
  self.music_name = string.lower(name)
  self.music_loop = looping ~= false
  if video.music_open(path) then
    self.music_on = true
    M.set_music_volume(self, self.music_volume)
    print("musica " .. self.music_name)
    return
  end
  print("musica muda")
  M.stop_music(self)
end

function M.play_title_music(self)
  if not self.wad then
    return
  end
  if wad.check_num_for_name(self.wad, "MAP01") >= 0 then
    M.change_music(self, "dm2ttl", false)
  elseif wad.check_num_for_name(self.wad, "D_INTROA") >= 0 then
    M.change_music(self, "introa", false)
  else
    M.change_music(self, "intro", false)
  end
end

function M.play_level_music(self, episode, mapn)
  if not self.wad then
    return
  end
  local name
  if wad.check_num_for_name(self.wad, "MAP01") >= 0 then
    local idx = (math.max(1, mapn) - 1) % #DOOM2_MUSIC
    name = DOOM2_MUSIC[idx + 1]
  else
    name = "e" .. tostring(episode) .. "m" .. tostring(mapn)
  end
  M.change_music(self, name, true)
end

local function push_s16(bytes, n)
  if n > 32767 then
    n = 32767
  elseif n < -32768 then
    n = -32768
  end
  if n < 0 then
    n = n + 65536
  end
  bytes[#bytes + 1] = n % 256
  bytes[#bytes + 1] = math.floor(n / 256) % 256
end

function M.update(self)
  if self.ready then
    local now = video.ticks()
    local dt = now - self.last_ms
    self.last_ms = now
    if dt < 0 then
      dt = 0
    elseif dt > 1000 then
      dt = 1000
    end
    local count = math.floor(dt * self.freq / 1000)
    if count > 0 and #self.voices > 0 then
      local frame = self.channels >= 2 and 2 or 1
      local bytes = {}
      local voices = self.voices
      for s = 1, count do
        local acc = 0
        for i = 1, #voices do
          local v = voices[i]
          if v.pos < v.n then
            v.pos = v.pos + 1
            acc = acc + v.samples[v.pos] * v.vol
          end
        end
        acc = math.floor(acc / 15)
        if frame == 2 then
          push_s16(bytes, acc)
          push_s16(bytes, acc)
        else
          push_s16(bytes, acc)
        end
      end
      local live = {}
      for i = 1, #voices do
        local v = voices[i]
        if v.pos < v.n then
          live[#live + 1] = v
        end
      end
      self.voices = live
      if #bytes > 0 then
        video.audio_queue(bytes_to_string(bytes))
      end
    end
  end
  if self.music_on and self.music_loop then
    local mode = string.lower(video.music_status() or "")
    if mode ~= "" and mode ~= "playing" then
      video.music_play()
    end
  end
end

function M.cut_sfx(self)
  self.voices = {}
  if video.audio_clear then
    video.audio_clear()
  end
end

function M.shutdown(self)
  M.stop_music(self)
  self.voices = {}
  self.ready = false
  video.audio_close()
end

return M
