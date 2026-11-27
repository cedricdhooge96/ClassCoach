-- ClassCoach's own settings window (/coach, or the minimap's addon menu).
--
-- The addon never opens the game's Settings window itself (that is one known
-- way to upset the action bars in combat), so this window is ClassCoach's own
-- plain frame: a sidebar of sections, each option on one row with its control
-- on the right, a live preview where a setting is about looks, a first-time
-- setup page, and a page to share your settings as one line of text.
-- Every control writes straight into the saved settings; the coach picks the
-- change up on its next refresh.
local _, ns = ...

local Window = {}
ns.Window = Window

local W, H, SIDE, HEAD = 660, 500, 164, 64
local BODY_W = W - SIDE - 48          -- content column
local CONTROL_W = 196                  -- the right-hand column of a row
local TEXT_W = BODY_W - CONTROL_W - 20

-- Sidebar pages. A section page lists the options under that header in UI/Options.lua.
Window.PAGES = {
  { id = "start", name = "Start here" },
  { id = "Coach", name = "Coach", section = true, about = "The ring under your character: what to press now, what you already cast, what comes next." },
  { id = "Action bars", name = "Action bars", section = true, about = "Your bars by purpose: the fight on the main bar, emergencies on Action Bar 2, buffs on Action Bar 3." },
  { id = "Talents", name = "Talents", section = true, about = "Your build, followed inside the game's talent window." },
  { id = "Journey", name = "Journey", section = true, about = "The list beside the coach: XP, rested XP and what to do between fights." },
  { id = "Professions", name = "Professions", section = true, about = "Which two professions suit your class, and what to make next in each." },
  { id = "Look", name = "Look", section = true, about = "How the coach and the journey list are drawn." },
  { id = "share", name = "Share" },
}

local S, C = ns.Style, ns.Style.COLORS
local function db() return ClassCoachDB or {} end
local function charDB() return ClassCoachCharDB or {} end
local function run(cmd) return function() SlashCmdList.CLASSCOACH(cmd) end end

local function color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

---------------------------------------------------------------------------
-- Controls. Each takes the option and a function to call after a change.
---------------------------------------------------------------------------

local function value(o)
  local v = (o.perChar and charDB() or db())[o.key]
  if v == nil then return o.default end
  return v
end

local function write(o, v, changed)
  if ns.Options.set(db(), charDB(), o.key, v) and changed then changed(o) end
end

-- A switch: a capsule with a knob. Gold and to the right when on.
local function switch(parent, o, changed)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(36, 18)
  b.track = b:CreateTexture(nil, "ARTWORK")
  b.track:SetAllPoints()
  b.track:SetTexture(S.MEDIA .. "pill")
  b.track:SetTexCoord(0, 1, 0.25, 0.75)
  b.knob = b:CreateTexture(nil, "OVERLAY")
  b.knob:SetTexture(S.MEDIA .. "disc")
  b.knob:SetSize(14, 14)
  function b.refresh()
    local on = value(o) == true
    S.tint(b.track, on and C.accent or C.line)
    S.tint(b.knob, on and C.dark or C.muted)
    b.knob:ClearAllPoints()
    b.knob:SetPoint(on and "RIGHT" or "LEFT", on and -2 or 2, 0)
    b.on = on
  end
  b:SetScript("OnClick", S.guard(function() write(o, not (value(o) == true), changed); b.refresh() end))
  b.refresh()
  return b
end

