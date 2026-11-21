-- The coach: one ring in the middle of your view.
--   middle   what to press now, in a gold ring, with its key
--   left     what you already cast on this enemy (damage over time shows its
--            seconds left); before a fight: what to fix first, in amber rings
--   right    what comes next, each with its key
--   under    your true mana as a bar, the spell's name, why, and any advice
-- The steps on either side sit on a rising arc and get smaller the further
-- they are from now. Nothing here has a background except the plate behind
-- the text, so it covers as little of the game as it can.
local _, ns = ...

local Panel = {}
ns.Panel = Panel

local RING, ICON = 84, 72            -- the current step: ring across, icon inside it
local MAX_SIDE = 4                   -- the most steps shown on either side of the current one
local MISSING_SLOTS = 6
local SIZES, FADE = { 34, 30, 26, 22 }, { 1, 0.92, 0.80, 0.68 }
local TEXT_WIDTH = 380
local DEFAULT_ABOVE_BOTTOM = 240     -- how far the ring's middle starts above the bottom of the screen
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local MANA_BY_LEVEL = { high = "mana", medium = "warn", low = "danger" }

-- Where the k-th step from the middle sits: further out and a little higher each time.
local function spot(k)
  return 74 + (k - 1) * 48, (k - 1) * (k - 1) * 5, SIZES[k], FADE[k]
end

local function seconds(left)
  return ("%ds"):format(math.floor(left + 0.5))
end

-- How many steps to show before and after the current one: 0 to 4 each, 2 unless you changed it.
local function count(v)
  v = tonumber(v)
  if not v or v ~= v then return 2 end
  return math.max(0, math.min(MAX_SIDE, math.floor(v + 0.5)))
end
function Panel.steps(db)
  db = db or Panel.db or {}
  return count(db.stepsBefore), count(db.stepsAfter)
end

-- One step beside the ring: a round icon, a key badge and a short text under it.
-- Hover it for its name; dragging it drags the coach.
local function slot(f, ringed)
  local S = ns.Style
  local s = CreateFrame("Frame", nil, f)
  s:SetSize(28, 28)
  local icon = s:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  S.round(s, icon)
  s.icon = icon
  if ringed then
    -- "before you pull": an amber ring around it
    local edge = CreateFrame("Frame", nil, s)
    edge:SetPoint("TOPLEFT", -3, 3)
    edge:SetPoint("BOTTOMRIGHT", 3, -3)
    s.edge = S.shape(edge, "ring_bold", "OVERLAY")
    s.badgeText = S.text(edge, "bold", 11, S.COLORS.ink, "OUTLINE")
    s.badgeText:SetPoint("CENTER")
    s.badgeText:SetJustifyH("CENTER")
  end
  s.key = S.badge(s, 15)
  s.key:SetPoint("BOTTOMRIGHT", 7, -6)
  s.timer = S.text(s, "body", 11, S.COLORS.ink, "OUTLINE")
  s.timer:SetJustifyH("CENTER")
  s.timer:SetPoint("TOP", s, "BOTTOM", 0, -3)
  s:EnableMouse(true)
  s:SetScript("OnEnter", S.guard(S.tooltip))
  s:SetScript("OnLeave", S.guard(S.hideTooltip))
  s:RegisterForDrag("LeftButton")
  s:SetScript("OnDragStart", S.guard(function() local d = f:GetScript("OnDragStart"); if d then d(f) end end))
  s:SetScript("OnDragStop", S.guard(function() local d = f:GetScript("OnDragStop"); if d then d(f) end end))
  s:Hide()
  return s
end

-- Puts a side slot on the k-th place of the arc; side is -1 for the left, 1 for the right.
local function seat(f, s, k, side, size, lift)
  local dx, rise, natural, fade = spot(k)
  size = size or natural
  s:SetSize(size, size)
  s:ClearAllPoints()
  s:SetPoint("CENTER", f, "CENTER", side * dx, rise + (lift or 0))
  s.fade = fade
end

function Panel.place()
  local f = Panel.frame
  if not f then return end
  f:ClearAllPoints()
  local pos = Panel.charDB.focusPos
  if type(pos) == "table" and type(pos[3]) == "number" and type(pos[4]) == "number" then
    f:SetPoint(pos[1] or "CENTER", UIParent, pos[2] or "CENTER", pos[3], pos[4])
  else
    -- under your character, well above the action bars
    f:SetPoint("CENTER", UIParent, "BOTTOM", 0, DEFAULT_ABOVE_BOTTOM)
  end
end

