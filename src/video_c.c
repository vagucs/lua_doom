/* DOOM generic portado do python_doom para Lua com SDL3.

   Por Wagner Nunes da Silva

   vagucs@bol.com.br
   vagucs@vagucs.com.br
   vagucs@gmail.com

   www.vagucs.com.br

   Ponte Lua 5.4 -> SDL3. Janela redimensionavel, paleta, textura e teclado.
   O botao maximizar entra em tela cheia. O motor do jogo nao entra aqui. */

#define SDL_MAIN_HANDLED
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <SDL3/SDL.h>

#include <lauxlib.h>
#include <lua.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static SDL_Window *window = NULL;
static SDL_Renderer *renderer = NULL;
static SDL_Texture *texture = NULL;
static Uint32 *pixels = NULL;
static Uint32 palette32[256];
static int tex_w = 0;
static int tex_h = 0;
static int win_w = 0;
static int win_h = 0;
static int sdl_up = 0;
static int fullscreen_on = 0;
static int suppress_maximize = 0;
static int crt_on = 0;
static SDL_AudioStream *audio_stream = NULL;
static unsigned char pal_r[256];
static unsigned char pal_g[256];
static unsigned char pal_b[256];
static SDL_Texture *crt_tex = NULL;
static int *crt_map = NULL;
static unsigned char *crt_gain = NULL;
static unsigned char *crt_src = NULL;
static unsigned char *crt_blur = NULL;
static Uint32 *crt_pix = NULL;
static int crt_mask[3][3];
static int crt_dw = 0;
static int crt_dh = 0;

static void crt_free(void) {
  if (crt_tex) SDL_DestroyTexture(crt_tex);
  free(crt_map);
  free(crt_gain);
  free(crt_src);
  free(crt_blur);
  free(crt_pix);
  crt_tex = NULL;
  crt_map = NULL;
  crt_gain = NULL;
  crt_src = NULL;
  crt_blur = NULL;
  crt_pix = NULL;
  crt_dw = 0;
  crt_dh = 0;
}

static int mci_cmd(const char *cmd, wchar_t *ret, UINT retlen) {
  wchar_t wide[2048];
  if (MultiByteToWideChar(CP_UTF8, 0, cmd, -1, wide, 2048) <= 0) return 1;
  return (int)mciSendStringW(wide, ret, retlen, NULL);
}

static Uint32 pack_argb(Uint8 r, Uint8 g, Uint8 b) {
  return ((Uint32)255 << 24) | ((Uint32)r << 16) | ((Uint32)g << 8) | (Uint32)b;
}

static void sync_window_size(void) {
  int w = 0;
  int h = 0;
  if (window && SDL_GetWindowSizeInPixels(window, &w, &h) && w > 1 && h > 1) {
    win_w = w;
    win_h = h;
  }
}

static void set_fullscreen(int on) {
  if (!window) return;
  if (on) {
    if (SDL_SetWindowFullscreen(window, true)) fullscreen_on = 1;
  } else {
    suppress_maximize = 1;
    SDL_SetWindowFullscreen(window, false);
    SDL_RestoreWindow(window);
    fullscreen_on = 0;
  }
  sync_window_size();
}

static void audio_stop(void) {
  if (audio_stream) {
    SDL_DestroyAudioStream(audio_stream);
    audio_stream = NULL;
  }
  mci_cmd("close doommus", NULL, 0);
}

static void video_teardown(void) {
  audio_stop();
  crt_free();
  if (texture) SDL_DestroyTexture(texture);
  if (renderer) SDL_DestroyRenderer(renderer);
  if (window) SDL_DestroyWindow(window);
  free(pixels);
  texture = NULL;
  renderer = NULL;
  window = NULL;
  pixels = NULL;
  tex_w = 0;
  tex_h = 0;
  fullscreen_on = 0;
  if (sdl_up) {
    SDL_Quit();
    sdl_up = 0;
  }
}

static int l_shutdown(lua_State *L) {
  (void)L;
  video_teardown();
  return 0;
}

