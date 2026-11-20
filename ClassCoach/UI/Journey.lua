-- The journey panel: everything outside the fight. Your XP and rested XP,
-- and a short list of things guides tell you to keep on top of (food buff,
-- trainer, talent points, repairs, bags). It hides itself in combat so the
-- coach panel is all you see while fighting.
local _, ns = ...

local Journey = {}
ns.Journey = Journey

local WIDTH, MAX_LINES, ICON_SIZE = 320, 9, 20
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local COLORS = {
  act = { 1.00, 0.78, 0.30 }, info = { 0.70, 0.72, 0.78 }, dim = { 0.62, 0.62, 0.66 },
  xp = { 0.58, 0.35, 0.85 }, rested = { 0.30, 0.55, 1.00 },
}

local function font(parent, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  fs:SetJustifyH("LEFT")
  return fs
end

-- One to-do: an icon like a spell button, its text, and the full advice on mouse-over.
local function row(parent)
  local r = CreateFrame("Frame", nil, parent)
  r:SetSize(WIDTH - 20, ICON_SIZE)
  local icon = r:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetPoint("TOPLEFT", 0, 0)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.icon = icon
  local label = font(r, "GameFontHighlightSmall")
  label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
  label:SetWidth(WIDTH - 20 - ICON_SIZE - 6)
  label:SetWordWrap(false)
  r.label = label
  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self)
    if not self.title or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.title, 1, 0.82, 0.2)
    if self.hint then GameTooltip:AddLine(self.hint, 0.9, 0.9, 0.9, true) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- dragging a row drags the panel
  r:RegisterForDrag("LeftButton")
  r:SetScript("OnDragStart", function() local s = parent:GetScript("OnDragStart"); if s then s(parent) end end)
  r:SetScript("OnDragStop", function() local s = parent:GetScript("OnDragStop"); if s then s(parent) end end)
  return r
end

function Journey.create(charDB, db)
  if Journey.frame then return Journey.frame end
  local f = CreateFrame("Frame", "ClassCoachJourney", UIParent)
  Journey.frame, Journey.charDB, Journey.db = f, charDB, db
  f:SetSize(WIDTH, 60)
  f:SetFrameStrata("LOW")   -- below the action bars, like the coach panel
  f:SetClampedToScreen(true)
  ns.Style.skin(f)
  ns.Style.apply(f, db, db.journeyScale)
  Journey.place()
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local pinned = ns.Style.pin(self)
    if pinned then
      charDB.journeyPos = pinned
    else
      local point, _, relPoint, x, y = self:GetPoint()
      charDB.journeyPos = { point, relPoint, x, y }
    end
  end)

  local title = font(f, "GameFontDisableSmall")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetWidth(WIDTH - 20)
  f.title = title

  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetMinMaxValues(0, 100)
  bar:SetSize(WIDTH - 20, 10)
  bar:SetPoint("TOPLEFT", 10, -22)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.5)
  local barText = font(bar, "GameFontHighlightSmall")
  barText:SetPoint("CENTER")
  barText:SetJustifyH("CENTER")
  f.bar, f.barText = bar, barText

  f.rows = {}
  for i = 1, MAX_LINES do f.rows[i] = row(f) end
  local allSet = font(f, "GameFontHighlightSmall")
  allSet:SetTextColor(0.55, 0.85, 0.55)
  f.allSet = allSet
  local hint = font(f, "GameFontDisableSmall")
  hint:SetWidth(WIDTH - 20)
  hint:SetWordWrap(true)
  f.hint = hint

  if db.journey == false then f:Hide() end
  return f
end

-- Its own spot on screen: it never follows the coach panel. Drag it anywhere.
function Journey.place()
  local f = Journey.frame
  if not f then return end
  f:ClearAllPoints()
  local pos = Journey.charDB.journeyPos
  Journey.repin = ns.Style.unpinned(pos)
  if pos then
    f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    f:SetPoint("TOPLEFT", UIParent, "LEFT", 30, 120)
  end
end

-- view = { title, inCombat, xp = { pct, restedPct, resting }, lines = { { kind, text, hint, icon } } }
function Journey.render(view)
  local f = Journey.frame
  if not f then return end
  local wanted = Journey.db.journey ~= false and not view.inCombat
  if not wanted then
    if Journey.visible ~= false then f:Hide(); Journey.visible = false end
    return
  end
  if Journey.visible ~= true then f:Show(); Journey.visible = true end
  ns.Style.apply(f, Journey.db, Journey.db.journeyScale)
  if Journey.repin then
    local pinned = ns.Style.pin(f)
    if pinned then Journey.charDB.journeyPos = pinned; Journey.repin = false end
  end

  f.title:SetText(view.title or "Journey")
  local y = -22
  if view.xp then
    f.bar:Show()
    f.bar:SetValue(view.xp.pct)
    local rested = view.xp.restedPct or 0
    local c = rested > 0 and COLORS.rested or COLORS.xp
    f.bar:SetStatusBarColor(c[1], c[2], c[3])
    f.barText:SetText(rested > 0
      and ("XP %d%% · rested %d%% of a level"):format(math.floor(view.xp.pct), math.floor(rested + 0.5))
      or ("XP %d%% · not rested"):format(math.floor(view.xp.pct)))
    y = y - 16
  else
    f.bar:Hide()
  end

  local lines, firstHint = view.lines or {}, nil
  for i = 1, MAX_LINES do
    local r, item = f.rows[i], lines[i]
    r:ClearAllPoints()
    if item then
      local c = item.kind == "do" and COLORS.act or COLORS.info
      r.icon:SetTexture(item.icon or QUESTION)
      r.icon:SetDesaturated(item.kind ~= "do")
      r.label:SetTextColor(c[1], c[2], c[3])
      r.label:SetText(item.text)
      r.title, r.hint = item.text, item.hint
      r:SetPoint("TOPLEFT", 10, y)
      r:Show()
      y = y - ICON_SIZE - 3
      if not firstHint and item.kind == "do" and item.hint then firstHint = item.hint end
    else
      r.label:SetText("")
      r.title, r.hint = nil, nil
      r:Hide()
    end
  end
  f.allSet:ClearAllPoints()
  if #lines == 0 then
    f.allSet:SetText("All set. Go quest.")
    f.allSet:SetPoint("TOPLEFT", 10, y)
    f.allSet:Show()
    y = y - 14
  else
    f.allSet:SetText("")
    f.allSet:Hide()
  end
  f.hint:ClearAllPoints()
  if firstHint then
    f.hint:SetText(firstHint)
    f.hint:SetPoint("TOPLEFT", 10, y - 2)
    f.hint:Show()
    y = y - 4 - (f.hint:GetStringHeight() or 12)
  else
    f.hint:SetText("")
    f.hint:Hide()
  end
  f:SetHeight(-y + 8)
end

function Journey.reset()
  Journey.charDB.journeyPos = nil
  Journey.place()
end
