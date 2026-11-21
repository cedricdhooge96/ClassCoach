-- Guides you through your build inside the game's own talent window.
--
-- Forever's talent window is PlayerSpellsFrame.TalentsFrame; each talent is a
-- button that knows which talent it shows. ClassCoach reads that and lays its
-- own frames over the buttons:
--   the glow (your chosen look) and "Next" on the talent to take now,
--   a small round 2, 3, 4, 5 on the talents after it,
--   a dark veil over talents that are not part of your build,
--   a card beside the window: the build, your progress, the next five points
--   with the level each one comes at, and (when you turn it on) "Learn now".
-- A level-up toast names the talent to take when you get a point.
--
-- Nothing here changes the game's window. The marks are ClassCoach's own
-- frames, they are not children of the game's buttons and they let every click
-- through. A talent is only ever learned when you click "Learn now".
local _, ns = ...

local Talents = {}
ns.Talents = Talents

local S, C = ns.Style, ns.Style.COLORS

local MARKS = 5          -- the next talent and four after it
local VEILS = 80         -- talents dimmed at most
local ROWS = 5           -- points listed on the card
local CARD_W, ROW_H = 216, 34

local function window()
  local spells = _G.PlayerSpellsFrame
  local talents = type(spells) == "table" and spells.TalentsFrame
  if type(talents) ~= "table" or type(talents.EnumerateAllTalentButtons) ~= "function" then return nil end
  return talents
end
Talents.window = window

local function visible(frame)
  local ok, shown = pcall(frame.IsVisible, frame)
  return ok and shown == true
end

-- A number the game frame gives about itself (its edge, its scale), or nil.
local function read(f, method)
  local fn = f[method]
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, f)
  return ok and type(v) == "number" and v == v and v or nil
end

-- A round number badge for the talents after the next one, and the "Next" tag.
local function mark(holder)
  local m = CreateFrame("Frame", nil, holder)
  m:EnableMouse(false)
  m.disc = m:CreateTexture(nil, "OVERLAY")
  m.disc:SetTexture(S.MEDIA .. "disc")
  m.disc:SetSize(18, 18)
  S.tint(m.disc, C.dark, 0.92)
  m.edge = m:CreateTexture(nil, "OVERLAY", nil, 1)
  m.edge:SetTexture(S.MEDIA .. "ring_bold")
  m.edge:SetAllPoints(m.disc)
  S.tint(m.edge, C.accent)
  m.tag = S.text(m, "bold", 10, C.accent)
  m.tag:SetJustifyH("CENTER")
  m:Hide()
  return m
end

-- role "next": the tag sits on a small plate above the talent. Otherwise a numbered disc at its top right.
local function dress(m, role, text)
  m.disc:ClearAllPoints()
  if role == "next" then
    m.disc:SetSize(34, 16)
    m.disc:SetPoint("BOTTOM", m, "TOP", 0, 3)
    m.disc:SetTexture(nil)
    local d = S.COLORS.dark
    m.disc:SetColorTexture(d[1], d[2], d[3], 0.92)
    m.edge:Hide()
  else
    m.disc:SetSize(18, 18)
    m.disc:SetPoint("CENTER", m, "TOPRIGHT", -2, -2)
    m.disc:SetTexture(S.MEDIA .. "disc")
    S.tint(m.disc, S.COLORS.dark, 0.92)
    m.edge:Show()
  end
  m.tag:ClearAllPoints()
  m.tag:SetPoint("CENTER", m.disc, "CENTER", 0, 0)
  S.set(m.tag, text)
  m.role, m.text = role, text
end

local function veil(holder)
  local v = holder:CreateTexture(nil, "OVERLAY")
  v:SetColorTexture(0, 0, 0, 0.55)
  v:Hide()
  return v
end

local function row(card, i)
  local r = CreateFrame("Frame", nil, card)
  r:SetSize(CARD_W - 28, ROW_H)
  r:SetPoint("TOPLEFT", card.rowsTop, "BOTTOMLEFT", 0, -(i - 1) * ROW_H)
  r:EnableMouse(false)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(22, 22)
  r.icon:SetPoint("TOPLEFT", 0, -2)
  S.round(r, r.icon)
  r.name = S.text(r, "body", 12, C.ink)
  r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 9, 1)
  r.name:SetWidth(CARD_W - 28 - 31)
  r.name:SetWordWrap(false)
  r.detail = S.text(r, "body", 10, C.muted)
  r.detail:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
  r.detail:SetWidth(CARD_W - 28 - 31)
  r.detail:SetWordWrap(false)
  return r