function Panel.create(charDB, db)
  if Panel.frame then return Panel.frame end
  local S = ns.Style
  local C = S.COLORS
  local f = CreateFrame("Frame", "ClassCoachPanel", UIParent)
  Panel.frame, Panel.charDB, Panel.db = f, charDB, db
  -- The frame itself is only the ring. Everything else is drawn around it and
  -- lets clicks through, so the coach never takes a click meant for the game.
  f:SetSize(RING, RING)
  f:SetFrameStrata("LOW")   -- below the action bars: if the two ever overlap, your buttons stay on top
  f:SetClampedToScreen(true)
  f:SetScale(db.scale or 1)
  charDB.pos = nil          -- where the old, wide panel stood: the ring starts from its own default place
  Panel.place()
  f:SetMovable(true)
  f:EnableMouse(not db.locked)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", S.guard(function(self) if not db.locked then self:StartMoving() end end))
  f:SetScript("OnDragStop", S.guard(function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    if type(x) == "number" and type(y) == "number" then charDB.focusPos = { point, relPoint, x, y } end
  end))

  -- The current step
  f.disc = S.shape(f, "disc", "BACKGROUND")
  S.tint(f.disc, C.dark, 0.92)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetPoint("CENTER")
  f.icon:SetSize(ICON, ICON)
  S.round(f, f.icon)
  local top = CreateFrame("Frame", nil, f)
  top:SetAllPoints(f)
  f.ring = S.shape(top, "ring", "ARTWORK")
  S.tint(f.ring, C.accent)
  f.keyBadge = S.badge(top, 22)
  f.keyBadge:SetPoint("TOPLEFT", f, "CENTER", 22, -22)
  f.key = f.keyBadge.text

  -- The cue: a ring of light that grows out of the gold ring when a new key is needed
  local pulse = CreateFrame("Frame", nil, f)
  pulse:SetPoint("CENTER")
  pulse:SetSize(RING, RING)
  f.pulseFrame = pulse
  f.pulse = S.shape(pulse, "pulse", "OVERLAY")
  S.tint(f.pulse, C.accent)
  f.pulse:SetAlpha(0)
  pcall(f.pulse.SetBlendMode, f.pulse, "ADD")

  -- Your true mana: the game draws the value into this bar; the addon never reads it in a fight
  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  bar:SetMinMaxValues(0, 100)
  bar:SetSize(100, 5)
  bar:SetPoint("TOPLEFT", f, "CENTER", -50, -52)
  pcall(bar.SetStatusBarColor, bar, C.mana[1], C.mana[2], C.mana[3])
  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetPoint("TOPLEFT", -1, 1)
  barBg:SetPoint("BOTTOMRIGHT", 1, -1)
  barBg:SetColorTexture(C.dark[1], C.dark[2], C.dark[3], 0.9)
  local barText = S.text(bar, "body", 11, C.ink, "OUTLINE")
  barText:SetPoint("LEFT", bar, "RIGHT", 6, 0)
  f.bar, f.barText = bar, barText

  -- Steps on the arc. Slot 1 is nearest the ring on both sides.
  f.done, f.upcoming, f.missing = {}, {}, {}
  for i = 1, MAX_SIDE do
    f.done[i] = slot(f)
    seat(f, f.done[i], i, -1)
    f.upcoming[i] = slot(f)
    seat(f, f.upcoming[i], i, 1)
    f.upcoming[i].timer:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    f.upcoming[i].timer:ClearAllPoints()
    f.upcoming[i].timer:SetPoint("TOP", f.upcoming[i], "BOTTOM", 0, -6)
  end
  -- Before a pull: what is missing, as the icon of the spell that fixes it.
  -- Four on the arc; a fifth and sixth sit above the first two.
  for i = 1, MISSING_SLOTS do
    local s = slot(f, true)
    if i <= MAX_SIDE then seat(f, s, i, -1, 28) else seat(f, s, i - MAX_SIDE, -1, 28, 46) end
    f.missing[i] = s
  end
  f.leftLabel = S.text(f, "body", 11, C.muted, "OUTLINE")
  f.leftLabel:SetJustifyH("RIGHT")
  f.chainLabel = S.text(f, "body", 11, C.muted, "OUTLINE")

  -- Under the ring: a dark plate, then the name, why, and whatever else needs saying
  local words = CreateFrame("Frame", nil, f)
  words:SetSize(TEXT_WIDTH, 10)
  words:SetPoint("TOP", f, "CENTER", 0, -62)
  f.words = words
  S.skin(words)
  local function line(face, size, color)
    local fs = S.text(words, face, size, color)
    fs:SetWidth(TEXT_WIDTH - 20)
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(true)
    return fs
  end
  f.name = line("title", 19, C.ink)
  f.why = line("body", 12, C.ink)
  f.status = line("body", 12, C.warn)
  f.dots = line("body", 11, C.muted)
  f.msg = line("body", 12, C.ink)
  f.lines = { f.name, f.why, f.status, f.dots, f.msg }
  f.hint = S.text(f, "body", 11, C.muted, "OUTLINE")
  f.hint:SetPoint("BOTTOM", f, "TOP", 0, 8)
  f.hint:SetText("Drag the ring to move the coach")
  f.hint:Hide()

  if db.showCoach == false then f:Hide() end
  return f
