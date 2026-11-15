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
-- MUS do E1M1 e o tiro da pistola batem com o Python. Nao abre janela.

local wad = require("wad")
local mus2mid = require("mus2mid")
local sound = require("sound")

local function sum_bytes(s)
  local n = 0
  for i = 1, #s do
    n = n + s:byte(i)
  end
  return n
end

local function sum_samples(samples)
  local n = 0
  for i = 1, #samples do
    n = n + samples[i]
  end
  return n
end

local same = mus2mid.mus2mid("MThdxyz")
assert(same == "MThdxyz", "MThd passa direto")
assert(mus2mid.mus2mid("MUS") == nil, "MUS curto")
assert(sound.decode("\3\0\1\0\1\0\0\0", 11025, 1) == nil, "DS curto")

local w = wad.new()
wad.add_file(w, wad.find_iwad())
local mid = mus2mid.mus2mid(wad.cache_lump_name(w, "D_E1M1"))
assert(mid ~= nil, "D_E1M1")
assert(#mid == 23334, "tamanho " .. tostring(#mid))
assert(sum_bytes(mid) == 1468394, "soma " .. tostring(sum_bytes(mid)))
assert(mid:sub(1, 4) == "MThd", "cabecalho")
assert(mid:sub(-8) == "\0\129\51\0\0\255\47\0", "fim")

local samples = sound.decode(wad.cache_lump_name(w, "DSPISTOL"), 11025, 1)
assert(samples ~= nil, "DSPISTOL")
assert(#samples == 5629, "amostras " .. tostring(#samples))
assert(samples[1] == -512 and samples[#samples] == -512, "pontas")
assert(sum_samples(samples) == -2625024, "soma ds " .. tostring(sum_samples(samples)))

print("som ok midi 23334 pistol 5629")
