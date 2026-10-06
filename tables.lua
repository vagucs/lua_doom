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
-- finesine, finetangent e tantoangle, a partir de tables.py.

local compat = require("compat")

local M = {}

local FINEANGLES = 8192
local FINEMASK = 8191
local ANGLETOFINESHIFT = 19
local FRACUNIT = 65536
local SLOPERANGE = 2048
local ANG90 = 1073741824
local DBITS = 5

local function trunc(n)
  if n >= 0 then
    return math.floor(n)
  end
  return math.ceil(n)
end

local function idiv(n, d)
  if d == 0 then
    return 0
  end
  return math.floor(n / d)
end

M.finesine = {}
M.finetangent = {}
M.tantoangle = {}
local ready = false

function M.init()
  if ready then
    return
  end
  local nsin = idiv(FINEANGLES, 4) * 5
  for i = 0, nsin - 1 do
    local a = (i + 0.5) * math.pi * 2 / FINEANGLES
    M.finesine[i] = trunc(FRACUNIT * math.sin(a))
  end
  local half = idiv(FINEANGLES, 2)
  local quarter = idiv(FINEANGLES, 4)
  for i = 0, half - 1 do
    local a = (i - quarter + 0.5) * math.pi * 2 / FINEANGLES
    local v = FRACUNIT * math.tan(a)
    if v ~= v or v == math.huge or v == -math.huge then
      if a > 0 then
        v = 2147483647
      else
        v = -2147483647
      end
    else
      v = trunc(v)
      if v > 2147483647 then
        v = 2147483647
      elseif v < -2147483647 then
        v = -2147483647
      end
    end
    M.finetangent[i] = v
  end
  for i = 0, SLOPERANGE do
    local ang = math.atan(i / SLOPERANGE) / (math.pi * 2) * 4294967295
    M.tantoangle[i] = compat.as_u32(trunc(ang))
  end
  ready = true
end

function M.fine_sin(angle)
  local i = compat.band(compat.ushr(compat.as_u32(angle), ANGLETOFINESHIFT), FINEMASK)
  return M.finesine[i]
end

function M.fine_cos(angle)
  local i = compat.band(compat.ushr(compat.as_u32(angle), ANGLETOFINESHIFT) + idiv(FINEANGLES, 4), FINEMASK)
  return M.finesine[i]
end

function M.slope_div(num, den)
  if den < 512 then
    return SLOPERANGE
  end
  local ans = idiv(num * 8, compat.ushr(den, 8))
  if ans > SLOPERANGE then
    return SLOPERANGE
  end
  return ans
end

M.ANG90 = ANG90
M.DBITS = DBITS
M.FINEANGLES = FINEANGLES
M.FINEMASK = FINEMASK

return M
