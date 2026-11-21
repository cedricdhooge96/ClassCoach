-- Click to cast, before a fight.
--
-- Out of combat, the coach's icons can be clicked: an amber "before you pull"
-- icon casts the spell that fixes it (your armor, your demon, Life Tap, or the
-- CC Rest macro to drink and eat), and with an enemy targeted the ring and the
-- steps after it cast that step.
--
-- What the game allows, and what this is:
--   * Only the game's own secure buttons may cast. ClassCoach lays invisible
--     ones over its icons and tells them what to cast while you are OUT of combat.
--   * In a fight an addon may not change what a click casts, and it may not
--     move or hide such a button. So the game itself hides all of them the
--     moment a fight starts, and in a fight the coach's icons are pictures
--     again: use your keys, or the lit button on your action bar.
--   * The buttons are never anchored to the coach, so dragging the coach in a
--     fight cannot be blocked by them. They are put back in place between fights.
local _, ns = ...

local Click = {}
ns.Click = Click

local MAX = 11   -- six "before you pull" icons, the ring, four next steps

local function inCombat() return ns.API.inCombat() end

-- Makes the buttons. Only possible out of combat. Returns true when they exist.
function Click.create(panel)
  if Click.holder then return true end
  if inCombat() or not panel then return false end
  local S = ns.Style
  local made, why = pcall(function()
    local holder = CreateFrame("Frame", "ClassCoachClicks", UIParent, "SecureHandlerStateTemplate")
    holder:SetSize(2, 2)
    holder:SetFrameStrata("LOW")
    -- the game hides every button the moment a fight starts and shows them again after it
    RegisterStateDriver(holder, "visibility", "[combat] hide; show")
    local buttons = {}
    for i = 1, MAX do
      local b = CreateFrame("Button", "ClassCoachClick" .. i, holder, "SecureActionButtonTemplate")
      b:RegisterForClicks("AnyDown", "AnyUp")
      b:SetFrameLevel(60)
      b:SetAttribute("checkselfcast", true)
      b.clickable = true
      b:SetScript("OnEnter", S.guard(S.tooltip))
      b:SetScript("OnLeave", S.guard(S.hideTooltip))
      -- dragging a button drags the coach under it
      b:RegisterForDrag("LeftButton")
      b:SetScript("OnDragStart", S.guard(function() local d = panel:GetScript("OnDragStart"); if d and not inCombat() then d(panel) end end))
      b:SetScript("OnDragStop", S.guard(function() local d = panel:GetScript("OnDragStop"); if d then d(panel) end end))
      b:Hide()
      buttons[i] = b
    end
    Click.holder, Click.buttons = holder, buttons
  end)
  if not made then Click.error = tostring(why) return false end
  return true
end

-- targets = { { x, y, size, kind = "spell" | "macro", value, title, hint, bind, does } }: places
-- measured from the middle of the ring. Out of combat only; in a fight this does nothing.
function Click.update(panel, targets, db)
  if inCombat() then return false end
  if db.clickable == false then targets = {} end
  if #targets == 0 and not Click.holder then return true end   -- nothing to click yet: make nothing
  if not Click.create(panel) then return false end
  local holder = Click.holder
  local done = pcall(function()
    -- follow the coach: same place, same size
    local x, y = panel:GetCenter()
    local scale = panel:GetScale()
    if type(x) == "number" and type(y) == "number" and type(scale) == "number" and scale > 0 then
      local where = ("%.1f:%.1f:%.3f"):format(x, y, scale)
      if where ~= Click.where then
        Click.where = where
        holder:SetScale(scale)
        holder:ClearAllPoints()
        holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
      end
    end
    for i = 1, MAX do
      local b, t = Click.buttons[i], targets[i]
      if t and t.value and (t.kind == "spell" or t.kind == "macro") then
        local sig = ("%s:%s:%d:%d:%d"):format(t.kind, t.value, t.x, t.y, t.size)
        if b.sig ~= sig then
          b.sig = sig
          b:SetAttribute("type", t.kind)
          b:SetAttribute("spell", t.kind == "spell" and t.value or nil)
          b:SetAttribute("macro", t.kind == "macro" and t.value or nil)
          b:SetSize(t.size, t.size)
          b:ClearAllPoints()
          b:SetPoint("CENTER", holder, "CENTER", t.x, t.y)
        end
        b.title, b.hint, b.bind, b.does = t.title, t.hint, t.bind, t.does
        if not b.on then b.on = true; b:Show() end
      elseif b.on ~= false then
        b.on = false
        b:Hide()
      end
    end
  end)
  if not done then return false end
  return true
end

-- What is clickable right now, for /coach check and the tests.
function Click.describe()
  local out = {}
  for _, b in ipairs(Click.buttons or {}) do
    if b.on then out[#out + 1] = ("%s %s"):format(b:GetAttribute("type") or "?", b:GetAttribute("spell") or b:GetAttribute("macro") or "?") end
  end
  return out
end
