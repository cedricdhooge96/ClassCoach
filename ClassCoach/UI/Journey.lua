-- The journey panel: everything outside the fight. Your level, XP and rested
-- XP, then two short lists: what to do now and what is coming (food buff,
-- trainer, talent points, repairs, bags, milestones). In combat it is not redrawn: it
-- stays as it was before the pull, or hides if you turned that option off.
local _, ns = ...

local Journey = {}
ns.Journey = Journey

local WIDTH, MAX_LINES, ICON_SIZE, PAD = 244, 9, 20, 10
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- One to-do: an icon like a spell button, its text, and the full advice on mouse-over.
local function row(parent)
  local S = ns.Style
  local r = CreateFrame("Frame", nil, parent)
  r:SetSize(WIDTH - 2 * PAD, ICON_SIZE)
  local icon = r:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetPoint("TOPLEFT", 0, 0)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.icon = icon
  local label = S.text(r, "body", 12, S.COLORS.ink)
  label:SetPoint("LEFT", icon, "RIGHT", 9, 0)
  label:SetWidth(WIDTH - 2 * PAD - ICON_SIZE - 9)
  label:SetWordWrap(false)
  r.label = label
  r:EnableMouse(true)
  r:SetScript("OnEnter", S.guard(S.tooltip))
  r:SetScript("OnLeave", S.guard(S.hideTooltip))
  -- dragging a row drags the panel
  r:RegisterForDrag("LeftButton")
  r:SetScript("OnDragStart", S.guard(function() local s = parent:GetScript("OnDragStart"); if s then s(parent) end end))
  r:SetScript("OnDragStop", S.guard(function() local s = parent:GetScript("OnDragStop"); if s then s(parent) end end))
  return r
end

function Journey.create(charDB, db)
  if Journey.frame then return Journey.frame end
  local S = ns.Style
  local C = S.COLORS
  local f = CreateFrame("Frame", "ClassCoachJourney", UIParent)
  Journey.frame, Journey.charDB, Journey.db = f, charDB, db
  f:SetSize(WIDTH, 60)
  f:SetFrameStrata("LOW")   -- below the action bars, like the coach
  f:SetClampedToScreen(true)
  S.skin(f)
  S.apply(f, db, db.journeyScale)
  Journey.place()
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", S.guard(function(self) if not db.locked then self:StartMoving() end end))
  f:SetScript("OnDragStop", S.guard(function(self)
    self:StopMovingOrSizing()
    local pinned = S.pin(self)
    if pinned then
      charDB.journeyPos = pinned
    else
      local point, _, relPoint, x, y = self:GetPoint()
      charDB.journeyPos = { point, relPoint, x, y }
    end
  end))

  -- "Level 11" on the left, "79% · rested 4%" on the right, a thin XP bar under both
  f.title = S.text(f, "bold", 18, C.ink)   -- not Marcellus: its digit 1 reads as a capital I ("Level II")
  f.title:SetPoint("TOPLEFT", PAD, -8)
  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  bar:SetMinMaxValues(0, 100)
  bar:SetSize(WIDTH - 2 * PAD, 5)
  bar:SetPoint("TOPLEFT", PAD, -34)
  pcall(bar.SetStatusBarColor, bar, C.xp[1], C.xp[2], C.xp[3])
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(C.dark[1], C.dark[2], C.dark[3], 0.9)
  local barText = S.text(f, "body", 11, C.muted)
  barText:SetPoint("TOPRIGHT", -PAD, -14)
  barText:SetJustifyH("RIGHT")
  f.bar, f.barText = bar, barText

  -- Two short lists: what to do now, and what is coming
  f.doHead = S.text(f, "bold", 11, C.accent)
  f.doHead:SetText("Do now")
  f.laterHead = S.text(f, "bold", 11, C.muted)
  f.laterHead:SetText("Coming up")
  f.rows = {}
  for i = 1, MAX_LINES do f.rows[i] = row(f) end
  f.allSet = S.text(f, "body", 12, C.ok)
  f.hint = S.text(f, "body", 11, C.muted)
  f.hint:SetWidth(WIDTH - 2 * PAD)
  f.hint:SetWordWrap(true)

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
  local db = Journey.db
  -- In combat the game hides most of what this panel reads, so it is not redrawn.
  -- It stays up showing what it showed before the pull, unless you asked it to hide.
  -- (After a reload in the middle of a fight there is nothing to show until the fight ends.)
  if view.inCombat and db.journey ~= false and db.journeyInCombat ~= false and Journey.drawn then
    if Journey.visible ~= true then f:Show(); Journey.visible = true end
    return
  end
  local wanted = db.journey ~= false and not view.inCombat
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

  local C = ns.Style.COLORS
  f.title:SetText(view.title or "Journey")
  local y = -30
  if view.xp then
    f.bar:Show()
    f.bar:SetValue(view.xp.pct)
    local rested = view.xp.restedPct or 0
    f.barText:SetText(rested > 0
      and ("%d%% · rested %d%%"):format(math.floor(view.xp.pct), math.floor(rested + 0.5))
      or ("%d%% · not rested"):format(math.floor(view.xp.pct)))
    y = -34 - 5 - 10
  else
    f.bar:Hide()
    f.barText:SetText("")
  end

  -- "Do now" first, then what is coming; the order inside each list is the engine's.
  local lines, firstHint = {}, nil
  for _, item in ipairs(view.lines or {}) do if item.kind == "do" and #lines < MAX_LINES then lines[#lines + 1] = item end end
  local doing = #lines
  for _, item in ipairs(view.lines or {}) do if item.kind ~= "do" and #lines < MAX_LINES then lines[#lines + 1] = item end end
  local function head(fs, shown)
    fs:ClearAllPoints()
    if shown then
      fs:SetPoint("TOPLEFT", PAD, y)
      fs:Show()
      y = y - 11 - 8
    else
      fs:Hide()
    end
  end
  head(f.doHead, doing > 0)
  for i = 1, MAX_LINES do
    local r, item = f.rows[i], lines[i]
    r:ClearAllPoints()
    if i == doing + 1 then head(f.laterHead, item ~= nil) end
    if item then
      local now = item.kind == "do"
      local c = now and C.ink or C.muted
      r.icon:SetTexture(item.icon or QUESTION)
      r.icon:SetDesaturated(not now)
      r.label:SetTextColor(c[1], c[2], c[3])
      ns.Style.set(r.label, item.text)
      r.title, r.hint = item.text, item.hint
      r:SetPoint("TOPLEFT", PAD, y)
      r:Show()
      y = y - ICON_SIZE - 8
      if not firstHint and now and item.hint then firstHint = item.hint end
    else
      r.label:SetText("")
      r.title, r.hint = nil, nil
      r:Hide()
    end
  end
  if doing == MAX_LINES then head(f.laterHead, false) end
  f.allSet:ClearAllPoints()
  if #lines == 0 then
    f.allSet:SetText("All set. Go quest.")
    f.allSet:SetPoint("TOPLEFT", PAD, y)
    f.allSet:Show()
    y = y - 16
  else
    f.allSet:SetText("")
    f.allSet:Hide()
  end
  f.hint:ClearAllPoints()
  if firstHint then
    ns.Style.set(f.hint, firstHint)
    f.hint:SetPoint("TOPLEFT", PAD, y - 2)
    f.hint:Show()
    y = y - 6 - (f.hint:GetStringHeight() or 12)
  else
    f.hint:SetText("")
    f.hint:Hide()
  end
  f:SetHeight(-y + 8)
  Journey.drawn = true
end

function Journey.reset()
  Journey.charDB.journeyPos = nil
  Journey.place()
end
