-- DOOM generic portado do python_doom para Lua com SDL3.
--
-- Por Wagner Nunes da Silva
--
-- vagucs@bol.com.br
-- vagucs@vagucs.com.br
-- vagucs@gmail.com
--
-- www.vagucs.com.br
--
-- SDL3 pela FFI. So o LuaJIT carrega este arquivo.

local ffi = require("ffi")

local function load_sdl()
  local src = debug.getinfo(1, "S").source
  local dir = src:match("^@(.+)[\\/][^\\/]+$")
  if dir then
    local full = dir .. "\\sdl3\\SDL3-3.4.18-win32-x64\\SDL3.dll"
    local f = io.open(full, "rb")
    if f then
      f:close()
      return ffi.load(full)
    end
  end
  return ffi.load("SDL3")
end

local SDL = load_sdl()

ffi.cdef[[
typedef struct SDL_Window SDL_Window;
typedef struct SDL_Renderer SDL_Renderer;
typedef struct SDL_Texture SDL_Texture;
typedef struct SDL_AudioStream SDL_AudioStream;
typedef uint32_t SDL_AudioDeviceID;
typedef uint16_t SDL_AudioFormat;
typedef struct SDL_AudioSpec {
  SDL_AudioFormat format;
  int channels;
  int freq;
} SDL_AudioSpec;
typedef struct SDL_KeyboardEvent {
  uint32_t type;
  uint32_t reserved;
  uint64_t timestamp;
  uint32_t windowID;
  uint32_t which;
  uint32_t scancode;
  uint32_t key;
  uint16_t mod;
  uint16_t raw;
  uint8_t down;
  uint8_t repeat;
} SDL_KeyboardEvent;
typedef struct SDL_MouseMotionEvent {
  uint32_t type;
  uint32_t reserved;
  uint64_t timestamp;
  uint32_t windowID;
  uint32_t which;
  uint32_t state;
  float x;
  float y;
  float xrel;
  float yrel;
} SDL_MouseMotionEvent;
typedef struct SDL_MouseButtonEvent {
  uint32_t type;
  uint32_t reserved;
  uint64_t timestamp;
  uint32_t windowID;
  uint32_t which;
  uint8_t button;
  uint8_t down;
  uint8_t clicks;
  uint8_t padding;
  float x;
  float y;
} SDL_MouseButtonEvent;
typedef union SDL_Event {
  uint32_t type;
  SDL_KeyboardEvent key;
  SDL_MouseMotionEvent motion;
  SDL_MouseButtonEvent button;
  uint8_t pad[128];
} SDL_Event;
bool SDL_Init(uint32_t flags);
bool SDL_InitSubSystem(uint32_t flags);
void SDL_Quit(void);
const char *SDL_GetError(void);
void *SDL_CreateWindow(const char *title, int w, int h, uint64_t flags);
bool SDL_SetWindowPosition(void *window, int x, int y);
bool SDL_GetWindowSizeInPixels(void *window, int *w, int *h);
bool SDL_SetWindowFullscreen(void *window, bool fullscreen);
bool SDL_RestoreWindow(void *window);
bool SDL_SetWindowRelativeMouseMode(void *window, bool enabled);
void *SDL_CreateRenderer(void *window, const char *name);
void *SDL_CreateTexture(void *renderer, uint32_t format, int access, int w, int h);
bool SDL_SetTextureScaleMode(void *texture, int mode);
bool SDL_UpdateTexture(void *texture, const void *rect, const void *pixels, int pitch);
bool SDL_RenderClear(void *renderer);
bool SDL_RenderTexture(void *renderer, void *texture, const void *srcrect, const void *dstrect);
bool SDL_RenderPresent(void *renderer);
void SDL_DestroyTexture(void *texture);
void SDL_DestroyRenderer(void *renderer);
void SDL_DestroyWindow(void *window);
bool SDL_PollEvent(SDL_Event *event);
void SDL_Delay(uint32_t ms);
uint64_t SDL_GetTicks(void);
void *SDL_OpenAudioDeviceStream(SDL_AudioDeviceID devid, const SDL_AudioSpec *spec, void *callback, void *userdata);
bool SDL_ResumeAudioStreamDevice(void *stream);
bool SDL_PutAudioStreamData(void *stream, const void *buf, int len);
int SDL_GetAudioStreamQueued(void *stream);
bool SDL_ClearAudioStream(void *stream);
void SDL_DestroyAudioStream(void *stream);
unsigned int mciSendStringW(const uint16_t *cmd, uint16_t *ret, unsigned int retlen, void *wnd);
int MultiByteToWideChar(unsigned int cp, unsigned long flags, const char *src, int srclen, uint16_t *dst, int dstlen);
int WideCharToMultiByte(unsigned int cp, unsigned long flags, const uint16_t *src, int srclen, char *dst, int dstlen, const char *defchar, int *used);
]]

