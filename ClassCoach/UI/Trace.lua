-- The debug trace: an opt-in record of what the coach saw and decided, kept on
-- this computer. It works the way QuestieTrace does (Questie's recorder):
--   * it asks first, once, with its own pop-up; "No" means nothing is ever recorded
--   * every play session is recorded into the addon's own saved file, which the
--     game writes to disk at /reload, logout and quit
--     (WTF\Account\<account>\SavedVariables\ClassCoach.lua)
--   * nothing leaves your computer unless you export it (/coach trace export)
--     or share that file yourself
--   * player names, realm names and player ids are never recorded
-- The idea is QuestieTrace's; none of its code is used here.
local _, ns = ...

local Trace = {}
ns.Trace = Trace

local MAX_SESSIONS = 10      -- the oldest session goes first
local MAX_EVENTS = 3000      -- per session; the oldest lines go first
local MAX_LINE = 300

local function store()
  if type(ClassCoachTrace) ~= "table" then ClassCoachTrace = {} end
  if type(ClassCoachTrace.settings) ~= "table" then ClassCoachTrace.settings = {} end
  return ClassCoachTrace
end

-- The sessions of all your characters sit in the account's file (one place to look;
-- each session says which character it is).
local function charStore()
  local t = store()
  if type(t.sessions) ~= "table" then t.sessions = {} end
  return t
end

local function say(text) if ns.say then ns.say(text) end end
local function now() return GetTime and GetTime() or 0 end

-- true, false (declined) or nil (not asked yet)
function Trace.consent() return store().settings.consent end
function Trace.recording() return Trace.session ~= nil end

---------------------------------------------------------------------------
-- Privacy: no player names, realm names or player ids, ever
---------------------------------------------------------------------------

