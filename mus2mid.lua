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
-- MUS para MIDI. O mesmo resultado de mus2mid.py (Chocolate Doom).

local compat = require("compat")
local band, bor = compat.band, compat.bor
local unpack = unpack or table.unpack

local MUS_RELEASEKEY = 0x00
local MUS_PRESSKEY = 0x10
local MUS_PITCHWHEEL = 0x20
local MUS_SYSTEMEVENT = 0x30
local MUS_CHANGECONTROLLER = 0x40
local MUS_SCOREEND = 0x60

local HEADER = {
  0x4D, 0x54, 0x68, 0x64, 0x00, 0x00, 0x00, 0x06,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x46, 0x4D, 0x54,
  0x72, 0x6B, 0x00, 0x00, 0x00, 0x00,
}

local CONTROLLER_MAP = {
  [0] = 0x00, 0x20, 0x01, 0x07, 0x0A, 0x0B, 0x5B, 0x5D,
  0x40, 0x43, 0x78, 0x7B, 0x7E, 0x7F, 0x79,
}

local function pack(bytes)
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

local function write_time(out, time)
  local groups = { time % 128 }
  local t = math.floor(time / 128)
  while t ~= 0 do
    table.insert(groups, 1, (t % 128) + 128)
    t = math.floor(t / 128)
  end
  for i = 1, #groups do
    out.body[#out.body + 1] = groups[i]
    out.tracksize = out.tracksize + 1
  end
  out.queued = 0
end

local function write(out, data)
  write_time(out, out.queued)
  for i = 1, #data do
    out.body[#out.body + 1] = data[i]
  end
  out.tracksize = out.tracksize + #data
end

local function allocate_channel(out)
  local result = out.channel_map[0]
  for i = 1, 15 do
    if out.channel_map[i] > result then
      result = out.channel_map[i]
    end
  end
  result = result + 1
  if result == 9 then
    result = result + 1
  end
  return result
end

local function midi_channel(out, mus_channel)
  if mus_channel == 15 then
    return 9
  end
  if out.channel_map[mus_channel] == -1 then
    out.channel_map[mus_channel] = allocate_channel(out)
    local ch = out.channel_map[mus_channel]
    write(out, { bor(0xB0, ch), 0x7B, 0 })
  end
  return out.channel_map[mus_channel]
end

local function new_midi()
  local velocities = {}
  local channel_map = {}
  for i = 0, 15 do
    velocities[i] = 127
    channel_map[i] = -1
  end
  return {
    body = {},
    queued = 0,
    tracksize = 0,
    velocities = velocities,
    channel_map = channel_map,
  }
end

local function mus2mid(mus)
  if #mus >= 4 and mus:sub(1, 4) == "MThd" then
    return mus
  end
  if #mus < 16 or mus:sub(1, 4) ~= "MUS\26" then
    return nil
  end
  local scorestart = mus:byte(7) + mus:byte(8) * 256
  local pos = scorestart
  local out = new_midi()
  local hitscoreend = false

  local function read_u8()
    if pos >= #mus then
      return nil
    end
    local b = mus:byte(pos + 1)
    pos = pos + 1
    return b
  end

  while not hitscoreend do
    while not hitscoreend do
      local descriptor = read_u8()
      if descriptor == nil then
        return nil
      end
      local channel = midi_channel(out, band(descriptor, 0x0F))
      local event = band(descriptor, 0x70)
      if event == MUS_RELEASEKEY then
        local key = read_u8()
        if key == nil then
          return nil
        end
        write(out, { bor(0x80, channel), band(key, 0x7F), 0 })
      elseif event == MUS_PRESSKEY then
        local key = read_u8()
        if key == nil then
          return nil
        end
        if band(key, 0x80) ~= 0 then
          local vel = read_u8()
          if vel == nil then
            return nil
          end
          out.velocities[channel] = band(vel, 0x7F)
        end
        write(out, { bor(0x90, channel), band(key, 0x7F), out.velocities[channel] })
      elseif event == MUS_PITCHWHEEL then
        local key = read_u8()
        if key == nil then
          break
        end
        local wheel = key * 64
        write(out, { bor(0xE0, channel), wheel % 128, math.floor(wheel / 128) % 128 })
      elseif event == MUS_SYSTEMEVENT then
        local ctrl = read_u8()
        if ctrl == nil or ctrl < 10 or ctrl > 14 then
          return nil
        end
        write(out, { bor(0xB0, channel), CONTROLLER_MAP[ctrl], 0 })
      elseif event == MUS_CHANGECONTROLLER then
        local ctrl = read_u8()
        local val = read_u8()
        if ctrl == nil or val == nil then
          return nil
        end
        if ctrl == 0 then
          write(out, { bor(0xC0, channel), band(val, 0x7F) })
        else
          if ctrl < 1 or ctrl > 9 then
            return nil
          end
          local working = val
          if band(val, 0x80) ~= 0 then
            working = 0x7F
          end
          write(out, { bor(0xB0, channel), CONTROLLER_MAP[ctrl], working })
        end
      elseif event == MUS_SCOREEND then
        hitscoreend = true
      else
        return nil
      end
      if band(descriptor, 0x80) ~= 0 then
        break
      end
    end
    if not hitscoreend then
      local timedelay = 0
      while true do
        local working = read_u8()
        if working == nil then
          return nil
        end
        timedelay = timedelay * 128 + band(working, 0x7F)
        if band(working, 0x80) == 0 then
          break
        end
      end
      out.queued = out.queued + timedelay
    end
  end

  write_time(out, out.queued)
  out.body[#out.body + 1] = 0xFF
  out.body[#out.body + 1] = 0x2F
  out.body[#out.body + 1] = 0x00
  out.tracksize = out.tracksize + 3

  local header = {}
  for i = 1, #HEADER do
    header[i] = HEADER[i]
  end
  local ts = out.tracksize
  header[19] = math.floor(ts / 16777216) % 256
  header[20] = math.floor(ts / 65536) % 256
  header[21] = math.floor(ts / 256) % 256
  header[22] = ts % 256
  for i = 1, #out.body do
    header[#header + 1] = out.body[i]
  end
  return pack(header)
end

return { mus2mid = mus2mid }
