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
-- Nomes de tecla a partir do SDL_Keycode. Igual nos dois runtimes.

local M = {}

local MASK = 1073741824

local NAMED = {
  [27] = "escape",
  [13] = "return",
  [9] = "tab",
  [8] = "backspace",
  [32] = "space",
  [44] = "comma",
  [46] = "period",
  [45] = "minus",
  [61] = "equals",
  [MASK + 79] = "right",
  [MASK + 80] = "left",
  [MASK + 81] = "down",
  [MASK + 82] = "up",
  [MASK + 86] = "minus",
  [MASK + 87] = "equals",
  [MASK + 88] = "return",
  [MASK + 224] = "ctrl",
  [MASK + 228] = "ctrl",
  [MASK + 225] = "shift",
  [MASK + 229] = "shift",
  [MASK + 226] = "alt",
  [MASK + 230] = "alt",
}

function M.name_of(sym)
  sym = sym or 0
  if sym == 0 then
    return "quit"
  end
  local named = NAMED[sym]
  if named then
    return named
  end
  if sym >= MASK + 58 and sym <= MASK + 69 then
    return "f" .. tostring(sym - (MASK + 58) + 1)
  end
  if (sym >= 97 and sym <= 122) or (sym >= 48 and sym <= 57) then
    return string.char(sym)
  end
  return ""
end

return M
