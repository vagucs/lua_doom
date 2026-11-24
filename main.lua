-- DOOM generic portado do python_doom para Lua com SDL3.
--
-- Por Wagner Nunes da Silva
--
-- vagucs@bol.com.br
-- vagucs@vagucs.com.br
-- vagucs@gmail.com
--
-- www.vagucs.com.br
--
-- Laço a 35 Hz. A skill abre a vista e o jogador anda.

io.stdout:setvbuf("no")
io.stderr:setvbuf("no")

local wad = require("wad")
local video = require("video")
local v = require("v_video")
local menu_mod = require("menu")
local world_mod = require("world")
local rdata = require("r_data")
local render = require("render")
local sprites = require("sprites")
local collision = require("collision")
local player_mod = require("player")
local specials_mod = require("specials")
local rng = require("random")
local thinker = require("thinker")
local enemy = require("enemy")
local sound_mod = require("sound")
local status_mod = require("status")
local wi_mod = require("wi_stuff")
local wipe_mod = require("wipe")
local am_map = require("am_map")
local finale_mod = require("finale")
local saveg = require("saveg")
local cheats_mod = require("cheats")

local function take_args(argv)
  local out = {
    iwad = nil,
    files = {},
    warp = false,
    episode = 1,
    mapn = 1,
    skill = 2,
    show_fps = true,
    crt = false,
    nomonsters = false,
    fastparm = false,
    respawnparm = false,
    nosound = false,
    nomusic = false,
    nocheats = false,
    timedemo = nil,
    playdemo = nil,
  }
  local i = 1
  argv = argv or {}
  while argv[i] do
    local a = argv[i]
    if a == "-iwad" and argv[i + 1] then
      out.iwad = argv[i + 1]
      i = i + 2
    elseif a == "-warp" and argv[i + 2] then
      out.warp = true
      out.episode = tonumber(argv[i + 1]) or 1
      out.mapn = tonumber(argv[i + 2]) or 1
      i = i + 3
    elseif a == "-skill" and argv[i + 1] then
      out.skill = tonumber(argv[i + 1]) or 2
      i = i + 2
    elseif a == "-file" then
      i = i + 1
      while argv[i] and argv[i]:sub(1, 1) ~= "-" do
        out.files[#out.files + 1] = argv[i]
        i = i + 1
      end
    elseif a == "-fps" then
      out.show_fps = true
      i = i + 1
    elseif a == "-crt" then
      out.crt = true
      i = i + 1
    elseif a == "-nomonsters" then
      out.nomonsters = true
      i = i + 1
    elseif a == "-fast" then
      out.fastparm = true
      i = i + 1
    elseif a == "-respawn" then
      out.respawnparm = true
      i = i + 1
    elseif a == "-nosound" then
      out.nosound = true
      i = i + 1
    elseif a == "-nomusic" then
      out.nomusic = true
      i = i + 1
    elseif a == "-nocheats" then
      out.nocheats = true
      i = i + 1
    elseif a == "-timedemo" and argv[i + 1] then
      out.timedemo = argv[i + 1]
      out.nosound = true
      out.nomusic = true
      i = i + 2
    elseif a == "-playdemo" and argv[i + 1] then
      out.playdemo = argv[i + 1]
      i = i + 2
    elseif a:lower():sub(-4) == ".wad" and a:sub(1, 1) ~= "-" then
      out.iwad = a
      i = i + 1
    else
      i = i + 1
    end
  end
  return out
end

local opts = take_args(arg)

local TICRATE = 35
local TICK_MS = 1000 / TICRATE

local w = wad.new()
local iwad_path = opts.iwad or wad.find_iwad()
wad.add_file(w, iwad_path)
for i = 1, #opts.files do
  wad.add_file(w, opts.files[i])
end
local title = wad.cache_lump_name(w, "TITLEPIC")
local pal = wad.cache_lump_name(w, "PLAYPAL")
local res = rdata.new(w)
rdata.init(res)
res.sprites = sprites.init_defs(w)
local renderer = render.new(res)

local sound = sound_mod.new()

local game = {
  running = true,
  gamestate = "title",
  show_messages = true,
  detail_level = 0,
  screen_size = 7,
  mouse_sensitivity = 5,
  sound = sound,
  skill = opts.skill,
  episode = opts.episode,
  mapn = opts.mapn,
  warp = opts.warp,
  show_fps = opts.show_fps,
  crt = opts.crt,
  nomonsters = opts.nomonsters,
  fastparm = opts.fastparm,
  respawnparm = opts.respawnparm,
  nocheats = opts.nocheats,
  use_mouse = true,
  mouse_sensitivity = 5,
  mousex = 0,
  mousey = 0,
  mouse_fire = false,
  iwad_path = iwad_path,
  world = nil,
  wad = w,
}

function game.start_sound(name)
  sound.play(name)
end

function game.damage_mobj(target, source, damage, inflictor)
  enemy.damage_mobj(game, target, source, damage, inflictor)
end

local function copy_list(src, n)
  local out = {}
  for i = 0, n - 1 do
    out[i] = src[i]
  end
  return out
end

local function apply_carry(player, prev)
  player.health = prev.health
  player.mo.health = prev.health
  player.armorpoints = prev.armorpoints
  player.armortype = prev.armortype
  player.ammo = prev.ammo
  player.maxammo = prev.maxammo
  player.weaponowned = prev.weaponowned
  player.pendingweapon = 10
  player.readyweapon = prev.readyweapon
  player.psprite_state = "up"
  player.psprite_sy = 128 * 65536
  player.psprite_body = ""
  player.cheats = prev.cheats
  player.didsecret = prev.didsecret
  player.cards = { [0] = false, false, false, false, false, false }
  player.damagecount = 0
  player.bonuscount = 0
  player.extralight = 0
  player.playerstate = 0
end

local function commercial_wad()
  return wad.check_num_for_name(w, "MAP01") >= 0
end

local function arm_title(self)
  self.gamestate = "title"
  self.carry = nil
  self.player = nil
  self.world = nil
  self.specials = nil
  self.wi = nil
  self.finale = nil
  self.wiping = false
  self.demo_playback = false
  self.demo_buffer = nil
  self.demo_sequence = -1
  self.advancedemo = true
  self.page_patch = title
end

local function lump_patch(name)
  local n = wad.check_num_for_name(w, name)
  if n < 0 then
    return nil
  end
  return wad.cache_lump_num(w, n)
end

function game.touch_special(special, toucher)
  player_mod.touch_special(game, special, toucher)
end

function game.use_special(line, thing, side)
  if game.specials then
    return specials_mod.use_special(game.specials, line, thing, side)
  end
  return false
end

function game.cross_special(line, side, thing)
  if game.specials then
    specials_mod.cross_special(game.specials, line, side, thing)
  end
end

function game.shoot_special(line, thing)
  if game.specials then
    specials_mod.shoot_special(game.specials, line, thing)
  end
end

function game.begin_exit(self)
  if self.automap then
    am_map.stop(self.automap)
  end
  local p = self.player
  local secret = self.specials and self.specials.secret_exit
  self.was_secret = secret and true or false
  local commercial = wad.check_num_for_name(w, "MAP01") >= 0
  if p and self.mapn == 9 then
    p.didsecret = true
  end
  if p then
    self.carry = {
      health = p.health,
      armorpoints = p.armorpoints,
      armortype = p.armortype,
      ammo = copy_list(p.ammo, 4),
      maxammo = copy_list(p.maxammo, 4),
      weaponowned = copy_list(p.weaponowned, 9),
      readyweapon = p.readyweapon,
      cheats = p.cheats,
      didsecret = (self.mapn == 9) or p.didsecret or secret or false,
    }
  end
  if not commercial and self.mapn == 8 then
    self.finale = finale_mod.new(self)
    self.gamestate = "finale"
    print("finale")
    return
  end
  local nxt
  if secret then
    nxt = 9
  elseif self.mapn == 9 then
    local back = { [1] = 4, [2] = 6, [3] = 7, [4] = 3 }
    nxt = back[self.episode] or 1
  else
    nxt = self.mapn + 1
  end
  self.pending_map = nxt
  local kills = self.totalkills or 0
  local items = self.totalitems or 0
  local secrets = self.totalsecret or 0
  if kills < 1 then
    kills = 1
  end
  if items < 1 then
    items = 1
  end
  if secrets < 1 then
    secrets = 1
  end
  self.wi = wi_mod.new(self, {
    epsd = self.episode - 1,
    last = self.mapn - 1,
    next = nxt - 1,
    maxkills = kills,
    maxitems = items,
    maxsecret = secrets,
    partime = wi_mod.partime(self.episode, self.mapn, commercial),
    skills = p and (p.killcount or 0) or 0,
    sitems = p and (p.itemcount or 0) or 0,
    ssecret = p and (p.secretcount or 0) or 0,
    stime = self.leveltime or 0,
    didsecret = p and p.didsecret or false,
    commercial = commercial,
  })
  self.gamestate = "intermission"
  print(string.format("intermissao E%dM%d", self.episode, nxt))
end

function game.finish_finale(self)
  local action = "title"
  if self.finale and self.finale.action ~= "" then
    action = self.finale.action
  end
  self.finale = nil
  if action == "worlddone" then
    self.mapn = self.pending_map
    self.start_level(self)
    return
  end
  arm_title(self)
end

function game.advance(self)
  local commercial = wad.check_num_for_name(w, "MAP01") >= 0
  if commercial and finale_mod.commercial_map(self.mapn, self.was_secret) then
    self.finale = finale_mod.new(self)
    self.gamestate = "finale"
    return
  end
  local lump = string.format("E%dM%d", self.episode, self.pending_map)
  if wad.check_num_for_name(w, "MAP01") >= 0 then
    lump = string.format("MAP%02d", self.pending_map)
  end
  if wad.check_num_for_name(w, lump) < 0 then
    arm_title(self)
    return
  end
  self.mapn = self.pending_map
  self.start_level(self)
end

function game.end_game(self)
  if self.automap then
    am_map.stop(self.automap)
  end
  self.finale = nil
  self.wi = nil
  arm_title(self)
end

function game.save_game(self, slot, desc)
  local name = desc
  if (name == nil or name == "") and self.world then
    name = self.world.mapname
  end
  return saveg.write(self, slot, name or "save")
end

function game.load_game(self, slot)
  return saveg.load(self, slot)
end

function game.slot_desc(self, slot)
  return saveg.description(self, slot)
end

function game.start_level(self)
  if not self.keep_demo then
    self.demo_playback = false
    self.advancedemo = false
    self.demo_buffer = nil
  end
  self.keep_demo = false
  if self.automap then
    am_map.reset_level(self.automap)
  end
  rng.clear()
  local world = world_mod.new()
  world_mod.setup_level(world, w, res, self.episode, self.mapn)
  self.world = world
  self.res = res
  self.player = nil
  self.specials = specials_mod.new(world, res, sound)
  self.specials.game = self
  local kills, items = thinker.spawn_map(world, self.skill, self)
  if self.specials then
    specials_mod.spawn_specials(self.specials)
  end
  local secrets = 0
  for i = 1, #world.sectors do
    if world.sectors[i].special == 9 then
      secrets = secrets + 1
    end
  end
  self.totalkills = kills
  self.totalitems = items
  self.totalsecret = secrets
  thinker.apply_fast(self)
  if self.status and self.player then
    status_mod.reset(self.status, self.player)
  end
  sound_mod.cut_sfx(sound)
  sound_mod.play_level_music(sound, self.episode, self.mapn)
  self.gamestate = "view"
  self.leveltime = 0
  self.turnheld = 0
  local ps = world_mod.player_start(world)
  local px, py = 0, 0
  if ps then
    px, py = ps.x, ps.y
  end
  if self.player and self.carry then
    apply_carry(self.player, self.carry)
    self.carry = nil
  end
  print(string.format(
    "vista %s  linhas %d  coisas %d  jogador %d,%d",
    world.mapname, #world.lines, #world.mobjs, px, py
  ))
end

local function map_unit(v)
  v = v or 0
  if v >= 0 then
    return math.floor(v / 65536)
  end
  return -math.floor((-v) / 65536)
end

local function sync_log()
  if not game.timingdemo or game.sync_fh == nil or game.player == nil or game.player.mo == nil then
    return
  end
  local mo = game.player.mo
  local n, sx = 0, 0
  local compat = require("compat")
  for i = 1, #game.world.mobjs do
    local m = game.world.mobjs[i]
    if compat.band(m.flags or 0, 4194304) ~= 0 and (m.health or 0) > 0 then
      n = n + 1
      sx = sx + map_unit(m.x)
    end
  end
  local ammo = 0
  if game.player.ammo then
    ammo = game.player.ammo[3] or 0
  end
  game.sync_fh:write(string.format(
    "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
    game.leveltime or 0,
    game.player.health or 0,
    game.player.armorpoints or 0,
    map_unit(mo.x), map_unit(mo.y), map_unit(mo.z), map_unit(mo.floorz),
    math.floor(mo.momx or 0), math.floor(mo.momy or 0), math.floor(mo.angle or 0),
    n, sx, rng.index(),
    game.player.readyweapon or 0, ammo
  ))
end

local function finish_demo()
  game.demo_playback = false
  game.demo_buffer = nil
  if game.timingdemo or game.singledemo then
    game.running = false
    return
  end
  game.advancedemo = true
end

local function read_demo_ticcmd()
  local buf = game.demo_buffer
  local p = game.demo_p or 1
  local need = 4
  if game.longtics then
    need = 5
  end
  if buf == nil or p + need - 1 > #buf or buf:byte(p) == 128 then
    finish_demo()
    return nil
  end
  local function sbyte()
    local n = buf:byte(game.demo_p)
    game.demo_p = game.demo_p + 1
    if n >= 128 then
      n = n - 256
    end
    return n
  end
  game.demo_p = p
  local cmd = player_mod.empty_cmd()
  cmd.forwardmove = sbyte()
  cmd.sidemove = sbyte()
  if game.longtics then
    local low = buf:byte(game.demo_p)
    game.demo_p = game.demo_p + 1
    local high = buf:byte(game.demo_p)
    game.demo_p = game.demo_p + 1
    cmd.angleturn = low + high * 256
  else
    cmd.angleturn = buf:byte(game.demo_p) * 256
    game.demo_p = game.demo_p + 1
  end
  if cmd.angleturn >= 32768 then
    cmd.angleturn = cmd.angleturn - 65536
  end
  cmd.buttons = buf:byte(game.demo_p)
  game.demo_p = game.demo_p + 1
  return cmd
end

local function play_demo(name, timed)
  local lump = string.upper(name)
  if wad.check_num_for_name(w, lump) < 0 then
    print("demo ausente: " .. lump)
    return false
  end
  local data = wad.cache_lump_name(w, lump)
  if data == nil or #data < 4 then
    return false
  end
  game.demo_buffer = data
  game.demo_p = 1
  local ver = data:byte(1)
  game.demo_p = 2
  game.longtics = false
  if ver <= 4 then
    game.demo_p = 1
  elseif ver == 111 then
    game.longtics = true
  end
  if game.demo_p + 2 > #data then
    return false
  end
  local skill = data:byte(game.demo_p)
  game.demo_p = game.demo_p + 1
  local episode = data:byte(game.demo_p)
  game.demo_p = game.demo_p + 1
  local mapn = data:byte(game.demo_p)
  game.demo_p = game.demo_p + 1
  if ver > 4 then
    if game.demo_p + 8 > #data then
      return false
    end
    game.demo_p = game.demo_p + 1
    game.respawnparm = data:byte(game.demo_p) ~= 0
    game.demo_p = game.demo_p + 1
    game.fastparm = data:byte(game.demo_p) ~= 0
    game.demo_p = game.demo_p + 1
    game.nomonsters = data:byte(game.demo_p) ~= 0
    game.demo_p = game.demo_p + 1
    game.demo_p = game.demo_p + 5
  end
  if skill < 0 then
    skill = 0
  end
  if skill > 4 then
    skill = 4
  end
  game.skill = skill
  if episode >= 1 then
    game.episode = episode
  end
  if mapn >= 1 then
    game.mapn = mapn
  end
  game.keep_demo = true
  game.timingdemo = timed and true or false
  game.demo_playback = true
  if timed then
    game.timedemo_name = string.lower(name)
    if game.sync_fh then
      game.sync_fh:close()
      game.sync_fh = nil
    end
    game.sync_fh = io.open("_sync_" .. game.timedemo_name .. ".log", "w")
    print("timedemo " .. lump)
  end
  game.start_level(game)
  game.gamestate = "view"
  return true
end

local credit_patch = lump_patch("CREDIT")
local help2_patch = lump_patch("HELP2")

local function show_page(patch, tics, music)
  game.page_tic = tics
  game.page_patch = patch or title
  game.gamestate = "title"
  game.demo_playback = false
  game.demo_buffer = nil
  game.player = nil
  game.world = nil
  game.specials = nil
  if music then
    sound_mod.play_title_music(sound)
  end
end

local function do_advance_demo()
  for _ = 1, 8 do
    game.advancedemo = false
    game.demo_playback = false
    game.demo_sequence = ((game.demo_sequence or -1) + 1) % 6
    local seq = game.demo_sequence
    if seq == 0 then
      show_page(title, commercial_wad() and TICRATE * 11 or 170, true)
      return
    elseif seq == 1 then
      if play_demo("demo1", false) then
        return
      end
    elseif seq == 2 then
      show_page(credit_patch or title, 200, false)
      return
    elseif seq == 3 then
      if play_demo("demo2", false) then
        return
      end
    elseif seq == 4 then
      if commercial_wad() then
        show_page(title, TICRATE * 11, true)
      elseif wad.check_num_for_name(w, "E2M1") < 0 then
        show_page(help2_patch or credit_patch or title, 200, false)
      else
        show_page(credit_patch or title, 200, false)
      end
      return
    elseif play_demo("demo3", false) then
      return
    end
  end
end

local menu = menu_mod.new(w, sound, game)
game.menu = menu
game.status = status_mod.new(w)
game.automap = am_map.new()
game.cheats = cheats_mod.new()
game.wipe = wipe_mod.new()
game.wiping = false
game.st_palette = 0
local fb = v.new_fb()
local raw = nil
local dirty = true

local jitlib = rawget(_G, "jit")
local runtime = jitlib and ("luajit " .. tostring(jitlib.version)) or _VERSION
print("lua_doom: " .. runtime .. "  Tab abre o mapa, o texto final conta a historia")
print("texturas " .. #res.textures .. "  flats " .. #res.flattranslation)

video.init(v.SCREENWIDTH, v.SCREENHEIGHT, 2, "DOOM (" .. runtime .. ")")
video.set_palette(pal)
video.set_crt(game.crt)
sound_mod.init(sound, w)
if opts.nosound then
  sound.enabled = false
end
if opts.nomusic then
  sound.music_enabled = false
end
if opts.timedemo then
  play_demo(opts.timedemo, true)
elseif opts.playdemo then
  game.singledemo = true
  print("playdemo " .. string.upper(opts.playdemo))
  if not play_demo(opts.playdemo, false) then
    os.exit(1)
  end
elseif game.warp then
  game.start_level(game)
  game.wipe_state = "view"
else
  game.demo_sequence = -1
  game.advancedemo = true
  do_advance_demo()
end

local function paint_view()
  if game.automap and game.automap.active then
    v.fill(fb, 0)
    am_map.drawer(game.automap, fb, game)
    if game.status and game.player then
      status_mod.draw(game.status, fb, game.player, game.show_messages)
    end
    return
  end
  local p = game.player
  local mo = p and p.mo
  local x, y, z, ang = 0, 0, 41 * 65536, 0
  local extra, cmap = 0, 0
  if mo then
    x, y, z, ang = mo.x, mo.y, p.viewz, mo.angle
    extra = p.extralight or 0
    cmap = p.fixedcolormap or 0
  end
  render.set_view_size(renderer, game.screen_size + 3, game.detail_level)
  render.setup_frame(renderer, x, y, z, ang, extra, cmap)
  v.fill(fb, 0)
  render.render(renderer, game.world, fb)
  sprites.draw(renderer, game.world, fb)
  render.draw_masked(renderer)
  if p and (p.playerstate ~= player_mod.PST_DEAD or p.psprite_sy < player_mod.WEAPONBOTTOM) then
    sprites.draw_weapon(renderer, fb, p, game.leveltime or 0)
  end
  if game.status and game.player and renderer.screenblocks < 11 then
    status_mod.draw(game.status, fb, game.player, game.show_messages)
  end
end

local function apply_palette()
  local paln = 0
  local p = game.player
  if p and game.gamestate == "view" then
    local cnt = p.damagecount or 0
    local strength = 0
    if p.powers then
      strength = p.powers[1] or 0
    end
    if strength ~= 0 then
      local bzc = 12 - math.floor(strength / 64)
      if bzc > cnt then
        cnt = bzc
      end
    end
    if cnt ~= 0 then
      paln = math.floor((cnt + 7) / 8)
      if paln >= 8 then
        paln = 7
      end
      paln = paln + 1
    elseif (p.bonuscount or 0) ~= 0 then
      paln = math.floor((p.bonuscount + 7) / 8)
      if paln >= 4 then
        paln = 3
      end
      paln = paln + 9
    else
      local feet = 0
      if p.powers then
        feet = p.powers[3] or 0
      end
      if feet > 4 * 32 or (feet % 16) >= 8 then
        paln = 13
      end
    end
  end
  if paln == game.st_palette then
    return
  end
  game.st_palette = paln
  local off = paln * 768
  video.set_palette(pal:sub(off + 1, off + 768))
end

local function paint_state()
  if game.gamestate == "view" and game.world then
    paint_view()
  elseif game.gamestate == "intermission" and game.wi then
    v.fill(fb, 0)
    wi_mod.draw(game.wi, fb)
  elseif game.gamestate == "finale" and game.finale then
    finale_mod.draw(game.finale, fb)
  else
    v.fill(fb, 0)
    v.draw_patch(fb, 0, 0, game.page_patch or title)
  end
end

local function draw_fps()
  if not game.show_fps or not game.status then
    return
  end
  local text = game.fps_text or "0 FPS  avg 0.0"
  local width = status_mod.text_width(game.status, text)
  local x = v.SCREENWIDTH - 6 - width
  if x < 0 then
    x = 0
  end
  status_mod.draw_text(game.status, fb, x, 4, text)
end

local function redraw()
  if game.wiping then
    menu_mod.draw(menu, fb)
    draw_fps()
    raw = v.to_raw(fb)
    dirty = false
    apply_palette()
    return
  end
  local prev = game.wipe_state
  local need = prev ~= nil and (prev ~= game.gamestate or game.force_wipe)
  if prev == "title" and game.gamestate == "view" and not game.force_wipe then
    need = false
  end
  game.force_wipe = false
  if need then
    wipe_mod.capture_start(game.wipe, fb)
  end
  paint_state()
  if need then
    wipe_mod.capture_end(game.wipe, fb)
    wipe_mod.begin(game.wipe, fb)
    game.wiping = true
  end
  game.wipe_state = game.gamestate
  menu_mod.draw(menu, fb)
  draw_fps()
  raw = v.to_raw(fb)
  dirty = false
  apply_palette()
end

local held = {}
local accum = 0
local last = video.ticks()
local fps_n = 0
local fps_t = last
local fps_avg_n = 0
local fps_avg_t = last
game.fps_text = "0 FPS  avg 0.0"

local function run_view_tic()
  if not (game.gamestate == "view" and game.player and game.world) then
    return false
  end
  if game.automap and not game.timingdemo then
    am_map.ticker(game.automap, game)
  end
  if game.demo_playback then
    local cmd = read_demo_ticcmd()
    if cmd == nil then
      return true
    end
    game.player.cmd = cmd
  elseif menu.active then
    game.player.cmd = player_mod.empty_cmd()
    game.mousex = 0
    game.mousey = 0
  else
    local cmd, heldn = player_mod.build_ticcmd(
      held, game.turnheld or 0, game.player,
      game.mousex, game.mousey, game.mouse_sensitivity, game.mouse_fire
    )
    game.turnheld = heldn
    game.player.cmd = cmd
    game.mousex = 0
    game.mousey = 0
  end
  player_mod.think(game.world, game.player, game, game.leveltime or 0)
  if game.player and game.player.playerstate == player_mod.PST_REBORN then
    game.start_level(game)
    return false
  end
  thinker.tick(game.world, game, false)
  if game.specials then
    specials_mod.tick_lights_early(game.specials)
  end
  thinker.tick(game.world, game, true)
  if game.specials then
    specials_mod.tick(game.specials)
  end
  if game.specials and game.specials.exit_requested then
    game.begin_exit(game)
    return true
  end
  sync_log()
  game.leveltime = (game.leveltime or 0) + 1
  player_mod.tick_fx(game.world)
  if game.status then
    status_mod.ticker(game.status, game.player)
  end
  return false
end

if game.timingdemo then
  local t0 = video.ticks()
  while game.running and game.demo_playback and game.gamestate == "view" do
    run_view_tic()
  end
  if game.sync_fh then
    game.sync_fh:close()
    game.sync_fh = nil
  end
  print(string.format("timed %d gametics in %d realtics", game.leveltime or 0, video.ticks() - t0))
  os.exit(0)
end

while game.running do
  local events = video.poll()
  for i = 1, #events do
    local ev = events[i]
    if ev.mouse then
      if ev.dx then
        game.mousex = game.mousex + ev.dx
        game.mousey = game.mousey - ev.dy
      end
      if ev.button == 1 then
        game.mouse_fire = ev.down and true or false
      end
    elseif ev.down and ev.key == "quit" then
      game.running = false
    elseif ev.down and ev.key == "f11" then
      game.show_fps = not game.show_fps
      fps_n = 0
      fps_avg_n = 0
      fps_t = video.ticks()
      fps_avg_t = fps_t
      game.fps_text = "0 FPS  avg 0.0"
      held[ev.key] = nil
      dirty = true
    elseif ev.key ~= "" then
      if ev.down and ev.key == "return" and (held.alt or ev.alt) then
        video.toggle_fullscreen()
      elseif ev.down and game.demo_playback and game.singledemo then
        game.running = false
      elseif ev.down and game.demo_playback and not game.timingdemo then
        game.demo_playback = false
        game.demo_buffer = nil
        game.advancedemo = false
        game.gamestate = "title"
        game.player = nil
        game.world = nil
        game.specials = nil
        game.page_patch = title
        game.page_tic = commercial_wad() and (TICRATE * 11) or 170
        sound_mod.play_title_music(sound)
        if not menu.active then
          menu_mod.start(menu)
        end
        held[ev.key] = nil
        dirty = true
      elseif ev.down then
        local block_menu = (game.gamestate == "intermission" or game.gamestate == "finale")
          and not menu.active and ev.key == "return"
        local used = false
        if not block_menu and menu_mod.responder(menu, ev.key) then
          used = true
          dirty = true
        end
        if not used and game.automap and am_map.responder(game.automap, ev.key, true, game) then
          used = true
          dirty = true
        end
        if used then
          held[ev.key] = nil
        else
          held[ev.key] = true
          if game.finale and game.gamestate == "finale" then
            finale_mod.responder(game.finale)
          end
          if game.cheats then
            cheats_mod.feed(game.cheats, ev.key, game)
          end
          if game.gamestate == "view" and not menu.active then
            if ev.key == "equals" and game.screen_size < 8 then
              game.screen_size = game.screen_size + 1
              dirty = true
            elseif ev.key == "minus" and game.screen_size > 0 then
              game.screen_size = game.screen_size - 1
              dirty = true
            end
          end
        end
      else
        held[ev.key] = nil
        if game.automap then
          am_map.responder(game.automap, ev.key, false, game)
        end
      end
    end
  end
  local now = video.ticks()
  accum = accum + (now - last)
  last = now
  local guard = 0
  game.held = held
  while accum >= TICK_MS and guard < 4 do
    if game.wiping then
      if wipe_mod.tick(game.wipe, 1, fb) then
        game.wiping = false
      end
      dirty = true
    else
    if menu_mod.ticker(menu) then
      dirty = true
    end
    if not menu.active and game.advancedemo then
      do_advance_demo()
      dirty = true
    end
    if game.gamestate == "title" then
      if not menu.active then
        game.page_tic = (game.page_tic or 0) - 1
        if game.page_tic < 0 then
          game.advancedemo = true
        end
      end
    elseif game.gamestate == "view" and game.player and game.world then
      if run_view_tic() then
        break
      end
      dirty = true
    elseif game.gamestate == "intermission" and game.wi then
      wi_mod.ticker(game.wi)
      if game.wi.done then
        game.wi = nil
        game.advance(game)
      end
      dirty = true
    elseif game.gamestate == "finale" and game.finale then
      finale_mod.ticker(game.finale)
      if game.finale and game.finale.done then
        game.finish_finale(game)
      end
      dirty = true
    end
    end
    accum = accum - TICK_MS
    guard = guard + 1
  end
  if accum > TICK_MS * 4 then
    accum = 0
  end
  if dirty or raw == nil then
    redraw()
  end
  sound_mod.update(sound)
  video.mouse_relative(game.use_mouse and game.gamestate == "view" and not menu.active)
  video.present(raw)
  video.delay(1)
  if game.show_fps then
    fps_n = fps_n + 1
    fps_avg_n = fps_avg_n + 1
    local fps_now = video.ticks()
    local elapsed = fps_now - fps_avg_t
    local avg = 0
    if elapsed > 0 then
      avg = fps_avg_n * 1000 / elapsed
    end
    if fps_now - fps_t >= 1000 then
      game.fps_text = string.format("%d FPS  avg %.1f", fps_n, avg)
      fps_n = 0
      fps_t = fps_now
      dirty = true
    end
  end
end

sound_mod.shutdown(sound)
video.shutdown()
print("janela fechada")
