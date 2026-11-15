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
-- Teste de compat.lua. Sem janela.

local C = require("compat")
local F = C.FRACUNIT

local function eq(name, got, want)
  if got ~= want then
    error(name .. " got " .. tostring(got) .. " want " .. tostring(want))
  end
end

eq("u-1", C.as_u32(-1), 4294967295)
eq("i800", C.as_i32(2147483648), -2147483648)
eq("iff", C.as_i32(4294967295), -1)
eq("ushr", C.ushr(2147483648, 1), 1073741824)
eq("ushr32", C.ushr(4294967295, 32), 0)
eq("shar-5", C.shar(-5, 1), -3)
eq("shar-4", C.shar(-4, 1), -2)
eq("sharhi", C.shar(2147483648, 1), -1073741824)
eq("shar31", C.shar(-2, 31), -1)
eq("fm1", C.fixed_mul(F, F), 65536)
eq("fm6", C.fixed_mul(2 * F, 3 * F), 393216)
eq("fmneg", C.fixed_mul(-2 * F, 3 * F), -393216)
eq("fmm1", C.fixed_mul(-1, F), -1)
eq("fmmm", C.fixed_mul(-1, -1), 0)
eq("fmbig", C.fixed_mul(2147483647, 2147483647), -65536)
eq("fd2", C.fixed_div(F, 2), 2147483647)
eq("fdhalf", C.fixed_div(F, 2 * F), 32768)
eq("fdnhalf", C.fixed_div(-F, 2 * F), -32768)
eq("fdn3", C.fixed_div(-1, 3), -21846)
eq("fd0", C.fixed_div(1, 0), 2147483647)
eq("fdn0", C.fixed_div(-1, 0), -2147483648)
eq("fdsat", C.fixed_div(1073741824, F), 2147483647)
eq("fdns", C.fixed_div(-1073741824, F), -2147483648)
eq("band", C.band(0xFF00, 0x0FF0), 0x0F00)
eq("bor", C.bor(0xFF00, 0x0FF0), 0xFFF0)
eq("bxor", C.bxor(0xFF00, 0x0FF0), 0xF0F0)
eq("bnot", C.bnot(0), 4294967295)
eq("bandhi", C.band(2147483648, 2147483648), 2147483648)
eq("shl31", C.shl(1, 31), 2147483648)
eq("shl32", C.shl(1, 32), 0)
eq("abs", C.abs_fixed(-F), F)

print("compat ok")
