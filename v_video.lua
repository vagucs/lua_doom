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
-- V_DrawPatch. Framebuffer is a 1-based table of palette indexes.
-- Patch offsets stay 0-based, like v_video.py.

local M = {}

M.SCREENWIDTH = 320
M.SCREENHEIGHT = 200
M.PIXELS = 320 * 200

local unpack = unpack or table.unpack

local function i16(data, off)
  local b1, b2 = data:byte(off + 1, off + 2)
  local v = b1 + b2 * 256
  if v >= 32768 then
    v = v - 65536
  end
  return v
end

local function u32(data, off)
  local b1, b2, b3, b4 = data:byte(off + 1, off + 4)
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

function M.patch_size(patch)
  return i16(patch, 0), i16(patch, 2), i16(patch, 4), i16(patch, 6)
end

function M.new_fb()
  local bytes = {}
  for i = 1, M.PIXELS do
    bytes[i] = 0
  end
  return bytes
end

function M.fill(fb, color)
  color = color or 0
  for i = 1, #fb do
    fb[i] = color
  end
end

function M.draw_patch(fb, x, y, patch, flipped)
  local w, h, left, top = M.patch_size(patch)
  x = x - left
  y = y - top
  local desttop = y * M.SCREENWIDTH + x
  local plen = #patch
  for col = 0, w - 1 do
    local src_col = col
    if flipped then
      src_col = w - 1 - col
    end
    local column = u32(patch, 8 + src_col * 4)
    while column < plen do
      local topdelta = patch:byte(column + 1)
      if topdelta == 255 then
        break
      end
      local length = patch:byte(column + 2)
      local source = column + 3
      local dest = desttop + topdelta * M.SCREENWIDTH
      for _ = 1, length do
        if dest >= 0 and dest < M.PIXELS and source < plen then
          fb[dest + 1] = patch:byte(source + 1)
        end
        source = source + 1
        dest = dest + M.SCREENWIDTH
      end
      column = column + length + 4
    end
    desttop = desttop + 1
  end
end

function M.plot(fb, x, y, color)
  x = math.floor(x)
  y = math.floor(y)
  if x < 0 or y < 0 or x >= M.SCREENWIDTH or y >= M.SCREENHEIGHT then
    return
  end
  fb[y * M.SCREENWIDTH + x + 1] = color
end

function M.draw_line(fb, x0, y0, x1, y1, color)
  x0 = math.floor(x0 + 0.5)
  y0 = math.floor(y0 + 0.5)
  x1 = math.floor(x1 + 0.5)
  y1 = math.floor(y1 + 0.5)
  local dx = math.abs(x1 - x0)
  local dy = math.abs(y1 - y0)
  local sx = 1
  local sy = 1
  if x0 >= x1 then
    sx = -1
  end
  if y0 >= y1 then
    sy = -1
  end
  local err = dx - dy
  local guard = dx + dy + 1
  while guard > 0 do
    M.plot(fb, x0, y0, color)
    if x0 == x1 and y0 == y1 then
      return
    end
    local e2 = err * 2
    if e2 > -dy then
      err = err - dy
      x0 = x0 + sx
    end
    if e2 < dx then
      err = err + dx
      y0 = y0 + sy
    end
    guard = guard - 1
  end
end

function M.to_raw(fb)
  local parts = {}
  local n = 0
  local i = 1
  while i <= #fb do
    local last = i + 4095
    if last > #fb then
      last = #fb
    end
    n = n + 1
    parts[n] = string.char(unpack(fb, i, last))
    i = last + 1
  end
  return table.concat(parts)
end

return M
