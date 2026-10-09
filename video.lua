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
-- Uma API de video. LuaJIT usa a FFI. Lua 5.4 usa video_c.dll.

local keys = require("keys")

local function backend()
  if rawget(_G, "jit") then
    return require("video_ffi")
  end
  return require("video_c")
end

local raw = backend()
local M = {}

function M.init(w, h, scale, title)
  raw.init(w, h, scale, title)
end

function M.shutdown()
  raw.shutdown()
end

function M.set_palette(rgb)
  raw.set_palette(rgb)
end

function M.present(fb)
  raw.present(fb)
end

function M.delay(ms)
  raw.delay(ms)
end

function M.ticks()
  return raw.ticks()
end

function M.poll()
  local events = raw.poll()
  for i = 1, #events do
    if events[i].mouse then
      events[i].key = ""
    else
      events[i].key = keys.name_of(events[i].sym)
    end
  end
  return events
end

function M.set_crt(on)
  if raw.set_crt then
    raw.set_crt(on)
  end
end

function M.mouse_relative(on)
  if raw.mouse_relative then
    raw.mouse_relative(on)
  end
end

function M.toggle_fullscreen()
  if raw.toggle_fullscreen then
    return raw.toggle_fullscreen()
  end
  return false
end

function M.audio_open()
  if not raw.audio_open then
    return nil
  end
  return raw.audio_open()
end

function M.audio_queue(pcm)
  if raw.audio_queue then
    raw.audio_queue(pcm)
  end
end

function M.audio_clear()
  if raw.audio_clear then
    raw.audio_clear()
  end
end

function M.audio_close()
  if raw.audio_close then
    raw.audio_close()
  end
end

function M.music_open(path)
  if not raw.music_open then
    return false
  end
  return raw.music_open(path)
end

function M.music_status()
  if not raw.music_status then
    return ""
  end
  return raw.music_status()
end

function M.music_play()
  if raw.music_play then
    raw.music_play()
  end
end

function M.music_volume(level)
  if raw.music_volume then
    raw.music_volume(level)
  end
end

function M.music_close()
  if raw.music_close then
    raw.music_close()
  end
end

return M
