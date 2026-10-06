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
-- Teste do menu. Sem janela.

local wad = require("wad")
local v = require("v_video")
local menu_mod = require("menu")

local w = wad.new()
wad.add_file(w, wad.find_iwad())
local sound = { sfx_volume = 8, music_volume = 8 }
function sound.play() end
local game = {
  running = true,
  show_messages = true,
  detail_level = 0,
  screen_size = 7,
  mouse_sensitivity = 5,
  sound = sound,
  skill = 2,
  episode = 1,
  mapn = 1,
}
local menu = menu_mod.new(w, sound, game)
local fb = v.new_fb()

local function ink()
  local n = 0
  for i = 1, #fb do
    if fb[i] ~= 0 then
      n = n + 1
    end
  end
  return n
end

menu_mod.responder(menu, "return")
if not menu.active or menu.screen ~= "main" then
  error("enter nao abriu o menu")
end
menu_mod.draw(menu, fb)
if ink() < 1000 then
  error("menu principal sem patches")
end
menu_mod.responder(menu, "return")
if menu.screen ~= "episode" then
  error("novo jogo foi para " .. tostring(menu.screen))
end
menu_mod.responder(menu, "down")
menu_mod.responder(menu, "return")
if menu.screen ~= "read1" or menu.message == nil then
  error("episodio 2 deveria avisar a versao registrada")
end
menu_mod.responder(menu, "escape")
if menu.message ~= nil then
  error("aviso nao fechou")
end
menu_mod.responder(menu, "backspace")
if menu.screen ~= "main" then
  error("backspace foi para " .. tostring(menu.screen))
end

menu = menu_mod.new(w, sound, game)
menu_mod.responder(menu, "return")
menu_mod.responder(menu, "return")
menu_mod.responder(menu, "return")
if menu.screen ~= "skill" or menu.item_on ~= 2 then
  error("skill " .. tostring(menu.screen) .. " item " .. tostring(menu.item_on))
end
menu_mod.responder(menu, "return")
if game.episode ~= 1 or game.skill ~= 2 or game.mapn ~= 1 then
  error("escolha " .. tostring(game.episode) .. " " .. tostring(game.skill))
end
if menu.message == nil then
  error("sem aviso de skill")
end
menu_mod.draw(menu, fb)
if ink() < 20 then
  error("aviso de skill sem texto")
end
menu.message = nil
menu.screen = "options"
menu.item_on = 3
menu_mod.responder(menu, "down")
if menu.item_on ~= 5 then
  error("seta nao pulou o item vazio, ficou em " .. tostring(menu.item_on))
end
menu_mod.draw(menu, fb)
menu.screen = "sound"
menu_mod.draw(menu, fb)
menu.screen = "load"
menu_mod.draw(menu, fb)
menu.screen = "read1"
menu.message = nil
menu_mod.draw(menu, fb)
for _ = 1, 8 do
  menu_mod.ticker(menu)
end
if menu.which_skull ~= 1 then
  error("caveira nao animou")
end
print("menu ok episodio " .. game.episode .. " skill " .. game.skill)
