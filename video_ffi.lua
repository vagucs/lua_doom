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
-- SDL2 pela FFI. So o LuaJIT carrega este arquivo.

local ffi = require("ffi")
local SDL = ffi.load("SDL2")

ffi.cdef[[
typedef struct SDL_Window SDL_Window;
typedef struct SDL_Renderer SDL_Renderer;
typedef struct SDL_Texture SDL_Texture;
typedef struct SDL_PixelFormat SDL_PixelFormat;
int SDL_Init(unsigned int flags);
void SDL_Quit(void);
const char *SDL_GetError(void);
int SDL_SetHint(const char *name, const char *value);
void *SDL_CreateWindow(const char *title, int x, int y, int w, int h, unsigned int flags);
void *SDL_CreateRenderer(void *window, int index, unsigned int flags);
void *SDL_CreateTexture(void *renderer, unsigned int format, int access, int w, int h);
void *SDL_AllocFormat(unsigned int format);
unsigned int SDL_MapRGBA(void *format, unsigned char r, unsigned char g, unsigned char b, unsigned char a);
int SDL_UpdateTexture(void *texture, const void *rect, const void *pixels, int pitch);
int SDL_RenderClear(void *renderer);
int SDL_RenderCopy(void *renderer, void *texture, const void *srcrect, const void *dstrect);
void SDL_RenderPresent(void *renderer);
void SDL_DestroyTexture(void *texture);
void SDL_DestroyRenderer(void *renderer);
void SDL_DestroyWindow(void *window);
void SDL_FreeFormat(void *format);
int SDL_PollEvent(unsigned char *event);
int SDL_SetRelativeMouseMode(int enabled);
int SDL_SetWindowFullscreen(void *window, unsigned int flags);
void SDL_Delay(unsigned int ms);
unsigned int SDL_GetTicks(void);
int SDL_InitSubSystem(unsigned int flags);
typedef struct SDL_AudioSpec {
  int freq;
  uint16_t format;
  uint8_t channels;
  uint8_t silence;
  uint16_t samples;
  uint16_t padding;
  uint32_t size;
  void *callback;
  void *userdata;
} SDL_AudioSpec;
unsigned int SDL_OpenAudioDevice(const char *device, int iscapture, const SDL_AudioSpec *desired, SDL_AudioSpec *obtained, int allowed_changes);
void SDL_PauseAudioDevice(unsigned int dev, int pause_on);
void SDL_CloseAudioDevice(unsigned int dev);
int SDL_QueueAudio(unsigned int dev, const void *data, unsigned int len);
unsigned int SDL_GetQueuedAudioSize(unsigned int dev);
void SDL_ClearQueuedAudio(unsigned int dev);
unsigned int mciSendStringW(const uint16_t *cmd, uint16_t *ret, unsigned int retlen, void *wnd);
int MultiByteToWideChar(unsigned int cp, unsigned long flags, const char *src, int srclen, uint16_t *dst, int dstlen);
int WideCharToMultiByte(unsigned int cp, unsigned long flags, const uint16_t *src, int srclen, char *dst, int dstlen, const char *defchar, int *used);
]]

local WINMM = ffi.load("winmm")
local K32 = ffi.load("kernel32")

local INIT = 32
local CENTERED = 805240832
local SHOWN = 4
local ACCEL = 2
local SOFTWARE = 1
local ARGB8888 = 372645892
local STREAMING = 1
local KEYDOWN = 768
local KEYUP = 769
local QUIT = 256
local MOUSEMOTION = 1024
local MOUSEDOWN = 1025
local MOUSEUP = 1026

local AUDIO = 16
local S16 = 0x8010
local ALLOW_RATE = 1
local ALLOW_CH = 4

local window, renderer, texture, pixfmt
local pixels, palette
local pal_r, pal_g, pal_b
local tex_w, tex_h = 0, 0
local win_w, win_h = 0, 0
local crt_on = false
local fullscreen_on = false
local FULLSCREEN = 4097
local crt_map, crt_gain, crt_src, crt_blur, crt_pix, crt_tex
local crt_mask
local crt_dw, crt_dh = 0, 0
local up = false
local audio_dev = 0

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

local function shutdown()
  fullscreen_on = false
  if audio_dev ~= 0 then
    SDL.SDL_CloseAudioDevice(audio_dev)
    audio_dev = 0
  end
  music_close()
  if crt_tex ~= nil then SDL.SDL_DestroyTexture(crt_tex) end
  crt_tex, crt_map, crt_gain, crt_src, crt_blur, crt_pix = nil, nil, nil, nil, nil, nil
  crt_dw, crt_dh = 0, 0
  if texture ~= nil then SDL.SDL_DestroyTexture(texture) end
  if renderer ~= nil then SDL.SDL_DestroyRenderer(renderer) end
  if window ~= nil then SDL.SDL_DestroyWindow(window) end
  if pixfmt ~= nil then SDL.SDL_FreeFormat(pixfmt) end
  texture, renderer, window, pixfmt = nil, nil, nil, nil
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
  SDL.SDL_SetHint("SDL_RENDER_SCALE_QUALITY", "0")
  if SDL.SDL_Init(INIT) ~= 0 then fail("SDL_Init") end
  up = true
  window = SDL.SDL_CreateWindow(title, CENTERED, CENTERED, w * scale, h * scale, SHOWN)
  if window == nil then fail("SDL_CreateWindow") end
  renderer = SDL.SDL_CreateRenderer(window, -1, ACCEL)
  if renderer == nil then renderer = SDL.SDL_CreateRenderer(window, -1, SOFTWARE) end
  if renderer == nil then fail("SDL_CreateRenderer") end
  texture = SDL.SDL_CreateTexture(renderer, ARGB8888, STREAMING, w, h)
  if texture == nil then fail("SDL_CreateTexture") end
  pixfmt = SDL.SDL_AllocFormat(ARGB8888)
  if pixfmt == nil then fail("SDL_AllocFormat") end
  pixels = ffi.new("uint32_t[?]", w * h)
  palette = ffi.new("uint32_t[256]")
  pal_r = ffi.new("uint8_t[256]")
  pal_g = ffi.new("uint8_t[256]")
  pal_b = ffi.new("uint8_t[256]")
  tex_w, tex_h = w, h
  win_w, win_h = w * scale, h * scale
  for i = 0, 255 do
    pal_r[i], pal_g[i], pal_b[i] = i, i, i
    palette[i] = SDL.SDL_MapRGBA(pixfmt, i, i, i, 255)
  end