-- A picker for a list: the value between two arrows; click the value or an arrow to step through.
local function picker(parent, o, changed)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(CONTROL_W, 22)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(1, 1, 1, 0.05)
  local function arrow(text, point, step)
    local a = CreateFrame("Button", nil, f)
    a:SetSize(22, 22)
    a:SetPoint(point)
    a.label = S.text(a, "bold", 13, C.muted)
    a.label:SetPoint("CENTER")
    S.set(a.label, text)
    a:SetScript("OnEnter", function() color(a.label, C.accent) end)
    a:SetScript("OnLeave", function() color(a.label, C.muted) end)
    a:SetScript("OnClick", S.guard(function() f.step(step) end))
    return a
  end
  f.prev, f.next = arrow("<", "LEFT", -1), arrow(">", "RIGHT", 1)
  f.text = S.text(f, "body", 12, C.ink)
  f.text:SetPoint("CENTER")
  f.text:SetJustifyH("CENTER")
  f.text:SetWidth(CONTROL_W - 48)
  f.text:SetWordWrap(false)
  function f.step(by)
    local list, at = o.choices(), 1
    for i, c in ipairs(list) do if c[1] == value(o) then at = i end end
    local pick = list[(at - 1 + by) % #list + 1]
    if pick then write(o, pick[1], changed) end
    f.refresh()
  end
  function f.refresh()
    local label = tostring(value(o))
    for _, c in ipairs(o.choices()) do if c[1] == value(o) then label = c[2] end end
    S.set(f.text, label)
  end
  local hit = CreateFrame("Button", nil, f)
  hit:SetPoint("TOPLEFT", 22, 0)
  hit:SetPoint("BOTTOMRIGHT", -22, 0)
  hit:SetScript("OnClick", S.guard(function() f.step(1) end))
  f.refresh()
  return f
end

-- A slider: a thin track that fills in gold, a round thumb, the value on the right.
local function slider(parent, o, changed)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(CONTROL_W, 22)
  local sl = CreateFrame("Slider", nil, f)
  sl:SetPoint("LEFT")
  sl:SetSize(CONTROL_W - 52, 16)
  sl:SetOrientation("HORIZONTAL")
  sl:SetMinMaxValues(o.min, o.max)
  sl:SetValueStep(o.step)
  pcall(sl.SetObeyStepOnDrag, sl, true)
  sl:SetThumbTexture(S.MEDIA .. "disc")
  local thumb = sl.GetThumbTexture and sl:GetThumbTexture()
  if thumb then thumb:SetSize(14, 14); S.tint(thumb, C.ink) end
  f.track = sl:CreateTexture(nil, "BACKGROUND")
  f.track:SetPoint("LEFT"); f.track:SetPoint("RIGHT")
  f.track:SetHeight(3)
  f.track:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
  f.fill = sl:CreateTexture(nil, "ARTWORK")
  f.fill:SetPoint("LEFT")
  f.fill:SetHeight(3)
  f.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
  f.text = S.text(f, "body", 12, C.ink)
  f.text:SetPoint("RIGHT")
  f.text:SetJustifyH("RIGHT")
  local function show(v)
    local share = (v - o.min) / (o.max - o.min)
    f.fill:SetWidth(math.max(1, share * (CONTROL_W - 52)))
    S.set(f.text, o.unit == "x" and ("%.2fx"):format(v) or ("%d%s"):format(v, o.unit or ""))
  end
  f.refreshing = false
  sl:SetScript("OnValueChanged", S.guard(function(_, v)
    if f.refreshing or type(v) ~= "number" then return end
    v = math.floor((v - o.min) / o.step + 0.5) * o.step + o.min
    write(o, v, changed)
    show(v)
  end))
  function f.refresh()
    f.refreshing = true
    sl:SetValue(value(o))
    f.refreshing = false
    show(value(o))
  end
  f.slider = sl
  f.refresh()
  return f
end

local CONTROLS = { check = switch, slider = slider, choice = picker }

---------------------------------------------------------------------------
-- Layout helpers
---------------------------------------------------------------------------

-- Text that wraps in the text column. Returns the font string and its height.
local function para(parent, x, y, text, size, c, width)
  local fs = S.text(parent, size >= 13 and "bold" or "body", size, c)
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetWidth(width or BODY_W)
  fs:SetWordWrap(true)
  S.set(fs, text)
  local h = fs:GetStringHeight()
  return fs, (type(h) == "number" and h > 0) and h or size + 2
end

-- One option: its name and what it does on the left, the control on the right.
local function optionRow(page, o, y, changed)
  local name, h1 = para(page, 0, y, o.name, 13, C.ink, TEXT_W)
  local tip, h2 = para(page, 0, y - h1 - 3, o.tip or "", 11, C.muted, TEXT_W)
  local control = CONTROLS[o.kind](page, o, changed)
  control:SetPoint("TOPRIGHT", page, "TOPLEFT", BODY_W, y - 1)
  page.controls[#page.controls + 1] = control
  page.byKey[o.key] = control
  local rule = page:CreateTexture(nil, "BORDER")
  rule:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.6)
  rule:SetHeight(1)
  local height = math.max(h1 + 3 + h2, 22) + 14
  rule:SetPoint("TOPLEFT", 0, y - height + 7)
  rule:SetWidth(BODY_W)
  return y - height, name, tip
end

local function button(page, label, x, y, onClick, width)
  local b = S.button(page, label, width)
  b:SetPoint("TOPLEFT", x, y)
  b:SetScript("OnClick", S.guard(onClick))
  return b
end

-- A tile with one icon and the chosen highlight on it, so a look can be judged before a fight.
local function preview(page, y, icon, styleKey, caption)
  local tile = CreateFrame("Frame", nil, page)
  tile:SetSize(BODY_W, 76)
  tile:SetPoint("TOPLEFT", 0, y)
  tile.bg = tile:CreateTexture(nil, "BACKGROUND")
  tile.bg:SetAllPoints()
  tile.bg:SetColorTexture(1, 1, 1, 0.04)
  tile.button = CreateFrame("Frame", nil, tile)
  tile.button:SetSize(40, 40)
  tile.button:SetPoint("LEFT", 26, 0)
  tile.icon = tile.button:CreateTexture(nil, "ARTWORK")
  tile.icon:SetAllPoints()
  tile.icon:SetTexture(icon)
  tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  tile.caption = S.text(tile, "body", 11, C.muted)
  tile.caption:SetPoint("LEFT", tile.button, "RIGHT", 26, 0)
  tile.caption:SetWidth(BODY_W - 120)
  tile.caption:SetWordWrap(true)
  S.set(tile.caption, caption)
  tile.glow = ns.Glow.new()
  function tile.refresh()
    local style = db()[styleKey]
    if style == "off" then style = nil end
    ns.Glow.show(tile.glow, style and tile.button or nil, style, db().glowColor)
    tile.glow:SetFrameStrata("DIALOG")
    local level = Window.frame and Window.frame:GetFrameLevel()
    tile.glow:SetFrameLevel((type(level) == "number" and level or 10) + 20)
  end
  tile.top = -y      -- where it sits in the page, to know when it is scrolled out of sight
  page.previews[#page.previews + 1] = tile
  return tile, y - 76 - 18
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

local function newPage(content)
  local page = CreateFrame("Frame", nil, content)
  page:SetPoint("TOPLEFT")
  page:SetSize(BODY_W, 10)
  page.controls, page.byKey, page.previews, page.extra = {}, {}, {}, {}
  page:Hide()
  return page
end

local function refreshPage(page)
  for _, c in ipairs(page.controls) do c.refresh() end
  if page.update then page.update() end
  -- the previews follow the scroll position (Window.scrollBy shows only those in view)
  local f = Window.frame
  if f and f.pages[Window.current] == page then Window.scrollBy(0)
  else for _, p in ipairs(page.previews) do p.refresh() end end
end

local function sectionPage(content, info)
  local page = newPage(content)
  local changed = function() refreshPage(page) end
  local y = 0
  local _, h = para(page, 0, y, info.about, 12, C.muted)
  y = y - h - 16
  if info.id == "Coach" then
    button(page, "Play the demo", 0, y, run("demo"), 150)
    button(page, "Put the panels back", 162, y, run("reset"), 170)
    y = y - 24 - 18
  elseif info.id == "Action bars" then
    local icon = ns.C.lastView and ns.C.lastView.chain and ns.C.lastView.chain[1] and ns.C.lastView.chain[1].icon
    _, y = preview(page, y, icon or "Interface\\Icons\\Spell_Shadow_ShadowBolt",
      "barGlow", "This is how the button to press looks on your action bars. Change the look or the colour below and watch it here.")
  elseif info.id == "Talents" then
    local state = ns.C.talentState
    local nextOne = state and state.plan and state.plan.readable and ns.Engine.talentSchedule(state.plan, ns.C.level or 1, 1)[1]
    _, y = preview(page, y, nextOne and nextOne.icon or "Interface\\Icons\\Spell_Shadow_UnholyStrength",
      "talentGlow", "This is how your next talent looks in the talent window.")
  end
  for _, section in ipairs(ns.Options.sections()) do
    if section.name == info.id then
      for _, o in ipairs(section.options) do y = optionRow(page, o, y, changed) end
    end
  end
  if info.id == "Action bars" then
    y = y - 6
    local _, h2 = para(page, 0, y, "Lay out your bars", 13, C.ink)
    y = y - h2 - 8
    button(page, "Fill empty buttons", 0, y, run("bar"), 150)
    button(page, "Reset to the coach's layout", 162, y, run("bar reset"), 210)
    y = y - 32
    button(page, "Undo the reset", 0, y, run("bar undo"), 150)
    button(page, "Refresh the CC macros", 162, y, run("macros"), 210)
    y = y - 32
  elseif info.id == "Talents" then
    y = y - 6
    local _, h2 = para(page, 0, y, "Drag the build card anywhere; it stays where you put it. To follow a build from a guide, type /coach build followed by an Icy Veins or Warcraft Tavern talent calculator link.", 11, C.muted)
    y = y - h2 - 10
    button(page, "Put the build card back", 0, y, function() db().talentCardPos = nil end, 190)
    y = y - 32
  end
  page:SetHeight(-y + 12)
  return page
end

-- A numbered step of the first-time setup (it is a sequence, so the numbers mean something).
local function stepCard(page, n, y, title, body)
  local num = S.text(page, "bold", 20, C.accent)
  num:SetPoint("TOPLEFT", 0, y + 2)
  S.set(num, tostring(n))
  local t, h1 = para(page, 30, y, title, 13, C.ink, BODY_W - 30)
  local b, h2 = para(page, 30, y - h1 - 4, body, 11, C.muted, BODY_W - 30)
  return y - h1 - 4 - h2 - 10, t, b
end

local function startPage(content)
  local page = newPage(content)
  local y = 0
  local _, h = para(page, 0, y, "Four steps, once. After that the coach looks after itself.", 12, C.muted)
  y = y - h - 18
  y = stepCard(page, 1, y, "Lay out your action bars",
    "The fight on your main bar, emergencies on Action Bar 2, buffs on Action Bar 3, with no gaps. What was there can be put back.")
  button(page, "Reset my bars", 30, y, run("bar reset"), 150)
  button(page, "Undo", 192, y, run("bar undo"), 80)
  y = y - 24 - 22
  local smartBody
  y, _, smartBody = stepCard(page, 2, y, "Bind the smart key",
    "One key that walks the coach's plan. Bind it under Options, Keybindings, AddOns, ClassCoach.")
  page.smartLine = S.text(page, "body", 11, C.ok)
  page.smartLine:SetPoint("TOPLEFT", 30, y + 4)
  y = y - 18
  local _, buildLine
  y, _, buildLine = stepCard(page, 3, y, "Follow a talent build", "")
  page.buildLine = buildLine
  y = stepCard(page, 4, y, "Place the coach",
    "Drag the ring where you like, then lock it. The demo plays every state the coach can show.")
  button(page, "Play the demo", 30, y, run("demo"), 150)
  local lock = switch(page, ns.Options.find("locked"))
  lock:SetPoint("TOPLEFT", 196, y - 3)
  page.controls[#page.controls + 1] = lock
  local lockText = S.text(page, "body", 11, C.muted)
  lockText:SetPoint("LEFT", lock, "RIGHT", 8, 0)
  S.set(lockText, "Locked in place")
  y = y - 24 - 12
  function page.update()
    local keys = ns.Smart.status().keys
    if keys.next then
      S.set(page.smartLine, "Bound to " .. keys.next .. ". Type /coach smart to see its steps.")
      color(page.smartLine, C.ok)
    else
      S.set(page.smartLine, "Not bound yet.")
      color(page.smartLine, C.warn)
    end
    local state = ns.C.talentState
    local text
    if not state then
      text = "There is no build for this class yet."
    else
      text = "You follow " .. tostring(state.build.name) .. "."
      if state.plan.readable and state.plan.next then text = text .. " Next: " .. ns.Engine.nextTalent(state.plan) .. "." end
      text = text .. " Open your talent window: the next talent is lit there."
    end
    S.set(page.buildLine, text)
  end
  page:SetHeight(-y + 12)
  return page
end

local function sharePage(content)
  local page = newPage(content)
  local y = 0
  local _, h = para(page, 0, y, "Your settings as one line of text: keep it, or give it to a friend. Only what differs from the defaults is in it, and nothing that belongs to one character.", 12, C.muted)
  y = y - h - 16
  local function box(yy)
    local frame = CreateFrame("Frame", nil, page)
    frame:SetPoint("TOPLEFT", 0, yy)
    frame:SetSize(BODY_W, 28)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(1, 1, 1, 0.06)
    local e = CreateFrame("EditBox", nil, frame)
    e:SetPoint("TOPLEFT", 8, 0)
    e:SetPoint("BOTTOMRIGHT", -8, 0)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
  end
  local _, h1 = para(page, 0, y, "Your settings", 13, C.ink)
  y = y - h1 - 8
  page.out = box(y)
  page.out:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  page.out:SetScript("OnTextChanged", function(self, typed) if typed then self:SetText(page.exported or ""); self:HighlightText() end end)
  y = y - 28 - 6
  local _, h2 = para(page, 0, y, "Click the line, then press Ctrl+C to copy it.", 11, C.muted)
  y = y - h2 - 20
  local _, h3 = para(page, 0, y, "Use settings from a line", 13, C.ink)
  y = y - h3 - 8
  page.inBox = box(y)
  y = y - 28 - 8
  page.result = S.text(page, "body", 11, C.muted)
  page.result:SetPoint("TOPLEFT", 162, y - 6)
  page.result:SetWidth(BODY_W - 162)
  button(page, "Use these settings", 0, y, function()
    local taken, skipped = ns.Options.import(page.inBox:GetText(), db(), charDB())
    if not taken then
      S.set(page.result, "That is not a ClassCoach settings line.")
      color(page.result, C.warn)
    else
      S.set(page.result, ("%d setting%s used."):format(taken, taken == 1 and "" or "s")
        .. (#skipped > 0 and (" Not used: " .. table.concat(skipped, ", ") .. ".") or ""))
      color(page.result, #skipped > 0 and C.warn or C.ok)
      page.update()
    end
  end, 150)
  y = y - 24 - 12
  function page.update()
    page.exported = ns.Options.export(db())
    page.out:SetText(page.exported)
  end
  page:SetHeight(-y + 12)
  return page
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function closeButton(f)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(28, 28)
  b:SetPoint("TOPRIGHT", -12, -14)
  b.lines = {}
  for i, ends in ipairs({ { -6, 6, 6, -6 }, { -6, -6, 6, 6 } }) do
    local l = b:CreateLine(nil, "OVERLAY")
    l:SetThickness(2)
    l:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 1)
    l:SetStartPoint("CENTER", ends[1], ends[2])
    l:SetEndPoint("CENTER", ends[3], ends[4])
    b.lines[i] = l
  end
  local function tint(c) for _, l in ipairs(b.lines) do l:SetColorTexture(c[1], c[2], c[3], 1) end end
  b:SetScript("OnEnter", function() tint(C.ink) end)
  b:SetScript("OnLeave", function() tint(C.muted) end)
  b:SetScript("OnClick", S.guard(function() Window.close() end))
  return b
end

local function navItem(f, info, i)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(SIDE - 16, 30)
  b:SetPoint("TOPLEFT", 8, -HEAD - 12 - (i - 1) * 32)
  b.mark = b:CreateTexture(nil, "ARTWORK")
  b.mark:SetPoint("TOPLEFT", 0, -6); b.mark:SetPoint("BOTTOMLEFT", 0, 6); b.mark:SetWidth(2)
  b.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
  b.hover = b:CreateTexture(nil, "BACKGROUND")
  b.hover:SetAllPoints()
  b.hover:SetColorTexture(1, 1, 1, 0.05)
  b.hover:Hide()
  b.label = S.text(b, "body", 13, C.muted)
  b.label:SetPoint("LEFT", 14, 0)
  S.set(b.label, info.name)
  b:SetScript("OnEnter", function() b.hover:Show() end)
  b:SetScript("OnLeave", function() b.hover:Hide() end)
  b:SetScript("OnClick", S.guard(function() Window.show(info.id) end))
  b.id = info.id
  return b
end

local function subtitle()
  local p, c = ns.C.profile, ns.C
  if not p then return "" end
  local class = p.class == "ANY" and (c.class or "") or (p.class:sub(1, 1) .. p.class:sub(2):lower())
  return ("%s %s, level %d"):format(p.spec or "", class, c.level or 1)
end

local function create()
  local f = CreateFrame("Frame", "ClassCoachSettings", UIParent)
  f:SetSize(W, H)
  f:SetPoint("CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(C.dark[1], C.dark[2], C.dark[3], 0.97)
  f.side = f:CreateTexture(nil, "BORDER")
  f.side:SetPoint("TOPLEFT", 0, -HEAD); f.side:SetPoint("BOTTOMLEFT"); f.side:SetWidth(SIDE)
  f.side:SetColorTexture(1, 1, 1, 0.03)
  f.edges = S.edges(f, "BORDER", 1, C.line)
  f.headRule = f:CreateTexture(nil, "BORDER")
  f.headRule:SetPoint("TOPLEFT", 0, -HEAD); f.headRule:SetPoint("TOPRIGHT", 0, -HEAD); f.headRule:SetHeight(1)
  f.headRule:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
  f.title = S.text(f, "title", 20, C.accent)
  f.title:SetPoint("TOPLEFT", 22, -14)
  S.set(f.title, "ClassCoach")
  f.sub = S.text(f, "body", 11, C.muted)
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
  f.close = closeButton(f)
  f.nav = {}
  for i, info in ipairs(Window.PAGES) do f.nav[i] = navItem(f, info, i) end
  -- the page area scrolls with the mouse wheel; a thin bar shows where you are
  f.scroll = CreateFrame("ScrollFrame", nil, f)
  f.scroll:SetPoint("TOPLEFT", SIDE + 24, -HEAD - 20)
  f.scroll:SetPoint("BOTTOMRIGHT", -24, 18)
  f.content = CreateFrame("Frame", nil, f.scroll)
  f.content:SetSize(BODY_W, 10)
  f.scroll:SetScrollChild(f.content)
  f.thumb = f:CreateTexture(nil, "OVERLAY")
  f.thumb:SetWidth(2)
  f.thumb:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 0.6)
  f.scroll:EnableMouseWheel(true)
  f.scroll:SetScript("OnMouseWheel", S.guard(function(_, delta) Window.scrollBy(-delta * 48) end))
  f.pages = {}
  f:SetScript("OnHide", function() Window.current = nil end)
  -- Esc closes it, out of combat. In a fight the window leaves the keyboard alone.
  f:SetScript("OnKeyDown", S.guard(function(self, key)
    if InCombatLockdown() then return end
    if key == "ESCAPE" then
      pcall(self.SetPropagateKeyboardInput, self, false)
      Window.close()
    else
      pcall(self.SetPropagateKeyboardInput, self, true)
    end
  end))
  f:Hide()
  Window.frame = f
  return f
end

local function keyboard(on)
  local f = Window.frame
  if not f or InCombatLockdown() then return end
  pcall(f.EnableKeyboard, f, on)
  pcall(f.SetPropagateKeyboardInput, f, true)
end

function Window.scrollBy(dy)
  local f = Window.frame
  local page = f and f.pages[Window.current]
  if not page then return end
  local visible = f.scroll:GetHeight()
  visible = type(visible) == "number" and visible > 0 and visible or (H - HEAD - 38)
  local most = math.max(0, page:GetHeight() - visible)
  Window.offset = math.max(0, math.min(most, (Window.offset or 0) + dy))
  f.scroll:SetVerticalScroll(Window.offset)
  -- A preview's highlight is drawn above the window, not inside its scrolling part:
  -- show it only while its tile is fully in view.
  for _, t in ipairs(page.previews) do
    local inView = t.top >= Window.offset and t.top + 76 <= Window.offset + visible
    if inView then t.refresh() else ns.Glow.hide(t.glow) end
  end
  f.thumb:SetShown(most > 0)
  if most > 0 then
    local share = visible / page:GetHeight()
    local track = visible
    f.thumb:SetHeight(math.max(24, track * share))
    f.thumb:ClearAllPoints()
    f.thumb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -HEAD - 20 - (track - track * share) * (Window.offset / most))
  end
end

-- Shows a page by id ("start", a section name, "share").
function Window.show(id)
  local f = Window.frame or create()
  local info
  for _, p in ipairs(Window.PAGES) do if p.id == id then info = p end end
  info = info or Window.PAGES[2]
  for _, p in pairs(f.pages) do p:Hide() end
  local page = f.pages[info.id]
  -- A page laid out before the typefaces changed has the wrong line heights: build it again.
  if page and page.fontEpoch ~= S.fontEpoch then
    page:Hide()
    for _, t in ipairs(page.previews) do ns.Glow.hide(t.glow) end
    page = nil
  end
  if not page then
    if info.id == "start" then page = startPage(f.content)
    elseif info.id == "share" then page = sharePage(f.content)
    else page = sectionPage(f.content, info) end
    page.fontEpoch = S.fontEpoch
    f.pages[info.id] = page
  end
  f.content:SetHeight(page:GetHeight())
  refreshPage(page)
  page:Show()
  for _, n in ipairs(f.nav) do
    local on = n.id == info.id
    n.mark:SetShown(on)
    color(n.label, on and C.ink or C.muted)
  end
  for _, p in pairs(f.pages) do
    for _, t in ipairs(p.previews) do if p ~= page then ns.Glow.hide(t.glow) end end
  end
  Window.current, Window.offset = info.id, 0
  Window.scrollBy(0)
  S.set(f.sub, subtitle())
  -- the game itself measures the page once it is drawn: anything that does not fit is noted (/coach layout)
  if C_Timer and ns.C and ns.C.noteLayout then C_Timer.After(0.5, function() pcall(ns.C.noteLayout, "settings, " .. info.name) end) end
  if not f:IsShown() then
    f:Show()
    keyboard(true)
  end
  return page
end

function Window.close()
  local f = Window.frame
  if not f then return end
  for _, p in pairs(f.pages) do for _, t in ipairs(p.previews) do ns.Glow.hide(t.glow) end end
  f:Hide()
  keyboard(false)
end

function Window.toggle(id)
  if Window.frame and Window.frame:IsShown() and (not id or id == Window.current) then Window.close() else Window.show(id or Window.current or "start") end
end

function Window.isOpen() return Window.frame ~= nil and Window.frame:IsShown() end

-- Settings can change elsewhere (/coach set, the game's page): the open page catches up.
function Window.refresh()
  local f = Window.frame
  local page = f and f:IsShown() and f.pages[Window.current]
  if page then refreshPage(page) end
end

-- A fight ending: a window opened during the fight gets its Esc key now. Nothing
-- changes when a fight starts: keys pass straight through to the game, and the
-- key script does nothing in combat.
function Window.combat(inCombat)
  local f = Window.frame
  if inCombat or not f or not f:IsShown() then return end
  keyboard(true)
end