end

-- The card beside the talent window.
local function makeCard(holder)
  local card = CreateFrame("Frame", "ClassCoachTalentCard", holder)
  card:SetSize(CARD_W, 120)
  card.bg = card:CreateTexture(nil, "BACKGROUND")
  card.bg:SetAllPoints()
  card.bg:SetColorTexture(C.dark[1], C.dark[2], C.dark[3], 0.94)
  card.rule = card:CreateTexture(nil, "BORDER")
  card.rule:SetPoint("TOPLEFT"); card.rule:SetPoint("BOTTOMLEFT"); card.rule:SetWidth(2)
  S.tint(card.rule, C.accent)
  card.kicker = S.text(card, "body", 10, C.muted)
  card.kicker:SetPoint("TOPLEFT", 14, -12)
  card.kicker:SetWidth(CARD_W - 28)
  card.kicker:SetWordWrap(true)
  card.title = S.text(card, "bold", 14, C.ink)
  card.title:SetPoint("TOPLEFT", card.kicker, "BOTTOMLEFT", 0, -4)
  card.title:SetWidth(CARD_W - 28)
  card.title:SetWordWrap(true)
  card.bar = CreateFrame("StatusBar", nil, card)
  card.bar:SetSize(CARD_W - 28, 4)
  card.bar:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -10)
  card.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  card.bar:SetStatusBarColor(C.accent[1], C.accent[2], C.accent[3])
  card.bar.track = card.bar:CreateTexture(nil, "BACKGROUND")
  card.bar.track:SetAllPoints()
  card.bar.track:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
  card.progress = S.text(card, "body", 10, C.muted)
  card.progress:SetPoint("TOPLEFT", card.bar, "BOTTOMLEFT", 0, -5)
  card.rowsTop = CreateFrame("Frame", nil, card)
  card.rowsTop:SetSize(1, 1)
  card.rowsTop:SetPoint("TOPLEFT", card.progress, "BOTTOMLEFT", 0, -8)
  card.rows = {}
  for i = 1, ROWS do card.rows[i] = row(card, i) end
  card.line = S.text(card, "body", 11, C.warn)   -- "Next: ..." when nothing is listed, or a warning
  card.line:SetWidth(CARD_W - 28)
  card.line:SetWordWrap(true)
  card.learn = S.button(card, "Learn now")
  card.learn:SetScript("OnClick", S.guard(function() Talents.learn() end))
  -- The card is our own frame: it catches clicks on itself only, and you can
  -- drag it anywhere. Where you put it is remembered.
  card:EnableMouse(true)
  card:SetMovable(true)
  card:SetClampedToScreen(true)
  card:RegisterForDrag("LeftButton")
  card:SetScript("OnDragStart", function(self) self:StartMoving() end)
  card:SetScript("OnDragStop", S.guard(function(self)
    self:StopMovingOrSizing()
    local left, top = self:GetLeft(), self:GetTop()
    if Talents.db and type(left) == "number" and type(top) == "number" then Talents.db.talentCardPos = { left, top } end
  end))
  return card
end

local function create()
  local holder = CreateFrame("Frame", "ClassCoachTalentMarks", UIParent)
  holder:EnableMouse(false)
  holder.marks, holder.veils = {}, {}
  for i = 1, MARKS do holder.marks[i] = mark(holder) end
  holder.glow = ns.Glow.new("ClassCoachTalentGlow")
  holder.card = makeCard(holder)
  holder.banner = holder.card   -- what the tests and /coach check call it
  holder:Hide()
  Talents.holder = holder
  return holder
end

function Talents.hide()
  local holder = Talents.holder
  if holder then ns.Glow.hide(holder.glow) end
  if holder and Talents.shown then holder:Hide() end
  Talents.shown = false
end

-- For /coach check: what the marks found the last time the talent window was open.
function Talents.describe()
  if not Talents.seen then return "talent window: not opened yet this session" end
  local holder = Talents.holder
  local glow = holder and holder.glow
  local function about(f)
    if not f then return "-" end
    local function v(m) local ok, x = pcall(f[m], f); return ok and tostring(x) or "?" end
    return ("%s/%s lvl %s %sx%s vis %s"):format(v("IsShown"), v("GetFrameStrata"), v("GetFrameLevel"), v("GetWidth"), v("GetHeight"), v("IsVisible"))
  end
  local step = Talents.nextStep
  local button = step and step.node and Talents.buttons and Talents.buttons[step.node]
  local count = 0
  for _ in pairs(Talents.buttons or {}) do count = count + 1 end
  return ("talent window: %d buttons (%d talents), top level %d; next %s node %s known %s; its button %s; holder %s; mark %s; glow %s (%s); veils %s"):format(
    Talents.seen, count, Talents.top or 0, step and tostring(step.name) or "-", step and tostring(step.node) or "-", step and tostring(step.known) or "-",
    about(button), about(holder), about(holder and holder.marks[1]), about(glow), glow and tostring(glow.style) or "-", tostring(Talents.veiled))
