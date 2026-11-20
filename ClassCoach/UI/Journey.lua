-- The journey panel: everything outside the fight. Your XP and rested XP,
-- and a short list of things guides tell you to keep on top of (food buff,
-- trainer, talent points, repairs, bags). It hides itself in combat so the
-- coach panel is all you see while fighting.
local _, ns = ...

local Journey = {}
ns.Journey = Journey

local WIDTH, MAX_LINES = 320, 6
local COLORS = {
  act = { 1.00, 0.78, 0.30 }, info = { 0.70, 0.72, 0.78 }, dim = { 0.62, 0.62, 0.66 },
  xp = { 0.58, 0.35, 0.85 }, rested = { 0.30, 0.55, 1.00 },
}

local function font(parent, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  fs:SetJustifyH("LEFT")
  return fs
end

function Journey.create(charDB, db, anchor)
  if Journey.frame then return Journey.frame end
  local ok, f = pcall(CreateFrame, "Frame", "ClassCoachJourney", UIParent, "BackdropTemplate")
  if not ok or not f then f = CreateFrame("Frame", "ClassCoachJourney", UIParent) end
  Journey.frame, Journey.charDB, Journey.db, Journey.anchor = f, charDB, db, anchor
  f:SetSize(WIDTH, 60)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  if f.SetBackdrop then
    pcall(f.SetBackdrop, f, {
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    pcall(f.SetBackdropColor, f, 0.05, 0.05, 0.07, 0.78)
    pcall(f.SetBackdropBorderColor, f, 0.35, 0.35, 0.40, 0.9)
  end
  Journey.place()
  f:SetScale(db.scale or 1)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    charDB.journeyPos = { point, relPoint, x, y }
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

  f.lines = {}
  for i = 1, MAX_LINES do
    local line = font(f, "GameFontHighlightSmall")
    line:SetWidth(WIDTH - 20)
    line:SetWordWrap(true)
    f.lines[i] = line
  end
  local hint = font(f, "GameFontDisableSmall")
  hint:SetWidth(WIDTH - 20)
  hint:SetWordWrap(true)
  f.hint = hint

  if db.journey == false then f:Hide() end
  return f
end

-- Sits under the coach panel until you drag it somewhere else.
function Journey.place()
  local f = Journey.frame
  if not f then return end
  f:ClearAllPoints()
  local pos = Journey.charDB.journeyPos
  if pos then
    f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  elseif Journey.anchor then
    f:SetPoint("TOPLEFT", Journey.anchor, "BOTTOMLEFT", 0, -4)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -320)
  end
end

-- view = { title, inCombat, xp = { pct, restedPct, resting }, lines = { { kind, text, hint } } }
function Journey.render(view)
  local f = Journey.frame
  if not f then return end
  local wanted = Journey.db.journey ~= false and not view.inCombat
  if not wanted then
    if Journey.visible ~= false then f:Hide(); Journey.visible = false end
    return
  end
  if Journey.visible ~= true then f:Show(); Journey.visible = true end

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
    local line, item = f.lines[i], lines[i]
    line:ClearAllPoints()
    if item then
      local c = item.kind == "do" and COLORS.act or COLORS.info
      line:SetTextColor(c[1], c[2], c[3])
      line:SetText((item.kind == "do" and "! " or "· ") .. item.text)
      line:SetPoint("TOPLEFT", 10, y)
      line:Show()
      y = y - (line:GetStringHeight() or 12) - 2
      if not firstHint and item.kind == "do" and item.hint then firstHint = item.hint end
    else
      line:SetText("")
      line:Hide()
    end
  end
  if #lines == 0 then
    f.lines[1]:SetTextColor(0.55, 0.85, 0.55)
    f.lines[1]:SetText("All set. Go quest.")
    f.lines[1]:SetPoint("TOPLEFT", 10, y)
    f.lines[1]:Show()
    y = y - 14
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

function Journey.setScale(scale) if Journey.frame then Journey.frame:SetScale(scale) end end
function Journey.reset()
  Journey.charDB.journeyPos = nil
  Journey.place()
end
