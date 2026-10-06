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

The same source runs on PUC-Rio Lua 5.4 and on LuaJIT. The game loop, the map, and the renderer stay in Lua. SDL2 sits behind one API. LuaJIT calls `SDL2.dll` through the FFI. Lua 5.4 uses a small C bridge (`src/video_c.c`).

Versão em português: [README.pt.md](README.pt.md)

---

## How to run

Tools, already installed on MSYS2 UCRT64:

| Runtime | Executable |
| --- | --- |
| Lua 5.4.9 (PUC-Rio) | `C:\msys64\ucrt64\bin\lua5.4.exe` |
| LuaJIT 2.1 | `C:\msys64\ucrt64\bin\luajit.exe` |
| SDL2 | `C:\msys64\ucrt64\bin\SDL2.dll` |

```
run.bat
run.bat jit
```

`run.bat` opens the window with Lua 5.4. `run.bat jit` opens the same scene with LuaJIT. Extra arguments are forwarded: `run.bat -warp 1 1 -skill 2` and `run.bat jit -warp 1 1`. The title plays music. Esc or Enter opens the menu. Choosing a skill opens the view, without a melt, and the level music loops. The bottom bar shows health, ammo, weapons, keys, and the face. Arrows walk and turn, Shift runs, Ctrl fires, Space uses. The mouse looks and the left button fires. `-` and `=` change the view size; on the automap they zoom. Tab opens the map, `f` follows the player, `g` toggles the grid, `0` shows the whole map. A shot, a door, and a monster play their sounds. Enemies look, chase, and fall. A key on the floor opens the locked door. The exit switch melts into the tally and then the next map. At the end of the episode the text scrolls on the flat and, on Enter, returns to the title. Save and Load use `doomsav0.dsg` through `doomsav5.dsg`, next to the IWAD. The cheats are the usual ones: `iddqd`, `idkfa`, `idfa`, `idclip`, `idspispopd`, `iddt`, `idbehold`, `idchoppers`, `idmypos`, `idclev`, and `idmus`. `-fps` prints the frame rate, `-crt` turns on the tube. Quit is the menu item, or closing the window. Rebuild the bridge, only when `src\video_c.c` changes, with `build_video.bat`.

The engine is written in the common dialect (Lua 5.1). No `//`, no `&` `|` `<<` `>>`, and no `ffi` outside `video_ffi.lua`. WAD, BSP, and menu indexes stay 0-based in the data and are read with `+ 1`.

Each phase below depends on the one before it. The reference code is `python_doom/doom/`.

## Phases

1. **Compat.** Done. `compat.lua` follows `compat.py`. `fixed_mul` splits into 16-bit halves. `band` / `bor` / `bxor` / `shl` use `bit.*` on LuaJIT and the Lua 5.4 operators, loaded with `load` so LuaJIT never parses that text. Both executables pass `test_compat.lua`.

2. **WAD.** Done. `wad.lua` follows `wad.py`. Lump numbers stay 0-based. `PLAYPAL` (10752 bytes) and `TITLEPIC` (68168) come out of `DOOM1.WAD` on both executables, through `test_wad.lua`. No window.

3. **Window.** Done. `video.lua` picks the backend. `video_ffi.lua` on LuaJIT. `src/video_c.c` on Lua 5.4, as `video_c.dll`. Both open 640×400, stretch the 320×200 framebuffer, and read the keyboard. Esc closes.

4. **Title.** Done. `v_video.lua` follows `v_video.py`. `run.bat` shows `TITLEPIC` with the first `PLAYPAL`.

5. **Loop and menu.** Done. `main.lua` accumulates `SDL_GetTicks` and ticks the menu at 35 Hz. `menu.lua` follows `menu.py`. Esc or Enter opens it. Arrows, Enter, and Backspace navigate. On the shareware IWAD the episode menu appears even without `E2M1`; episodes 2 through 4 show the registered-version message. The chosen skill writes `EPISODIO n SKILL n` and does not enter the map yet. Sound stays silent until phase 12. Both executables pass `test_menu.lua`.