end

local function set_palette(rgb)
  if pixfmt == nil then error("SDL ainda nao foi iniciado") end
  if #rgb < 768 then error("paleta precisa de 768 bytes RGB") end
  for i = 0, 255 do
    local at = i * 3
    local r, g, b = rgb:byte(at + 1), rgb:byte(at + 2), rgb:byte(at + 3)
    pal_r[i], pal_g[i], pal_b[i] = r, g, b
    palette[i] = SDL.SDL_MapRGBA(pixfmt, r, g, b, 255)
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
  if renderer == nil or pixfmt == nil or win_w < 2 or win_h < 2 then
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
        crt_pix[i] = SDL.SDL_MapRGBA(pixfmt, 0, 0, 0, 255)
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
        crt_pix[i] = SDL.SDL_MapRGBA(pixfmt, r, g, b, 255)
      end
    end
  end
  SDL.SDL_UpdateTexture(crt_tex, nil, crt_pix, win_w * 4)
  SDL.SDL_RenderClear(renderer)
  SDL.SDL_RenderCopy(renderer, crt_tex, nil, nil)
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
  SDL.SDL_RenderCopy(renderer, texture, nil, nil)
  SDL.SDL_RenderPresent(renderer)
end

local function set_crt(on)
  crt_on = on and true or false
end

local function mouse_relative(on)
  SDL.SDL_SetRelativeMouseMode(on and 1 or 0)
end

local function toggle_fullscreen()
  if window == nil then
    return false
  end
  local next_on = not fullscreen_on
  if SDL.SDL_SetWindowFullscreen(window, next_on and FULLSCREEN or 0) == 0 then
    fullscreen_on = next_on
  end
  return fullscreen_on
end

local function u32_at(ev, offset)
  return ev[offset] + ev[offset + 1] * 256 + ev[offset + 2] * 65536 + ev[offset + 3] * 16777216
end

local function i32_at(ev, offset)
  local n = u32_at(ev, offset)
  if n >= 2147483648 then
    n = n - 4294967296
  end
  return n
end

local function poll()
  local ev = ffi.new("unsigned char[56]")
  local out = {}
  while SDL.SDL_PollEvent(ev) ~= 0 and #out < 64 do
    local kind = u32_at(ev, 0)
    if kind == QUIT then
      out[#out + 1] = { down = true, sym = 0 }
    elseif kind == KEYDOWN or kind == KEYUP then
      if not (kind == KEYDOWN and ev[13] ~= 0) then
        local mod = ev[24] + ev[25] * 256
        local alt = math.floor(mod / 256) % 4 ~= 0
        out[#out + 1] = { down = kind == KEYDOWN, sym = i32_at(ev, 20), alt = alt }
      end
    elseif kind == MOUSEMOTION then
      out[#out + 1] = { mouse = true, down = false, sym = -1, dx = i32_at(ev, 28), dy = i32_at(ev, 32) }
    elseif (kind == MOUSEDOWN or kind == MOUSEUP) and ev[16] == 1 then
      out[#out + 1] = { mouse = true, down = kind == MOUSEDOWN, sym = -1, button = 1 }
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
  return SDL.SDL_GetTicks()
end

local function audio_open()
  if audio_dev ~= 0 then
    SDL.SDL_CloseAudioDevice(audio_dev)
    audio_dev = 0
  end
  if SDL.SDL_InitSubSystem(AUDIO) ~= 0 then
    return nil
  end
  local want = ffi.new("SDL_AudioSpec")
  local have = ffi.new("SDL_AudioSpec")
  want.freq = 11025
  want.format = S16
  want.channels = 1
  want.samples = 512
  want.callback = nil
  audio_dev = SDL.SDL_OpenAudioDevice(nil, 0, want, have, ALLOW_RATE + ALLOW_CH)
  if audio_dev == 0 or have.format ~= S16 then
    if audio_dev ~= 0 then
      SDL.SDL_CloseAudioDevice(audio_dev)
      audio_dev = 0
    end
    return nil
  end
  SDL.SDL_PauseAudioDevice(audio_dev, 0)
  return have.freq, have.channels
end

local function audio_queue(pcm)
  if audio_dev == 0 or pcm == nil or #pcm == 0 then
    return
  end
  if SDL.SDL_GetQueuedAudioSize(audio_dev) > 11025 * 4 then
    return
  end
  SDL.SDL_QueueAudio(audio_dev, ffi.cast("const void*", pcm), #pcm)
end

local function audio_clear()
  if audio_dev ~= 0 then
    SDL.SDL_ClearQueuedAudio(audio_dev)
  end
end

local function audio_close()
  if audio_dev ~= 0 then
    SDL.SDL_CloseAudioDevice(audio_dev)
    audio_dev = 0
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