local WINMM = ffi.load("winmm")
local K32 = ffi.load("kernel32")

local INIT = 0x20
local AUDIO = 0x10
local RESIZABLE = 0x20
local CENTERED = 0x2FFF0000
local ARGB8888 = 0x16362004
local STREAMING = 1
local NEAREST = 0
local KEYDOWN = 0x300
local KEYUP = 0x301
local QUIT = 0x100
local CLOSE = 0x210
local MAXIMIZED = 0x20A
local RESTORED = 0x20B
local RESIZED = 0x206
local PIXEL = 0x207
local MOUSEMOTION = 0x400
local MOUSEDOWN = 0x401
local MOUSEUP = 0x402
local KMOD_ALT = 0x0300
local S16 = 0x8010
local DEFAULT_PLAYBACK = 0xFFFFFFFF

local window, renderer, texture
local pixels, palette
local pal_r, pal_g, pal_b
local tex_w, tex_h = 0, 0
local win_w, win_h = 0, 0
local crt_on = false
local fullscreen_on = false
local suppress_maximize = false
local crt_map, crt_gain, crt_src, crt_blur, crt_pix, crt_tex
local crt_mask
local crt_dw, crt_dh = 0, 0
local up = false
local audio_stream = nil

local function fail(what)
  error(what .. ": " .. ffi.string(SDL.SDL_GetError()))
end

local function wide_cmd(cmd)
  local n = #cmd
  local buf = ffi.new("uint16_t[?]", n + 1)
  K32.MultiByteToWideChar(65001, 0, cmd, -1, buf, n + 1)
  return buf
end

local function mci(cmd, ret)
  return WINMM.mciSendStringW(wide_cmd(cmd), ret, ret and 64 or 0, nil)
end

local function music_close()
  mci("close doommus", nil)
end

local function pack_argb(r, g, b)
  return 0xFF000000 + r * 65536 + g * 256 + b
end

local function sync_window_size()
  if window == nil then
    return
  end
  local w = ffi.new("int[1]")
  local h = ffi.new("int[1]")
  if SDL.SDL_GetWindowSizeInPixels(window, w, h) and w[0] > 1 and h[0] > 1 then
    win_w, win_h = w[0], h[0]
  end
end

local function set_fullscreen(on)
  if window == nil then
    return
  end
  if on then
    if SDL.SDL_SetWindowFullscreen(window, true) then
      fullscreen_on = true
    end
  else
    suppress_maximize = true
    SDL.SDL_SetWindowFullscreen(window, false)
    SDL.SDL_RestoreWindow(window)
    fullscreen_on = false
  end
  sync_window_size()
end

local function shutdown()
  fullscreen_on = false
  suppress_maximize = false
  if audio_stream ~= nil then
    SDL.SDL_DestroyAudioStream(audio_stream)
    audio_stream = nil
  end
  music_close()
  if crt_tex ~= nil then SDL.SDL_DestroyTexture(crt_tex) end
  crt_tex, crt_map, crt_gain, crt_src, crt_blur, crt_pix = nil, nil, nil, nil, nil, nil
  crt_dw, crt_dh = 0, 0
  if texture ~= nil then SDL.SDL_DestroyTexture(texture) end
  if renderer ~= nil then SDL.SDL_DestroyRenderer(renderer) end
  if window ~= nil then SDL.SDL_DestroyWindow(window) end
  texture, renderer, window = nil, nil, nil
  pixels, palette = nil, nil
  tex_w, tex_h = 0, 0
  if up then
    SDL.SDL_Quit()
    up = false
  end
end

