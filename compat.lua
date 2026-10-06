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
-- 32-bit wrap, shifts and 16.16 fixed-point.
-- Same source on Lua 5.4 and LuaJIT. Bitwise operators stay inside load()
-- so LuaJIT never parses them. fixed_mul splits into 16-bit halves because
-- a LuaJIT double cannot hold the 64-bit product.

local M = {}

M.FRACBITS = 16
M.FRACUNIT = 65536

local MASK32 = 4294967296
local SIGN32 = 2147483648
local MAXINT = 2147483647
local MININT = -2147483648

local function trunc_int(n)
  if n >= 0 then
    return math.floor(n)
  end
  return math.ceil(n)
end

function M.as_u32(n)
  n = trunc_int(n)
  n = n % MASK32
  if n < 0 then
    n = n + MASK32
  end
  return n
end

function M.as_i32(n)
  n = M.as_u32(n)
  if n >= SIGN32 then
    n = n - MASK32
  end
  return n
end

function M.ushr(n, bits)
  n = M.as_u32(n)
  bits = bits or 0
  if bits <= 0 then
    return n
  end
  if bits >= 32 then
    return 0
  end
  return math.floor(n / (2 ^ bits))
end

function M.shar(n, bits)
  n = M.as_i32(n)
  bits = bits or 0
  if bits <= 0 then
    return n
  end
  if bits >= 31 then
    if n < 0 then
      return -1
    end
    return 0
  end
  if n >= 0 then
    return math.floor(n / (2 ^ bits))
  end
  local d = 2 ^ bits
  return -math.floor((-n + d - 1) / d)
end

local function div_rem(r, d)
  local q = math.floor(r / d)
  local prod = q * d
  if prod > r then
    q = q - 1
    prod = prod - d
  elseif r - prod >= d then
    q = q + 1
    prod = prod + d
  end
  return q, r - prod
end

-- floor(n / d) for a 48-bit numerator. Matches Python //.
local function floor_div(n, d)
  local neg = false
  if n < 0 then
    n = -n
    neg = not neg
  end
  if d < 0 then
    d = -d
    neg = not neg
  end
  local n0 = n % 65536
  local rest = (n - n0) / 65536
  local n1 = rest % 65536
  local n2 = (rest - n1) / 65536
  local q2, r = div_rem(n2, d)
  local q1
  q1, r = div_rem(r * 65536 + n1, d)
  local q0, rem = div_rem(r * 65536 + n0, d)
  local q = q2 * MASK32 + q1 * 65536 + q0
  if neg then
    if rem ~= 0 then
      q = q + 1
    end
    q = -q
  end
  return q
end

function M.fixed_mul(a, b)
  a = M.as_i32(a)
  b = M.as_i32(b)
  local function parts(n)
    local u = M.as_u32(n)
    local lo = u % 65536
    local hi = (u - lo) / 65536
    if hi >= 32768 then
      hi = hi - 65536
    end
    return hi, lo
  end
  local ah, al = parts(a)
  local bh, bl = parts(b)
  local low = math.floor((al * bl) / 65536)
  return M.as_i32(ah * bh * 65536 + ah * bl + al * bh + low)
end

function M.fixed_div(a, b)
  a = M.as_i32(a)
  b = M.as_i32(b)
  if b == 0 then
    if a >= 0 then
      return MAXINT
    end
    return MININT
  end
  local abs_a = a < 0 and -a or a
  local abs_b = b < 0 and -b or b
  if M.ushr(abs_a, 14) >= abs_b then
    if (a < 0) == (b < 0) then
      return MAXINT
    end
    return MININT
  end
  return M.as_i32(floor_div(a * 65536, b))
end

function M.abs_fixed(n)
  n = M.as_i32(n)
  if n < 0 then
    return -n
  end
  return n
end

local band, bor, bxor, bnot, shl

if rawget(_G, "jit") then
  local bit = require("bit")
  local function u(n)
    return M.as_u32(bit.tobit(n))
  end
  band = function(a, b)
    return u(bit.band(a, b))
  end
  bor = function(a, b)
    return u(bit.bor(a, b))
  end
  bxor = function(a, b)
    return u(bit.bxor(a, b))
  end
  bnot = function(a)
    return u(bit.bnot(a))
  end
  shl = function(a, bits)
    return u(bit.lshift(a, bits))
  end
else
  local chunk = assert(load([[
    local MASK32 = 4294967296
    local function u32(n)
      if n >= 0 then
        n = math.floor(n)
      else
        n = math.ceil(n)
      end
      n = n % MASK32
      if n < 0 then
        n = n + MASK32
      end
      return n
    end
    return function(a, b) return u32(u32(a) & u32(b)) end,
           function(a, b) return u32(u32(a) | u32(b)) end,
           function(a, b) return u32(u32(a) ~ u32(b)) end,
           function(a) return u32(~u32(a)) end,
           function(a, bits) return u32(u32(a) << bits) end
  ]], "compat_ops"))
  band, bor, bxor, bnot, shl = chunk()
end

function M.band(a, b)
  return band(a, b)
end

function M.bor(a, b)
  return bor(a, b)
end

function M.bxor(a, b)
  return bxor(a, b)
end

function M.bnot(a)
  return bnot(a)
end

function M.shl(a, bits)
  bits = bits or 0
  if bits <= 0 then
    return M.as_u32(a)
  end
  if bits >= 32 then
    return 0
  end
  return shl(a, bits)
end

return M
