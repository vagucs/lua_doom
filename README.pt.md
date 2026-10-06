# lua_doom

![DOOM rodando em Lua com SDL2](screenshot/doom.png)

**Vídeo:** [DOOM rodando em Lua](https://youtu.be/4OYTretHKtY)

DOOM generic portado de **[python_doom](https://github.com/vagucs/python_doom)** para **Lua 5.4 e LuaJIT + SDL2**.

Por **Wagner Nunes da Silva**

- vagucs@bol.com.br
- vagucs@vagucs.com.br
- vagucs@gmail.com
- [www.vagucs.com.br](https://www.vagucs.com.br)
- [LinkedIn](https://www.linkedin.com/in/wagner-nunes-da-silva-b0a15360)

Esta árvore é aquele motor em Python, agora em Lua. O mesmo fonte roda no Lua 5.4 da PUC-Rio e no LuaJIT. O laço, o mapa e o renderer ficam em Lua. A SDL2 fica atrás de uma API só. O LuaJIT chama a `SDL2.dll` pela FFI. O Lua 5.4 usa uma ponte pequena em C (`src/video_c.c`). O MCI do Windows toca o MIDI, porque a SDL2 não toca.

English version: [README.md](README.md)

---

## O que é este projeto

`python_doom` é um motor de DOOM condensado e jogável, em Python. Este diretório é a **mesma peça de estudo**, reescrita em Lua:

- Janela, teclas, rato, PCM: **SDL2**, uma API para os dois runtimes
- Framebuffer: 320×200, um índice da PLAYPAL por posição, esticado numa janela de 640×400
- Tic: 35 Hz (`TICRATE`). Cada quadro mostrado corre até 4 tics
- Renderer: BSP, visplanes, colunas, spans, sprites, o sprite da arma
- Mapa: VERTEXES, LINEDEFS, SIDEDEFS, SECTORS, SEGS, SSECTORS, NODES, THINGS, BLOCKMAP, REJECT
- Jogo: andar, portas, elevadores, interruptores, saída, itens, armas, barra, automapa no Tab, som `DS*`, música MUS→MIDI, menu no Esc, contagem, derretimento ao trocar de fase, inimigos que olham, perseguem e atacam, rato que olha

É preciso um IWAD legal (shareware `doom1.wad` ou comercial `doom.wad` / `doom2.wad`). Este repositório não traz WAD comercial.

É um **port educacional condensado**: o motor é Lua, a camada nativa é a SDL2.

Fora desta árvore:

- Rede, joystick, CD de áudio

---

## Proposta educacional

Este projeto é uma **peça de estudo**. O port em Python já tirou o pré-processador e os arrays 1-based do Harbour. O port em Lua pergunta outra coisa: **o que sobrevive quando o fonte tem de rodar no Lua 5.4 e no LuaJIT**, com tabelas 1-based e sem sintaxe de bit no dialeto comum.

O que ele pretende ensinar:

- **Python, depois Lua.** Abra `python_doom/doom/` ao lado de `lua_doom/`. Os nomes ficam perto (`thrust`, `fixed_mul`, `line_attack`) para os dois arquivos ficarem lado a lado.
- **Um dialeto, dois runtimes.** O motor é o subconjunto comum do Lua 5.1. Sem `//`, sem `&` `|` `<<` `>>` nos arquivos que o LuaJIT lê, e sem `ffi` fora de `video_ffi.lua`. `band` / `bor` / `bxor` / `shl` usam `bit.*` no LuaJIT e os operadores do Lua 5.4, carregados com `load`.
- **Leitura 1-based.** Lumps do WAD, nós da BSP, linhas do menu e colunas da tela continuam 0-based nos dados e são lidos com `+ 1`.
- **Onde o Lua basta.** Colunas, chão, sprites e thinkers rodam em Lua. A SDL2 é a janela, o teclado, o rato e a fila de PCM.

Caminho sugerido:

1. Rode `run.bat`, depois `run.bat jit`, e leia `main.lua` — arranque, tic, entrada.
2. Compare `compat.lua` com `python_doom/doom/compat.py`.
3. Abra `render.lua` ao lado de `python_doom/doom/render.py`.
4. Siga uma porta do **Espaço** (`use_lines` em `collision.lua`) até `specials.lua`.
5. Siga um tiro do **Ctrl** em `player.lua` até `spawn_player_missile` em `enemy.lua`.

---

## De Python para Lua

Listas em Python são 0-based. Tabelas do Lua usadas como array são 1-based. Lumps do WAD, nós da BSP, linhas do menu e faixas de clip continuam 0-based nos dados e são lidos com `+ 1`.

| Python (`python_doom`) | Lua (`lua_doom`) |
| --- | --- |
| `thing.x` | `thing.x` |
| `None` | `nil` |
| `items[0]` | `items[1]` |
| classe | tabela (referência compartilhada) |
| `int` sem limite | número do Lua; `as_u32` / `as_i32` devolvem o estouro de 32 bits |
| `&`, `\|`, `^` | `band` / `bor` / `bxor` (`bit.*`, ou os operadores do Lua 5.4 atrás de `load`) |
| `x >> n` | `ushr` / `shar` |
| `a // b` | `math.floor` |
| `fixed_mul` / `fixed_div` | `fixed_mul` / `fixed_div` |
| framebuffer `bytearray` | tabela de bytes, 64000 posições |
| pygame | SDL2: FFI no LuaJIT, `video_c.dll` no Lua 5.4 |
| `+=` | `x = x + ...` |

Uma tabela é uma referência, então escrever um campo aparece para quem chamou, do mesmo jeito que um objeto em Python.

### Lado a lado: `P_Thrust`

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

`.` continua `.`. Não há `+=`. `mo` é uma tabela, então o impulso novo fica no mobj que quem chamou já tem.

---

## Tecnologia

| Camada | Este port | Python (`python_doom`) |
| --- | --- | --- |
| Linguagem | Lua 5.4.9 e LuaJIT 2.1, um fonte só | Python 3.10+ |
| Janela, teclas, rato, PCM | SDL2. FFI em `video_ffi.lua`, ou `src/video_c.c` | pygame 2.x |
| Blit da paleta / CRT | Lua, depois a textura da SDL | numpy |
| MIDI (Windows) | winmm MCI | a mesma ideia, fora do pygame |
| IWAD | os mesmos lumps | os mesmos lumps |
| Build | nenhum no LuaJIT. `build_video.bat` só quando `src/video_c.c` muda | `pip install -r requirements.txt` |

O renderer é Lua. O arquivo em C é só a ponte do Lua 5.4.

---

## Como rodar

Ferramentas, no MSYS2 UCRT64:

| Runtime | Executável |
| --- | --- |
| Lua 5.4.9 (PUC-Rio) | `C:\msys64\ucrt64\bin\lua5.4.exe` |
| LuaJIT 2.1 | `C:\msys64\ucrt64\bin\luajit.exe` |
| SDL2 | `C:\msys64\ucrt64\bin\SDL2.dll` |

Neste diretório:

```
run.bat
run.bat jit
run.bat -warp 1 1 -skill 2
run.bat jit -fps -crt
```

`run.bat` abre a janela com o Lua 5.4. `run.bat jit` abre o mesmo jogo com o LuaJIT. A janela é 640×400. Sem `-crt`, a textura de 320×200 é esticada em nearest-neighbor.

---

## Teclas

Controles clássicos do DOOM.

### Movimento e ações

| Tecla | Ação |
| --- | --- |
| Setas | Frente, trás, virar |
| **Shift** | Correr |
| **Alt** | Andar de lado (segurar) |
| **Ctrl** ou botão esquerdo | Atirar |
| **Espaço** / **E** | Usar / abrir porta |
| Rato | Olhar |
| **Enter** / **Esc** | Menu |
| **Tab** | Automapa. **F** segue, **G** desenha a grade, **0** mostra o mapa inteiro |
| **-** / **=** | Zoom do automapa quando ele está aberto; senão, vista 3D menor / maior |
| **Alt+Enter** | Tela cheia |

Sair está no item do menu, ou no fechar da janela. **Y** confirma a saída.

### Truques

Digite durante a fase, com o menu fechado. Sem Enter. No pesadelo só **IDCLEV** e **IDDT** entram.

| Código | Efeito |
| --- | --- |
| **IDDQD** | Modo deus |
| **IDKFA** | Todas as armas, munição, chaves e armadura |
| **IDFA** | Armas, munição e armadura |
| **IDCLIP** / **IDSPISPOPD** | Sem colisão |
| **IDDT** | Automapa: todas as paredes, depois as coisas |
| **IDBEHOLD** | Power-ups; depois **V** **S** **I** **R** **A** **L** |
| **IDCHOPPERS** | Motosserra |
| **IDMYPOS** | Coordenadas e ângulo |
| **IDCLEV** + 2 dígitos | Warp (`11` = E1M1, ou MAP11 num IWAD comercial) |
| **IDMUS** + 2 dígitos | Troca a música |

---

## Parâmetros de linha de comando

### IWAD

| Parâmetro | Descrição |
| --- | --- |
| `-iwad file.wad` | IWAD a carregar |
| `file.wad` | A mesma coisa, sem `-iwad` |
| `-file wad [wad…]` | PWADs extras depois do IWAD |

### Vídeo

| Parâmetro | Descrição |
| --- | --- |
| `-crt` | Tubo de CRT, desenhado sobre a textura da SDL |
| `-fps` | Quadros por segundo. O jogo continua em 35 Hz |

### Jogo

| Parâmetro | Descrição |
| --- | --- |
| `-warp e m` | Pula o título e começa o episódio `e` mapa `m` |
| `-skill n` | Skill |
| `-nomonsters` | Não spawna inimigos |
| `-fast` | Monstros mais rápidos |
| `-respawn` | Respawn estilo pesadelo |
| `-nosound` | Sem efeitos |
| `-nomusic` | Sem MIDI |

Trocar de fase derrete a tela. Um jogo novo a partir do título não derrete. O mapa 8 do shareware escreve o `E1TEXT` em `FLOOR4_8`. Os saves vão de `doomsav0.dsg` a `doomsav5.dsg`, ao lado do IWAD, com o cabeçalho `DOOMPY01`.

---

## Estrutura

```
main.lua             entrada
run.bat              Lua 5.4, ou `jit` para o LuaJIT
video_ffi.lua        SDL2 pela FFI do LuaJIT
src/video_c.c        a mesma API para o Lua 5.4
build_video.bat      recompila essa ponte
screenshot/doom.png  a imagem do topo
```

| Caminho | Python |
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
| `cheats.lua` | a máquina de truques em `doom/game.py` |
| `am_map.lua` | `doom/am_map.py` |
| `finale.lua` | `doom/finale.py` |
| `saveg.lua` | `doom/saveg.py` |
| `main.lua` | a entrada do Python |

---

## Linhagem

1. **[python_doom](https://github.com/vagucs/python_doom)** — Python + pygame
2. **[lua_doom](https://github.com/vagucs/lua_doom)** — Lua 5.4 e LuaJIT + SDL2 (esta árvore)

---

## Doe

### Patrocínio no GitHub

[github.com/sponsors/vagucs](https://github.com/sponsors/vagucs)

### Ethereum

`0x1b64038A2b1DB73ABd0068d8B9B0d1dC5a90C5F1`

![QR Code Ethereum](docs/qr-ethereum.png)

### PIX

Chave: `vagucs@bol.com.br`

![QR Code PIX](docs/qr-pix.png)
