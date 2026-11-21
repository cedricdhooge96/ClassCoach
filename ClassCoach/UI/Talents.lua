-- Marks the next talent of your build inside the game's own talent window.
--
-- Forever's talent window is PlayerSpellsFrame.TalentsFrame; each talent is a
-- button that knows which talent it shows. ClassCoach reads that and lays its
-- own frames over the buttons:
--   a gold frame and "NEXT" on the talent to take now,
--   a small 2, 3, 4, 5 on the talents after it,
--   one line at the bottom left naming the build and the next talent.
--
-- Nothing here changes the game's window. The marks are ClassCoach's own
-- frames, they are not children of the game's buttons, they let every click
-- through, and ClassCoach never learns a talent for you.
local _, ns = ...

local Talents = {}
ns.Talents = Talents

local GOLD = { 1.00, 0.82, 0.20 }
local MARKS = 5   -- the next talent and four after it

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

local function edge(parent, r, g, b, a)
  local t = parent:CreateTexture(nil, "OVERLAY")
  t:SetColorTexture(r, g, b, a)
  return t
end

local function mark(holder)
  local m = CreateFrame("Frame", nil, holder)
  m:EnableMouse(false)
  -- a 2-pixel gold frame just outside the talent's icon
  m.edges = {}
  for i = 1, 4 do m.edges[i] = edge(m, GOLD[1], GOLD[2], GOLD[3], 1) end
  m.edges[1]:SetPoint("TOPLEFT", -3, 3);    m.edges[1]:SetPoint("TOPRIGHT", 3, 3);       m.edges[1]:SetHeight(2)
  m.edges[2]:SetPoint("BOTTOMLEFT", -3, -3); m.edges[2]:SetPoint("BOTTOMRIGHT", 3, -3);   m.edges[2]:SetHeight(2)
  m.edges[3]:SetPoint("TOPLEFT", -3, 3);    m.edges[3]:SetPoint("BOTTOMLEFT", -3, -3);   m.edges[3]:SetWidth(2)
  m.edges[4]:SetPoint("TOPRIGHT", 3, 3);    m.edges[4]:SetPoint("BOTTOMRIGHT", 3, -3);   m.edges[4]:SetWidth(2)
  m.tagBack = edge(m, 0.05, 0.05, 0.07, 0.92)
  m.tag = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  m.tag:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  m.tagBack:SetPoint("TOPLEFT", m.tag, "TOPLEFT", -3, 2)
  m.tagBack:SetPoint("BOTTOMRIGHT", m.tag, "BOTTOMRIGHT", 3, -2)
  m:Hide()
  return m
end

-- role "next": the gold frame and NEXT above the icon. Otherwise the pick number at its top right corner.
local function dress(m, role, text)
  for i = 1, 4 do
    if role == "next" then m.edges[i]:Show() else m.edges[i]:Hide() end
  end
  m.tag:ClearAllPoints()
  if role == "next" then m.tag:SetPoint("BOTTOM", m, "TOP", 0, 5) else m.tag:SetPoint("CENTER", m, "TOPRIGHT", -1, -1) end
  m.tag:SetText(text)
  m.role, m.text = role, text
end

local function create()
  local holder = CreateFrame("Frame", "ClassCoachTalentMarks", UIParent)
  holder:EnableMouse(false)
  holder.marks = {}
  for i = 1, MARKS do holder.marks[i] = mark(holder) end
  local banner = CreateFrame("Frame", nil, holder)
  banner:EnableMouse(false)
  banner:SetSize(360, 30)
  banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  banner.title:SetPoint("TOPLEFT")
  banner.title:SetJustifyH("LEFT")
  banner.line = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  banner.line:SetPoint("TOPLEFT", 0, -13)
  banner.line:SetJustifyH("LEFT")
  holder.banner = banner
  holder:Hide()
  Talents.holder = holder
  return holder
end

function Talents.hide()
  local holder = Talents.holder
  if holder and Talents.shown then holder:Hide() end
  Talents.shown = false
end

-- Is the game's talent window open right now?
function Talents.open()
  local t = window()
  return t ~= nil and visible(t)
end

-- state = { build = { name }, plan, how }, see ClassCoach.lua. Returns true while marks are up.
function Talents.update(state, db)
  local t = window()
  if not t or not visible(t) or not state or not state.plan or (db and db.talentMarks == false) then
    Talents.hide()
    return false
  end
  local holder = Talents.holder or create()
  local plan = state.plan

  -- which talent each of the game's buttons shows
  local buttons, seen = {}, 0
  for button in t:EnumerateAllTalentButtons() do
    seen = seen + 1
    if seen > 400 then break end
    local ok, node = pcall(button.GetNodeID, button)
    if ok and type(node) == "number" then buttons[node] = button end
  end

  -- what to mark: the next talent, then the ones after it
  local wanted = {}
  local nextStep = plan.next and plan.steps[plan.next]
  if nextStep and nextStep.known and nextStep.node then
    wanted[1] = { node = nextStep.node, role = "next", text = "NEXT" }
  end
  for _, up in ipairs(ns.Engine.upcomingTalents(plan, MARKS - 1)) do
    wanted[#wanted + 1] = { node = up.node, role = "later", text = tostring(up.order) }
  end

  local strata, level = t:GetFrameStrata(), t:GetFrameLevel()
  if type(strata) == "string" then holder:SetFrameStrata(strata) end
  if type(level) == "number" then holder:SetFrameLevel(math.min(level + 200, 9000)) end
  local used = 0
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
    end
  end
  for i = used + 1, MARKS do holder.marks[i].node = nil; holder.marks[i]:Hide() end

  -- the line at the bottom left of the talent window
  local banner = holder.banner
  banner:ClearAllPoints()
  banner:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 18, 12)
  banner.title:SetText("ClassCoach · " .. tostring(state.build and state.build.name or "your build")
    .. (state.how == "auto" and " (fits your talents best)" or ""))
  local line
  if not plan.readable then
    line = "The game did not give your talents, so nothing is marked."
  elseif not plan.next then
    line = "This build is complete."
  elseif not nextStep.known then
    line = "Next: " .. tostring(nextStep.label) .. "  (not in your talent window)"
  else
    line = "Next: " .. ns.Engine.nextTalent(plan)
  end
  if plan.readable and plan.extra > 0 then
    line = line .. ("  ·  %d point%s outside this build"):format(plan.extra, plan.extra == 1 and "" or "s")
  elseif plan.readable and plan.ahead > 0 then
    line = line .. ("  ·  %d point%s taken earlier than this build does"):format(plan.ahead, plan.ahead == 1 and "" or "s")
  end
  banner.line:SetText(line)
  banner.text = line
  if not Talents.shown then holder:Show() end
  Talents.shown = true
  return true
end