local function init(w, h, scale, title)
  scale = scale or 2
  title = title or "DOOM"
  if w < 1 or h < 1 then error("tamanho de textura invalido") end
  if scale < 1 then scale = 1 end
  shutdown()
  if not SDL.SDL_Init(INIT) then fail("SDL_Init") end
  up = true
  window = SDL.SDL_CreateWindow(title, w * scale, h * scale, RESIZABLE)
  if window == nil then fail("SDL_CreateWindow") end
  SDL.SDL_SetWindowPosition(window, CENTERED, CENTERED)
  renderer = SDL.SDL_CreateRenderer(window, nil)
  if renderer == nil then fail("SDL_CreateRenderer") end
  texture = SDL.SDL_CreateTexture(renderer, ARGB8888, STREAMING, w, h)
  if texture == nil then fail("SDL_CreateTexture") end
  SDL.SDL_SetTextureScaleMode(texture, NEAREST)
  pixels = ffi.new("uint32_t[?]", w * h)
  palette = ffi.new("uint32_t[256]")
  pal_r = ffi.new("uint8_t[256]")
  pal_g = ffi.new("uint8_t[256]")
  pal_b = ffi.new("uint8_t[256]")
  tex_w, tex_h = w, h
  win_w, win_h = w * scale, h * scale
  for i = 0, 255 do
    pal_r[i], pal_g[i], pal_b[i] = i, i, i
    palette[i] = pack_argb(i, i, i)
  end
end

local function set_palette(rgb)
  if pixels == nil then error("SDL ainda nao foi iniciado") end
  if #rgb < 768 then error("paleta precisa de 768 bytes RGB") end
  for i = 0, 255 do
    local at = i * 3
    local r, g, b = rgb:byte(at + 1), rgb:byte(at + 2), rgb:byte(at + 3)
    pal_r[i], pal_g[i], pal_b[i] = r, g, b
    palette[i] = pack_argb(r, g, b)
  end
end

local function crt_build(dw, dh)
  if crt_map ~= nil and crt_dw == dw and crt_dh == dh then
    return
  end
  if crt_tex ~= nil then
    SDL.SDL_DestroyTexture(crt_tex)
  end
  crt_map = ffi.new("int[?]", dw * dh)
  crt_gain = ffi.new("uint8_t[?]", dw * dh)
  crt_pix = ffi.new("uint32_t[?]", dw * dh)
  crt_tex = SDL.SDL_CreateTexture(renderer, ARGB8888, STREAMING, dw, dh)
  if crt_tex ~= nil then
    SDL.SDL_SetTextureScaleMode(crt_tex, NEAREST)
  end
  crt_dw, crt_dh = dw, dh
  if crt_src == nil then
    crt_src = ffi.new("uint8_t[?]", 320 * 200 * 3)
    crt_blur = ffi.new("uint8_t[?]", 320 * 200 * 3)
  end
  local sl = dh / 200 - 1
  if sl < 0 then
    sl = 0
  end
  if sl > 1 then
    sl = 1
  end
  sl = sl * 0.45
  for y = 0, dh - 1 do
    local ny = 2 * y / dh - 1
    local ny2 = ny * ny
    for x = 0, dw - 1 do
      local nx = 2 * (x + 0.5) / dw - 1
      local u = nx * (1 + ny2 / 32)
      local v = ny * (1 + (nx * nx) / 24)
      local outside = u <= -1 or u >= 1 or v <= -1 or v >= 1
      local sx = (u + 1) * 0.5 * 320
      local sy = (v + 1) * 0.5 * 200
      local ix = math.floor(sx)
      local iy = math.floor(sy)
      if sx < 0 then
        ix = math.ceil(sx)
      end
      if sy < 0 then
        iy = math.ceil(sy)
      end
      if ix < 0 then
        ix = 0
      end
      if iy < 0 then
        iy = 0
      end
      if ix > 319 then
        ix = 319
      end
      if iy > 199 then
        iy = 199
      end
      local d = (sy - iy) - 0.5
      local uu = (u + 1) * 0.5
      local vv = (v + 1) * 0.5
      local vig = 16 * uu * vv * (1 - uu) * (1 - vv)
      if vig < 0 then
        vig = 0
      end
      local base = vig
      if base < 1e-20 then
        base = 1e-20
      end
      local g = (1 - sl * 4 * d * d) * (base ^ 0.12) * 255
      if g < 0 then
        g = 0
      end
      if g > 255 then
        g = 255
      end
      local i = y * dw + x
      if outside then
        crt_map[i] = 65535
        crt_gain[i] = 0
      else
        crt_map[i] = iy * 320 + ix
        crt_gain[i] = math.floor(g + 0.5)
      end
    end
  end
  local off, boost = 1.0, 1.15
  if dw >= 640 then
    off, boost = 0.70, 1.40
  end
  crt_mask = {}
  for m = 0, 2 do
    crt_mask[m] = {}
    for c = 0, 2 do
      local mv = 256 * boost
      if m ~= c then
        mv = mv * off
      end
      crt_mask[m][c] = math.floor(mv)
    end
  end
