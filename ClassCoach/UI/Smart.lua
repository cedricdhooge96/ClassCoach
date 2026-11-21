-- The smart key: one key that walks the coach's plan.
--
-- What the game allows, and what this is:
--   * One key press may do one thing. That never changes.
--   * An addon may not choose, during a fight, what your key will cast. So
--     the plan is loaded into a secure button BETWEEN fights (your level,
--     spells, demon, mana and usual kill time), as one /castsequence.
--   * The game's own cast sequence moves on only when the spell really went
--     off. A cast that fails (out of range, not ready, still casting) stays the
--     next step: press again. It starts over by itself on a new target and
--     after a fight, and after its last step.
--   * The coach reads where the sequence is (QueryCastSequence, the same
--     thing the game's own buttons read) and shows exactly that step.
--   * One key, bound in the game's Keybindings screen (AddOns > ClassCoach).
--     It will not cut off a spell you are channeling.
--
-- This is the same mechanism a /castsequence macro uses: one press, one action.
local _, ns = ...

local Smart = {}
ns.Smart = Smart

local NAME = "ClassCoachSmartButton"
Smart.NAME = NAME
local BIND = { next = "CLICK " .. NAME .. ":LeftButton" }
local CLICKS = { next = "LeftButton" }

-- Names shown in the game's Keybindings screen
BINDING_HEADER_CLASSCOACH = "ClassCoach"
_G["BINDING_NAME_" .. BIND.next] = "Smart key"

-- Runs inside the game's secure environment on every key press, before the
-- press acts. It may only read what the game lets secure code read. It puts the
-- cast sequence on the button; the press then runs it.
-- (Secure code may not contain comments or define functions, so it has neither.)
local ON_CLICK = [[
  if not down then return end
  local text = self:GetAttribute("cc-text")
  if not text or button ~= "LeftButton" then
    self:SetAttribute("type", nil)
    return
  end
  if SecureCmdOptionParse("[channeling] hold; go") == "hold" then
    self:SetAttribute("type", nil)
    return
  end
  local gate = self:GetAttribute("cc-gate")
  if gate and SecureCmdOptionParse(gate) == "hold" then
    self:SetAttribute("type", "macro")
    self:SetAttribute("macrotext", nil)
    self:SetAttribute("macro", self:GetAttribute("cc-gate-macro"))
    return
  end
  self:SetAttribute("type", "macro")
  self:SetAttribute("macro", nil)
  self:SetAttribute("macrotext", text)
]]

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- Creates the secure button. Only possible out of combat.
function Smart.create()
  if Smart.button then return true end
  if inCombat() or not CreateFrame then return false end
  local ok, b = pcall(CreateFrame, "Button", NAME, UIParent, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
  if not ok or not b then return false end
  local built, why = pcall(function()
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetAttribute("useOnKeyDown", true)
    b:WrapScript(b, "OnClick", ON_CLICK)
  end)
  if not built then Smart.error = tostring(why) return false end
  Smart.button = b
  return true
end

-- built = { entries = { { key, label, text } }, sequence, macrotext } (Engine.smartSteps)
-- gate  = { when = "[pet:Voidwalker,nocombat]", macro = "CC Send" }: while `when`
--         holds, a press runs that macro instead.
-- Out of combat only; returns true when the button now holds this sequence.
function Smart.load(built, gate)
  local b = Smart.button
  if not b or inCombat() then return false end
  local text = built and built.macrotext
  local sig = (text or "") .. "#" .. (gate and (gate.when .. gate.macro) or "")
  if sig == Smart.signature then return true end
  local done = pcall(function()
    b:SetAttribute("cc-text", text)
    b:SetAttribute("cc-gate", gate and (gate.when .. " hold; go") or nil)
    b:SetAttribute("cc-gate-macro", gate and gate.macro or nil)
  end)
  if not done then return false end
  Smart.signature, Smart.steps, Smart.sequence = sig, built.entries or {}, built.sequence
  return true
end

-- The game starts the sequence over by itself (a new target, the end of a fight).
function Smart.restart() return true end

local function shortKey(key)
  if type(key) ~= "string" or key == "" then return nil end
  return (key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A"):gsub("NUMPAD", "N"):gsub("BUTTON", "M"))
end

-- Where the key is right now: readable at any time, also in combat.
-- { ready, count, step, nextLabel, firstLabel, keys = { next } }
local keyCache, keysAt = {}, -100
function Smart.status()
  local b, steps = Smart.button, Smart.steps
  local now = GetTime and GetTime() or 0
  if now - keysAt > 2 or now < keysAt then
    keysAt, keyCache = now, {}
    for what, binding in pairs(BIND) do
      local found, key = pcall(GetBindingKey, binding)
      keyCache[what] = found and shortKey(key) or nil
    end
  end
  local keys = keyCache
  local out = { ready = b ~= nil and steps ~= nil and #steps > 0 and Smart.sequence ~= nil, count = steps and #steps or 0, keys = keys }
  if out.ready then
    -- the game's own record of the sequence: the step its next press casts
    local fine, index = pcall(QueryCastSequence, Smart.sequence)
    if fine and type(index) == "number" and steps[index] then
      out.step = index
      out.nextLabel, out.nextText = steps[index].label, steps[index].text
      out.firstLabel = steps[1].label
    end
  end
  return out
end

-- Binds a key without the Keybindings screen: /coach smart 1
function Smart.bind(what, key)
  if not CLICKS[what] or not Smart.button or inCombat() then return false end
  local ok = pcall(function()
    SetBindingClick(key, NAME, CLICKS[what])
    SaveBindings(GetCurrentBindingSet())
  end)
  keysAt = -100   -- read the keys again
  return ok
end

function Smart.describe()
  local lines = {}
  for i, st in ipairs(Smart.steps or {}) do
    lines[#lines + 1] = ("%d %s%s"):format(i, st.label, i == #Smart.steps and " (then it starts over)" or "")
  end
  return lines
end