static int l_init(lua_State *L) {
  int w = (int)luaL_checkinteger(L, 1);
  int h = (int)luaL_checkinteger(L, 2);
  int scale = (int)luaL_optinteger(L, 3, 2);
  const char *title = luaL_optstring(L, 4, "DOOM");
  if (w < 1 || h < 1) luaL_error(L, "tamanho de textura invalido");
  if (scale < 1) scale = 1;
  video_teardown();
  if (!SDL_Init(SDL_INIT_VIDEO)) luaL_error(L, "SDL_Init: %s", SDL_GetError());
  sdl_up = 1;
  window = SDL_CreateWindow(title, w * scale, h * scale, SDL_WINDOW_RESIZABLE);
  if (!window) luaL_error(L, "SDL_CreateWindow: %s", SDL_GetError());
  SDL_SetWindowPosition(window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
  renderer = SDL_CreateRenderer(window, NULL);
  if (!renderer) luaL_error(L, "SDL_CreateRenderer: %s", SDL_GetError());
  texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, w, h);
  if (!texture) luaL_error(L, "SDL_CreateTexture: %s", SDL_GetError());
  SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_NEAREST);
  pixels = (Uint32 *)malloc((size_t)w * (size_t)h * sizeof(Uint32));
  if (!pixels) luaL_error(L, "sem memoria para o quadro");
  tex_w = w;
  tex_h = h;
  win_w = w * scale;
  win_h = h * scale;
  for (int i = 0; i < 256; i++) {
    pal_r[i] = (unsigned char)i;
    pal_g[i] = (unsigned char)i;
    pal_b[i] = (unsigned char)i;
    palette32[i] = pack_argb((Uint8)i, (Uint8)i, (Uint8)i);
  }
  return 0;
}

static int l_palette(lua_State *L) {
  size_t n = 0;
  const unsigned char *p = (const unsigned char *)luaL_checklstring(L, 1, &n);
  if (!pixels) luaL_error(L, "SDL ainda nao foi iniciado");
  if (n < 768) luaL_error(L, "paleta precisa de 768 bytes RGB");
  for (int i = 0; i < 256; i++) {
    pal_r[i] = p[i * 3];
    pal_g[i] = p[i * 3 + 1];
    pal_b[i] = p[i * 3 + 2];
    palette32[i] = pack_argb(pal_r[i], pal_g[i], pal_b[i]);
  }
  return 0;
}

static void crt_build(int dw, int dh) {
  if (crt_map && crt_dw == dw && crt_dh == dh) return;
  free(crt_map);
  free(crt_gain);
  free(crt_pix);
  if (crt_tex) SDL_DestroyTexture(crt_tex);
  crt_map = (int *)malloc((size_t)dw * (size_t)dh * sizeof(int));
  crt_gain = (unsigned char *)malloc((size_t)dw * (size_t)dh);
  crt_pix = (Uint32 *)malloc((size_t)dw * (size_t)dh * sizeof(Uint32));
  crt_tex = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, dw, dh);
  if (crt_tex) SDL_SetTextureScaleMode(crt_tex, SDL_SCALEMODE_NEAREST);
  crt_dw = dw;
  crt_dh = dh;
  if (!crt_src) crt_src = (unsigned char *)malloc(320 * 200 * 3);
  if (!crt_blur) crt_blur = (unsigned char *)malloc(320 * 200 * 3);
  double sl = (double)dh / 200.0 - 1.0;
  if (sl < 0.0) sl = 0.0;
  if (sl > 1.0) sl = 1.0;
  sl *= 0.45;
  for (int y = 0; y < dh; y++) {
    double ny = 2.0 * (double)y / (double)dh - 1.0;
    double ny2 = ny * ny;
    for (int x = 0; x < dw; x++) {
      double nx = 2.0 * ((double)x + 0.5) / (double)dw - 1.0;
      double u = nx * (1.0 + ny2 / 32.0);
      double v = ny * (1.0 + (nx * nx) / 24.0);
      int outside = (u <= -1.0) || (u >= 1.0) || (v <= -1.0) || (v >= 1.0);
      double sx = (u + 1.0) * 0.5 * 320.0;
      double sy = (v + 1.0) * 0.5 * 200.0;
      int ix = (int)sx;
      int iy = (int)sy;
      if (ix < 0) ix = 0;
      if (iy < 0) iy = 0;
      if (ix > 319) ix = 319;
      if (iy > 199) iy = 199;
      double d = (sy - (double)iy) - 0.5;
      double uu = (u + 1.0) * 0.5;
      double vv = (v + 1.0) * 0.5;
      double vig = 16.0 * uu * vv * (1.0 - uu) * (1.0 - vv);
      if (vig < 0.0) vig = 0.0;
      double base = vig < 1e-20 ? 1e-20 : vig;
      double g = (1.0 - sl * 4.0 * d * d) * pow(base, 0.12) * 255.0;
      if (g < 0.0) g = 0.0;
      if (g > 255.0) g = 255.0;
      int i = y * dw + x;
      if (outside) {
        crt_map[i] = 0xFFFF;
        crt_gain[i] = 0;
      } else {
        crt_map[i] = iy * 320 + ix;
        crt_gain[i] = (unsigned char)(g + 0.5);
      }
    }
  }
  double off = 1.0;
  double boost = 1.15;
  if (dw >= 640) {
    off = 0.70;
    boost = 1.40;
  }
  for (int m = 0; m < 3; m++) {
    for (int c = 0; c < 3; c++) {
      double mv = 256.0 * boost * (m == c ? 1.0 : off);
      crt_mask[m][c] = (int)mv;
    }
  }
}

