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
-- Vista, a partir de render.py. BSP, paredes, chao, teto e ceu.

local compat = require("compat")
local tables = require("tables")
local rdata = require("r_data")

local M = {}

local band, bor, bxor = compat.band, compat.bor, compat.bxor
local shl = compat.shl
local ushr, shar = compat.ushr, compat.shar
local as_i32, as_u32 = compat.as_i32, compat.as_u32
local fixed_mul, fixed_div = compat.fixed_mul, compat.fixed_div
local abs_fixed = compat.abs_fixed
local byte = string.byte

local FRACBITS = 16
local FRACUNIT = 65536
local SCREENWIDTH = 320
local SCREENHEIGHT = 200
local SBARHEIGHT = 32
local FINEANGLES = 8192
local FINEMASK = 8191
local ANGLETOFINESHIFT = 19
local ANG90 = 1073741824
local ANG180 = 2147483648
local FIELDOFVIEW = 2048
local LIGHTLEVELS = 16
local LIGHTZSHIFT = 20
local MAXLIGHTZ = 128
local LIGHTSCALESHIFT = 12
local MAXLIGHTSCALE = 48
local NUMCOLORMAPS = 32
local NF_SUBSECTOR = 32768
local ML_DONTPEGTOP = 8
local ML_DONTPEGBOTTOM = 16
local ML_MAPPED = 256
local SIL_NONE = 0
local SIL_TOP = 1
local SIL_BOTTOM = 2
local SIL_BOTH = 3
local HEIGHTBITS = 12
local HEIGHTUNIT = 4096
local ANGLETOSKYSHIFT = 22
local SHRT_MAX = 32767
local INT_MAX = 2147483647
local INT_MIN = -2147483647
local PIXELS = SCREENWIDTH * SCREENHEIGHT

local function idiv(n, d)
  if d == 0 then
    return 0
  end
  return math.floor(n / d)
end

local function lsh(n, bits)
  if bits <= 0 then
    return n
  end
  return n * (2 ^ bits)
end

local function span_tables()
  local top, bottom = {}, {}
  for i = 0, SCREENWIDTH - 1 do
    top[i] = 255
    bottom[i] = 0
  end
  return top, bottom
end

local function put(fb, dest, val)
  if dest >= 0 and dest < PIXELS then
    fb[dest + 1] = val
  end
end

local function draw_column(self)
  local count = self.dc_yh - self.dc_yl
  if count < 0 or self.dc_x < 0 or self.dc_x >= self.viewwidth then
    return
  end
  local yl = self.dc_yl
  if yl < 0 then
    yl = 0
  end
  if yl > SCREENHEIGHT - 1 then
    yl = SCREENHEIGHT - 1
  end
  local dest, dest2
  if self.detailshift ~= 0 then
    local x = shl(self.dc_x, 1)
    if x < 0 or x + 1 >= SCREENWIDTH then
      return
    end
    dest = self.ylookup[yl] + self.columnofs[x]
    dest2 = dest + 1
  else
    dest = self.ylookup[yl] + self.columnofs[self.dc_x]
    dest2 = nil
  end
  local fracstep = self.dc_iscale
  local frac = self.dc_texturemid + (self.dc_yl - self.centery) * fracstep
  local src = self.dc_source
  local slen = #src
  if slen == 0 then
    return
  end
  local cm = self.dc_colormap
  local cmlen = #cm
  local fb = self.fb
  while count >= 0 and dest < PIXELS do
    local idx = band(shar(frac, FRACBITS), 127)
    local pix = byte(src, (idx % slen) + 1)
    local val = pix
    if pix < cmlen then
      val = byte(cm, pix + 1)
    end
    fb[dest + 1] = val
    if dest2 and dest2 < PIXELS then
      fb[dest2 + 1] = val
    end
    dest = dest + SCREENWIDTH
    if dest2 then
      dest2 = dest2 + SCREENWIDTH
    end
    frac = as_i32(frac + fracstep)
    count = count - 1
  end
end

