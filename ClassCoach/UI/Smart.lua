-- The smart key: one key that walks the coach's plan.
--
-- What the game allows, and what this is:
--   * One key press may do one thing. That never changes.
--   * An addon may not choose, during a fight, what your key will cast. So
--     the plan is loaded into a secure button BETWEEN fights (your level,
--     spells, demon and usual kill time), and in a fight only the game's own
--     secure code steps through it.
--   * Three keys, bound in the game's Keybindings screen (AddOns > ClassCoach):
--       Next     cast the next step; after the last one it stays on the filler
--       Again    cast the previous step once more (the coach tells you when a
--                spell was resisted)
--       Restart  go back to the first step (a new enemy joined)
--   * It goes back to the first step by itself when your enemy dies or you
--     drop your target, and it will not cut off a spell you are channeling.
--
-- This is the same mechanism addons like GSE use: one press, one action.
local _, ns = ...

local Smart = {}
ns.Smart = Smart

local NAME = "ClassCoachSmartButton"
Smart.NAME = NAME
local BIND = { next = "CLICK " .. NAME .. ":LeftButton", again = "CLICK " .. NAME .. ":RightButton",
  restart = "CLICK " .. NAME .. ":MiddleButton" }
local CLICKS = { next = "LeftButton", again = "RightButton", restart = "MiddleButton" }

-- Names shown in the game's Keybindings screen
BINDING_HEADER_CLASSCOACH = "ClassCoach"
_G["BINDING_NAME_" .. BIND.next] = "Smart key: next step"
_G["BINDING_NAME_" .. BIND.again] = "Smart key: cast the last step again"
_G["BINDING_NAME_" .. BIND.restart] = "Smart key: start over"

-- Runs inside the game's secure environment on every key press, before the
-- press acts. It may only read what the game lets secure code read. It picks
-- the step and puts it on the button; the press then performs it.
-- (Secure code may not contain comments or define functions, so it has neither.)
local ON_CLICK = [[
  if not down then return end
  local count = self:GetAttribute("cc-count") or 0
  if count < 1 then return end
  local step = self:GetAttribute("cc-step") or 1
  if button == "RightButton" then
    step = self:GetAttribute("cc-last") or 1
  elseif button == "MiddleButton" then
    step = 1
  end
  if step < 1 then step = 1 end
  if step > count then step = count end
  if button == "LeftButton" and SecureCmdOptionParse("[channeling] hold; go") == "hold" then
    self:SetAttribute("type", nil)
    return
  end
  local gate = self:GetAttribute("cc-gate")
  if gate and step == 1 and SecureCmdOptionParse(gate) == "hold" then
    self:SetAttribute("type", "macro")
    self:SetAttribute("macro", self:GetAttribute("cc-gate-macro"))
    return
  end
  local kind = self:GetAttribute("cc-t" .. step)
  self:SetAttribute("type", kind)
  if kind == "spell" then
    self:SetAttribute("spell", self:GetAttribute("cc-v" .. step))
  else
    self:SetAttribute("macro", self:GetAttribute("cc-v" .. step))
  end
  self:SetAttribute("cc-last", step)
  if step < count then
    self:SetAttribute("cc-step", step + 1)
  else
    self:SetAttribute("cc-step", count)
  end
]]

-- Back to step one when there is no living enemy targeted.
local ON_RESET = [[
  if newstate == "reset" then
    self:SetAttribute("cc-step", 1)
    self:SetAttribute("cc-last", 1)
  end
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
    b:SetAttribute("cc-count", 0)
    b:SetAttribute("cc-step", 1)
    b:WrapScript(b, "OnClick", ON_CLICK)
    b:SetAttribute("_onstate-ccreset", ON_RESET)
    RegisterStateDriver(b, "ccreset", "[@target,harm,nodead] keep; reset")
  end)
  if not built then Smart.error = tostring(why) return false end
  Smart.button = b
  return true
end

-- steps = { { kind = "spell" | "macro", value = name, label = shown name } }
-- gate  = { when = "[pet:Voidwalker,nocombat]", macro = "CC Send" }: while `when`
--         holds, the first press runs that macro and stays on step one.
-- Out of combat only; returns true when the button now holds these steps.
function Smart.load(steps, gate)
  local b = Smart.button
  if not b or inCombat() then return false end
  local sig = {}
  for i, st in ipairs(steps) do sig[i] = st.kind .. ":" .. st.value end
  sig = table.concat(sig, "|") .. "#" .. (gate and (gate.when .. gate.macro) or "")
  if sig == Smart.signature then return true end
  local done = pcall(function()
    for i, st in ipairs(steps) do
      b:SetAttribute("cc-t" .. i, st.kind)
      b:SetAttribute("cc-v" .. i, st.value)
    end
    b:SetAttribute("cc-count", #steps)
    b:SetAttribute("cc-step", 1)
    b:SetAttribute("cc-last", 1)
    b:SetAttribute("cc-gate", gate and (gate.when .. " hold; go") or nil)
    b:SetAttribute("cc-gate-macro", gate and gate.macro or nil)
  end)
  if not done then return false end
  Smart.signature, Smart.steps = sig, steps
  return true
end

local function shortKey(key)
  if type(key) ~= "string" or key == "" then return nil end
  return (key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A"):gsub("NUMPAD", "N"):gsub("BUTTON", "M"))
end

-- Where the key is right now: readable at any time, also in combat.
-- { ready, count, nextLabel, lastLabel, keys = { next, again, restart } }
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
  local out = { ready = b ~= nil and steps ~= nil and #steps > 0, count = steps and #steps or 0, keys = keys }
  if out.ready then
    local fine, step, last = pcall(function() return b:GetAttribute("cc-step"), b:GetAttribute("cc-last") end)
    if fine and type(step) == "number" then
      out.step = step
      out.nextLabel = steps[step] and steps[step].label
      out.lastLabel = type(last) == "number" and steps[last] and steps[last].label or nil
    end
  end
  return out
end

-- Binds a key without the Keybindings screen: /coach smart next 1
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
    lines[#lines + 1] = ("%d %s%s"):format(i, st.label, i == #Smart.steps and " (stays here)" or "")
  end
  return lines
end