static int crt_show(const unsigned char *src) {
  if (!renderer || win_w < 2 || win_h < 2) return 0;
  crt_build(win_w, win_h);
  if (!crt_map || !crt_gain || !crt_src || !crt_blur || !crt_pix || !crt_tex) return 0;
  for (int i = 0; i < 320 * 200; i++) {
    int pix = src[i];
    crt_src[i * 3] = pal_r[pix];
    crt_src[i * 3 + 1] = pal_g[pix];
    crt_src[i * 3 + 2] = pal_b[pix];
  }
  for (int y = 0; y < 200; y++) {
    for (int x = 0; x < 320; x++) {
      int at = (y * 320 + x) * 3;
      int left = x == 0 ? at : at - 3;
      int right = x == 319 ? at : at + 3;
      crt_blur[at] = (unsigned char)((crt_src[left] + crt_src[at] * 2 + crt_src[right]) >> 2);
      crt_blur[at + 1] = (unsigned char)((crt_src[left + 1] + crt_src[at + 1] * 2 + crt_src[right + 1]) >> 2);
      crt_blur[at + 2] = (unsigned char)((crt_src[left + 2] + crt_src[at + 2] * 2 + crt_src[right + 2]) >> 2);
    }
  }
  for (int y = 0; y < win_h; y++) {
    for (int x = 0; x < win_w; x++) {
      int i = y * win_w + x;
      int idx = crt_map[i];
      if (idx == 0xFFFF) {
        crt_pix[i] = pack_argb(0, 0, 0);
        continue;
      }
      unsigned gain = crt_gain[i];
      int m = x % 3;
      int base = idx * 3;
      unsigned r = ((unsigned)crt_blur[base] * gain * (unsigned)crt_mask[m][0]) >> 16;
      unsigned g = ((unsigned)crt_blur[base + 1] * gain * (unsigned)crt_mask[m][1]) >> 16;
      unsigned b = ((unsigned)crt_blur[base + 2] * gain * (unsigned)crt_mask[m][2]) >> 16;
      if (r > 255) r = 255;
      if (g > 255) g = 255;
      if (b > 255) b = 255;
      crt_pix[i] = pack_argb((Uint8)r, (Uint8)g, (Uint8)b);
    }
  }
  SDL_UpdateTexture(crt_tex, NULL, crt_pix, win_w * (int)sizeof(Uint32));
  SDL_RenderClear(renderer);
  SDL_RenderTexture(renderer, crt_tex, NULL, NULL);
  SDL_RenderPresent(renderer);
  return 1;
}

static int l_present(lua_State *L) {
  size_t n = 0;
  const unsigned char *src = (const unsigned char *)luaL_checklstring(L, 1, &n);
  int count = tex_w * tex_h;
  if (!texture || !pixels) luaL_error(L, "SDL ainda nao foi iniciado");
  if ((int)n < count) luaL_error(L, "framebuffer curto");
  if (crt_on && tex_w == 320 && tex_h == 200 && crt_show(src)) return 0;
  for (int i = 0; i < count; i++) pixels[i] = palette32[src[i]];
  SDL_UpdateTexture(texture, NULL, pixels, tex_w * (int)sizeof(Uint32));
  SDL_RenderClear(renderer);
  SDL_RenderTexture(renderer, texture, NULL, NULL);
  SDL_RenderPresent(renderer);
  return 0;
}