local function draw_masked_column(self, posts, sprtopscreen, spryscale, mceil, mfloor)
  local basemid = self.dc_texturemid
  for p = 1, #posts do
    local topdelta = posts[p].topdelta
    local post = posts[p]
    local pixels = post.pixels
    if #pixels > 0 then
      local topscreen = sprtopscreen + spryscale * topdelta
      local bottomscreen = topscreen + spryscale * #pixels
      local yl = shar(topscreen + FRACUNIT - 1, FRACBITS)
      local yh = shar(bottomscreen - 1, FRACBITS)
      if yh >= mfloor then
        yh = mfloor - 1
      end
      if yl <= mceil then
        yl = mceil + 1
      end
      if yl < 0 then
        yl = 0
      end
      if yh >= self.viewheight then
        yh = self.viewheight - 1
      end
      if yl <= yh then
        local src = post.col128
        if not src then
          src = pixels
          if #src < 128 then
            src = src .. string.rep("\0", 128 - #src)
          elseif #src > 128 then
            src = src:sub(1, 128)
          end
          post.col128 = src
        end
        self.dc_yl = yl
        self.dc_yh = yh
        self.dc_source = src
        self.dc_texturemid = basemid - shl(topdelta, FRACBITS)
        draw_column(self)
      end
    end
  end
  self.dc_texturemid = basemid
end

function M.render_masked_seg_range(self, ds, x1, x2)
  if not ds.maskedtexturecol or not ds.curline then
    return
  end
  local line = ds.curline
  local front = line.frontsector
  local back = line.backsector
  local sidedef = line.sidedef
  local texnum = 0
  if sidedef then
    texnum = sidedef.midtexture
  end
  if texnum == 0 or not back or not front then
    return
  end
  local lightnum = ushr(front.lightlevel, 4) + self.extralight
  if line.v1.y == line.v2.y then
    lightnum = lightnum - 1
  elseif line.v1.x == line.v2.x then
    lightnum = lightnum + 1
  end
  if lightnum < 0 then
    lightnum = 0
  end
  if lightnum > LIGHTLEVELS - 1 then
    lightnum = LIGHTLEVELS - 1
  end
  local walllights = self.scalelight[lightnum]
  local dc_texturemid
  if band(line.linedef.flags, ML_DONTPEGBOTTOM) ~= 0 then
    dc_texturemid = front.floorheight
    if back.floorheight > dc_texturemid then
      dc_texturemid = back.floorheight
    end
    dc_texturemid = dc_texturemid + rdata.texture_height(self.res, texnum) - self.viewz
  else
    dc_texturemid = front.ceilingheight
    if back.ceilingheight < dc_texturemid then
      dc_texturemid = back.ceilingheight
    end
    dc_texturemid = dc_texturemid - self.viewz
  end
  dc_texturemid = dc_texturemid + sidedef.rowoffset
  local spryscale = ds.scale1 + (x1 - ds.x1) * ds.scalestep
  for dc_x = x1, x2 do
    local i = dc_x - ds.x1
    local ncol = 0
    if ds.maskedtexturecol then
      ncol = ds.masked_count
    end
    if i < 0 or i >= ds.masked_count then
      spryscale = spryscale + ds.scalestep
    else
      local tcol = ds.maskedtexturecol[i]
      if tcol ~= SHRT_MAX then
        local index = 0
        if spryscale > 0 then
          index = ushr(spryscale, LIGHTSCALESHIFT)
        end
        if index >= MAXLIGHTSCALE then
          index = MAXLIGHTSCALE - 1
        end
        local level = walllights[index]
        if self.fixedcolormap then
          self.dc_colormap = self.fixedcolormap
        else
          self.dc_colormap = rdata.colormap(self.res, level)
        end
        self.dc_x = dc_x
        if spryscale ~= 0 then
          self.dc_iscale = idiv(4294967295, spryscale)
        else
          self.dc_iscale = 0
        end
        self.dc_texturemid = dc_texturemid
        local sprtopscreen = self.centeryfrac - fixed_mul(dc_texturemid, spryscale)
        local mceil = -1
        if ds.sprtopclip and i < ds.clip_count then
          mceil = ds.sprtopclip[i]
        end
        local mfloor = self.viewheight
        if ds.sprbottomclip and i < ds.clip_count then
          mfloor = ds.sprbottomclip[i]
        end
        local posts = rdata.column_posts(self.res, texnum, tcol)
        draw_masked_column(self, posts, sprtopscreen, spryscale, mceil, mfloor)
        ds.maskedtexturecol[i] = SHRT_MAX
      end
      spryscale = spryscale + ds.scalestep
    end
  end
end

function M.draw_masked(self)
  for n = #self.drawsegs, 1, -1 do
    local ds = self.drawsegs[n]
    if ds.maskedtexturecol then
      M.render_masked_seg_range(self, ds, ds.x1, ds.x2)
    end
  end
end

local function draw_planes(self)
  for p = 1, #self.visplanes do
    local pl = self.visplanes[p]
    if pl.minx <= pl.maxx then
      if pl.picnum == self.res.skyflatnum then
        self.dc_iscale = idiv(9 * FRACUNIT, 10)
        self.dc_colormap = rdata.colormap(self.res, 0)
        self.dc_texturemid = 100 * FRACUNIT
        for x = pl.minx, pl.maxx do
          local yl, yh = pl.top[x], pl.bottom[x]
          if yl <= yh and yl < 255 then
            local ang = ushr(as_u32(self.viewangle + self.xtoviewangle[x]), ANGLETOSKYSHIFT)
            self.dc_x = x
            self.dc_yl = yl
            self.dc_yh = yh
            self.dc_source = rdata.get_column(self.res, self.res.skytexture, ang)
            draw_column(self)
          end
        end
      else
        local light = ushr(pl.lightlevel, 4) + self.extralight
        if light < 0 then
          light = 0
        end
        if light > LIGHTLEVELS - 1 then
          light = LIGHTLEVELS - 1
        end
        local planezlight = self.zlight[light]
        local flat = rdata.flat_pixels(self.res, pl.picnum)
        local flatlen = #flat
        local planeheight = abs_fixed(pl.height - self.viewz)
        if planeheight ~= 0 then
          local cached_y = -1
          local light_index = -1
          local cm, cmlen
          local distance, ds_xstep, ds_ystep = 0, 0, 0
          local x0 = pl.minx
          if x0 < 0 then
            x0 = 0
          end
          local x1 = pl.maxx
          if x1 > self.viewwidth - 1 then
            x1 = self.viewwidth - 1
          end
          for x = x0, x1 do
            local t1, b1 = pl.top[x], pl.bottom[x]
            if t1 <= b1 and t1 ~= 255 then
              local y1 = b1
              if y1 > self.viewheight - 1 then
                y1 = self.viewheight - 1
              end
              for y = t1, y1 do
                if y ~= cached_y then
                  cached_y = y
                  distance = fixed_mul(planeheight, self.yslope[y])
                  ds_xstep = fixed_mul(distance, self.basexscale)
                  ds_ystep = fixed_mul(distance, self.baseyscale)
                end
                local length = fixed_mul(distance, self.distscale[x])
                local ang = band(ushr(as_u32(self.viewangle + self.xtoviewangle[x]), ANGLETOFINESHIFT), FINEMASK)
                local ds_xfrac = self.viewx + fixed_mul(tables.finesine[band(ang + idiv(FINEANGLES, 4), FINEMASK)], length)
                local ds_yfrac = -self.viewy - fixed_mul(tables.finesine[ang], length)
                local index = ushr(distance, LIGHTZSHIFT)
                if index > MAXLIGHTZ - 1 then
                  index = MAXLIGHTZ - 1
                end
                if index ~= light_index then
                  light_index = index
                  if self.fixedcolormap then
                    cm = self.fixedcolormap
                  else
                    cm = rdata.colormap(self.res, planezlight[index])
                  end
                  cmlen = #cm
                end
                local spot = bor(band(shar(ds_xfrac, 16), 63), band(shar(ds_yfrac, 10), 4032))
                local pix = 0
                if spot >= 0 and spot < flatlen then
                  pix = byte(flat, spot + 1)
                end
                local val = pix
                if pix < cmlen then
                  val = byte(cm, pix + 1)
                end
                if self.detailshift ~= 0 then
                  local xx = shl(x, 1)
                  local off = self.ylookup[y] + self.columnofs[xx]
                  put(self.fb, off, val)
                  put(self.fb, off + 1, val)
                else
                  put(self.fb, self.ylookup[y] + self.columnofs[x], val)
                end
              end
            end
          end
        end
      end
    end
  end
end

local function scale_from_global_angle(self, visangle)
  local anglea = as_u32(ANG90 + as_u32(visangle - self.viewangle))
  local angleb = as_u32(ANG90 + as_u32(visangle - self.rw_normalangle))
  local sinea = tables.finesine[band(ushr(anglea, ANGLETOFINESHIFT), FINEMASK)]
  local sineb = tables.finesine[band(ushr(angleb, ANGLETOFINESHIFT), FINEMASK)]
  local num = lsh(fixed_mul(self.projection, sineb), self.detailshift)
  local den = fixed_mul(self.rw_distance, sinea)
  local scale
  if den > ushr(num, 16) and den ~= 0 then
    scale = fixed_div(num, den)
    if scale > 64 * FRACUNIT then
      scale = 64 * FRACUNIT
    elseif scale < 256 then
      scale = 256
    end
  else
    scale = 64 * FRACUNIT
  end
  return scale
end

local function render_seg_loop(self)
  local texturecolumn = 0
  while self.rw_x < self.rw_stopx do
    local yl = shar(self.topfrac + HEIGHTUNIT - 1, HEIGHTBITS)
    if yl < self.ceilingclip[self.rw_x] + 1 then
      yl = self.ceilingclip[self.rw_x] + 1
    end
    if self.markceiling and self.ceilingplane then
      local top = self.ceilingclip[self.rw_x] + 1
      local bottom = yl - 1
      if bottom >= self.floorclip[self.rw_x] then
        bottom = self.floorclip[self.rw_x] - 1
      end
      if top <= bottom then
        self.ceilingplane.top[self.rw_x] = top
        self.ceilingplane.bottom[self.rw_x] = bottom
      end
    end
    local yh = shar(self.bottomfrac, HEIGHTBITS)
    if yh >= self.floorclip[self.rw_x] then
      yh = self.floorclip[self.rw_x] - 1
    end
    if self.markfloor and self.floorplane then
      local top = yh + 1
      local bottom = self.floorclip[self.rw_x] - 1
      if top <= self.ceilingclip[self.rw_x] then
        top = self.ceilingclip[self.rw_x] + 1
      end
      if top <= bottom then
        self.floorplane.top[self.rw_x] = top
        self.floorplane.bottom[self.rw_x] = bottom
      end
    end
    if self.segtextured then
      local angle = ushr(as_u32(self.rw_centerangle + self.xtoviewangle[self.rw_x]), ANGLETOFINESHIFT)
      local tanv = tables.finetangent[band(angle, idiv(FINEANGLES, 2) - 1)]
      texturecolumn = shar(self.rw_offset - fixed_mul(tanv, self.rw_distance), FRACBITS)
      local index = ushr(self.rw_scale, LIGHTSCALESHIFT)
      if index >= MAXLIGHTSCALE then
        index = MAXLIGHTSCALE - 1
      end
      if self.fixedcolormap then
        self.dc_colormap = self.fixedcolormap
      else
        self.dc_colormap = rdata.colormap(self.res, self.walllights[index])
      end
      self.dc_x = self.rw_x
      if self.rw_scale ~= 0 then
        self.dc_iscale = idiv(4294967295, self.rw_scale)
      else
        self.dc_iscale = 0
      end
    end
    if self.midtexture ~= 0 then
      self.dc_yl = yl
      self.dc_yh = yh
      self.dc_texturemid = self.rw_midtexturemid
      self.dc_source = rdata.get_column(self.res, self.midtexture, texturecolumn)
      draw_column(self)
      self.ceilingclip[self.rw_x] = self.viewheight
      self.floorclip[self.rw_x] = -1
    else
      if self.toptexture ~= 0 then
        local mid = shar(self.pixhigh, HEIGHTBITS)
        self.pixhigh = self.pixhigh + self.pixhighstep
        if mid >= self.floorclip[self.rw_x] then
          mid = self.floorclip[self.rw_x] - 1
        end
        if mid >= yl then
          self.dc_yl = yl
          self.dc_yh = mid
          self.dc_texturemid = self.rw_toptexturemid
          self.dc_source = rdata.get_column(self.res, self.toptexture, texturecolumn)
          draw_column(self)
          self.ceilingclip[self.rw_x] = mid
        else
          self.ceilingclip[self.rw_x] = yl - 1
        end
      elseif self.markceiling then
        self.ceilingclip[self.rw_x] = yl - 1
      end
      if self.bottomtexture ~= 0 then
        local mid = shar(self.pixlow + HEIGHTUNIT - 1, HEIGHTBITS)
        self.pixlow = self.pixlow + self.pixlowstep
        if mid <= self.ceilingclip[self.rw_x] then
          mid = self.ceilingclip[self.rw_x] + 1
        end
        if mid <= yh then
          self.dc_yl = mid
          self.dc_yh = yh
          self.dc_texturemid = self.rw_bottomtexturemid
          self.dc_source = rdata.get_column(self.res, self.bottomtexture, texturecolumn)
          draw_column(self)
          self.floorclip[self.rw_x] = mid
        else
          self.floorclip[self.rw_x] = yh + 1
        end
      elseif self.markfloor then
        self.floorclip[self.rw_x] = yh + 1
      end
      if self.maskedtexture and self.maskedtexturecol then
        self.maskedtexturecol[self.rw_x - self.rw_start] = texturecolumn
      end
    end
    self.rw_scale = self.rw_scale + self.rw_scalestep
    self.topfrac = self.topfrac + self.topstep
    self.bottomfrac = self.bottomfrac + self.bottomstep
    self.rw_x = self.rw_x + 1
  end
end

local function point_to_dist(self, x, y)
  local dx = abs_fixed(x - self.viewx)
  local dy = abs_fixed(y - self.viewy)
  if dy > dx then
    dx, dy = dy, dx
  end
  if dx == 0 then
    return 0
  end
  local frac = fixed_div(dy, dx)
  local idx = shar(frac, tables.DBITS)
  if idx > 2048 then
    idx = 2048
  end
  if idx < 0 then
    idx = 0
  end
  local ang = ushr(tables.tantoangle[idx] + ANG90, ANGLETOFINESHIFT)
  return fixed_div(dx, tables.finesine[band(ang, FINEMASK)])
end

local function copy_clip(src, start, stop)
  local out = {}
  local n = 0
  for i = start, stop do
    out[n] = src[i]
    n = n + 1
  end
  return out, n
end

local function push_drawseg(self, start, stop, scale1)
  local ds = {
    x1 = start,
    x2 = stop,
    scale1 = scale1,
    scale2 = scale1 + self.rw_scalestep * math.max(0, stop - start),
    curline = self.curline,
    scalestep = self.rw_scalestep,
    maskedtexturecol = self.maskedtexturecol,
    masked_count = 0,
    silhouette = SIL_NONE,
    bsilheight = 0,
    tsilheight = 0,
    sprtopclip = nil,
    sprbottomclip = nil,
    clip_count = 0,
  }
  if self.maskedtexturecol then
    ds.masked_count = stop - start + 1
  end
  if not self.backsector then
    ds.silhouette = SIL_BOTH
    ds.bsilheight = INT_MAX
    ds.tsilheight = INT_MIN
    local width = stop - start + 1
    ds.sprtopclip = {}
    ds.sprbottomclip = {}
    for i = 0, width - 1 do
      ds.sprtopclip[i] = self.viewheight
      ds.sprbottomclip[i] = -1
    end
    ds.clip_count = width
  else
    if self.frontsector.floorheight > self.backsector.floorheight then
      ds.silhouette = SIL_BOTTOM
      ds.bsilheight = self.frontsector.floorheight
    elseif self.backsector.floorheight > self.viewz then
      ds.silhouette = SIL_BOTTOM
      ds.bsilheight = INT_MAX
    end
    if self.frontsector.ceilingheight < self.backsector.ceilingheight then
      ds.silhouette = bor(ds.silhouette, SIL_TOP)
      ds.tsilheight = self.frontsector.ceilingheight
    elseif self.backsector.ceilingheight < self.viewz then
      ds.silhouette = bor(ds.silhouette, SIL_TOP)
      ds.tsilheight = INT_MIN
    end
    if self.backsector.ceilingheight <= self.frontsector.floorheight then
      ds.silhouette = bor(ds.silhouette, SIL_BOTTOM)
      ds.bsilheight = INT_MAX
    end
    if self.backsector.floorheight >= self.frontsector.ceilingheight then
      ds.silhouette = bor(ds.silhouette, SIL_TOP)
      ds.tsilheight = INT_MIN
    end
    ds.sprtopclip, ds.clip_count = copy_clip(self.ceilingclip, start, stop)
    ds.sprbottomclip = copy_clip(self.floorclip, start, stop)
    if self.maskedtexture then
      if band(ds.silhouette, SIL_TOP) == 0 then
        ds.silhouette = bor(ds.silhouette, SIL_TOP)
        ds.tsilheight = INT_MIN
      end
      if band(ds.silhouette, SIL_BOTTOM) == 0 then
        ds.silhouette = bor(ds.silhouette, SIL_BOTTOM)
        ds.bsilheight = INT_MAX
      end
    end
  end
  self.drawsegs[#self.drawsegs + 1] = ds
end

local function store_wall_range(self, start, stop)
  if start > stop then
    return
  end
  local line = self.curline
  local linedef = line.linedef
  local sidedef = line.sidedef
  linedef.flags = bor(linedef.flags, ML_MAPPED)
  self.rw_normalangle = as_u32(line.angle + ANG90)
  local offsetangle = as_u32(self.rw_normalangle - self.rw_angle1)
  if offsetangle > ANG180 then
    offsetangle = as_u32(-offsetangle)
  end
  if offsetangle > ANG90 then
    offsetangle = ANG90
  end
  local distangle = as_u32(ANG90 - offsetangle)
  local hyp = point_to_dist(self, line.v1.x, line.v1.y)
  self.rw_distance = fixed_mul(hyp, tables.finesine[band(ushr(distangle, ANGLETOFINESHIFT), FINEMASK)])
  self.rw_x = start
  self.rw_start = start
  self.rw_stopx = stop + 1
  self.rw_scale = scale_from_global_angle(self, as_u32(self.viewangle + self.xtoviewangle[start]))
  if stop > start then
    local scale2 = scale_from_global_angle(self, as_u32(self.viewangle + self.xtoviewangle[stop]))
    self.rw_scalestep = idiv(scale2 - self.rw_scale, stop - start)
  else
    self.rw_scalestep = 0
  end
  self.worldtop = self.frontsector.ceilingheight - self.viewz
  self.worldbottom = self.frontsector.floorheight - self.viewz
  self.midtexture = 0
  self.toptexture = 0
  self.bottomtexture = 0
  self.maskedtexture = false
  self.maskedtexturecol = nil
  self.segtextured = false
  if not self.backsector then
    self.midtexture = sidedef.midtexture
    self.markfloor = true
    self.markceiling = true
    if band(linedef.flags, ML_DONTPEGBOTTOM) ~= 0 then
      local vtop = self.frontsector.floorheight + rdata.texture_height(self.res, self.midtexture)
      self.rw_midtexturemid = vtop - self.viewz
    else
      self.rw_midtexturemid = self.worldtop
    end
    self.rw_midtexturemid = self.rw_midtexturemid + sidedef.rowoffset
  else
    self.worldhigh = self.backsector.ceilingheight - self.viewz
    self.worldlow = self.backsector.floorheight - self.viewz
    if self.frontsector.ceilingpic == self.res.skyflatnum and self.backsector.ceilingpic == self.res.skyflatnum then
      self.worldtop = self.worldhigh
    end
    self.markfloor = self.worldlow ~= self.worldbottom
      or self.backsector.floorpic ~= self.frontsector.floorpic
      or self.backsector.lightlevel ~= self.frontsector.lightlevel
    self.markceiling = self.worldhigh ~= self.worldtop
      or self.backsector.ceilingpic ~= self.frontsector.ceilingpic
      or self.backsector.lightlevel ~= self.frontsector.lightlevel
    if self.backsector.ceilingheight <= self.frontsector.floorheight
      or self.backsector.floorheight >= self.frontsector.ceilingheight then
      self.markceiling = true
      self.markfloor = true
    end
    if self.worldhigh < self.worldtop then
      self.toptexture = sidedef.toptexture
      if band(linedef.flags, ML_DONTPEGTOP) ~= 0 then
        self.rw_toptexturemid = self.worldtop
      else
        local vtop = self.backsector.ceilingheight + rdata.texture_height(self.res, self.toptexture)
        self.rw_toptexturemid = vtop - self.viewz
      end
    end
    if self.worldlow > self.worldbottom then
      self.bottomtexture = sidedef.bottomtexture
      if band(linedef.flags, ML_DONTPEGBOTTOM) ~= 0 then
        self.rw_bottomtexturemid = self.worldtop
      else
        self.rw_bottomtexturemid = self.worldlow
      end
    end
    self.rw_toptexturemid = (self.rw_toptexturemid or 0) + sidedef.rowoffset
    self.rw_bottomtexturemid = (self.rw_bottomtexturemid or 0) + sidedef.rowoffset
    if sidedef.midtexture ~= 0 then
      self.maskedtexture = true
      self.maskedtexturecol = {}
      for i = 0, stop - start do
        self.maskedtexturecol[i] = SHRT_MAX
      end
    end
  end
  self.segtextured = self.midtexture ~= 0 or self.toptexture ~= 0 or self.bottomtexture ~= 0 or self.maskedtexture
  if self.segtextured then
    offsetangle = as_u32(self.rw_normalangle - self.rw_angle1)
    if offsetangle > ANG180 then
      offsetangle = as_u32(-offsetangle)
    end
    self.rw_offset = fixed_mul(hyp, tables.finesine[band(ushr(offsetangle, ANGLETOFINESHIFT), FINEMASK)])
    if as_u32(self.rw_normalangle - self.rw_angle1) < ANG180 then
      self.rw_offset = -self.rw_offset
    end
    self.rw_offset = self.rw_offset + sidedef.textureoffset + line.offset
    self.rw_centerangle = as_u32(ANG90 + self.viewangle - self.rw_normalangle)
  end
  if self.frontsector.floorheight >= self.viewz then
    self.markfloor = false
  end
  if self.frontsector.ceilingheight <= self.viewz and self.frontsector.ceilingpic ~= self.res.skyflatnum then
    self.markceiling = false
  end
  if self.markceiling then
    self.ceilingplane = M.check_plane(self, self.ceilingplane, start, stop)
  end
  if self.markfloor then
    self.floorplane = M.check_plane(self, self.floorplane, start, stop)
  end
  self.worldtop = shar(self.worldtop, 4)
  self.worldbottom = shar(self.worldbottom, 4)
  self.topstep = -fixed_mul(self.rw_scalestep, self.worldtop)
  self.topfrac = shar(self.centeryfrac, 4) - fixed_mul(self.worldtop, self.rw_scale)
  self.bottomstep = -fixed_mul(self.rw_scalestep, self.worldbottom)
  self.bottomfrac = shar(self.centeryfrac, 4) - fixed_mul(self.worldbottom, self.rw_scale)
  if self.backsector then
    self.worldhigh = shar(self.worldhigh, 4)
    self.worldlow = shar(self.worldlow, 4)
    if self.worldhigh < self.worldtop then
      self.pixhigh = shar(self.centeryfrac, 4) - fixed_mul(self.worldhigh, self.rw_scale)
      self.pixhighstep = -fixed_mul(self.rw_scalestep, self.worldhigh)
    end
    if self.worldlow > self.worldbottom then
      self.pixlow = shar(self.centeryfrac, 4) - fixed_mul(self.worldlow, self.rw_scale)
      self.pixlowstep = -fixed_mul(self.rw_scalestep, self.worldlow)
    end
  end
  local scale1 = self.rw_scale
  render_seg_loop(self)
  push_drawseg(self, start, stop, scale1)
end

local function crunch_solid(self, start, nexti)
  if nexti == start then
    return
  end
  local dest = start + 1
  for i = nexti + 1, self.newend - 1 do
    self.solidsegs[dest] = self.solidsegs[i]
    dest = dest + 1
  end
  self.newend = dest
end

local function clip_solid(self, first, last)
  if first > last then
    return
  end
  local start = 0
  while start < self.newend and self.solidsegs[start].last < first - 1 do
    start = start + 1
  end
  if start >= self.newend then
    store_wall_range(self, first, last)
    return
  end
  if first < self.solidsegs[start].first then
    if last < self.solidsegs[start].first - 1 then
      store_wall_range(self, first, last)
      for i = self.newend - 1, start, -1 do
        self.solidsegs[i + 1] = self.solidsegs[i]
      end
      self.solidsegs[start] = { first = first, last = last }
      self.newend = self.newend + 1
      return
    end
    store_wall_range(self, first, self.solidsegs[start].first - 1)
    self.solidsegs[start].first = first
  end
  if last <= self.solidsegs[start].last then
    return
  end
  local nexti = start
  while nexti + 1 < self.newend and last >= self.solidsegs[nexti + 1].first - 1 do
    store_wall_range(self, self.solidsegs[nexti].last + 1, self.solidsegs[nexti + 1].first - 1)
    nexti = nexti + 1
    if last <= self.solidsegs[nexti].last then
      self.solidsegs[start].last = self.solidsegs[nexti].last
      crunch_solid(self, start, nexti)
      return
    end
  end
  store_wall_range(self, self.solidsegs[nexti].last + 1, last)
  self.solidsegs[start].last = last
  crunch_solid(self, start, nexti)
end

local function clip_pass(self, first, last)
  if first > last then
    return
  end
  local start = 0
  while start < self.newend and self.solidsegs[start].last < first - 1 do
    start = start + 1
  end
  if start >= self.newend then
    store_wall_range(self, first, last)
    return
  end
  if first < self.solidsegs[start].first then
    if last < self.solidsegs[start].first - 1 then
      store_wall_range(self, first, last)
      return
    end
    store_wall_range(self, first, self.solidsegs[start].first - 1)
  end
  if last <= self.solidsegs[start].last then
    return
  end
  local nexti = start
  while nexti + 1 < self.newend and last >= self.solidsegs[nexti + 1].first - 1 do
    store_wall_range(self, self.solidsegs[nexti].last + 1, self.solidsegs[nexti + 1].first - 1)
    nexti = nexti + 1
    if last <= self.solidsegs[nexti].last then
      return
    end
  end
  store_wall_range(self, self.solidsegs[nexti].last + 1, last)
end

function M.point_to_angle(self, x, y)
  x = as_i32(x - self.viewx)
  y = as_i32(y - self.viewy)
  if x == 0 and y == 0 then
    return 0
  end
  if x >= 0 then
    if y >= 0 then
      if x > y then
        return tables.tantoangle[tables.slope_div(y, x)]
      end
      return as_u32(ANG90 - 1 - tables.tantoangle[tables.slope_div(x, y)])
    end
    y = -y
    if x > y then
      return as_u32(-tables.tantoangle[tables.slope_div(y, x)])
    end
    return as_u32(3221225472 + tables.tantoangle[tables.slope_div(x, y)])
  end
  x = -x
  if y >= 0 then
    if x > y then
      return as_u32(ANG180 - 1 - tables.tantoangle[tables.slope_div(y, x)])
    end
    return as_u32(ANG90 + tables.tantoangle[tables.slope_div(x, y)])
  end
  y = -y
  if x > y then
    return as_u32(ANG180 + tables.tantoangle[tables.slope_div(y, x)])
  end
  return as_u32(3221225472 - 1 - tables.tantoangle[tables.slope_div(x, y)])
end

local function point_on_side(self, x, y, node)
  local dx = as_i32(x - node.x)
  local dy = as_i32(y - node.y)
  local left = as_i32(shar(node.dy, 16)) * dx
  local right = dy * as_i32(shar(node.dx, 16))
  if right >= left then
    return 1
  end
  return 0
end

local function add_line(self, line)
  self.curline = line
  local angle1 = M.point_to_angle(self, line.v1.x, line.v1.y)
  local angle2 = M.point_to_angle(self, line.v2.x, line.v2.y)
  local span = as_u32(angle1 - angle2)
  if span >= ANG180 then
    return
  end
  self.rw_angle1 = angle1
  angle1 = as_u32(angle1 - self.viewangle)
  angle2 = as_u32(angle2 - self.viewangle)
  local tspan = as_u32(angle1 + self.clipangle)
  if tspan > as_u32(2 * self.clipangle) then
    tspan = as_u32(tspan - 2 * self.clipangle)
    if tspan >= span then
      return
    end
    angle1 = self.clipangle
  end
  tspan = as_u32(self.clipangle - angle2)
  if tspan > as_u32(2 * self.clipangle) then
    tspan = as_u32(tspan - 2 * self.clipangle)
    if tspan >= span then
      return
    end
    angle2 = as_u32(-self.clipangle)
  end
  local mask = idiv(FINEANGLES, 2) - 1
  local x1 = self.viewangletox[band(ushr(as_u32(angle1 + ANG90), ANGLETOFINESHIFT), mask)]
  local x2 = self.viewangletox[band(ushr(as_u32(angle2 + ANG90), ANGLETOFINESHIFT), mask)]
  if x1 == x2 then
    return
  end
  self.backsector = line.backsector
  if not self.backsector then
    clip_solid(self, x1, x2 - 1)
    return
  end
  if self.backsector.ceilingheight <= self.frontsector.floorheight
    or self.backsector.floorheight >= self.frontsector.ceilingheight then
    clip_solid(self, x1, x2 - 1)
    return
  end
  clip_pass(self, x1, x2 - 1)
end

local function subsector(self, world, num)
  local sub = world.subsectors[num + 1]
  self.frontsector = sub.sector
  local light = ushr(self.frontsector.lightlevel, 4) + self.extralight
  if light < 0 then
    light = 0
  end
  if light > LIGHTLEVELS - 1 then
    light = LIGHTLEVELS - 1
  end
  self.walllights = self.scalelight[light]
  self.floorplane = M.find_plane(self, self.frontsector.floorheight, self.frontsector.floorpic, self.frontsector.lightlevel)
  self.ceilingplane = M.find_plane(self, self.frontsector.ceilingheight, self.frontsector.ceilingpic, self.frontsector.lightlevel)
  local line = sub.firstline
  for _ = 1, sub.numlines do
    add_line(self, world.segs[line + 1])
    line = line + 1
  end
end

local function render_bsp_node(self, world, bspnum)
  if band(bspnum, NF_SUBSECTOR) ~= 0 or bspnum < 0 then
    local num = 0
    if bspnum ~= -1 then
      num = band(bspnum, 32767)
    end
    subsector(self, world, num)
    return
  end
  local node = world.nodes[bspnum + 1]
  local side = point_on_side(self, self.viewx, self.viewy, node)
  render_bsp_node(self, world, node.children[side + 1])
  render_bsp_node(self, world, node.children[bxor(side, 1) + 1])
end

local function clear_clip(self)
  self.solidsegs[0].first = -2147483647
  self.solidsegs[0].last = -1
  self.solidsegs[1].first = self.viewwidth
  self.solidsegs[1].last = 2147483647
  self.newend = 2
  for i = 0, self.viewwidth - 1 do
    self.floorclip[i] = self.viewheight
    self.ceilingclip[i] = -1
  end
end

function M.find_plane(self, height, picnum, lightlevel)
  if picnum == self.res.skyflatnum then
    height = 0
    lightlevel = 0
  end
  for i = 1, #self.visplanes do
    local p = self.visplanes[i]
    if p.height == height and p.picnum == picnum and p.lightlevel == lightlevel then
      return p
    end
  end
  local top, bottom = span_tables()
  local p = {
    height = height,
    picnum = picnum,
    lightlevel = lightlevel,
    minx = self.viewwidth,
    maxx = -1,
    top = top,
    bottom = bottom,
  }
  self.visplanes[#self.visplanes + 1] = p
  return p
end

local function dup_plane(self, src, start, stop)
  local top, bottom = span_tables()
  local p = {
    height = src.height,
    picnum = src.picnum,
    lightlevel = src.lightlevel,
    minx = start,
    maxx = stop,
    top = top,
    bottom = bottom,
  }
  self.visplanes[#self.visplanes + 1] = p
  return p
end

function M.check_plane(self, pl, start, stop)
  if not pl then
    return M.find_plane(self, 0, 0, 0)
  end
  local intrl, unionl, intrh, unionh
  if start < pl.minx then
    intrl, unionl = pl.minx, start
  else
    unionl, intrl = pl.minx, start
  end
  if stop > pl.maxx then
    intrh, unionh = pl.maxx, stop
  else
    unionh, intrh = pl.maxx, stop
  end
  local x = intrl
  while x <= intrh do
    if x >= 0 and x < SCREENWIDTH and pl.top[x] ~= 255 then
      break
    end
    x = x + 1
  end
  if x > intrh then
    pl.minx = unionl
    pl.maxx = unionh
    return pl
  end
  return dup_plane(self, pl, start, stop)
end

function M.setup_frame(self, x, y, z, angle, extra_light, fixedcolormap)
  self.viewx = x
  self.viewy = y
  self.viewz = z
  self.viewangle = as_u32(angle)
  self.viewsin = tables.fine_sin(self.viewangle)
  self.viewcos = tables.fine_cos(self.viewangle)
  self.extralight = extra_light or 0
  if fixedcolormap and fixedcolormap ~= 0 then
    self.fixedcolormap = rdata.colormap(self.res, fixedcolormap)
  else
    self.fixedcolormap = nil
  end
  local ang = band(ushr(as_u32(self.viewangle - ANG90), ANGLETOFINESHIFT), FINEMASK)
  local denom = self.centerxfrac
  if denom == 0 then
    denom = 1
  end
  self.basexscale = fixed_div(tables.finesine[band(ang + idiv(FINEANGLES, 4), FINEMASK)], denom)
  self.baseyscale = -fixed_div(tables.finesine[ang], denom)
end

function M.render(self, world, fb)
  self.fb = fb
  self.visplanes = {}
  self.drawsegs = {}
  clear_clip(self)
  if #world.nodes > 0 then
    render_bsp_node(self, world, world.numnodes - 1)
  else
    subsector(self, world, 0)
  end
  draw_planes(self)
end

local function init_mapping(self)
  local focallength = fixed_div(self.centerxfrac, tables.finetangent[idiv(FINEANGLES, 4) + idiv(FIELDOFVIEW, 2)])
  local half = idiv(FINEANGLES, 2)
  for i = 0, half - 1 do
    local ft = tables.finetangent[i]
    local t
    if ft > FRACUNIT * 2 then
      t = -1
    elseif ft < -FRACUNIT * 2 then
      t = self.viewwidth + 1
    else
      t = shar(as_i32(self.centerxfrac - fixed_mul(ft, focallength) + FRACUNIT - 1), FRACBITS)
      if t < -1 then
        t = -1
      end
      if t > self.viewwidth + 1 then
        t = self.viewwidth + 1
      end
    end
    self.viewangletox[i] = t
  end
  for x = 0, self.viewwidth do
    local i = 0
    while i < half and self.viewangletox[i] > x do
      i = i + 1
    end
    self.xtoviewangle[x] = as_u32(shl(i, ANGLETOFINESHIFT) - ANG90)
  end
  for i = 0, half - 1 do
    if self.viewangletox[i] == -1 then
      self.viewangletox[i] = 0
    elseif self.viewangletox[i] == self.viewwidth + 1 then
      self.viewangletox[i] = self.viewwidth
    end
  end
  self.clipangle = self.xtoviewangle[0]
end

local function init_lights(self)
  for i = 0, LIGHTLEVELS - 1 do
    local startmap = idiv(((LIGHTLEVELS - 1 - i) * 2) * NUMCOLORMAPS, LIGHTLEVELS)
    self.zlight[i] = {}
    for j = 0, MAXLIGHTZ - 1 do
      local scale = ushr(fixed_div(idiv(SCREENWIDTH, 2) * FRACUNIT, shl(j + 1, LIGHTZSHIFT)), LIGHTSCALESHIFT)
      local level = startmap - idiv(scale, 2)
      if level < 0 then
        level = 0
      end
      if level > NUMCOLORMAPS - 1 then
        level = NUMCOLORMAPS - 1
      end
      self.zlight[i][j] = level
    end
    self.scalelight[i] = {}
    local vw = lsh(self.viewwidth, self.detailshift)
    if vw < 1 then
      vw = 1
    end
    for j = 0, MAXLIGHTSCALE - 1 do
      local level = startmap - math.floor(j * SCREENWIDTH / vw / 2)
      if level < 0 then
        level = 0
      end
      if level > NUMCOLORMAPS - 1 then
        level = NUMCOLORMAPS - 1
      end
      self.scalelight[i][j] = level
    end
  end
end

local function init_slopes(self)
  for i = 0, self.viewheight - 1 do
    local dy = math.abs(lsh(i - self.centery, FRACBITS) + idiv(FRACUNIT, 2))
    if dy < 1 then
      dy = 1
    end
    self.yslope[i] = fixed_div(idiv(lsh(self.viewwidth, self.detailshift), 2) * FRACUNIT, dy)
  end
  for i = 0, self.viewwidth - 1 do
    local cosadj = abs_fixed(tables.fine_cos(self.xtoviewangle[i]))
    if cosadj < 1 then
      cosadj = 1
    end
    self.distscale[i] = fixed_div(FRACUNIT, cosadj)
  end
end

function M.set_view_size(self, blocks, detail)
  if blocks < 3 then
    blocks = 3
  end
  if blocks > 11 then
    blocks = 11
  end
  if detail ~= 0 then
    detail = 1
  else
    detail = 0
  end
  if self.sized_blocks == blocks and self.sized_detail == detail then
    return
  end
  self.sized_blocks = blocks
  self.sized_detail = detail
  self.screenblocks = blocks
  self.detailshift = detail
  local scaled, viewheight
  if blocks == 11 then
    scaled = SCREENWIDTH
    viewheight = SCREENHEIGHT
  else
    scaled = blocks * 32
    viewheight = band(idiv(blocks * 168, 10), compat.bnot(7))
  end
  self.scaledviewwidth = scaled
  self.viewwidth = ushr(scaled, detail)
  self.viewheight = viewheight
  self.centerx = idiv(self.viewwidth, 2)
  self.centery = idiv(self.viewheight, 2)
  self.centerxfrac = shl(self.centerx, FRACBITS)
  self.centeryfrac = shl(self.centery, FRACBITS)
  self.projection = self.centerxfrac
  self.viewwindowx = ushr(SCREENWIDTH - scaled, 1)
  if scaled == SCREENWIDTH then
    self.viewwindowy = 0
  else
    self.viewwindowy = ushr(SCREENHEIGHT - SBARHEIGHT - viewheight, 1)
  end
  for i = 0, SCREENHEIGHT - 1 do
    self.ylookup[i] = (i + self.viewwindowy) * SCREENWIDTH
  end
  for i = 0, SCREENWIDTH - 1 do
    self.columnofs[i] = self.viewwindowx + i
  end
  self.ceilingclip = {}
  self.floorclip = {}
  local nclip = self.viewwidth
  if nclip < 1 then
    nclip = 1
  end
  for i = 0, nclip - 1 do
    self.ceilingclip[i] = 0
    self.floorclip[i] = 0
  end
  self.pspritescale = idiv(FRACUNIT * self.viewwidth, SCREENWIDTH)
  self.pspriteiscale = idiv(FRACUNIT * SCREENWIDTH, math.max(1, self.viewwidth))
  init_mapping(self)
  init_slopes(self)
  init_lights(self)
end

function M.new(res)
  tables.init()
  local self = {
    res = res,
    viewwidth = SCREENWIDTH,
    viewheight = SCREENHEIGHT - SBARHEIGHT,
    detailshift = 0,
    viewangletox = {},
    xtoviewangle = {},
    yslope = {},
    distscale = {},
    scalelight = {},
    zlight = {},
    walllights = {},
    ylookup = {},
    columnofs = {},
    ceilingclip = {},
    floorclip = {},
    solidsegs = {},
    visplanes = {},
    drawsegs = {},
    screenblocks = 10,
    extralight = 0,
    fixedcolormap = nil,
    fb = nil,
  }
  self.centerx = idiv(self.viewwidth, 2)
  self.centery = idiv(self.viewheight, 2)
  self.centerxfrac = shl(self.centerx, FRACBITS)
  self.centeryfrac = shl(self.centery, FRACBITS)
  self.projection = self.centerxfrac
  for i = 0, 63 do
    self.solidsegs[i] = { first = 0, last = 0 }
  end
  for i = 0, SCREENHEIGHT - 1 do
    self.ylookup[i] = i * SCREENWIDTH
  end
  for i = 0, SCREENWIDTH - 1 do
    self.columnofs[i] = i
    self.ceilingclip[i] = 0
    self.floorclip[i] = 0
  end
  init_mapping(self)
  init_lights(self)
  init_slopes(self)
  return self
end

return M