local function escape(s) return (s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")) end

-- Names that must never be stored: yours (other players are kept out at the source).
local function ownNames()
  local out = {}
  local ok, name, realm = pcall(UnitName, "player")
  if ok and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then out[#out + 1] = name end
  if ok and type(realm) == "string" and realm ~= "" and not (issecretvalue and issecretvalue(realm)) then out[#out + 1] = realm end
  return out
end

function Trace.clean(text)
  text = tostring(text)
  text = text:gsub("Player%-[%w%-]+", "player")
  for _, n in ipairs(Trace.names or {}) do text = text:gsub(escape(n), "<you>") end
  if #text > MAX_LINE then text = text:sub(1, MAX_LINE) .. "..." end
  return text
end

-- How a unit is written down: an NPC by name and level, a player never by name.
-- In a fight the game may hide names: then the name read when you picked it.
local known = {}
function Trace.unit(unit)
  local okE, exists = pcall(UnitExists, unit)
  if not okE or exists ~= true then return "nothing" end
  local okP, isPlayer = pcall(UnitIsPlayer, unit)
  if okP and isPlayer == true then known[unit] = "a player" return "a player" end
  local okN, name = pcall(UnitName, unit)
  local okL, level = pcall(UnitLevel, unit)
  name = okN and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name or nil
  level = okL and type(level) == "number" and not (issecretvalue and issecretvalue(level)) and level or nil
  if not name then return known[unit] or ("? (%s)"):format(tostring(level or "?")) end
  known[unit] = ("%s (%s)"):format(name, tostring(level or "?"))
  return known[unit]
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

function Trace.start(info)
  if Trace.session or Trace.consent() ~= true then return end
  Trace.names = ownNames()
  local sessions = charStore().sessions
  local s = { started = date and date("%Y-%m-%d %H:%M:%S") or "?", t0 = now(), events = {}, dropped = 0 }
  for k, v in pairs(info or {}) do s[k] = v end
  sessions[#sessions + 1] = s   -- linked in now, so a /reload saves it as it is
  while #sessions > MAX_SESSIONS do table.remove(sessions, 1) end
  Trace.session = s
  Trace.add("session", "started: ClassCoach %s, %s", tostring(s.version), tostring(s.who))
end

function Trace.stop()
  if Trace.session then Trace.add("session", "stopped") end
  Trace.session = nil
end

-- One line: kind is a short word ("cast", "ring", "fight", ...).
function Trace.add(kind, fmt, ...)
  local s = Trace.session
  if not s then return end
  local ok, text = pcall(string.format, fmt, ...)
  text = Trace.clean(ok and text or fmt)
  local events = s.events
  events[#events + 1] = ("%7.1f %-7s %s"):format(now() - s.t0, kind, text)
  if #events > MAX_EVENTS then
    table.remove(events, 1)
    s.dropped = (s.dropped or 0) + 1
  end
end

-- Only when something changed since the last line of this kind (the coach decides 10 times a second).
local lastOf = {}
function Trace.change(kind, fmt, ...)
  if not Trace.session then return end
  local ok, text = pcall(string.format, fmt, ...)
  text = ok and text or fmt
  if lastOf[kind] == text then return end
  lastOf[kind] = text
  Trace.add(kind, "%s", text)
end

function Trace.clear()
  charStore().sessions = {}
  local running = Trace.session
  Trace.session = nil
  if running then
    local info = {}
    for k, v in pairs(running) do if k ~= "events" and k ~= "dropped" and k ~= "started" and k ~= "t0" then info[k] = v end end
    Trace.start(info)
  end
end

---------------------------------------------------------------------------
-- Text for export and /coach trace
---------------------------------------------------------------------------

function Trace.text(all)
  local sessions = charStore().sessions
  local lines = {}
  local from = all and 1 or math.max(1, #sessions)
  for i = from, #sessions do
    local s = sessions[i]
    lines[#lines + 1] = ("== ClassCoach trace, session %d of %d, %s, %s %s, %d lines%s =="):format(i, #sessions, tostring(s.started),
      tostring(s.version), tostring(s.who), #(s.events or {}), (s.dropped or 0) > 0 and (", " .. s.dropped .. " oldest dropped") or "")
    for _, e in ipairs(s.events or {}) do lines[#lines + 1] = e end
  end
  return table.concat(lines, "\n")
end

function Trace.status()
  local sessions = charStore().sessions
  local lines = 0
  for _, s in ipairs(sessions) do lines = lines + #(s.events or {}) end
  local c = Trace.consent()
  return ("trace: %s; %d sessions, %d lines kept on this computer"):format(
    c == true and (Trace.session and "recording" or "allowed, not recording") or c == false and "off (you said no)" or "not asked yet",
    #sessions, lines)
end

---------------------------------------------------------------------------
-- The pop-up and the export window (our own frames: the game's shared
-- pop-up list can carry addon taint into other game windows)
---------------------------------------------------------------------------

local function panel(name, w, h)
  local S, C = ns.Style, ns.Style.COLORS
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(w, h)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  f:SetFrameStrata("DIALOG")
  f:SetFrameLevel(50)
  f:EnableMouse(true)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(C.dark[1], C.dark[2], C.dark[3], 0.96)
  f.edges = S.edges(f, "BORDER", 1, C.accent)
  f.title = S.text(f, "bold", 14, C.ink)
  f.title:SetPoint("TOPLEFT", 16, -14)
  f:Hide()
  return f
end

function Trace.prompt()
  local f = Trace.promptFrame
  if not f then
    local S, C = ns.Style, ns.Style.COLORS
    f = panel("ClassCoachTraceConsent", 400, 170)
    S.set(f.title, "Help fix ClassCoach")
    f.text = S.text(f, "body", 12, C.ink)
    f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
    f.text:SetWidth(368)
    f.text:SetWordWrap(true)
    S.set(f.text, "May ClassCoach record what it sees and decides in your fights (your spells, their timers, your mana, its advice) on this computer? "
      .. "It stays here unless you export it or share the file. Player names are never recorded. You can change your mind with /coach trace consent.")
    f.yes = S.button(f, "Yes, record", 150)
    f.yes:SetPoint("BOTTOMLEFT", 16, 14)
    f.no = S.button(f, "No", 150)
    f.no:SetPoint("BOTTOMRIGHT", -16, 14)
    f.yes:SetScript("OnClick", S.guard(function() f:Hide(); Trace.answer(true) end))
    f.no:SetScript("OnClick", S.guard(function() f:Hide(); Trace.answer(false) end))
    Trace.promptFrame = f
  end
  f:Show()
  return f
end

function Trace.answer(yes)
  store().settings.consent = yes == true
  if yes then
    say("Thank you! ClassCoach now records a debug trace on this computer. /coach trace shows it.")
    Trace.start(Trace.info)
  else
    Trace.stop()
    say("No trace is recorded. If you change your mind: /coach trace consent")
  end
end

-- At login: ask once; otherwise start recording or say it is off.
function Trace.onLogin(info)
  Trace.info = info
  local c = Trace.consent()
  if c == nil then
    Trace.prompt()
  elseif c == true then
    say("A debug trace is being recorded on this computer (/coach trace).")
    Trace.start(info)
  else
    say("Debug trace is off (you said no). /coach trace consent to change that.")
  end
end

function Trace.export(all)
  local f = Trace.exportFrame
  if not f then
    local S, C = ns.Style, ns.Style.COLORS
    f = panel("ClassCoachTraceExport", 560, 380)
    S.set(f.title, "ClassCoach trace")
    f.help = S.text(f, "body", 11, C.muted)
    f.help:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.help:SetWidth(528)
    f.help:SetWordWrap(true)
    S.set(f.help, "Ctrl+A, then Ctrl+C to copy, and paste it where you want it. Or press Save to disk: the game writes it into ClassCoach's saved file (it reloads your interface).")
    f.box = CreateFrame("EditBox", nil, f)
    f.box:SetMultiLine(true)
    f.box:SetAutoFocus(false)
    f.box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    f.box:SetPoint("TOPLEFT", 16, -64)
    f.box:SetPoint("BOTTOMRIGHT", -16, 50)
    f.box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
    f.close = S.button(f, "Close", 120)
    f.close:SetPoint("BOTTOMRIGHT", -16, 14)
    f.close:SetScript("OnClick", S.guard(function() f:Hide() end))
    f.save = S.button(f, "Save to disk", 140)
    f.save:SetPoint("RIGHT", f.close, "LEFT", -10, 0)
    f.save:SetScript("OnClick", S.guard(function()
      if InCombatLockdown and InCombatLockdown() then say("After the fight: saving reloads your interface.") return end
      if C_UI and C_UI.Reload then C_UI.Reload() end
    end))
    Trace.exportFrame = f
  end
  f.box:SetText(Trace.text(all))
  f:Show()
  f.box:SetFocus()
  f.box:HighlightText()
  return f
end

-- /coach trace [status | consent | export [all] | clear]
function Trace.command(arg)
  local what, rest = (arg or ""):match("^(%S*)%s*(.-)$")
  what = (what or ""):lower()
  if what == "consent" then
    Trace.prompt()
  elseif what == "export" then
    Trace.export(rest == "all")
  elseif what == "clear" then
    Trace.clear()
    say("Trace cleared.")
  else
    say(Trace.status())
    print("  /coach trace export - show it, to copy; Save to disk writes it into ClassCoach's saved file")
    print("  /coach trace export all - every kept session;  /coach trace clear - forget them")
    print("  /coach trace consent - change your answer")
  end
end