end

-- Is the game's talent window open right now?
function Talents.open()
  local t = window()
  return t ~= nil and visible(t)
end

-- Where you dragged it; else beside the window, on the side with room; else
-- inside its bottom left corner.
local function place(card, t, db)
  card:ClearAllPoints()
  local pos = db.talentCardPos
  if type(pos) == "table" and type(pos[1]) == "number" and type(pos[2]) == "number" then
    card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
    card.where = "yours"
    return
  end
  local right, left = read(t, "GetRight"), read(t, "GetLeft")
  local scale = read(t, "GetEffectiveScale") or 1
  local screen = read(UIParent, "GetWidth") or 1365
  local uiScale = read(UIParent, "GetEffectiveScale") or 1
  local need = (CARD_W + 12) * uiScale
  if right and right * scale + need <= screen * uiScale then
    card:SetPoint("TOPLEFT", t, "TOPRIGHT", 10, -40)
    card.where = "right"
  elseif left and left * scale >= need then
    card:SetPoint("TOPRIGHT", t, "TOPLEFT", -10, -40)
    card.where = "left"
  else
    card:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 18, 44)
    card.where = "inside"
  end
end

-- The height a text takes, measured (it may wrap).
local function tall(fs, fallback)
  local h = fs:GetStringHeight()
  return type(h) == "number" and h > 0 and h or fallback
end

