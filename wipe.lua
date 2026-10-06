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
-- Derretimento da tela. O quadro velho escorre e o novo entra por cima.

local SCREENWIDTH = 320
local SCREENHEIGHT = 200
local COLW = SCREENWIDTH / 2

local M = {}

local function copy_span(dst, src, x0, y0, y1, src_y0)
  local rows = y1 - y0
  for row = 0, rows - 1 do
    local s = (src_y0 + row) * SCREENWIDTH + x0 + 1
    local d = (y0 + row) * SCREENWIDTH + x0 + 1
    dst[d] = src[s]
    dst[d + 1] = src[s + 1]
  end
end

local function clone_fb(fb)
  local out = {}
  for i = 1, #fb do
    out[i] = fb[i]
  end
  return out
end

function M.new()
  return {
    start = {},
    endfb = {},
    y = {},
    active = false,
  }
end

function M.capture_start(self, fb)
  self.start = clone_fb(fb)
end

function M.capture_end(self, fb)
  self.endfb = clone_fb(fb)
end

function M.begin(self, fb, rand)
  rand = rand or function(n)
    return math.random(0, n - 1)
  end
  for i = 1, #self.start do
    fb[i] = self.start[i]
  end
  local y = {}
  y[0] = -rand(16)
  for i = 1, COLW - 1 do
    local ny = y[i - 1] + rand(3) - 1
    if ny > 0 then
      ny = 0
    elseif ny == -16 then
      ny = -15
    end
    y[i] = ny
  end
  self.y = y
  self.active = true
end

function M.tick(self, tics, fb)
  local h = SCREENHEIGHT
  local done = true
  local steps = tics
  if steps < 1 then
    steps = 1
  end
  for _ = 1, steps do
    for i = 0, COLW - 1 do
      local yi = self.y[i]
      local x0 = i * 2
      if yi < 0 then
        copy_span(fb, self.start, x0, 0, h, 0)
        self.y[i] = yi + 1
        done = false
      elseif yi < h then
        local dy = 8
        if yi < 16 then
          dy = yi + 1
        end
        if yi + dy > h then
          dy = h - yi
        end
        copy_span(fb, self.endfb, x0, yi, yi + dy, yi)
        yi = yi + dy
        self.y[i] = yi
        local rem = h - yi
        if rem > 0 then
          copy_span(fb, self.start, x0, yi, h, 0)
        end
        done = false
      end
    end
  end
  if done then
    for i = 1, #self.endfb do
      fb[i] = self.endfb[i]
    end
    self.active = false
  end
  return done
end

return M