static int l_set_crt(lua_State *L) {
  crt_on = lua_toboolean(L, 1);
  return 0;
}

static int l_mouse_relative(lua_State *L) {
  if (window) SDL_SetWindowRelativeMouseMode(window, lua_toboolean(L, 1));
  return 0;
}

static int l_toggle_fullscreen(lua_State *L) {
  set_fullscreen(!fullscreen_on);
  lua_pushboolean(L, fullscreen_on);
  return 1;
}

static int l_poll(lua_State *L) {
  SDL_Event ev;
  int n = 0;
  lua_newtable(L);
  while (SDL_PollEvent(&ev) && n < 64) {
    int down = 0;
    int sym = 0;
    int keep = 0;
    if (ev.type == SDL_EVENT_QUIT || ev.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED) {
      down = 1;
      sym = 0;
      keep = 1;
    } else if (ev.type == SDL_EVENT_WINDOW_MAXIMIZED) {
      if (suppress_maximize) suppress_maximize = 0;
      else if (!fullscreen_on) set_fullscreen(1);
    } else if (ev.type == SDL_EVENT_WINDOW_RESTORED) {
      suppress_maximize = 0;
      if (!fullscreen_on) sync_window_size();
    } else if (ev.type == SDL_EVENT_WINDOW_RESIZED || ev.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED) {
      sync_window_size();
    } else if (ev.type == SDL_EVENT_KEY_DOWN || ev.type == SDL_EVENT_KEY_UP) {
      if (ev.type == SDL_EVENT_KEY_DOWN && ev.key.repeat) continue;
      down = ev.type == SDL_EVENT_KEY_DOWN;
      sym = (int)ev.key.key;
      keep = 1;
    } else if (ev.type == SDL_EVENT_MOUSE_MOTION) {
      keep = 2;
    } else if (ev.type == SDL_EVENT_MOUSE_BUTTON_DOWN || ev.type == SDL_EVENT_MOUSE_BUTTON_UP) {
      if (ev.button.button == SDL_BUTTON_LEFT) keep = 3;
    }
    if (!keep) continue;
    n++;
    lua_newtable(L);
    if (keep == 2) {
      lua_pushboolean(L, 1);
      lua_setfield(L, -2, "mouse");
      lua_pushboolean(L, 0);
      lua_setfield(L, -2, "down");
      lua_pushinteger(L, -1);
      lua_setfield(L, -2, "sym");
      lua_pushinteger(L, (lua_Integer)ev.motion.xrel);
      lua_setfield(L, -2, "dx");
      lua_pushinteger(L, (lua_Integer)ev.motion.yrel);
      lua_setfield(L, -2, "dy");
    } else if (keep == 3) {
      lua_pushboolean(L, 1);
      lua_setfield(L, -2, "mouse");
      lua_pushboolean(L, ev.type == SDL_EVENT_MOUSE_BUTTON_DOWN);
      lua_setfield(L, -2, "down");
      lua_pushinteger(L, -1);
      lua_setfield(L, -2, "sym");
      lua_pushinteger(L, 1);
      lua_setfield(L, -2, "button");
    } else {
      lua_pushboolean(L, down);
      lua_setfield(L, -2, "down");
      lua_pushinteger(L, sym);
      lua_setfield(L, -2, "sym");
      lua_pushboolean(L, (ev.key.mod & SDL_KMOD_ALT) != 0);
      lua_setfield(L, -2, "alt");
    }
    lua_rawseti(L, -2, n);
  }
  return 1;
}

static int l_delay(lua_State *L) {
  int ms = (int)luaL_checkinteger(L, 1);
  if (ms > 0) SDL_Delay((Uint32)ms);
  return 0;
}

static int l_ticks(lua_State *L) {
  lua_pushinteger(L, (lua_Integer)SDL_GetTicks());
  return 1;
}