-- Fills the card and lays it out from what its texts measure. Returns the
-- "Next: ..." line (also stored as card.text).
local function fillCard(card, state, db, level)
  local plan = state.plan
  S.set(card.kicker, state.how == "auto" and "Your build, the one that fits your talents best" or "Your build")
  S.set(card.title, tostring(state.build and state.build.name or "your build"))
  local total = #plan.steps
  card.bar:SetMinMaxValues(0, math.max(1, total))
  card.bar:SetValue(plan.taken or 0)
  S.set(card.progress, ("%d of %d points"):format(plan.taken or 0, total))
  local schedule = plan.readable and ns.Engine.talentSchedule(plan, level, ROWS, state.unspent) or {}
  for i, r in ipairs(card.rows) do
    local e = schedule[i]
    if e then
      r.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      r.icon:SetDesaturated(not e.known)
      S.set(r.name, e.name)
      S.set(r.detail, ns.Engine.describeTalentRow(e))
      local c = e.due and C.accent or C.muted
      r.detail:SetTextColor(c[1], c[2], c[3])
      r.entry = e
      r:Show()
    else
      r.entry = nil
      r:Hide()
    end
  end
  local line
  local nextStep = plan.next and plan.steps[plan.next]
  Talents.nextStep = nextStep
  if not plan.readable then
    line = "The game did not give your talents, so nothing is marked."
  elseif not plan.next then
    line = "This build is complete."
  elseif not nextStep.known then
    line = "Next: " .. tostring(nextStep.label) .. "  (not in your talent window)"
  else
    line = "Next: " .. ns.Engine.nextTalent(plan)
  end
  local warn
  if plan.readable and plan.extra > 0 then
    warn = ("%d of your points are in talents this build never takes."):format(plan.extra)
    if plan.extra == 1 then warn = "1 of your points is in a talent this build never takes." end
  elseif plan.readable and plan.ahead > 0 then
    warn = ("%d of your points are in talents this build takes later."):format(plan.ahead)
    if plan.ahead == 1 then warn = "1 of your points is in a talent this build takes later." end
  end
  card.text = warn and (line .. "  " .. warn) or line
  -- top to bottom, from measured heights
  local y = 12
  y = y + tall(card.kicker, 12) + 4 + tall(card.title, 16) + 10 + 4 + 5 + tall(card.progress, 12) + 8
  y = y + #schedule * ROW_H
  local below = warn or (#schedule == 0 and line) or nil
  card.line:ClearAllPoints()
  card.line:SetPoint("TOPLEFT", card.rowsTop, "BOTTOMLEFT", 0, -(#schedule * ROW_H) - 2)
  S.set(card.line, below or "")
  local c = warn and C.warn or C.muted
  card.line:SetTextColor(c[1], c[2], c[3])
  card.line:SetShown(below ~= nil)
  local lineH = below and tall(card.line, 14) + 8 or 0
  y = y + lineH
  -- Learn now: only when you turned it on, out of combat, with a point to spend on the talent that is next
  local first = schedule[1]
  local points = type(state.unspent) == "number" and state.unspent or 0
  local canLearn = db.learnNow == true and points > 0 and first and first.due and first.known and first.node and not ns.API.inCombat()
  card.learn:ClearAllPoints()
  card.learn:SetPoint("TOPLEFT", card.rowsTop, "BOTTOMLEFT", 0, -(#schedule * ROW_H) - 2 - lineH)
  card.learn:SetWidth(CARD_W - 28)
  if canLearn then S.set(card.learn.label, "Learn " .. first.name) end
  card.learn.node = canLearn and first.node or nil
  card.learn:SetShown(canLearn and true or false)
  if canLearn then y = y + 24 + 6 end
  card:SetHeight(y + 12)
  return line
end

-- state = { build = { name }, plan, how, have }, see ClassCoach.lua. Returns true while marks are up.
function Talents.update(state, db, level)
  local t = window()
  if not t or not visible(t) or not state or not state.plan or (db and db.talentMarks == false) then
    Talents.hide()
    return false
  end
  local holder = Talents.holder or create()
  Talents.db = db
  local plan = state.plan

  -- which talent each of the game's buttons shows, and how high they are drawn
  -- (the game draws its talent buttons at level 1000 and up, far above its window)
  local buttons, seen, top, strata = {}, 0, read(t, "GetFrameLevel") or 0, nil
  for button in t:EnumerateAllTalentButtons() do
    seen = seen + 1
    if seen > 400 then break end
    local ok, node = pcall(button.GetNodeID, button)
    -- the game may keep more than one button for a talent: the one on screen wins
    if ok and type(node) == "number" and (not buttons[node] or visible(button)) then
      buttons[node] = button
      top = math.max(top, read(button, "GetFrameLevel") or 0)
      if not strata then
        local okS, st = pcall(button.GetFrameStrata, button)
        strata = okS and type(st) == "string" and st or nil
      end
    end
  end
  Talents.seen, Talents.top, Talents.buttons = seen, top, buttons
  strata = strata or t:GetFrameStrata()
  if type(strata) == "string" and holder:GetFrameStrata() ~= strata then holder:SetFrameStrata(strata) end
  local want = math.min(top + 20, 9000)
  if holder:GetFrameLevel() ~= want then holder:SetFrameLevel(want) end

  -- the next talent: the glow and its tag; then numbered discs on the ones after it
  local wanted = {}
  local nextStep = plan.next and plan.steps[plan.next]
  Talents.nextStep = nextStep
  if nextStep and nextStep.known and nextStep.node then
    wanted[1] = { node = nextStep.node, role = "next", text = "Next" }
  end
  for _, up in ipairs(ns.Engine.upcomingTalents(plan, MARKS - 1)) do
    wanted[#wanted + 1] = { node = up.node, role = "later", text = tostring(up.order) }
  end
  local used, glowOn = 0, nil
  for _, w in ipairs(wanted) do
    local button = buttons[w.node]
    if button and used < MARKS and visible(button) then
      used = used + 1
      local m = holder.marks[used]
      m:ClearAllPoints()
      m:SetAllPoints(button)
      dress(m, w.role, w.text)
      m.node = w.node
      m:Show()
      if w.role == "next" then glowOn = button end
    end
  end
  for i = used + 1, MARKS do holder.marks[i].node = nil; holder.marks[i]:Hide() end
  ns.Glow.show(holder.glow, glowOn, db.talentGlow or "glow", db.glowColor, top)
  Talents.nextFound = glowOn ~= nil

  -- a veil over every talent that is not part of the build
  local outside = db.talentDim ~= false and plan.readable and ns.Engine.outsideBuild(plan, state.have) or {}
  local veiled = 0
  for node in pairs(outside) do
    local button = buttons[node]
    if button and veiled < VEILS and visible(button) then
      veiled = veiled + 1
      local v = holder.veils[veiled] or veil(holder)
      holder.veils[veiled] = v
      v:ClearAllPoints()
      v:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
      v:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
      v:Show()
    end
  end
  for i = veiled + 1, #holder.veils do holder.veils[i]:Hide() end
  Talents.veiled = veiled

  -- the card
  local card = holder.card
  if db.talentList ~= false then
    place(card, t, db)
    fillCard(card, state, db, level or 1)
    card:Show()
  else
    card.text = nil
    card:Hide()
  end
  if not Talents.shown then holder:Show() end
  Talents.shown = true
  return true
end

---------------------------------------------------------------------------
-- Learn now (opt-in)
---------------------------------------------------------------------------

local LEARN_SAYS = {
  combat = "Talents can only be learned out of combat.",
  pending = "Your talent window has changes you have not applied. Apply or undo them first.",
  cannot = "The game would not learn that talent now. Click it in the talent window yourself.",
  failed = "The game did not take it. Click the talent in the talent window yourself.",
}

-- The node to learn: the card's button, else the toast's.
function Talents.learn(node)
  node = node or (Talents.holder and Talents.holder.card.learn.node) or Talents.toastNode
  if not node then return nil end
  local result = ns.API.learnTalent(node)
  if Talents.onLearn then Talents.onLearn(result, LEARN_SAYS[result]) end
  return result
end

---------------------------------------------------------------------------
-- The level-up toast
---------------------------------------------------------------------------

local TOAST_SECONDS = 9

local function makeToast()
  local f = CreateFrame("Frame", "ClassCoachToast", UIParent)
  f:SetSize(340, 64)
  f:SetPoint("TOP", UIParent, "TOP", 0, -150)
  f:SetFrameStrata("MEDIUM")
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(C.dark[1], C.dark[2], C.dark[3], 0.94)
  f.rule = f:CreateTexture(nil, "BORDER")
  f.rule:SetPoint("TOPLEFT"); f.rule:SetPoint("BOTTOMLEFT"); f.rule:SetWidth(2)
  S.tint(f.rule, C.accent)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(40, 40)
  f.icon:SetPoint("LEFT", 14, 0)
  S.round(f, f.icon)
  f.ring = f:CreateTexture(nil, "OVERLAY")
  f.ring:SetTexture(S.MEDIA .. "ring")
  f.ring:SetPoint("CENTER", f.icon)
  f.ring:SetSize(46, 46)
  S.tint(f.ring, C.accent)
  f.kicker = S.text(f, "body", 10, C.muted)
  f.kicker:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, 1)
  f.name = S.text(f, "bold", 15, C.ink)
  f.name:SetPoint("TOPLEFT", f.kicker, "BOTTOMLEFT", 0, -3)
  f.name:SetWidth(180)
  f.name:SetWordWrap(false)
  f.detail = S.text(f, "body", 10, C.muted)
  f.detail:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
  f.learn = S.button(f, "Learn", 70)
  f.learn:SetPoint("RIGHT", -12, 0)
  f.learn:SetScript("OnClick", S.guard(function()
    local result = Talents.learn(Talents.toastNode)
    if result == "learned" then f:Hide() end
  end))
  f:EnableMouse(true)
  f:SetScript("OnMouseUp", function(self) self:Hide() end)   -- a click anywhere else on it puts it away
  f:SetScript("OnUpdate", S.guard(function(self)
    local left = (self.untilT or 0) - GetTime()
    if self:IsMouseOver() then self.untilT = GetTime() + 2 return end   -- reading it: keep it
    if left <= 0 then self:Hide() return end
    self:SetAlpha(left < 1 and left or 1)
  end))
  f:Hide()
  return f
end

-- At a level-up with a talent point: which talent to take, with Learn when you turned that on.
-- entry: the first line of Engine.talentSchedule. Returns true when shown.
function Talents.toast(entry, db, level)
  if not entry or db.talentToast == false or (level or 0) < ns.Engine.FIRST_TALENT_LEVEL then return false end
  local f = Talents.toastFrame or makeToast()
  Talents.toastFrame = f
  f.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  S.set(f.kicker, ("Level %d: a talent point to spend"):format(level))
  S.set(f.name, entry.name)
  S.set(f.detail, ("Rank %d of %d in your build"):format(entry.fromRank, entry.max))
  Talents.toastNode = entry.known and entry.due and entry.node or nil
  f.learn:SetShown(db.learnNow == true and Talents.toastNode ~= nil and not ns.API.inCombat())
  f.untilT = GetTime() + TOAST_SECONDS
  f:SetAlpha(1)
  f:Show()
  return true
end
