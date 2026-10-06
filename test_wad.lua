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
-- Teste de wad.lua. Sem janela.

local W = require("wad")

local path = W.find_iwad()
local wad = W.new()
W.add_file(wad, path)

local pal_num = W.get_num_for_name(wad, "playpal")
local title_num = W.get_num_for_name(wad, "TITLEPIC")
local pal = W.cache_lump_name(wad, "PLAYPAL")
local title = W.cache_lump_num(wad, title_num)

if #pal < 768 or #pal ~= W.lump_length(wad, pal_num) then
  error("PLAYPAL size " .. tostring(#pal))
end
if #title < 8 or #title ~= W.lump_length(wad, title_num) then
  error("TITLEPIC size " .. tostring(#title))
end
if W.cache_lump_name(wad, "PLAYPAL") ~= pal then
  error("cache miss")
end
if W.check_num_for_name(wad, "NO_SUCH_LUMP") ~= -1 then
  error("missing lump should be -1")
end
if W.num_lumps(wad) < 1 or W.lump_name(wad, 0) == "" then
  error("empty directory")
end

print("wad ok " .. path .. " lumps " .. W.num_lumps(wad) .. " pal " .. #pal .. " title " .. #title)
