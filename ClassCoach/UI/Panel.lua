-- The one compact panel: next ability, mana, what's missing or what to do,
-- and a message area for fight reports and level-up tips.
local _, ns = ...

local Panel = {}
ns.Panel = Panel

local WIDTH = 320
local COLORS = {
  high = { 0.32, 0.62, 1.00 }, medium = { 1.00, 0.78, 0.25 }, low = { 1.00, 0.35, 0.30 },
  warn = { 1.00, 0.70, 0.28 }, ok = { 0.55, 0.85, 0.55 }, dim = { 0.62, 0.62, 0.66 }, text = { 0.95, 0.93, 0.88 },
}

local function font(parent, template, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  if r then fs:SetTextColor(r, g, b) end
  fs:SetJustifyH("LEFT")
  return fs
end

function Panel.create(charDB, db)
  if Panel.frame then return Panel.frame end
  local ok, f = pcall(CreateFrame, "Frame", "ClassCoachPanel", UIParent, "BackdropTemplate")
  if not ok or not f then f = CreateFrame("Frame", "ClassCoachPanel", UIParent) end
  Panel.frame, Panel.charDB, Panel.db = f, charDB, db
  f:SetSize(WIDTH, 100)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  if f.SetBackdrop then
    pcall(f.SetBackdrop, f, {
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    pcall(f.SetBackdropColor, f, 0.05, 0.05, 0.07, 0.82)
    pcall(f.SetBackdropBorderColor, f, 0.35, 0.35, 0.40, 0.9)
  else
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.82)
  end

  -- Position
  local pos = charDB.pos
  f:ClearAllPoints()
  if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER", UIParent, "CENTER", 0, -180) end
  f:SetScale(db.scale or 1)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    charDB.pos = { point, relPoint, x, y }
  end)

  -- Next ability icon
  local iconFrame = CreateFrame("Frame", nil, f)
  iconFrame:SetSize(42, 42)
  iconFrame:SetPoint("TOPLEFT", 10, -10)
  local icon = iconFrame:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.icon = icon
  local key = font(iconFrame, "NumberFontNormal", 1, 1, 1)
  key:SetPoint("BOTTOMRIGHT", -1, 2)
  key:SetJustifyH("RIGHT")
  f.key = key

  -- Text block
  local title = font(f, "GameFontDisableSmall")
  title:SetPoint("TOPLEFT", 62, -9)
  title:SetWidth(WIDTH - 72)
  f.title = title
  local name = font(f, "GameFontHighlight")
  name:SetPoint("TOPLEFT", 62, -22)
  name:SetWidth(WIDTH - 72)
  f.name = name
  local why = font(f, "GameFontHighlightSmall", unpack(COLORS.dim))
  why:SetPoint("TOPLEFT", 62, -37)
  why:SetWidth(WIDTH - 72)
  why:SetWordWrap(true)
  f.why = why

  -- Mana bar
  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetMinMaxValues(0, 100)
  bar:SetSize(WIDTH - 20, 12)
  bar:SetPoint("TOPLEFT", 10, -60)
  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetColorTexture(0, 0, 0, 0.5)
  local barText = font(bar, "GameFontHighlightSmall")
  barText:SetPoint("CENTER")
  barText:SetJustifyH("CENTER")
  f.bar, f.barText = bar, barText

  -- Status line (checklist or live advice)
  local status = font(f, "GameFontNormalSmall")
  status:SetPoint("TOPLEFT", 10, -78)
  status:SetWidth(WIDTH - 20)
  status:SetWordWrap(true)
  f.status = status

  -- Messages (fight report, level-up)
  local msg = font(f, "GameFontHighlightSmall", unpack(COLORS.text))
  msg:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -6)
  msg:SetWidth(WIDTH - 20)
  msg:SetWordWrap(true)
  f.msg = msg

  if db.hidden then f:Hide() end
  return f
end

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- view = { title, next = {label, icon, keybind, why}, usesMana, manaPct, manaExact,
--          manaLevel, status, statusKind ("warn"|"ok"|"advice") }
function Panel.render(view)
  local f = Panel.frame
  if not f or not f:IsShown() then return end
  f.title:SetText(view.title or "")
  local n = view.next
  if n then
    f.icon:SetTexture(n.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    f.icon:SetDesaturated(false)
    f.key:SetText(n.keybind or "")
    f.name:SetText(n.label or "")
    f.why:SetText(n.why or "")
  else
    f.icon:SetTexture(view.idleIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
    f.icon:SetDesaturated(true)
    f.key:SetText("")
    f.name:SetText(view.idleText or "Ready")
    f.why:SetText(view.idleWhy or "")
  end

  if view.usesMana and view.manaPct then
    f.bar:Show()
    f.bar:SetValue(view.manaPct)
    local c = COLORS[view.manaLevel or "high"] or COLORS.high
    f.bar:SetStatusBarColor(c[1], c[2], c[3])
    f.barText:SetText((view.manaExact and "Mana %d%%" or "Mana ~%d%% (estimate)"):format(math.floor(view.manaPct + 0.5)))
  else
    f.bar:Hide()
  end

  f.status:SetText(view.status or "")
  setColor(f.status, view.statusKind == "warn" and COLORS.warn or view.statusKind == "ok" and COLORS.ok or COLORS.text)

  local now = GetTime()
  if Panel.msgUntil and now > Panel.msgUntil then
    Panel.msgUntil = nil
    f.msg:SetText("")
  end
  -- grow to fit
  local h = 84 + (f.status:GetStringHeight() or 12)
  if Panel.msgUntil then h = h + 6 + (f.msg:GetStringHeight() or 12) end
  f:SetHeight(h + 8)
end

-- Shows a few lines in the message area for a while.
function Panel.flash(lines, seconds)
  local f = Panel.frame
  if not f then return end
  f.msg:SetText(table.concat(lines, "\n"))
  Panel.msgUntil = GetTime() + (seconds or 15)
end

function Panel.setScale(scale) if Panel.frame then Panel.frame:SetScale(scale) end end
function Panel.toggle(show)
  local f = Panel.frame
  if not f then return end
  if show then f:Show() else f:Hide() end
end
function Panel.resetPosition()
  local f = Panel.frame
  if not f then return end
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
  Panel.charDB.pos = nil
end