end

local function fill(s, item, alpha)
  if not item then
    s.title, s.hint, s.spell, s.bind = nil, nil, nil, nil
    s:Hide()
    return false
  end
  s.icon:SetTexture(item.icon or QUESTION)
  s.icon:SetDesaturated(false)
  s:SetAlpha(alpha or 1)
  ns.Style.setBadge(s.key, item.keybind or nil)
  s.timer:SetText("")
  s:Show()
  return true
end

-- Places a text line at height y inside the plate and returns the height below it.
local function place(fs, y, value, gap)
  fs:ClearAllPoints()
  if not value or value == "" then
    fs:SetText("")
    fs:Hide()
    return y
  end
  ns.Style.set(fs, value)
  fs:SetPoint("TOP", fs:GetParent(), "TOP", 0, y)
  fs:Show()
  return y - (fs:GetStringHeight() or 12) - (gap or 4)
end

-- A label beside the outermost step on one side, level with it: never over the ring.
local function caption(f, fs, text, side, n)
  fs:ClearAllPoints()
  if not text or n < 1 then
    fs:SetText("")
    fs:Hide()
    return
  end
  local dx, rise, size = spot(math.min(n, MAX_SIDE))
  fs:SetText(text)
  if side < 0 then
    fs:SetPoint("RIGHT", f, "CENTER", -(dx + size / 2 + 12), rise)
  else
    fs:SetPoint("LEFT", f, "CENTER", dx + size / 2 + 16, rise)
  end
  fs:Show()
end

-- The cue runs for a moment, then stops costing anything.
local function animate(f)
  local left = (Panel.pulseUntil or 0) - GetTime()
  if left <= 0 then
    f.pulse:SetAlpha(0)
    f.keyBadge:SetAlpha(1)
    f:SetScript("OnUpdate", nil)
    return
  end
  local phase = (GetTime() % 0.8) / 0.8
  local size = RING * (0.95 + 0.45 * phase)
  f.pulseFrame:SetSize(size, size)
  f.pulse:SetAlpha(0.85 * (1 - phase * phase))
  f.keyBadge:SetAlpha(phase < 0.5 and 1 or 0.5)   -- the key blinks too
end

-- A new key is needed: pulse the ring and, if you want it, play a short sound.
function Panel.cue()
  local f = Panel.frame
  if not f then return end
  Panel.pulseUntil = GetTime() + 1.6
  f:SetScript("OnUpdate", ns.Style.guard(animate))
  Panel.cues = (Panel.cues or 0) + 1
  local sound = Panel.db.cueSound
  if sound ~= "off" then ns.API.sound(sound or "click") end
end

