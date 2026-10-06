# lua_doom

![DOOM running on Lua with SDL2](screenshot/doom.png)

**Video:** [DOOM running in Lua](https://youtu.be/4OYTretHKtY)

DOOM generic ported from **[python_doom](https://github.com/vagucs/python_doom)** to **Lua 5.4 and LuaJIT + SDL2**.

By **Wagner Nunes da Silva**

- vagucs@bol.com.br
- vagucs@vagucs.com.br
- vagucs@gmail.com
- [www.vagucs.com.br](https://www.vagucs.com.br)
- [LinkedIn](https://www.linkedin.com/in/wagner-nunes-da-silva-b0a15360)

This tree is that Python engine again, in Lua. The same source runs on PUC-Rio Lua 5.4 and on LuaJIT. The game loop, the map, and the renderer stay in Lua. SDL2 sits behind one API. LuaJIT calls `SDL2.dll` through the FFI. Lua 5.4 uses a small C bridge (`src/video_c.c`). Windows MCI plays the MIDI, because SDL2 does not.

Versão em português: [README.pt.md](README.pt.md)

---

## What this project is

`python_doom` is a condensed, playable DOOM engine in Python. This directory is the **same study piece**, rewritten in Lua:

- Window, keys, mouse, PCM: **SDL2**, one API for both runtimes
- Framebuffer: 320×200, one PLAYPAL index per slot, stretched to a 640×400 window
- Game tick: 35 Hz (`TICRATE`). Each displayed frame runs up to 4 tics
- Renderer: BSP, visplanes, columns, spans, sprites, the weapon sprite
- Map: VERTEXES, LINEDEFS, SIDEDEFS, SECTORS, SEGS, SSECTORS, NODES, THINGS, BLOCKMAP, REJECT
- Play: walk, doors, lifts, switches, exit, pickups, weapons, status bar, Tab automap, DS* sound, MUS→MIDI music, ESC menu, intermission tally, melt wipe on a level change, monster look/chase/attack, mouse look

You need a legal IWAD (shareware `doom1.wad` or commercial `doom.wad` / `doom2.wad`). This repository does not ship commercial WAD data.

It is a **condensed educational port**: the engine is Lua, the native layer is SDL2.

Left out of this tree:

- Network, joystick, CD audio

---

## Educational purpose

This project is a **study piece**. The Python port already dropped the preprocessor and Harbour's 1-based arrays. The Lua port asks a different question: **what survives when the source has to run on Lua 5.4 and on LuaJIT**, with 1-based tables and no bitwise syntax in the shared dialect.

What it is meant to teach:

- **Python, then Lua.** Open `python_doom/doom/` next to `lua_doom/`. The names stay close (`thrust`, `fixed_mul`, `line_attack`) so the two files can sit side by side.
- **One dialect, two runtimes.** The engine is the Lua 5.1 common subset. No `//`, no `&` `|` `<<` `>>` in files LuaJIT parses, and no `ffi` outside `video_ffi.lua`. `band` / `bor` / `bxor` / `shl` use `bit.*` on LuaJIT and the Lua 5.4 operators, loaded with `load`.
- **1-based reads.** WAD lumps, BSP nodes, menu rows, and screen columns stay 0-based in the data and are read with `+ 1`.
- **Where Lua is enough.** Columns, floors, sprites, and thinkers run in Lua. SDL2 is the window, the keyboard, the mouse, and the PCM queue.

Suggested way to study:

1. Run `run.bat`, then `run.bat jit`, and read `main.lua` — boot, tic, input.
2. Compare `compat.lua` with `python_doom/doom/compat.py`.
3. Open `render.lua` next to `python_doom/doom/render.py`.
4. Follow a door from **Space** (`use_lines` in `collision.lua`) through `specials.lua`.
5. Follow a shot from **Ctrl** in `player.lua` to `spawn_player_missile` in `enemy.lua`.

---

## From Python to Lua

Python lists are 0-based. Lua tables used as arrays are 1-based. WAD lumps, BSP nodes, menu rows, and clip ranges stay 0-based in the data and are read with `+ 1`.

| Python (`python_doom`) | Lua (`lua_doom`) |
| --- | --- |
| `thing.x` | `thing.x` |
| `None` | `nil` |
| `items[0]` | `items[1]` |
| class | table (shared reference) |
| unlimited `int` | Lua number; `as_u32` / `as_i32` put the 32-bit wrap back |
| `&`, `\|`, `^` | `band` / `bor` / `bxor` (`bit.*`, or Lua 5.4 operators behind `load`) |
| `x >> n` | `ushr` / `shar` |
| `a // b` | `math.floor` |
| `fixed_mul` / `fixed_div` | `fixed_mul` / `fixed_div` |
| `bytearray` framebuffer | table of bytes, length 64000 |
| pygame | SDL2: FFI on LuaJIT, `video_c.dll` on Lua 5.4 |
| `+=` | `x = x + ...` |

A table is a reference, so a field write is visible to the caller, the same way a Python object is.

### Side-by-side: `P_Thrust`

Python (`doom/player.py`):

```python
def thrust(mo, angle, move):
    mo.momx += fixed_mul(move, fine_cos(angle))
    mo.momy += fixed_mul(move, fine_sin(angle))
```

Lua (`player.lua`):

```lua
function M.thrust(mo, angle, move)
  mo.momx = mo.momx + fixed_mul(move, tables.fine_cos(angle))
  mo.momy = mo.momy + fixed_mul(move, tables.fine_sin(angle))
end
```

`.` stays `.`. There is no `+=`. `mo` is a table, so the new momentum stays on the mobj the caller already holds.

---

## Technology

| Layer | This port | Python (`python_doom`) |
| --- | --- | --- |
| Language | Lua 5.4.9 and LuaJIT 2.1, one source | Python 3.10+ |
| Window, keys, mouse, PCM | SDL2. FFI in `video_ffi.lua`, or `src/video_c.c` | pygame 2.x |
| Palette blit / CRT | Lua, then the SDL texture | numpy |
| MIDI (Windows) | winmm MCI | the same idea, outside pygame |
| IWAD | the same lumps | the same lumps |
| Build | none for LuaJIT. `build_video.bat` only when `src/video_c.c` changes | `pip install -r requirements.txt` |

The renderer is Lua. The C file is only the Lua 5.4 bridge.

---

## How to run

Tools, on MSYS2 UCRT64:

| Runtime | Executable |
| --- | --- |
| Lua 5.4.9 (PUC-Rio) | `C:\msys64\ucrt64\bin\lua5.4.exe` |
| LuaJIT 2.1 | `C:\msys64\ucrt64\bin\luajit.exe` |
| SDL2 | `C:\msys64\ucrt64\bin\SDL2.dll` |

From this directory:

```
run.bat
run.bat jit
run.bat -warp 1 1 -skill 2
run.bat jit -fps -crt
```

`run.bat` opens the window with Lua 5.4. `run.bat jit` opens the same game with LuaJIT. The window is 640×400. Without `-crt`, the 320×200 texture is stretched with nearest-neighbor.

---

## Keys

Classic DOOM controls.

### Movement and actions

| Key | Action |
| --- | --- |
| Arrow keys | Forward, back, turn |
| **Shift** | Run |
| **Alt** | Strafe (hold) |
| **Ctrl** or left mouse | Fire |
| **Space** / **E** | Use / open door |
| Mouse | Look |
| **Enter** / **Esc** | Menu |
| **Tab** | Automap. **F** follows, **G** draws the grid, **0** shows the whole map |
| **-** / **=** | Zoom the automap when it is open; otherwise a smaller / larger 3D view |
| **Alt+Enter** | Fullscreen |

Quit is the menu item, or closing the window. **Y** confirms quit.

### Cheats

Type these during a level, with the menu closed. No Enter. On Nightmare skill only **IDCLEV** and **IDDT** are accepted.

| Code | Effect |
| --- | --- |
| **IDDQD** | God mode |
| **IDKFA** | All weapons, ammo, keys, and armor |
| **IDFA** | Weapons, ammo, and armor |
| **IDCLIP** / **IDSPISPOPD** | No clipping |
| **IDDT** | Automap: all walls, then things |
| **IDBEHOLD** | Power-ups; then **V** **S** **I** **R** **A** **L** |
| **IDCHOPPERS** | Chainsaw |
| **IDMYPOS** | Coordinates and angle |
| **IDCLEV** + 2 digits | Warp (`11` = E1M1, or MAP11 on a commercial IWAD) |
| **IDMUS** + 2 digits | Change music |

---

## Command-line parameters

### IWAD

| Parameter | Description |
| --- | --- |
| `-iwad file.wad` | IWAD to load |
| `file.wad` | Same thing, without `-iwad` |
| `-file wad [wad…]` | Extra PWADs after the IWAD |

### Video

| Parameter | Description |
| --- | --- |
| `-crt` | CRT tube, drawn over the SDL texture |
| `-fps` | Frame rate. The game still ticks at 35 Hz |

### Game

| Parameter | Description |
| --- | --- |
| `-warp e m` | Skip the title and start episode `e` map `m` |
| `-skill n` | Skill |
| `-nomonsters` | Do not spawn enemies |
| `-fast` | Faster monsters |
| `-respawn` | Nightmare-style respawn |
| `-nosound` | No sound effects |
| `-nomusic` | No MIDI |

A level change melts the screen. Starting a new game from the title does not. Shareware map 8 writes `E1TEXT` on `FLOOR4_8`. Saves are `doomsav0.dsg` through `doomsav5.dsg`, next to the IWAD, with the header `DOOMPY01`.

---

## Layout

```
main.lua             entry
run.bat              Lua 5.4, or `jit` for LuaJIT
video_ffi.lua        SDL2 through the LuaJIT FFI
src/video_c.c        the same API for Lua 5.4
build_video.bat      rebuild that bridge
screenshot/doom.png  the picture at the top
```

| Path | Python |
| --- | --- |
| `compat.lua` | `doom/compat.py` |
| `wad.lua` | `doom/wad.py` |
| `video.lua` | `doom/video.py` |
| `v_video.lua` | `doom/v_video.py` |
| `tables.lua` | `doom/tables.py` |
| `r_data.lua` | `doom/r_data.py` |
| `render.lua` | `doom/render.py` |
| `world.lua` | `doom/world.py` |
| `collision.lua` | `doom/collision.py` |
| `player.lua` | `doom/player.py` |
| `specials.lua` | `doom/specials.py` |
| `info.lua` | `doom/info.py` |
| `sprites.lua` | `doom/sprites.py` |
| `enemy.lua` | `doom/enemy.py` |
| `thinker.lua` | `doom/thinker.py` |
| `status.lua` | `doom/status.py` |
| `sound.lua` | `doom/sound.py` |
| `mus2mid.lua` | `doom/mus2mid.py` |
| `menu.lua` | `doom/menu.py` |
| `wi_stuff.lua` | `doom/wi_stuff.py` |
| `wipe.lua` | `doom/wipe.py` |
| `cheats.lua` | cheat machine in `doom/game.py` |
| `am_map.lua` | `doom/am_map.py` |
| `finale.lua` | `doom/finale.py` |
| `saveg.lua` | `doom/saveg.py` |
| `main.lua` | the Python entry |

---

## Lineage

1. **[python_doom](https://github.com/vagucs/python_doom)** — Python + pygame
2. **[lua_doom](https://github.com/vagucs/lua_doom)** — Lua 5.4 and LuaJIT + SDL2 (this tree)

---

## Donate

### GitHub Sponsors

[github.com/sponsors/vagucs](https://github.com/sponsors/vagucs)

### Ethereum

`0x1b64038A2b1DB73ABd0068d8B9B0d1dC5a90C5F1`

![Ethereum QR Code](docs/qr-ethereum.png)

### PIX

Key: `vagucs@bol.com.br`

![PIX QR Code](docs/qr-pix.png)
