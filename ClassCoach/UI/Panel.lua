-- The one compact panel. Its heart is a carousel:
--   left    what you already did to this enemy (damage over time shows its seconds left)
--   middle  what to press now (bigger, with its key)
--   right   what comes next
-- Below it: the reason, what is ticking on the enemy, your mana, the checklist
-- or live advice, and a message area for fight reports and level-up tips.
local _, ns = ...

local Panel = {}
ns.Panel = Panel

local WIDTH = 320
local SIDE, MAIN, GAP = 28, 46, 16
local ROW_TOP = -24
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local COLORS = {
  high = { 0.32, 0.62, 1.00 }, medium = { 1.00, 0.78, 0.25 }, low = { 1.00, 0.35, 0.30 },
  warn = { 1.00, 0.70, 0.28 }, ok = { 0.55, 0.85, 0.55 }, dim = { 0.62, 0.62, 0.66 }, text = { 0.95, 0.93, 0.88 },
  gold = { 1.00, 0.82, 0.20 },
}

local function font(parent, template, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  if r then fs:SetTextColor(r, g, b) end
  fs:SetJustifyH("LEFT")
  return fs
end

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- One carousel slot: icon, key (bottom right) and a timer (centre).
local function slot(parent, size, x, y)
  local s = CreateFrame("Frame", nil, parent)
  s:SetSize(size, size)
  s:SetPoint("TOPLEFT", x, y)
  local tex = s:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints()
  tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  s.icon = tex
  local key = font(s, size >= MAIN and "NumberFontNormal" or "NumberFontNormalSmall", 1, 1, 1)
  key:SetPoint("BOTTOMRIGHT", 1, 1)
  key:SetJustifyH("RIGHT")
  s.key = key
  local timer = font(s, "GameFontHighlight", 1, 1, 1)
  timer:SetPoint("CENTER")
  timer:SetJustifyH("CENTER")
  s.timer = timer
  return s
end

function Panel.create(charDB, db)
  if Panel.frame then return Panel.frame end
  local ok, f = pcall(CreateFrame, "Frame", "ClassCoachPanel", UIParent, "BackdropTemplate")
  if not ok or not f then f = CreateFrame("Frame", "ClassCoachPanel", UIParent) end
  Panel.frame, Panel.charDB, Panel.db = f, charDB, db
  f:SetSize(WIDTH, 120)
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

  local title = font(f, "GameFontDisableSmall")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetWidth(WIDTH - 20)
  f.title = title

  -- Carousel: done, done, NOW, next, next
  local total = SIDE * 4 + MAIN + GAP * 4
  local x = (WIDTH - total) / 2
  local sideY = ROW_TOP - (MAIN - SIDE) / 2
  f.done, f.upcoming, f.arrows = {}, {}, {}
  local function arrow(atX)
    local a = font(f, "GameFontDisable")
    a:SetPoint("TOPLEFT", atX + 4, ROW_TOP - MAIN / 2 + 6)
    a:SetText(">")
    f.arrows[#f.arrows + 1] = a
    return a
  end
  for i = 1, 2 do
    f.done[i] = slot(f, SIDE, x, sideY)
    f.done[i].arrow = arrow(x + SIDE)
    x = x + SIDE + GAP
  end
  local glow = f:CreateTexture(nil, "BORDER")
  glow:SetPoint("TOPLEFT", x - 2, ROW_TOP + 2)
  glow:SetSize(MAIN + 4, MAIN + 4)
  glow:SetColorTexture(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.9)
  f.glow = glow
  f.now = slot(f, MAIN, x, ROW_TOP)
  f.icon, f.key = f.now.icon, f.now.key
  x = x + MAIN
  for i = 1, 2 do
    local a = arrow(x)
    x = x + GAP
    f.upcoming[i] = slot(f, SIDE, x, sideY)
    f.upcoming[i].arrow = a
    x = x + SIDE
  end
  local caption = font(f, "GameFontDisableSmall")
  caption:SetPoint("TOPRIGHT", -10, -8)
  caption:SetJustifyH("RIGHT")
  f.chainLabel = caption

  -- Under the carousel: what to press, why, and the names of what follows
  local name = font(f, "GameFontNormalLarge", unpack(COLORS.text))
  name:SetWidth(WIDTH - 20)
  name:SetJustifyH("CENTER")
  f.name = name
  local why = font(f, "GameFontHighlightSmall", unpack(COLORS.dim))
  why:SetWidth(WIDTH - 20)
  why:SetJustifyH("CENTER")
  why:SetWordWrap(true)
  f.why = why
  local chainText = font(f, "GameFontDisableSmall")
  chainText:SetWidth(WIDTH - 20)
  chainText:SetJustifyH("CENTER")
  chainText:SetWordWrap(true)
  f.chainText = chainText

  -- What is ticking on the enemy
  local dots = font(f, "GameFontHighlightSmall", unpack(COLORS.text))
  dots:SetWidth(WIDTH - 20)
  dots:SetWordWrap(true)
  f.dots = dots

  -- Mana bar
  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetMinMaxValues(0, 100)
  bar:SetSize(WIDTH - 20, 12)
  pcall(bar.SetStatusBarColor, bar, unpack(COLORS.high))
  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetColorTexture(0, 0, 0, 0.5)
  local barText = font(bar, "GameFontHighlightSmall")
  barText:SetPoint("CENTER")
  barText:SetJustifyH("CENTER")
  f.bar, f.barText = bar, barText

  -- Status line (checklist or live advice)
  local status = font(f, "GameFontNormalSmall")
  status:SetWidth(WIDTH - 20)
  status:SetWordWrap(true)
  f.status = status

  -- Messages (fight report, level-up)
  local msg = font(f, "GameFontHighlightSmall", unpack(COLORS.text))
  msg:SetWidth(WIDTH - 20)
  msg:SetWordWrap(true)
  f.msg = msg

  if db.hidden then f:Hide() end
  return f
end

local function seconds(left)
  return ("%d"):format(math.floor(left + 0.5))
end

local function fill(s, step, faded)
  if not step then
    s:Hide()
    if s.arrow then s.arrow:Hide() end
    return false
  end
  s.icon:SetTexture(step.icon or QUESTION)
  s.icon:SetDesaturated(faded and true or false)
  s:SetAlpha(faded and 0.6 or 1)
  s.key:SetText(step.keybind or "")
  s.timer:SetText("")
  s:Show()
  if s.arrow then s.arrow:Show() end
  return true
end

-- Places a text line at height y and returns the height below it.
local function place(fs, y, value, gap)
  fs:ClearAllPoints()
  if not value or value == "" then
    fs:SetText("")
    fs:Hide()
    return y
  end
  fs:SetText(value)
  fs:SetPoint("TOPLEFT", 10, y)
  fs:Show()
  return y - (fs:GetStringHeight() or 12) - (gap or 3)
end

-- view = { title, chain = steps (1 = now), planning, done = { {label, icon, left} },
--          dots = { {label, left} }, otherDotted, usesMana, manaPct, manaExact, drawMana,
--          status, statusKind ("warn"|"ok") }
function Panel.render(view)
  local f = Panel.frame
  if not f or not f:IsShown() then return end
  f.title:SetText(view.title or "")
  local steps = view.chain or {}
  local now = steps[1]

  -- Middle: what to press now (or, with nothing targeted, how your next pull starts)
  if now then
    f.icon:SetTexture(now.icon or QUESTION)
    f.icon:SetDesaturated(view.planning and true or false)
    f.key:SetText(now.keybind or "")
    f.now.timer:SetText("")
    f.glow:SetAlpha(view.planning and 0.25 or 0.9)
  else
    f.icon:SetTexture(QUESTION)
    f.icon:SetDesaturated(true)
    f.key:SetText("")
    f.glow:SetAlpha(0.25)
  end
  f.chainLabel:SetText(view.planning and "Pull" or "Then")

  -- Left: what you already did here. Damage over time shows its seconds left.
  local done = view.done or {}
  for i = 1, 2 do
    local d = done[#done - 2 + i]
    local s = f.done[i]
    if fill(s, d, true) and d.left then
      if d.left > 0 then
        s.timer:SetText(seconds(d.left))
        setColor(s.timer, d.left <= 3 and COLORS.low or COLORS.text)
        s:SetAlpha(0.9)
      else
        s.timer:SetText("0")
        setColor(s.timer, COLORS.low)
      end
    end
  end

  -- Right: what comes next. A step that isn't due yet shows when it will be.
  local names = {}
  for i = 1, 2 do
    local st = steps[i + 1]
    local s = f.upcoming[i]
    if fill(s, st, false) then
      if st.inSeconds then
        s.timer:SetText(seconds(st.inSeconds))
        setColor(s.timer, COLORS.gold)
        s:SetAlpha(0.7)
        names[#names + 1] = ("%s in %ss"):format(st.label or "?", seconds(st.inSeconds))
      else
        names[#names + 1] = st.label or "?"
      end
    end
  end

  local y = ROW_TOP - MAIN - 6
  y = place(f.name, y, now and now.label or "Ready", 2)
  y = place(f.why, y, now and now.why, 3)
  y = place(f.chainText, y, table.concat(names, " > "), 4)

  -- What is ticking on this enemy
  local dotLine
  if view.dots and #view.dots > 0 then
    local parts = {}
    for _, d in ipairs(view.dots) do parts[#parts + 1] = ("%s %ss"):format(d.label, seconds(d.left)) end
    dotLine = "On this enemy: " .. table.concat(parts, " · ")
  end
  if view.otherDotted and view.otherDotted > 0 then
    local other = view.otherDotted == 1 and "1 other enemy still ticking" or (view.otherDotted .. " other enemies still ticking")
    dotLine = dotLine and (dotLine .. "\n" .. other) or (other:sub(1, 1):upper() .. other:sub(2))
  end
  y = place(f.dots, y, dotLine, 5)

  -- Mana: the game draws the true value. If it ever refuses, show our guess and say so.
  local barShown = false
  if view.usesMana then
    f.bar:ClearAllPoints()
    f.bar:SetPoint("TOPLEFT", 10, y)
    f.bar:Show()
    barShown = true
    local drawn = not Panel.manaRefused and view.drawMana and view.drawMana(f.bar, f.barText)
    if not drawn then
      if view.drawMana then Panel.manaRefused = true end
      if view.manaPct then
        f.bar:SetMinMaxValues(0, 100)
        f.bar:SetValue(view.manaPct)
        f.barText:SetText((view.manaExact and "Mana %d%%" or "Mana about %d%% (a guess)"):format(math.floor(view.manaPct + 0.5)))
      else
        f.bar:Hide()
        barShown = false
      end
    end
  else
    f.bar:Hide()
  end
  if barShown then y = y - 18 end

  setColor(f.status, view.statusKind == "warn" and COLORS.warn or view.statusKind == "ok" and COLORS.ok or COLORS.text)
  y = place(f.status, y, view.status, 4)

  local time = GetTime()
  if Panel.msgUntil and time > Panel.msgUntil then
    Panel.msgUntil = nil
    Panel.msgText = nil
  end
  y = place(f.msg, y, Panel.msgText, 4)
  f:SetHeight(-y + 6)
end

-- Shows a few lines in the message area for a while.
function Panel.flash(lines, seconds)
  local f = Panel.frame
  if not f then return end
  Panel.msgText = table.concat(lines, "\n")
  f.msg:SetText(Panel.msgText)
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
