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
-- Sprites da vista, a partir de sprites.py. O frame e o de spawn.

local compat = require("compat")
local wad = require("wad")
local v = require("v_video")
local render = require("render")
local rdata = require("r_data")

local M = {}

local band = compat.band
local ushr, shar = compat.ushr, compat.shar
local as_i32, as_u32 = compat.as_i32, compat.as_u32
local fixed_mul, fixed_div = compat.fixed_mul, compat.fixed_div
local byte = string.byte

local FRACBITS = 16
local FRACUNIT = 65536
local SCREENWIDTH = 320
local FINEANGLES = 8192
local ANG45 = 536870912
local MF_SHADOW = 262144
local MF_NOSECTOR = 8
local MINZ = 4 * FRACUNIT
local MAX_SPRITE_FRAMES = 29
local SIL_TOP = 1
local SIL_BOTTOM = 2

local FUZZ_DIR = {
  1, -1, 1, -1, 1, 1, -1, 1, 1, -1, 1, 1, 1, -1, 1, 1, 1, -1, -1, -1, -1, 1, -1, -1, 1,
  1, 1, 1, -1, 1, -1, 1, 1, -1, -1, 1, 1, -1, -1, -1, -1, 1, 1, 1, 1, -1, 1, 1, -1, 1,
}
local fuzzpos = 1

local function u32(data, off)
  local b1, b2, b3, b4 = data:byte(off + 1, off + 4)
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function install(frames, lump, frame, rotation, flipped)
  if frame < 0 or frame >= MAX_SPRITE_FRAMES or rotation < 0 or rotation > 8 then
    return false
  end
  local sf = frames[frame + 1]
  local flip = 0
  if flipped then
    flip = 1
  end
  if rotation == 0 then
    if sf.rotate == 1 then
      return true
    end
    sf.rotate = 0
    for r = 1, 8 do
      sf.lump[r] = lump
      sf.flip[r] = flip
    end
    return true
  end
  if sf.rotate == 0 then
    return true
  end
  sf.rotate = 1
  local idx = rotation
  if sf.lump[idx] < 0 then
    sf.lump[idx] = lump
    sf.flip[idx] = flip
  end
  return true
end

