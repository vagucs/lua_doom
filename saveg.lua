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
-- Save de 6 vagas. Cabecalho de 24 bytes, magica DOOMPY01 e JSON, como saveg.py.

local collision = require("collision")

local M = {}

local SAVESTRINGSIZE = 24
local MAGIC = "DOOMPY01"
local EMPTY = "empty slot"

local function enc_str(s)
  return '"' .. (s or ""):gsub('[%z\1-\31\\"]', function(c)
    if c == '"' then
      return '\\"'
    end
    if c == "\\" then
      return "\\\\"
    end
    if c == "\n" then
      return "\\n"
    end
    if c == "\r" then
      return "\\r"
    end
    if c == "\t" then
      return "\\t"
    end
    return string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function enc(v)
  if v == nil then
    return "null"
  end
  local t = type(v)
  if t == "boolean" then
    if v then
      return "true"
    end
    return "false"
  end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      return "null"
    end
    if v == math.floor(v) and math.abs(v) < 9007199254740992 then
      return string.format("%.0f", v)
    end
    return string.format("%.17g", v)
  end
  if t == "string" then
    return enc_str(v)
  end
  if t == "table" then
    if v._json == "array" then
      local parts = {}
      for i = 1, #v do
        parts[i] = enc(v[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local parts = {}
    for i = 1, #v do
      parts[i] = enc_str(v[i][1]) .. ":" .. enc(v[i][2])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

local function arr(list)
  list._json = "array"
  return list
end

local function skip(s, i)
  local n = #s
  while i <= n do
    local c = s:sub(i, i)
    if c ~= " " and c ~= "\n" and c ~= "\r" and c ~= "\t" then
      return i
    end
    i = i + 1
  end
  return i
end

local function parse_at(s, i)
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local obj = {}
    i = i + 1
    i = skip(s, i)
    if s:sub(i, i) == "}" then
      return obj, i + 1
    end
    while true do
      local key
      key, i = parse_at(s, i)
      i = skip(s, i)
      i = i + 1
      local val
      val, i = parse_at(s, i)
      if key ~= nil then
        obj[key] = val
      end
      i = skip(s, i)
      c = s:sub(i, i)
      if c == "}" then
        return obj, i + 1
      end
      i = i + 1
    end
  end
  if c == "[" then
    local list = {}
    i = i + 1
    i = skip(s, i)
    if s:sub(i, i) == "]" then
      return list, i + 1
    end
    while true do
      local val
      val, i = parse_at(s, i)
      list[#list + 1] = val
      i = skip(s, i)
      c = s:sub(i, i)
      if c == "]" then
        return list, i + 1
      end
      i = i + 1
    end
  end
  if c == '"' then
    i = i + 1
    local out = {}
    while i <= #s do
      local ch = s:sub(i, i)
      if ch == '"' then
        return table.concat(out), i + 1
      end
      if ch == "\\" then
        local e = s:sub(i + 1, i + 1)
        if e == "n" then
          out[#out + 1] = "\n"
        elseif e == "r" then
          out[#out + 1] = "\r"
        elseif e == "t" then
          out[#out + 1] = "\t"
        elseif e == "u" then
          local hex = s:sub(i + 2, i + 5)
          out[#out + 1] = string.char(tonumber(hex, 16) or 0)
          i = i + 4
        else
          out[#out + 1] = e
        end
        i = i + 2
      else
        out[#out + 1] = ch
        i = i + 1
      end
    end
    return table.concat(out), i
  end
  if s:sub(i, i + 3) == "true" then
    return true, i + 4
  end
  if s:sub(i, i + 4) == "false" then
    return false, i + 5
  end
  if s:sub(i, i + 3) == "null" then
    return nil, i + 4
  end
  local rest = s:sub(i)
  local num = rest:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*")
  if num == nil or num == "" or num == "-" then
    return nil, i + 1
  end
  return tonumber(num), i + #num
end

function M.decode(text)
  local value = parse_at(text, 1)
  return value
end

function M.encode(pairs)
  return enc(pairs)
end

local function save_dir(game)
  local path = game.iwad_path or ""
  local dir = path:match("^(.*)[/\\][^/\\]+$")
  if dir ~= nil and dir ~= "" then
    return dir
  end
  return "."
end

function M.path(game, slot)
  local dir = save_dir(game)
  local sep = "\\"
  if dir:find("/", 1, true) and not dir:find("\\", 1, true) then
    sep = "/"
  end
  if dir == "." then
    sep = ""
    dir = ""
  end
  return dir .. sep .. "doomsav" .. tostring(slot) .. ".dsg"
end

local function pad_desc(text)
  text = tostring(text or "")
  if #text > SAVESTRINGSIZE then
    text = text:sub(1, SAVESTRINGSIZE)
  end
  return text .. string.rep("\0", SAVESTRINGSIZE - #text)
end

local function decode_desc(raw)
  local cut = raw:find("\0", 1, true)
  if cut then
    raw = raw:sub(1, cut - 1)
  end
  return (raw:gsub("%s+$", ""))
end

function M.description(game, slot)
  local f = io.open(M.path(game, slot), "rb")
  if f == nil then
    return EMPTY, false
  end
  local header = f:read(SAVESTRINGSIZE + #MAGIC)
  f:close()
  if header == nil or #header < SAVESTRINGSIZE + #MAGIC then
    return EMPTY, false
  end
  if header:sub(SAVESTRINGSIZE + 1, SAVESTRINGSIZE + #MAGIC) ~= MAGIC then
    return EMPTY, false
  end
  local desc = decode_desc(header:sub(1, SAVESTRINGSIZE))
  if desc == "" then
    desc = EMPTY
  end
  return desc, true
end

local function num_list(src, n)
  local list = {}
  for i = 0, n - 1 do
    list[i + 1] = src[i] or 0
  end
  return arr(list)
end

local function bool_list(src, n)
  local list = {}
  for i = 0, n - 1 do
    list[i + 1] = src[i] and true or false
  end
  return arr(list)
end

local function mobj_index(mobjs, mo)
  if mo == nil then
    return nil
  end
  for i = 1, #mobjs do
    if mobjs[i] == mo then
      return i - 1
    end
  end
  return nil
end

local function dump_mobj(mo, mobjs)
  return {
    { "x", mo.x or 0 },
    { "y", mo.y or 0 },
    { "z", mo.z or 0 },
    { "angle", mo.angle or 0 },
    { "momx", mo.momx or 0 },
    { "momy", mo.momy or 0 },
    { "momz", mo.momz or 0 },
    { "radius", mo.radius or 0 },
    { "height", mo.height or 0 },
    { "floorz", mo.floorz or 0 },
    { "ceilingz", mo.ceilingz or 0 },
    { "flags", mo.flags or 0 },
    { "health", mo.health or 0 },
    { "type", mo.type or 0 },
    { "sprite", mo.sprite or "" },
    { "info", nil },
    { "alive", mo.alive ~= false },
    { "reactiontime", mo.reactiontime or 0 },
    { "target", mobj_index(mobjs, mo.target) },
    { "movedir", mo.movedir or 0 },
    { "movecount", mo.movecount or 0 },
    { "ai_state", "" },
    { "istate", mo.istate or 0 },
    { "frame", mo.frame or 0 },
    { "tics", mo.tics or 0 },
    { "chase_tics", mo.chase_tics or 0 },
    { "just_attacked", mo.just_attacked and true or false },
    { "damage", mo.damage or 0 },
    { "attack_kind", mo.attack_kind or "" },
    { "did_fire", mo.did_fire and true or false },
    { "is_player", mo.player ~= nil },
  }
end

local function dump_player(p)
  return {
    { "playerstate", p.playerstate or 0 },
    { "viewz", p.viewz or 0 },
    { "viewheight", p.viewheight or 0 },
    { "deltaviewheight", p.deltaviewheight or 0 },
    { "bob", p.bob or 0 },
    { "health", p.health or 0 },
    { "armorpoints", p.armorpoints or 0 },
    { "armortype", p.armortype or 0 },
    { "ammo", num_list(p.ammo or {}, 4) },
    { "maxammo", num_list(p.maxammo or {}, 4) },
    { "weaponowned", bool_list(p.weaponowned or {}, 9) },
    { "pendingweapon", p.pendingweapon or 0 },
    { "readyweapon", p.readyweapon or 0 },
    { "cards", bool_list(p.cards or {}, 6) },
    { "cheats", p.cheats or 0 },
    { "message", p.message or "" },
    { "message_tics", p.message_tics or 0 },
    { "attackdown", p.attackdown and true or false },
    { "usedown", p.usedown and true or false },
    { "damagecount", p.damagecount or 0 },
    { "bonuscount", p.bonuscount or 0 },
    { "extralight", p.extralight or 0 },
    { "refire", p.refire or 0 },
    { "killcount", p.killcount or 0 },
    { "itemcount", p.itemcount or 0 },
    { "secretcount", p.secretcount or 0 },
    { "didsecret", p.didsecret and true or false },
    { "psprite_y", p.psprite_sy or 0 },
    { "psprite_sy", p.psprite_sy or 0 },
    { "psprite_state", p.psprite_state or "" },
    { "psprite_tics", p.psprite_tics or 0 },
    { "psprite_step", p.psprite_step or 0 },
    { "psprite_body", p.psprite_body or "" },
    { "psprite_flash", p.psprite_flash or "" },
    { "flash_tics", p.flash_tics or 0 },
    { "powers", num_list(p.powers or {}, 6) },
  }
end

local function sector_index(world, sector)
  for i = 1, #world.sectors do
    if world.sectors[i] == sector then
      return i - 1
    end
  end
  return -1
end

local function dump_thinker(th, world)
  local sec_i = sector_index(world, th.sector)
  if sec_i < 0 then
    return nil
  end
  if th.kind == "door" then
    return {
      { "kind", "door" },
      { "sector", sec_i },
      { "type", th.type or 0 },
      { "direction", th.direction or 0 },
      { "topheight", th.topheight or 0 },
      { "speed", th.speed or 0 },
      { "topwait", th.topwait or 0 },
      { "topcountdown", th.topcountdown or 0 },
    }
  end
  if th.kind == "plat" then
    return {
      { "kind", "plat" },
      { "sector", sec_i },
      { "type", th.type or 0 },
      { "status", th.status or 0 },
      { "speed", th.speed or 0 },
      { "low", th.low or 0 },
      { "high", th.high or 0 },
      { "wait", th.wait or 0 },
      { "count", th.count or 0 },
    }
  end
  if th.kind == "floor" then
    return {
      { "kind", "floor" },
      { "sector", sec_i },
      { "direction", th.direction or 0 },
      { "dest", th.dest or 0 },
      { "speed", th.speed or 0 },
    }
  end
  return nil
end

local function dump_state(game)
  local world = game.world
  local mobjs = world.mobjs or {}
  local mobj_rows = {}
  for i = 1, #mobjs do
    mobj_rows[i] = dump_mobj(mobjs[i], mobjs)
  end
  local sectors = {}
  for i = 1, #world.sectors do
    local s = world.sectors[i]
    sectors[i] = {
      { "floorheight", s.floorheight or 0 },
      { "ceilingheight", s.ceilingheight or 0 },
      { "floorpic", s.floorpic or 0 },
      { "ceilingpic", s.ceilingpic or 0 },
      { "lightlevel", s.lightlevel or 0 },
      { "special", s.special or 0 },
    }
  end
  local sides = {}
  for i = 1, #(world.sides or {}) do
    local sd = world.sides[i]
    sides[i] = {
      { "textureoffset", sd.textureoffset or 0 },
      { "rowoffset", sd.rowoffset or 0 },
      { "toptexture", sd.toptexture or 0 },
      { "bottomtexture", sd.bottomtexture or 0 },
      { "midtexture", sd.midtexture or 0 },
    }
  end
  local lines = {}
  for i = 1, #(world.lines or {}) do
    local ln = world.lines[i]
    lines[i] = {
      { "flags", ln.flags or 0 },
      { "special", ln.special or 0 },
    }
  end
  local thinkers = {}
  if game.specials and game.specials.thinkers then
    for i = 1, #game.specials.thinkers do
      local th = game.specials.thinkers[i]
      if not th.dead then
        local rec = dump_thinker(th, world)
        if rec then
          thinkers[#thinkers + 1] = rec
        end
      end
    end
  end
  local buttons = {}
  if game.specials and game.specials.buttons then
    for i = 1, #game.specials.buttons do
      local btn = game.specials.buttons[i]
      local line = btn.line
      local idx = -1
      if line and line.i_line ~= nil then
        idx = line.i_line
      end
      buttons[#buttons + 1] = {
        { "line", idx },
        { "where", btn.attr or "toptexture" },
        { "texture", btn.texture or 0 },
        { "timer", btn.timer or 0 },
      }
    end
  end
  return {
    { "episode", game.episode or 1 },
    { "mapn", game.mapn or 1 },
    { "skill", game.skill or 2 },
    { "leveltime", game.leveltime or 0 },
    { "player", dump_player(game.player) },
    { "sectors", arr(sectors) },
    { "sides", arr(sides) },
    { "lines", arr(lines) },
    { "mobjs", arr(mobj_rows) },
    { "thinkers", arr(thinkers) },
    { "buttons", arr(buttons) },
    { "totalkills", game.totalkills or 0 },
    { "totalitems", game.totalitems or 0 },
    { "totalsecret", game.totalsecret or 0 },
  }
end

function M.write(game, slot, description)
  if game.world == nil or game.player == nil then
    return false
  end
  local payload = enc(dump_state(game))
  local blob = pad_desc(description) .. MAGIC .. payload
  local path = M.path(game, slot)
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "wb")
  if f == nil then
    return false
  end
  f:write(blob)
  f:close()
  os.remove(path)
  if not os.rename(tmp, path) then
    return false
  end
  return true
end

function M.read(game, slot)
  local f = io.open(M.path(game, slot), "rb")
  if f == nil then
    return nil
  end
  local data = f:read("*a")
  f:close()
  local need = SAVESTRINGSIZE + #MAGIC
  if data == nil or #data < need then
    return nil
  end
  if data:sub(SAVESTRINGSIZE + 1, need) ~= MAGIC then
    return nil
  end
  return M.decode(data:sub(need + 1))
end

local function copy_nums(dst, src)
  if src == nil then
    return
  end
  for i = 1, #src do
    dst[i - 1] = src[i]
  end
end

local function apply_player(player, rec)
  if rec == nil then
    return
  end
  local function take(name, fallback)
    if rec[name] ~= nil then
      return rec[name]
    end
    return fallback
  end
  player.playerstate = take("playerstate", player.playerstate)
  player.viewz = take("viewz", player.viewz)
  player.viewheight = take("viewheight", player.viewheight)
  player.deltaviewheight = take("deltaviewheight", player.deltaviewheight)
  player.bob = take("bob", player.bob)
  player.health = take("health", player.health)
  player.armorpoints = take("armorpoints", player.armorpoints)
  player.armortype = take("armortype", player.armortype)
  if rec.ammo then
    copy_nums(player.ammo, rec.ammo)
  end
  if rec.maxammo then
    copy_nums(player.maxammo, rec.maxammo)
  end
  if rec.weaponowned then
    for i = 1, #rec.weaponowned do
      player.weaponowned[i - 1] = rec.weaponowned[i] and true or false
    end
  end
  player.pendingweapon = take("pendingweapon", player.pendingweapon)
  player.readyweapon = take("readyweapon", player.readyweapon)
  if rec.cards then
    for i = 1, #rec.cards do
      player.cards[i - 1] = rec.cards[i] and true or false
    end
  end
  player.cheats = take("cheats", player.cheats)
  player.message = take("message", "")
  player.message_tics = take("message_tics", 0)
  player.attackdown = rec.attackdown and true or false
  player.usedown = rec.usedown and true or false
  player.damagecount = take("damagecount", 0)
  player.bonuscount = take("bonuscount", 0)
  player.extralight = take("extralight", 0)
  player.refire = take("refire", 0)
  player.killcount = take("killcount", 0)
  player.itemcount = take("itemcount", 0)
  player.secretcount = take("secretcount", 0)
  player.didsecret = rec.didsecret and true or false
  player.psprite_sy = take("psprite_sy", player.psprite_sy)
  player.psprite_state = take("psprite_state", player.psprite_state)
  player.psprite_tics = take("psprite_tics", player.psprite_tics)
  player.psprite_step = take("psprite_step", 0)
  player.psprite_body = take("psprite_body", "")
  player.psprite_flash = take("psprite_flash", "")
  player.flash_tics = take("flash_tics", 0)
  if rec.powers then
    copy_nums(player.powers, rec.powers)
  end
  if player.mo then
    player.mo.health = player.health
  end
end

local function apply_mobj(mo, rec)
  mo.x = rec.x or mo.x
  mo.y = rec.y or mo.y
  mo.z = rec.z or mo.z
  mo.angle = rec.angle or mo.angle
  mo.momx = rec.momx or 0
  mo.momy = rec.momy or 0
  mo.momz = rec.momz or 0
  mo.floorz = rec.floorz or mo.floorz
  mo.ceilingz = rec.ceilingz or mo.ceilingz
  mo.flags = rec.flags or mo.flags
  mo.health = rec.health or mo.health
  mo.sprite = rec.sprite or mo.sprite
  if rec.alive == false then
    mo.alive = false
  else
    mo.alive = true
  end
  mo.reactiontime = rec.reactiontime or 0
  mo.movedir = rec.movedir or mo.movedir
  mo.movecount = rec.movecount or 0
  mo.frame = rec.frame or 0
  mo.tics = rec.tics or mo.tics
  mo.damage = rec.damage or mo.damage
  if type(rec.istate) == "number" then
    mo.istate = rec.istate
  end
end

function M.apply(game, data)
  if data == nil or game.start_level == nil then
    return false
  end
  game.carry = nil
  game.episode = data.episode or game.episode
  game.mapn = data.mapn or game.mapn
  game.skill = data.skill or game.skill
  game.start_level(game)
  if game.world == nil or game.player == nil then
    return false
  end
  game.leveltime = data.leveltime or 0
  game.totalkills = data.totalkills or game.totalkills
  game.totalitems = data.totalitems or game.totalitems
  game.totalsecret = data.totalsecret or game.totalsecret
  local world = game.world
  local sectors = data.sectors or {}
  for i = 1, #sectors do
    local s = world.sectors[i]
    local rec = sectors[i]
    if s and rec then
      s.floorheight = rec.floorheight or s.floorheight
      s.ceilingheight = rec.ceilingheight or s.ceilingheight
      s.floorpic = rec.floorpic or s.floorpic
      s.ceilingpic = rec.ceilingpic or s.ceilingpic
      s.lightlevel = rec.lightlevel or s.lightlevel
      s.special = rec.special or s.special
    end
  end
  local sides = data.sides or {}
  for i = 1, #sides do
    local sd = world.sides[i]
    local rec = sides[i]
    if sd and rec then
      sd.textureoffset = rec.textureoffset or sd.textureoffset
      sd.rowoffset = rec.rowoffset or sd.rowoffset
      sd.toptexture = rec.toptexture or sd.toptexture
      sd.bottomtexture = rec.bottomtexture or sd.bottomtexture
      sd.midtexture = rec.midtexture or sd.midtexture
    end
  end
  local lines = data.lines or {}
  for i = 1, #lines do
    local ln = world.lines[i]
    local rec = lines[i]
    if ln and rec then
      ln.flags = rec.flags or ln.flags
      ln.special = rec.special or ln.special
    end
  end
  local where_attr = {
    top = "toptexture",
    middle = "midtexture",
    bottom = "bottomtexture",
    toptexture = "toptexture",
    midtexture = "midtexture",
    bottomtexture = "bottomtexture",
  }
  if game.specials then
    local thinkers = data.thinkers or {}
    for i = 1, #thinkers do
      local rec = thinkers[i]
      local sec_i = rec.sector or -1
      local sector = world.sectors[sec_i + 1]
      if sector then
        local th = {
          kind = rec.kind,
          sector = sector,
          type = rec.type or 0,
          direction = rec.direction or 0,
          topheight = rec.topheight or 0,
          speed = rec.speed or 0,
          topwait = rec.topwait or 0,
          topcountdown = rec.topcountdown or 0,
          status = rec.status or 0,
          low = rec.low or 0,
          high = rec.high or 0,
          wait = rec.wait or 0,
          count = rec.count or 0,
          dest = rec.dest or 0,
          dead = false,
        }
        if th.kind == "door" or th.kind == "plat" or th.kind == "floor" then
          sector.specialdata = th
          game.specials.thinkers[#game.specials.thinkers + 1] = th
        end
      end
    end
    local buttons = data.buttons or {}
    for i = 1, #buttons do
      local rec = buttons[i]
      local li = rec.line or -1
      local line = world.lines[li + 1]
      if line then
        game.specials.buttons[#game.specials.buttons + 1] = {
          line = line,
          attr = where_attr[rec.where or ""] or "toptexture",
          texture = rec.texture or 0,
          timer = rec.timer or 0,
        }
      end
    end
  end
  local recs = data.mobjs or {}
  local n = #recs
  if n > #world.mobjs then
    n = #world.mobjs
  end
  for i = 1, n do
    apply_mobj(world.mobjs[i], recs[i])
    collision.set_thing_position(world, world.mobjs[i])
  end
  for i = 1, n do
    local ti = recs[i].target
    if type(ti) == "number" and ti >= 0 and ti < #world.mobjs then
      world.mobjs[i].target = world.mobjs[ti + 1]
    end
  end
  apply_player(game.player, data.player)
  if game.status and game.player then
    local status = require("status")
    status.reset(game.status, game.player)
  end
  game.gamestate = "view"
  return true
end

function M.load(game, slot)
  local data = M.read(game, slot)
  if data == nil then
    return false
  end
  return M.apply(game, data)
end

return M