end

local function crt_show(fb)
  if renderer == nil or win_w < 2 or win_h < 2 then
    return false
  end
  crt_build(win_w, win_h)
  if crt_tex == nil then
    return false
  end
  for i = 0, 320 * 200 - 1 do
    local pix = fb:byte(i + 1)
    crt_src[i * 3] = pal_r[pix]
    crt_src[i * 3 + 1] = pal_g[pix]
    crt_src[i * 3 + 2] = pal_b[pix]
  end
  for y = 0, 199 do
    for x = 0, 319 do
      local at = (y * 320 + x) * 3
      local left = at
      local right = at
      if x > 0 then
        left = at - 3
      end
      if x < 319 then
        right = at + 3
      end
      crt_blur[at] = math.floor((crt_src[left] + crt_src[at] * 2 + crt_src[right]) / 4)
      crt_blur[at + 1] = math.floor((crt_src[left + 1] + crt_src[at + 1] * 2 + crt_src[right + 1]) / 4)
      crt_blur[at + 2] = math.floor((crt_src[left + 2] + crt_src[at + 2] * 2 + crt_src[right + 2]) / 4)
    end
  end
  for y = 0, win_h - 1 do
    for x = 0, win_w - 1 do
      local i = y * win_w + x
      local idx = crt_map[i]
      if idx == 65535 then
        crt_pix[i] = pack_argb(0, 0, 0)
      else
        local gain = crt_gain[i]
        local mask = crt_mask[x % 3]
        local base = idx * 3
        local r = math.floor(crt_blur[base] * gain * mask[0] / 65536)
        local g = math.floor(crt_blur[base + 1] * gain * mask[1] / 65536)
        local b = math.floor(crt_blur[base + 2] * gain * mask[2] / 65536)
        if r > 255 then
          r = 255
        end
        if g > 255 then
          g = 255
        end
        if b > 255 then
          b = 255
        end
        crt_pix[i] = pack_argb(r, g, b)
      end
    end
  end
  SDL.SDL_UpdateTexture(crt_tex, nil, crt_pix, win_w * 4)
  SDL.SDL_RenderClear(renderer)
  SDL.SDL_RenderTexture(renderer, crt_tex, nil, nil)
  SDL.SDL_RenderPresent(renderer)
  return true
end

local function present(fb)
  local count = tex_w * tex_h
  if texture == nil or pixels == nil then error("SDL ainda nao foi iniciado") end
  if #fb < count then error("framebuffer curto") end
  if crt_on and tex_w == 320 and tex_h == 200 and crt_show(fb) then
    return
  end
  for i = 0, count - 1 do
    pixels[i] = palette[fb:byte(i + 1)]
  end
  SDL.SDL_UpdateTexture(texture, nil, pixels, tex_w * 4)
  SDL.SDL_RenderClear(renderer)
  SDL.SDL_RenderTexture(renderer, texture, nil, nil)
  SDL.SDL_RenderPresent(renderer)
end

local function set_crt(on)
  crt_on = on and true or false
end

local function mouse_relative(on)
  if window ~= nil then
    SDL.SDL_SetWindowRelativeMouseMode(window, on and true or false)
  end
end

local function toggle_fullscreen()
  set_fullscreen(not fullscreen_on)
  return fullscreen_on
end

local function key_sym(code)
  if code >= 2147483648 then
    return code - 4294967296
  end
  return code
end