6. **Map.** Done. `world.lua` follows `world.py`. `E1M1` comes out with 467 vertices, 475 lines, 732 segs, 236 nodes, a 36×23 blockmap, and a 904-byte reject, matching Python. Choosing a skill clears the menu and draws the lines from above, with the player arrow. Texture names are stored; the numbers arrive in phase 7. Both executables pass `test_world.lua`.

7. **Textures.** Done. `r_data.lua` follows `r_data.py`. The shareware IWAD has 125 textures and 56 flats. `STARTAN2` is texture 69, `FLOOR4_8` is flat 10, `COLORMAP` is 8704 bytes. The composite column of `BIGDOOR1` matches Python. The overhead map paints each line with the most common color of the wall texture, or of the floor flat when the line has no texture. Sprites wait for the 3D view. Both executables pass `test_r_data.lua`.

8. **View.** Done. `render.lua` follows `render.py`, `tables.lua` follows `tables.py`, and `sprites.lua` follows the drawing in `sprites.py`. On `E1M1`, standing at the player start on medium skill, the 320×200 framebuffer matches Python: 34 walls, 100 planes, 91 things. The bottom band stays empty, where the status bar will go. Walking waits for phase 9. Both executables pass `test_view.lua`.

9. **Player.** Done. `player.lua` follows `player.py` and `collision.lua` follows movement, use, and hitscan from `collision.py`. On `E1M1`, 35 tics walking forward stop at the same point as Python, at the same speed. The pistol rises in front of the view and that frame matches Python. Ctrl spends one clip and the hitscan deals the same damage. Doors open in phase 10. Both executables pass `test_player.lua`.

10. **Sectors.** Done. `specials.lua` follows `specials.py`. On `E1M1`, the first door rises from 0 to 3932160 in 30 tics, the lights match Python, and the exit switch changes texture 100 to 119. The exit draws `WIMAP0` and, on Enter or after four seconds, enters the next map with health and weapons kept. The tally and the melt wait for phase 13. A key on the floor opens the locked door. Both executables pass `test_specials.lua`.

11. **Enemies.** Done. `enemy.lua` follows `enemy.py` and `thinker.lua` follows `thinker.py`. On `E1M1`, after 20 tics standing still, the monsters are in the same place and the same frame as Python. A dead zombie falls on `POSS` frame 12, at height 917504. The rocket, the plasma, and the BFG leave the weapon. Sound is still silent. Both executables pass `test_enemy.lua`.

12. **Sound.** Done. `sound.lua` follows `sound.py` and `mus2mid.lua` follows `mus2mid.py`. `D_E1M1` becomes the same MIDI as Python, 23334 bytes. `DSPISTOL` becomes the same 5629 samples. The bridge queues PCM at 11025 Hz and MIDI goes out through the Windows MCI. The title plays `D_INTROA` on the shareware IWAD. `E1M1` loops `D_E1M1`. A shot, a door, and a monster play `DS*`. If the device does not open, the game stays silent. Both executables pass `test_sound.lua`.

13. **Status bar, intermission, and melt.** Done. `status.lua` follows `status.py`, `wi_stuff.lua` follows `wi_stuff.py`, and `wipe.lua` follows `wipe.py`. The bottom band shows health, ammo, weapons, keys, and the face, in the same drawing as Python. Leaving a level melts into the tally: kills, items, secrets, time, and par. Enter, Space, or Ctrl speed it up and continue to the next map, which also melts. Starting a new game from the title does not melt. The tally music is `D_INTER`. Both executables pass `test_hud.lua`.

14. **The rest of python_doom.** Done. `am_map.lua` follows `am_map.py`, `finale.lua` follows `finale.py`, `saveg.lua` follows `saveg.py`, and `cheats.lua` follows the cheats in `game.py`. Tab opens the automap. Shareware map 8 writes `E1TEXT` on `FLOOR4_8` and melts into the art. Save and load write `doomsavN.dsg` with the `DOOMPY01` header. The mouse feeds `ticcmd`. `-warp`, `-skill`, `-file`, `-iwad`, `-nomonsters`, `-fast`, `-respawn`, `-nosound`, `-nomusic`, `-fps`, and `-crt` come from `game.py`. `-` and `=` change the view size. Both executables pass `test_phase14.lua`.

Left out of the `python_doom` cut: network, joystick, CD audio.

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