-- view = { chain = steps (1 = now), planning, inCombat, done = { {label, icon, left, missed} },
--          dots = { {label, left} }, otherDotted, usesMana, manaPct, manaExact, manaLevel, drawMana,
--          missing = { {text, hint, icon, keybind, spell, badge, kind, use} }, restMacro, status, statusKind ("warn"|"ok") }
function Panel.render(view)
  local f = Panel.frame
  if not f then return end
  local S, db = ns.Style, Panel.db
  local C = S.COLORS
  local wanted = db.showCoach ~= false
  if Panel.visible ~= wanted then
    Panel.visible = wanted
    if wanted then f:Show() else f:Hide() end
  end
  if not wanted then return end
  if Panel.scale ~= (db.scale or 1) then
    Panel.scale = db.scale or 1
    f:SetScale(Panel.scale)
  end
  if Panel.locked ~= (db.locked == true) then
    Panel.locked = db.locked == true
    f:EnableMouse(not Panel.locked)
  end
  local compact = db.compact == true
  local steps = view.chain or {}
  local now = steps[1]

  -- Middle: what to press now (or, with nothing targeted, how your next pull starts)
  if now then
    f.icon:SetTexture(now.icon or QUESTION)
    f.icon:SetDesaturated(false)   -- always in colour: grey reads as "you cannot cast this"
    S.setBadge(f.keyBadge, now.keybind or nil)
    f.ring:SetAlpha(view.planning and 0.45 or 1)
  else
    f.icon:SetTexture(QUESTION)
    f.icon:SetDesaturated(true)
    S.setBadge(f.keyBadge, nil)
    f.ring:SetAlpha(0.25)
  end

  -- The cue. Most of a fight is one steady key (wand, attack). When something
  -- else comes up, or a spell was resisted, the ring pulses once.
  local cueKey = now and view.inCombat and not now.filler and (now.key .. (now.retry and "!" or "")) or nil
  if cueKey and cueKey ~= Panel.lastCue and (Panel.wasSteady or now.retry) and db.cue ~= false then Panel.cue() end
  Panel.lastCue = cueKey
  Panel.wasSteady = view.inCombat and now ~= nil and now.filler == true

  -- Left: before a fight, what to fix first; in a fight, what you already cast here.
  local before, after = Panel.steps(db)
  local missing = (not view.inCombat) and view.missing or {}
  local shownLeft = 0
  for i = 1, MISSING_SLOTS do
    local s, item = f.missing[i], missing[i]
    if fill(s, item) then
      s.title, s.hint, s.spell, s.bind = item.text, item.hint, item.spell, item.keybind
      s.badgeText:SetText(item.badge or "")
      -- red: don't fight this; amber: fix before pulling; grey: good to know
      S.tint(s.edge, item.kind == "danger" and C.danger or item.kind == "info" and C.muted or C.warn)
      shownLeft = shownLeft + 1
    end
  end
  local done = view.done or {}
  for i = 1, MAX_SIDE do
    local s = f.done[i]
    local d = (#missing == 0 and i <= before) and done[#done - i + 1] or nil   -- the latest nearest the ring
    if fill(s, d, (s.fade or 1) * 0.85) then
      shownLeft = shownLeft + 1
      s.title = d.label
      if d.missed then
        -- resisted: it did not land
        s.timer:SetText(d.missed == "immune" and "immune" or "miss")
        s.timer:SetTextColor(C.danger[1], C.danger[2], C.danger[3])
        s.hint = d.missed == "immune" and "This enemy is immune to it." or "It was resisted: it did not land."
      elseif d.left then
        local soon = d.left <= 3
        s.timer:SetText(seconds(math.max(0, d.left)))
        local c = soon and C.danger or C.ink
        s.timer:SetTextColor(c[1], c[2], c[3])
        s.hint = d.left > 0 and (seconds(d.left) .. " left on this enemy.") or "Ran out on this enemy."
      else
        s.timer:SetText("done")
        s.timer:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        s.hint = "You cast it on this enemy."
      end
    end
  end
  caption(f, f.leftLabel, #missing > 0 and "before you pull" or "already cast", -1, math.min(shownLeft, MAX_SIDE))

  -- Right: what comes next. A step that isn't due yet says when it will be.
  local shownRight = 0
  for i = 1, MAX_SIDE do
    local s = f.upcoming[i]
    local st = i <= after and steps[i + 1] or nil
    if fill(s, st, s.fade) then
      shownRight = shownRight + 1
      s.title, s.bind = st.label, st.keybind
      if st.inSeconds then
        s.timer:SetText("in " .. seconds(st.inSeconds))
        s.hint = "Due again in " .. seconds(st.inSeconds) .. "."
      else
        s.hint = st.why
      end
    end
  end
  caption(f, f.chainLabel, view.planning and "your pull plan" or "next", 1, shownRight)

  -- What a click would cast, for the buttons that lie over these icons before a fight (UI/Click.lua).
  -- Only worked out between fights: in a fight those buttons are hidden and may not be touched.
  if not view.inCombat then
    local clicks = {}
    for i = 1, MISSING_SLOTS + 1 + MAX_SIDE do clicks[i] = { x = 0, y = 0, size = 1 } end
    for i = 1, MISSING_SLOTS do
      local item, c = missing[i], clicks[i]
      if item then
        local dx, rise = spot(i <= MAX_SIDE and i or i - MAX_SIDE)
        c.x, c.y, c.size = -dx, rise + (i > MAX_SIDE and 46 or 0), 34
        c.title, c.hint, c.bind = item.text, item.hint, item.keybind
        if item.spell then
          c.kind, c.value = "spell", item.spell
        elseif item.use == "rest" and view.restMacro then
          c.kind, c.value, c.does = "macro", view.restMacro, "drink and eat"
        end
      end
    end
    if not view.planning then
      for i = 1, 1 + MAX_SIDE do
        local st, c = steps[i], clicks[MISSING_SLOTS + i]
        if st and not st.melee and st.label and (i == 1 or i - 1 <= after) then
          c.kind, c.value, c.title, c.hint, c.bind = "spell", st.label, st.label, st.why, st.keybind
          if i == 1 then
            c.size = RING
          else
            local dx, rise, size = spot(i - 1)
            c.x, c.y, c.size = dx, rise, size
          end
        end
      end
    end
    Panel.clicks = clicks
  end

  -- Mana: the game draws the true value. If it ever refuses, show our guess and say so.
  if view.usesMana and db.showMana ~= false then
    f.bar:Show()
    local tone = C[MANA_BY_LEVEL[view.manaLevel or "high"] or "mana"]
    pcall(f.bar.SetStatusBarColor, f.bar, tone[1], tone[2], tone[3])
    local drawn = not Panel.manaRefused and view.drawMana and view.drawMana(f.bar, f.barText)
    if not drawn then
      if view.drawMana then Panel.manaRefused = true end
      if view.manaPct then
        f.bar:SetMinMaxValues(0, 100)
        f.bar:SetValue(view.manaPct)
        f.barText:SetText((view.manaExact and "%d%%" or "about %d%%"):format(math.floor(view.manaPct + 0.5)))
      else
        f.bar:Hide()
      end
    end
  else
    f.bar:Hide()
  end

  -- Words: the name, why, then advice. Timers the icons already show are not repeated.
  local y = -6
  y = place(f.name, y, now and now.label or (view.status and "" or "Ready"), 3)
  y = place(f.why, y, not compact and now and now.why or nil, 4)
  local explain = view.status
  if view.statusKind == "ok" or (compact and #missing > 0) then explain = nil end
  local tone = (view.statusKind == "warn" or #missing > 0) and C.warn or C.ink
  f.status:SetTextColor(tone[1], tone[2], tone[3])
  y = place(f.status, y, explain, 4)

  local dotLine
  if db.showDots ~= false then
    local onIcon, parts = {}, {}
    for i = 1, MAX_SIDE do
      local s = f.done[i]
      if s:IsShown() and s.title then onIcon[s.title] = true end
    end
    for _, d in ipairs(view.dots or {}) do
      if not onIcon[d.label] then parts[#parts + 1] = ("%s %s"):format(d.label, seconds(d.left)) end
    end
    if #parts > 0 then dotLine = "Also on this enemy: " .. table.concat(parts, " · ") end
    if view.otherDotted and view.otherDotted > 0 then
      local other = view.otherDotted == 1 and "1 other enemy still ticking" or (view.otherDotted .. " other enemies still ticking")
      dotLine = dotLine and (dotLine .. "\n" .. other) or other
    end
  end
  y = place(f.dots, y, dotLine, 4)

  local time = GetTime()
  if Panel.msgUntil and time > Panel.msgUntil then
    Panel.msgUntil = nil
    Panel.msgText = nil
  end
  y = place(f.msg, y, Panel.msgText, 4)

  -- The plate is as wide as the widest line and as tall as the lines, and gone when there are none.
  if y >= -6 then
    f.words:Hide()
  else
    local widest = 0
    for _, fs in ipairs(f.lines) do
      local w = fs:IsShown() and fs.GetStringWidth and fs:GetStringWidth() or 0
      if type(w) == "number" and w > widest then widest = w end
    end
    f.words:SetSize(widest > 0 and math.min(TEXT_WIDTH, widest + 28) or TEXT_WIDTH, -y + 4)
    S.apply(f.words, db, 1)
    f.words:Show()
  end
end

-- Shows a few lines under the coach for a while (fight report, level-up).
function Panel.flash(lines, seconds)
  local f = Panel.frame
  if not f then return end
  Panel.msgText = table.concat(lines, "\n")
  f.msg:SetText(Panel.msgText)
  Panel.msgUntil = GetTime() + (seconds or 15)
end

-- "Drag the ring to move the coach": shown while the demo plays, which is when you place it.
function Panel.showHint(on)
  local f = Panel.frame
  if not f then return end
  if on and not Panel.db.locked then f.hint:Show() else f.hint:Hide() end
end

function Panel.resetPosition()
  if not Panel.frame then return end
  Panel.charDB.focusPos = nil
  Panel.place()
end