static int l_audio_open(lua_State *L) {
  SDL_AudioSpec spec;
  SDL_zero(spec);
  spec.format = SDL_AUDIO_S16LE;
  spec.channels = 1;
  spec.freq = 11025;
  if (audio_stream) {
    SDL_DestroyAudioStream(audio_stream);
    audio_stream = NULL;
  }
  if (!SDL_InitSubSystem(SDL_INIT_AUDIO)) {
    lua_pushnil(L);
    return 1;
  }
  audio_stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, NULL, NULL);
  if (!audio_stream || !SDL_ResumeAudioStreamDevice(audio_stream)) {
    if (audio_stream) SDL_DestroyAudioStream(audio_stream);
    audio_stream = NULL;
    lua_pushnil(L);
    return 1;
  }
  lua_pushinteger(L, spec.freq);
  lua_pushinteger(L, spec.channels);
  return 2;
}

static int l_audio_queue(lua_State *L) {
  size_t n = 0;
  const char *p = luaL_checklstring(L, 1, &n);
  if (!audio_stream || n == 0) return 0;
  if (SDL_GetAudioStreamQueued(audio_stream) > 11025 * 4) return 0;
  SDL_PutAudioStreamData(audio_stream, p, (int)n);
  return 0;
}

static int l_audio_clear(lua_State *L) {
  (void)L;
  if (audio_stream) SDL_ClearAudioStream(audio_stream);
  return 0;
}

static int l_audio_close(lua_State *L) {
  (void)L;
  if (audio_stream) {
    SDL_DestroyAudioStream(audio_stream);
    audio_stream = NULL;
  }
  return 0;
}

static int l_music_open(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  char cmd[4096];
  mci_cmd("close doommus", NULL, 0);
  snprintf(cmd, sizeof(cmd), "open \"%s\" type sequencer alias doommus", path);
  if (mci_cmd(cmd, NULL, 0) != 0) {
    snprintf(cmd, sizeof(cmd), "open \"%s\" alias doommus", path);
    if (mci_cmd(cmd, NULL, 0) != 0) {
      lua_pushboolean(L, 0);
      return 1;
    }
  }
  lua_pushboolean(L, mci_cmd("play doommus from 0", NULL, 0) == 0);
  return 1;
}

static int l_music_status(lua_State *L) {
  wchar_t buf[64];
  char narrow[64];
  buf[0] = 0;
  if (mci_cmd("status doommus mode", buf, 64) != 0) {
    lua_pushliteral(L, "");
    return 1;
  }
  if (WideCharToMultiByte(CP_UTF8, 0, buf, -1, narrow, 64, NULL, NULL) <= 0) {
    lua_pushliteral(L, "");
    return 1;
  }
  lua_pushstring(L, narrow);
  return 1;
}

static int l_music_play(lua_State *L) {
  lua_pushboolean(L, mci_cmd("play doommus from 0", NULL, 0) == 0);
  return 1;
}

static int l_music_volume(lua_State *L) {
  char cmd[64];
  int vol = (int)luaL_checkinteger(L, 1);
  snprintf(cmd, sizeof(cmd), "setaudio doommus volume to %d", vol);
  mci_cmd(cmd, NULL, 0);
  return 0;
}

static int l_music_close(lua_State *L) {
  (void)L;
  mci_cmd("close doommus", NULL, 0);
  return 0;
}

static const luaL_Reg regs[] = {
  {"init", l_init},
  {"shutdown", l_shutdown},
  {"set_palette", l_palette},
  {"present", l_present},
  {"set_crt", l_set_crt},
  {"mouse_relative", l_mouse_relative},
  {"toggle_fullscreen", l_toggle_fullscreen},
  {"poll", l_poll},
  {"delay", l_delay},
  {"ticks", l_ticks},
  {"audio_open", l_audio_open},
  {"audio_queue", l_audio_queue},
  {"audio_clear", l_audio_clear},
  {"audio_close", l_audio_close},
  {"music_open", l_music_open},
  {"music_status", l_music_status},
  {"music_play", l_music_play},
  {"music_volume", l_music_volume},
  {"music_close", l_music_close},
  {NULL, NULL},
};

__declspec(dllexport) int luaopen_video_c(lua_State *L) {
  luaL_newlib(L, regs);
  return 1;
}
