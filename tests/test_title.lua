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
-- Teste do titulo. Sem janela.

local wad = require("wad")
local v = require("v_video")

local w = wad.new()
wad.add_file(w, wad.find_iwad())
local pal = wad.cache_lump_name(w, "PLAYPAL")
local title = wad.cache_lump_name(w, "TITLEPIC")
if #pal < 768 then
  error("PLAYPAL curta")
end

local width, height = v.patch_size(title)
if width ~= 320 or height ~= 200 then
  error("TITLEPIC " .. tostring(width) .. "x" .. tostring(height))
end

local fb = v.new_fb()
v.draw_patch(fb, 0, 0, title)
local ink = 0
for i = 1, #fb do
  if fb[i] ~= 0 then
    ink = ink + 1
  end
end
if ink < 10000 then
  error("titulo vazio " .. tostring(ink))
end

local raw = v.to_raw(fb)
if #raw ~= v.PIXELS then
  error("framebuffer " .. tostring(#raw))
end

print("title ok " .. width .. "x" .. height .. " ink " .. ink)