function M.init_defs(wadfile)
  local start = wad.check_num_for_name(wadfile, "S_START")
  local endn = wad.check_num_for_name(wadfile, "S_END")
  if start < 0 then
    start = wad.check_num_for_name(wadfile, "SS_START")
  end
  if endn < 0 then
    endn = wad.check_num_for_name(wadfile, "SS_END")
  end
  local first, last
  if start >= 0 and endn > start then
    first, last = start + 1, endn - 1
  else
    first, last = 0, wad.num_lumps(wadfile) - 1
  end
  local buckets = {}
  local order = {}
  for lump = first, last do
    local name = wad.lump_name(wadfile, lump)
    if #name >= 6 then
      local key = name:sub(1, 4)
      if not buckets[key] then
        buckets[key] = {}
        order[#order + 1] = key
      end
      local list = buckets[key]
      list[#list + 1] = lump
    end
  end
  local result = {}
  for _, sprname in ipairs(order) do
    local frames = {}
    for i = 1, MAX_SPRITE_FRAMES do
      frames[i] = { rotate = -1, lump = { -1, -1, -1, -1, -1, -1, -1, -1 }, flip = { 0, 0, 0, 0, 0, 0, 0, 0 } }
    end
    local maxframe = -1
    for _, lump in ipairs(buckets[sprname]) do
      local name = wad.lump_name(wadfile, lump)
      local frame = name:byte(5) - string.byte("A")
      local rotation = name:byte(6) - string.byte("0")
      if install(frames, lump, frame, rotation, false) and frame > maxframe then
        maxframe = frame
      end
      if #name >= 8 then
        local ch = name:sub(7, 7)
        if ch >= "A" and ch <= "]" then
          local frame2 = name:byte(7) - string.byte("A")
          local rotation2 = name:byte(8) - string.byte("0")
          if install(frames, lump, frame2, rotation2, true) and frame2 > maxframe then
            maxframe = frame2
          end
        end
      end
    end
    if maxframe >= 0 then
      for frame_i = 0, maxframe do
        local slot = frames[frame_i + 1]
        if slot.rotate == -1 then
          slot.rotate = 0
        end
      end
      local kept = {}
      for i = 1, maxframe + 1 do
        kept[i] = frames[i]
      end
      result[sprname] = kept
    end
  end
  return result
end

function M.lookup(res, name, ang_to_thing, moangle, frame)
  local base = (name or ""):sub(1, 4):upper()
  local sprframes = res.sprites[base]
  if not sprframes then
    return nil
  end
  local fi = band(frame, 32767)
  local sf = sprframes[fi + 1]
  if not sf then
    return nil
  end
  local lump, flip
  if sf.rotate ~= 0 then
    local rot = band(ushr(as_u32(ang_to_thing - moangle + 2415919104), 29), 7)
    lump = sf.lump[rot + 1]
    flip = sf.flip[rot + 1]
  else
    lump = sf.lump[1]
    flip = sf.flip[1]
  end
  if lump < 0 then
    return nil
  end
  return lump, flip
end

local function point_on_seg_side(x, y, line)
  local lx, ly = line.v1.x, line.v1.y
  local ldx = line.v2.x - lx
  local ldy = line.v2.y - ly
  if ldx == 0 then
    if x <= lx then
      if ldy > 0 then
        return 1
      end
      return 0
    end
    if ldy < 0 then
      return 1
    end
    return 0
  end
  if ldy == 0 then
    if y <= ly then
      if ldx < 0 then
        return 1
      end
      return 0
    end
    if ldx > 0 then
      return 1
    end
    return 0
  end
  local dx = x - lx
  local dy = y - ly
  local left = fixed_mul(shar(ldy, FRACBITS), dx)
  local right = fixed_mul(dy, shar(ldx, FRACBITS))
  if right < left then
    return 0
  end
  return 1
end

local function project(renderer, mo)
  local tr_x = as_i32(mo.x - renderer.viewx)
  local tr_y = as_i32(mo.y - renderer.viewy)
  local gxt = fixed_mul(tr_x, renderer.viewcos)
  local gyt = -fixed_mul(tr_y, renderer.viewsin)
  local tz = gxt - gyt
  if tz < MINZ then
    return nil
  end
  local xscale = fixed_div(renderer.projection, tz)
  gxt = -fixed_mul(tr_x, renderer.viewsin)
  gyt = fixed_mul(tr_y, renderer.viewcos)
  local tx = -(gyt + gxt)
  if math.abs(tx) > tz * 4 then
    return nil
  end
  local lump, flip = M.lookup(renderer.res, mo.sprite, render.point_to_angle(renderer, mo.x, mo.y), mo.angle, mo.frame or 0)
  if not lump then
    return nil
  end
  local patch = wad.cache_lump_num(renderer.res.wad, lump)
  local pw, _h, left, top = v.patch_size(patch)
  tx = tx - left * FRACUNIT
  local x1 = shar(renderer.centerxfrac + fixed_mul(tx, xscale), FRACBITS)
  if x1 > renderer.viewwidth then
    return nil
  end
  tx = tx + pw * FRACUNIT
  local x2 = shar(renderer.centerxfrac + fixed_mul(tx, xscale), FRACBITS) - 1
  if x2 < 0 then
    return nil
  end
  local iscale = FRACUNIT
  if xscale ~= 0 then
    iscale = fixed_div(FRACUNIT, xscale)
  end
  local xiscale = iscale
  local startfrac = 0
  if flip ~= 0 then
    xiscale = -iscale
    startfrac = pw * FRACUNIT - 1
  end
  local vis_x1 = x1
  if vis_x1 < 0 then
    vis_x1 = 0
  end
  local vis_x2 = x2
  if vis_x2 > renderer.viewwidth - 1 then
    vis_x2 = renderer.viewwidth - 1
  end
  if vis_x1 > x1 then
    startfrac = startfrac + xiscale * (vis_x1 - x1)
  end
  local detail = renderer.detailshift or 0
  return {
    mo = mo,
    patch = patch,
    w = pw,
    scale = xscale * (2 ^ detail),
    gx = mo.x,
    gy = mo.y,
    gz = mo.z,
    gzt = mo.z + top * FRACUNIT,
    texturemid = mo.z + top * FRACUNIT - renderer.viewz,
    x1 = vis_x1,
    x2 = vis_x2,
    xiscale = xiscale,
    startfrac = startfrac,
  }
end

local function clip_against_walls(renderer, spr)
  local x1, x2 = spr.x1, spr.x2
  local clipbot, cliptop = {}, {}
  for i = 0, SCREENWIDTH - 1 do
    clipbot[i] = -2
    cliptop[i] = -2
  end
  for n = #renderer.drawsegs, 1, -1 do
    local ds = renderer.drawsegs[n]
    if not (ds.x1 > x2 or ds.x2 < x1) then
      if ds.silhouette ~= 0 or ds.maskedtexturecol then
        local r1 = ds.x1
        if x1 > r1 then
          r1 = x1
        end
        local r2 = ds.x2
        if x2 < r2 then
          r2 = x2
        end
        local scale = ds.scale1
        if ds.scale2 > scale then
          scale = ds.scale2
        end
        local lowscale = ds.scale1
        if ds.scale2 < lowscale then
          lowscale = ds.scale2
        end
        local in_front = scale < spr.scale or (lowscale < spr.scale and ds.curline and point_on_seg_side(spr.gx, spr.gy, ds.curline) == 0)
        if in_front then
          if ds.maskedtexturecol then
            render.render_masked_seg_range(renderer, ds, r1, r2)
          end
        else
          local silhouette = ds.silhouette
          if spr.gz >= ds.bsilheight then
            silhouette = band(silhouette, compat.bnot(SIL_BOTTOM))
          end
          if spr.gzt <= ds.tsilheight then
            silhouette = band(silhouette, compat.bnot(SIL_TOP))
          end
          for x = r1, r2 do
            local i = x - ds.x1
            if i >= 0 and ds.sprtopclip and i < ds.clip_count then
              if band(silhouette, SIL_BOTTOM) ~= 0 and clipbot[x] == -2 then
                clipbot[x] = ds.sprbottomclip[i]
              end
              if band(silhouette, SIL_TOP) ~= 0 and cliptop[x] == -2 then
                cliptop[x] = ds.sprtopclip[i]
              end
            end
          end
        end
      end
    end
  end
  local viewh = renderer.viewheight
  for x = x1, x2 do
    if clipbot[x] == -2 then
      clipbot[x] = viewh
    end
    if cliptop[x] == -2 then
      cliptop[x] = -1
    end
  end
  return cliptop, clipbot
end

local function draw_fuzz_pixel(renderer, fb, x, y, cm)
  local colx = x
  if renderer.detailshift ~= 0 then
    colx = x * 2
  end
  local dest = renderer.ylookup[y] + renderer.columnofs[colx]
  local src = dest + FUZZ_DIR[fuzzpos] * SCREENWIDTH
  fuzzpos = fuzzpos + 1
  if fuzzpos > #FUZZ_DIR then
    fuzzpos = 1
  end
  if src < 0 or src >= 64000 then
    src = dest
  end
  local pix = fb[src + 1] or 0
  local val = pix
  if pix < #cm then
    val = byte(cm, pix + 1)
  end
  if dest >= 0 and dest < 64000 then
    fb[dest + 1] = val
  end
  if renderer.detailshift ~= 0 and dest + 1 < 64000 then
    fb[dest + 2] = val
  end
end

local function draw_one(renderer, fb, spr, clip_walls)
  local patch = spr.patch
  local patch_w = spr.w
  local iscale = spr.xiscale
  local spryscale = spr.scale
  local detail = renderer.detailshift or 0
  local y_iscale = math.abs(iscale)
  if detail > 0 then
    y_iscale = math.floor(y_iscale / (2 ^ detail))
  end
  if y_iscale < 1 then
    y_iscale = 1
  end
  local sprtopscreen = renderer.centeryfrac - fixed_mul(spr.texturemid, spryscale)
  local cliptop, clipbot
  if clip_walls then
    cliptop, clipbot = clip_against_walls(renderer, spr)
  else
    cliptop, clipbot = {}, {}
    for i = 0, SCREENWIDTH - 1 do
      cliptop[i] = -1
      clipbot[i] = renderer.viewheight
    end
  end
  local colofs = {}
  for c = 0, math.max(1, patch_w) - 1 do
    colofs[c] = u32(patch, 8 + c * 4)
  end
  local mo = spr.mo
  local fuzz = mo and band(mo.flags or 0, MF_SHADOW) ~= 0
  local cm
  if fuzz then
    cm = rdata.colormap(renderer.res, 6)
  elseif renderer.fixedcolormap then
    cm = renderer.fixedcolormap
  else
    cm = rdata.colormap(renderer.res, 0)
  end
  local frac = spr.startfrac
  for x = spr.x1, spr.x2 do
    local col = shar(frac, FRACBITS)
    if col >= 0 and col < patch_w then
      local column = colofs[col]
      while column < #patch do
        local topdelta = patch:byte(column + 1)
        if topdelta == 255 then
          break
        end
        local length = patch:byte(column + 2)
        local source = column + 3
        local topscreen = sprtopscreen + spryscale * topdelta
        local bottomscreen = topscreen + spryscale * length
        local yl = shar(topscreen + FRACUNIT - 1, FRACBITS)
        local yh = shar(bottomscreen - 1, FRACBITS)
        if yl <= cliptop[x] then
          yl = cliptop[x] + 1
        end
        if yh >= clipbot[x] then
          yh = clipbot[x] - 1
        end
        if yl < 0 then
          yl = 0
        end
        if yh >= renderer.viewheight then
          yh = renderer.viewheight - 1
        end
        if fuzz then
          if yl <= 0 then
            yl = 1
          end
          if yh >= renderer.viewheight - 1 then
            yh = renderer.viewheight - 2
          end
        end
        if yl <= yh then
          local texfrac = fixed_mul(yl * FRACUNIT - topscreen, y_iscale)
          if texfrac < 0 then
            texfrac = 0
          end
          for y = yl, yh do
            if fuzz then
              draw_fuzz_pixel(renderer, fb, x, y, cm)
            else
              local idx = shar(texfrac, FRACBITS)
              if idx >= 0 and idx < length then
                local pix = byte(patch, source + idx + 1)
                local val = pix
                if pix < #cm then
                  val = byte(cm, pix + 1)
                end
                if renderer.detailshift ~= 0 then
                  local xx = x * 2
                  local off = renderer.ylookup[y] + renderer.columnofs[xx]
                  if off >= 0 and off < 64000 then
                    fb[off + 1] = val
                    fb[off + 2] = val
                  end
                else
                  local off = renderer.ylookup[y] + renderer.columnofs[x]
                  if off >= 0 and off < 64000 then
                    fb[off + 1] = val
                  end
                end
              end
            end
            texfrac = texfrac + y_iscale
          end
        end
        column = column + length + 4
      end
    end
    frac = frac + iscale
  end
end

function M.spawn_things(world, skill)
  local thinker = require("thinker")
  thinker.spawn_map(world, skill, nil)
end

function M.draw(renderer, world, fb)
  local vis = {}
  for i = 1, #world.mobjs do
    local mo = world.mobjs[i]
    if mo.sprite and mo.sprite ~= "" and not mo.player and band(mo.flags or 0, MF_NOSECTOR) == 0 then
      local item = project(renderer, mo)
      if item then
        vis[#vis + 1] = item
      end
    end
  end
  for i = 1, #vis do
    vis[i]._i = i
  end
  table.sort(vis, function(a, b)
    if a.scale == b.scale then
      return a._i < b._i
    end
    return a.scale < b.scale
  end)
  for i = 1, #vis do
    draw_one(renderer, fb, vis[i], true)
  end
end

local BASEYCENTER = 100
local WEAPONTOP = 32 * FRACUNIT
local FINESINE_LEN = 10240

function M.weapon_xy(player, leveltime)
  local state = player.psprite_state or "ready"
  if state == "up" or state == "down" then
    return FRACUNIT, player.psprite_sy
  end
  if state == "atk" then
    local sy = player.psprite_sy
    if not sy or sy == 0 then
      sy = WEAPONTOP
    end
    return FRACUNIT, sy
  end
  local bob = player.bob or 0
  local tables = require("tables")
  local angle = band(128 * leveltime, 8191)
  local sx = FRACUNIT + fixed_mul(bob, tables.finesine[(angle + math.floor(FINEANGLES / 4)) % FINESINE_LEN])
  angle = band(angle, math.floor(FINEANGLES / 2) - 1)
  local sy = WEAPONTOP + fixed_mul(bob, tables.finesine[angle])
  player.psprite_sy = sy
  return sx, sy
end

function M.draw_psprite(renderer, fb, patch, sx, sy)
  if not patch then
    return
  end
  local w, _h, left, top = v.patch_size(patch)
  local pspritescale = renderer.pspritescale or FRACUNIT
  local pspriteiscale = renderer.pspriteiscale or FRACUNIT
  local tx = sx - 160 * FRACUNIT
  tx = tx - left * FRACUNIT
  local x1 = shar(renderer.centerxfrac + fixed_mul(tx, pspritescale), FRACBITS)
  if x1 > renderer.viewwidth then
    return
  end
  tx = tx + w * FRACUNIT
  local x2 = shar(renderer.centerxfrac + fixed_mul(tx, pspritescale), FRACBITS) - 1
  if x2 < 0 then
    return
  end
  local vis_x1 = x1
  if vis_x1 < 0 then
    vis_x1 = 0
  end
  local vis_x2 = x2
  if vis_x2 > renderer.viewwidth - 1 then
    vis_x2 = renderer.viewwidth - 1
  end
  local startfrac = 0
  if vis_x1 > x1 then
    startfrac = startfrac + pspriteiscale * (vis_x1 - x1)
  end
  local texturemid = BASEYCENTER * FRACUNIT + math.floor(FRACUNIT / 2) - (sy - top * FRACUNIT)
  local detail = renderer.detailshift or 0
  draw_one(renderer, fb, {
    patch = patch,
    w = w,
    scale = pspritescale * (2 ^ detail),
    texturemid = texturemid,
    x1 = vis_x1,
    x2 = vis_x2,
    xiscale = pspriteiscale,
    startfrac = startfrac,
  }, false)
end

function M.draw_weapon(renderer, fb, player, leveltime)
  local player_mod = require("player")
  local sx, sy = M.weapon_xy(player, leveltime)
  local body = player_mod.weapon_body(player)
  local wadfile = renderer.res.wad
  local n = wad.check_num_for_name(wadfile, body)
  if n < 0 then
    n = wad.check_num_for_name(wadfile, "PISGA0")
  end
  if n >= 0 then
    M.draw_psprite(renderer, fb, wad.cache_lump_num(wadfile, n), sx, sy)
  end
  local flash = ""
  if (player.flash_tics or 0) > 0 then
    flash = player.psprite_flash or ""
  end
  if flash ~= "" then
    local fn = wad.check_num_for_name(wadfile, flash)
    if fn >= 0 then
      M.draw_psprite(renderer, fb, wad.cache_lump_num(wadfile, fn), sx, sy)
    end
  end
end

M.ANG45 = ANG45
M.FINEANGLES = FINEANGLES

return M