local function poll()
  local ev = ffi.new("SDL_Event")
  local out = {}
  while SDL.SDL_PollEvent(ev) and #out < 64 do
    local kind = ev.type
    if kind == QUIT or kind == CLOSE then
      out[#out + 1] = { down = true, sym = 0 }
    elseif kind == MAXIMIZED then
      if suppress_maximize then
        suppress_maximize = false
      elseif not fullscreen_on then
        set_fullscreen(true)
      end
    elseif kind == RESTORED then
      suppress_maximize = false
      if not fullscreen_on then
        sync_window_size()
      end
    elseif kind == RESIZED or kind == PIXEL then
      sync_window_size()
    elseif kind == KEYDOWN or kind == KEYUP then
      if not (kind == KEYDOWN and ev.key["repeat"] ~= 0) then
        out[#out + 1] = {
          down = kind == KEYDOWN,
          sym = key_sym(ev.key.key),
          alt = bit.band(ev.key.mod, KMOD_ALT) ~= 0,
        }
      end
    elseif kind == MOUSEMOTION then
      out[#out + 1] = {
        mouse = true,
        down = false,
        sym = -1,
        dx = math.floor(ev.motion.xrel),
        dy = math.floor(ev.motion.yrel),
      }
    elseif (kind == MOUSEDOWN or kind == MOUSEUP) and ev.button.button == 1 then
      out[#out + 1] = {
        mouse = true,
        down = kind == MOUSEDOWN,
        sym = -1,
        button = 1,
      }
    end
  end
  return out
end

local function delay(ms)
  if ms and ms > 0 then
    SDL.SDL_Delay(ms)
  end
end

local function ticks()
  return tonumber(SDL.SDL_GetTicks())
end

local function audio_open()
  if audio_stream ~= nil then
    SDL.SDL_DestroyAudioStream(audio_stream)
    audio_stream = nil
  end
  if not SDL.SDL_InitSubSystem(AUDIO) then
    return nil
  end
  local spec = ffi.new("SDL_AudioSpec")
  spec.format = S16
  spec.channels = 1
  spec.freq = 11025
  audio_stream = SDL.SDL_OpenAudioDeviceStream(DEFAULT_PLAYBACK, spec, nil, nil)
  if audio_stream == nil or not SDL.SDL_ResumeAudioStreamDevice(audio_stream) then
    if audio_stream ~= nil then
      SDL.SDL_DestroyAudioStream(audio_stream)
      audio_stream = nil
    end
    return nil
  end
  return spec.freq, spec.channels
end

local function audio_queue(pcm)
  if audio_stream == nil or pcm == nil or #pcm == 0 then
    return
  end
  if SDL.SDL_GetAudioStreamQueued(audio_stream) > 11025 * 4 then
    return
  end
  SDL.SDL_PutAudioStreamData(audio_stream, ffi.cast("const void*", pcm), #pcm)
end

local function audio_clear()
  if audio_stream ~= nil then
    SDL.SDL_ClearAudioStream(audio_stream)
  end
end

local function audio_close()
  if audio_stream ~= nil then
    SDL.SDL_DestroyAudioStream(audio_stream)
    audio_stream = nil
  end
end

local function music_open(path)
  music_close()
  local quoted = string.gsub(path, "/", "\\")
  if mci('open "' .. quoted .. '" type sequencer alias doommus', nil) ~= 0 then
    if mci('open "' .. quoted .. '" alias doommus', nil) ~= 0 then
      return false
    end
  end
  return mci("play doommus from 0", nil) == 0
end

local function music_status()
  local buf = ffi.new("uint16_t[64]")
  if mci("status doommus mode", buf) ~= 0 then
    return ""
  end
  local narrow = ffi.new("char[64]")
  if K32.WideCharToMultiByte(65001, 0, buf, -1, narrow, 64, nil, nil) <= 0 then
    return ""
  end
  return ffi.string(narrow)
end

local function music_play()
  return mci("play doommus from 0", nil) == 0
end

local function music_volume(level)
  mci("setaudio doommus volume to " .. tostring(level), nil)
end

return {
  init = init,
  shutdown = shutdown,
  set_palette = set_palette,
  present = present,
  set_crt = set_crt,
  mouse_relative = mouse_relative,
  toggle_fullscreen = toggle_fullscreen,
  poll = poll,
  delay = delay,
  ticks = ticks,
  audio_open = audio_open,
  audio_queue = audio_queue,
  audio_clear = audio_clear,
  audio_close = audio_close,
  music_open = music_open,
  music_status = music_status,
  music_play = music_play,
  music_volume = music_volume,
  music_close = music_close,
}
