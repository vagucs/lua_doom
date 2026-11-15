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
-- Teste de texturas e flats. Sem janela.

local wad = require("wad")
local rdata = require("r_data")

local function eq(name, got, want)
  if got ~= want then
    error(name .. " got " .. tostring(got) .. " want " .. tostring(want))
  end
end

local w = wad.new()
wad.add_file(w, wad.find_iwad())
local res = rdata.new(w)
rdata.init(res)

eq("ntex", #res.textures, 125)
eq("nflats", #res.flattranslation, 56)
local t0 = res.textures[1]
eq("name0", t0.name, "AASTINKY")
eq("w0", t0.width, 24)
eq("h0", t0.height, 72)
eq("mask0", t0.widthmask, 15)
eq("patches0", #t0.patches, 2)
eq("STARTAN2", rdata.texture_num_for_name(res, "STARTAN2"), 69)
eq("BROWN1", rdata.texture_num_for_name(res, "BROWN1"), 14)
eq("dash", rdata.texture_num_for_name(res, "-"), 0)
eq("missing", rdata.texture_num_for_name(res, "NOTEX"), 0)
eq("noflat", rdata.flat_num_for_name(res, "NOFLAT"), 0)

local start = res.textures[70]
eq("sw", start.width, 128)
eq("smask", start.widthmask, 127)
eq("slump", start.col_lump[1], 1117)
eq("sofs", start.col_ofs[1], 136)
local col = rdata.get_column(res, 69, 0)
eq("clen", #col, 128)
eq("c0", col:byte(1), 143)
eq("c64", col:byte(65), 141)
local posts = rdata.column_posts(res, 69, 0)
eq("ptop", posts[1].topdelta, 0)
eq("p0", posts[1].pixels:byte(1), 143)

eq("big", res.textures[2].name, "BIGDOOR1")
local big = rdata.get_column(res, 1, 0)
eq("blen", #big, 128)
eq("b0", big:byte(1), 107)
eq("b10", big:byte(11), 104)
local bposts = rdata.column_posts(res, 1, 3)
eq("btop", bposts[1].topdelta, 0)
eq("bplen", #bposts[1].pixels, 96)
eq("bp0", bposts[1].pixels:byte(1), 107)

eq("FLOOR4_8", rdata.flat_num_for_name(res, "FLOOR4_8"), 10)
eq("skyflat", res.skyflatnum, 54)
eq("skytex", res.skytexture, 59)
local flat = rdata.flat_pixels(res, 10)
eq("flen", #flat, 4096)
eq("fcenter", flat:byte(32 * 64 + 32 + 1), 1)
eq("theight", rdata.texture_height(res, 69), 8388608)
eq("twidth", rdata.texture_width(res, 69), 128)
eq("cmap", #res.colormaps, 8704)
local cm0 = rdata.colormap(res, 0)
eq("cm0", #cm0, 256)
eq("cm0a", cm0:byte(1), 0)
eq("cm0b", cm0:byte(256), 255)
eq("cm32", rdata.colormap(res, 32):byte(1), 4)

print("r_data ok texturas " .. #res.textures .. " flats " .. #res.flattranslation)
