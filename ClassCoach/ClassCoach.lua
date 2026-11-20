-- Start-up, events, the update loop and the /coach commands.
-- This file glues the game (API) to the engine and the panel.
local ADDON, ns = ...
local API, Mana, Tracker, Engine, Profiles = ns.API, ns.Mana, ns.Tracker, ns.Engine, ns.Profiles

local DEFAULTS = { scale = 1, locked = false, hidden = false, chat = true, food = true, drinkAt = 60 }

local C = {}            -- runtime state
ns.C = C

local function say(text) print("|cff8fc7ffClassCoach:|r " .. text) end
ns.say = say

local function log(fmt, ...)
  local db = ClassCoachDB
  if not db then return end
  db.log = db.log or {}
  local ok, line = pcall(string.format, fmt, ...)
  db.log[#db.log + 1] = (date and date("%H:%M:%S") or "") .. " " .. (ok and line or tostring(fmt))
  while #db.log > 200 do table.remove(db.log, 1) end
end
API.log = log

---------------------------------------------------------------------------
-- Profile and spell scanning
---------------------------------------------------------------------------

local function chooseProfile()
  local class = API.classToken() or "ANY"
  local profile, why = Profiles.choose(class, API.talentPoints(), ClassCoachCharDB.spec)
  if profile ~= C.profile then C.manaLevel = nil end
  C.profile, C.profileWhy, C.class = profile, why, class
end

local function rescan()
  if API.inCombat() then C.rescanDue = true return end
  C.rescanDue = false
  local profile = C.profile
  local book = API.scanSpellbook()
  local spells, idToKey, costById = {}, {}, {}
  for key, spec in pairs(profile.spells) do
    for _, id in ipairs(spec.ids or {}) do idToKey[id] = key end
    local sp = API.resolveSpell(spec, book)
    if sp then
      spells[key] = sp
      idToKey[sp.id] = key
      idToKey[sp.lowest] = key
      costById[sp.id] = sp.cost
      costById[sp.lowest] = sp.lowestCost
      for _, id in ipairs(spec.ids or {}) do
        if costById[id] == nil then costById[id] = API.cost(id) end
      end
    end
  end
  -- Mana probes: every known spell with a different mana cost.
  local probes, seen = {}, {}
  for _, entry in pairs(book) do
    local cost = API.cost(entry.id)
    if cost and not seen[cost] then seen[cost] = true; probes[#probes + 1] = { id = entry.id, cost = cost } end
    costById[entry.id] = costById[entry.id] or cost
  end
  table.sort(probes, function(a, b) return a.cost < b.cost end)
  C.spells, C.idToKey, C.costById, C.probes, C.book = spells, idToKey, costById, probes, book
  C.keys = API.scanKeys()
  C.hasWand = API.equipped(18)
  C.usesMana = API.usesMana()
end

local rescanQueued = false
local function rescanSoon()
  if rescanQueued then return end
  rescanQueued = true
  C_Timer.After(0.5, function()
    rescanQueued = false
    local ok, err = pcall(rescan)
    if not ok then log("rescan error: %s", tostring(err)) end
  end)
end

---------------------------------------------------------------------------
-- Mana
---------------------------------------------------------------------------

local function readMana(now, inCombat)
  local cur, max = API.mana()
  if max then C.manaMax = max end
  if cur then
    C.lastMana = cur
    return cur / C.manaMax * 100, true
  end
  local pct = API.manaPct()
  if pct then return pct, true end
  if not inCombat then return nil, false end
  if C.manaAt and now - C.manaAt < 0.25 then return C.manaPct, false end
  C.manaAt = now
  local probes = {}
  for _, p in ipairs(C.probes or {}) do
    local _, short = API.usable(p.id)
    if short ~= nil then probes[#probes + 1] = { cost = p.cost, affordable = not short } end
  end
  local fight = C.tracker.fight
  local _, pct = Mana.estimate(fight and fight.manaStart, C.tracker:spent() - (fight and fight.restored or 0), C.manaMax, probes)
  C.manaPct = pct
  return pct, false
end

---------------------------------------------------------------------------
-- The update loop
---------------------------------------------------------------------------

-- Pet presence is readable out of combat; in combat we keep what it was at the pull.
local function petState(inCombat)
  if inCombat then return C.petAtPull end
  return API.hasPet()
end

local function buildState(now)
  local inCombat = API.inCombat() or C.tracker.fight ~= nil
  local manaPct, exact = readMana(now, inCombat)
  C.manaLevel = Mana.level(manaPct, C.profile.mana, C.manaLevel)
  local buffs, mainHand
  if not inCombat then
    if not C.buffsAt or now - C.buffsAt > 1 or C.aurasDirty then
      C.buffsAt, C.aurasDirty = now, false
      C.buffs = API.aurasReadable(false) and API.playerBuffs() or nil
      C.mainHand = API.mainHandBuff()
      for element in pairs(API.TOTEM_SLOT) do C.tracker:setTotem(element, API.totemUp(element), now) end
    end
    buffs, mainHand = C.buffs, C.mainHand
  end
  return Engine.newState({
    now = now, level = C.level or API.level(), inCombat = inCombat, inGroup = API.inGroup(),
    usesMana = C.usesMana, manaPct = manaPct, manaExact = exact, manaLevel = C.manaLevel,
    healthPct = (not inCombat) and API.healthPct() or nil, hasPet = petState(inCombat),
    target = API.target(), hasWand = C.hasWand, buffs = buffs, mainHandBuff = mainHand,
    keys = C.keys, spells = C.spells, bookReady = next(C.spells) ~= nil, tracker = C.tracker, fightTime = C.tracker:fightTime(now),
    check = { ready = API.ready, usable = API.usable },
    itemCount = API.itemCount, equipped = API.equipped,
  })
end

local function tick()
  local now = GetTime()
  local profile = C.profile
  local s = buildState(now)
  C.lastState = s
  local view = {
    title = ("%s · %s · level %d"):format(profile.spec, profile.class == "ANY" and (C.class or "") or profile.class:sub(1, 1) .. profile.class:sub(2):lower(), s.level),
    usesMana = s.usesMana, manaPct = s.manaPct, manaExact = s.manaExact, manaLevel = s.manaLevel,
  }
  view.next = Engine.next(profile, s)
  view.chain = Engine.chain(profile, s, 4)
  view.drawMana = API.drawMana
  if s.inCombat then
    view.status = Engine.advice(profile, s)
    view.statusKind = s.manaLevel == "low" and "warn" or nil
  else
    local missing = Engine.checklist(profile, s, { food = ClassCoachDB.food, drinkAt = ClassCoachDB.drinkAt })
    if #missing > 0 then
      local names = {}
      for _, m in ipairs(missing) do names[#names + 1] = m.text end
      view.status = "Before you pull: " .. table.concat(names, " · ") .. (missing[1].hint and ("\n" .. missing[1].hint) or "")
      view.statusKind = "warn"
    else
      view.status = "Ready to pull."
      view.statusKind = "ok"
    end
    local lvl, what = Engine.nextTraining(profile, s.level)
    view.idleText = "Out of combat"
    view.idleWhy = lvl and ("Next new spells at level %d."):format(lvl) or ""
  end
  ns.Panel.render(view)
end

local elapsed = 0
local function onUpdate(_, dt)
  elapsed = elapsed + dt
  local fast = C.tracker and C.tracker.fight ~= nil
  if elapsed < (fast and 0.1 or 0.4) then return end
  elapsed = 0
  local ok, err = pcall(tick)
  if not ok and err ~= C.lastError then
    C.lastError = err
    log("tick error: %s", tostring(err))
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local handlers = {}

local function castKey(id)
  local key = C.idToKey[id]
  if key then return key end
  local name = API.spellName(id)
  if not name then return nil end
  for k, sp in pairs(C.spells) do
    if sp.name == name then C.idToKey[id] = k return k end
  end
  return name
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
  if API.plain(unit) ~= "player" then return end
  local id = API.plain(spellID)
  if not id then return end
  local key = castKey(id)
  if not key then return end
  local cost = C.costById[id]
  if cost == nil then cost = API.cost(id); C.costById[id] = cost or false end
  local t = API.target()
  C.tracker:cast(GetTime(), key, cost or 0, C.profile.spells[key], t.key)
end

function handlers.PLAYER_SWING()
  C.tracker:swing()
end

function handlers.PLAYER_REGEN_DISABLED()
  local t = API.target()
  C.petAtPull = C.lastState and C.lastState.hasPet
  C.tracker:startFight(GetTime(), {
    target = t.hostile and t.name or nil, targetLevel = t.level,
    manaStart = C.lastMana, manaMax = C.manaMax, hasPet = C.petAtPull,
  })
end

local function finishFight()
  local cur, max = API.mana()
  local summary = C.tracker:endFight(GetTime(), cur, max)
  if not summary or summary.duration < 3 then return end
  local s = C.lastState or buildState(GetTime())
  local report = Engine.report(C.profile, summary, s)
  C.lastReport = report
  local lines = { report.headline }
  for _, tip in ipairs(report.tips) do lines[#lines + 1] = "• " .. tip end
  ns.Panel.flash(lines, 15)
  if ClassCoachDB.chat and #report.tips > 0 then
    say(report.headline)
    for _, tip in ipairs(report.tips) do say("• " .. tip) end
  end
end

function handlers.PLAYER_REGEN_ENABLED()
  C_Timer.After(0.3, function()
    local ok, err = pcall(finishFight)
    if not ok then log("fight report error: %s", tostring(err)) end
    if C.rescanDue then rescanSoon() end
  end)
end

function handlers.PLAYER_LEVEL_UP(level)
  level = API.plain(level)
  if type(level) ~= "number" then return end
  C.level = level
  local lines = Engine.levelUp(C.profile, level)
  ns.Panel.flash(lines, 25)
  for _, l in ipairs(lines) do say(l) end
  rescanSoon()
end

function handlers.UNIT_AURA(unit)
  if API.plain(unit) == "player" then C.aurasDirty = true end
end

local function talentsChanged()
  chooseProfile()
  rescanSoon()
end

for _, e in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "ACTIONBAR_SLOT_CHANGED",
  "UPDATE_BINDINGS", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" }) do
  handlers[e] = rescanSoon
end
for _, e in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED" }) do
  handlers[e] = talentsChanged
end

local function start()
  ClassCoachDB = ClassCoachDB or {}
  ClassCoachCharDB = ClassCoachCharDB or {}
  for k, v in pairs(DEFAULTS) do if ClassCoachDB[k] == nil then ClassCoachDB[k] = v end end
  C.tracker = Tracker.new()
  C.level = API.level()
  chooseProfile()
  local ok, err = pcall(rescan)
  if not ok then log("first scan error: %s", tostring(err)) end
  local mana, max = API.mana()
  C.lastMana, C.manaMax = mana, max
  ns.Panel.create(ClassCoachCharDB, ClassCoachDB)
  ns.Panel.frame:SetScript("OnUpdate", onUpdate)
end

local frame = CreateFrame("Frame")
C.refused = {}
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    local ok, err = pcall(start)
    if not ok then print("ClassCoach failed to start: " .. tostring(err)) return end
    for e in pairs(handlers) do
      local fine
      if e == "UNIT_SPELLCAST_SUCCEEDED" or e == "UNIT_AURA" then
        fine = pcall(self.RegisterUnitEvent, self, e, "player")
      else
        fine = pcall(self.RegisterEvent, self, e)
      end
      if not fine then C.refused[#C.refused + 1] = e end
    end
    return
  end
  local h = handlers[event]
  if not h or not C.profile then return end
  local ok, err = pcall(h, ...)
  if not ok then log("error in %s: %s", event, tostring(err)) end
end)

---------------------------------------------------------------------------
-- /coach
---------------------------------------------------------------------------

local function describe(v)
  if issecretvalue and issecretvalue(v) then return "SECRET" end
  return tostring(v)
end

local function check()
  local out = {}
  local function add(fmt, ...) out[#out + 1] = fmt:format(...) end
  local _, build, _, interface = API.try(GetBuildInfo)
  add("client build %s interface %s, issecretvalue %s", describe(build), describe(interface), tostring(issecretvalue ~= nil))
  add("class %s, level %s, profile %s %s (%s)", tostring(C.class), tostring(C.level), C.profile.class, C.profile.spec, tostring(C.profileWhy))
  local pts = API.talentPoints()
  add("talent points %s", pts and table.concat({ pts[1] or 0, pts[2] or 0, pts[3] or 0 }, "/") or "unreadable")
  add("mana now %s / %s (combat %s)", describe(API.try(UnitPower, "player", 0)), describe(API.try(UnitPowerMax, "player", 0)), tostring(API.inCombat()))
  local names = {}
  for key, sp in pairs(C.spells) do
    local usable, short = API.usable(sp.id)
    names[#names + 1] = ("%s id %s cost %s ready %s usable %s short %s key %s"):format(key, tostring(sp.id), tostring(sp.cost),
      tostring(API.ready(sp.id)), tostring(usable), tostring(short), tostring(C.keys[sp.name]))
  end
  table.sort(names)
  for _, l in ipairs(names) do add("%s", l) end
  local costs = {}
  for _, p in ipairs(C.probes) do costs[#costs + 1] = p.cost end
  add("mana probes: %s", table.concat(costs, " "))
  add("mana bar drawn by the game: %s; percent function %s, readable %s", tostring(not ns.Panel.manaRefused),
    tostring(UnitPowerPercent ~= nil), tostring(API.manaPct() ~= nil))
  add("buffs readable %s, weapon buff %s, wand %s", tostring(C.buffs ~= nil), tostring(API.mainHandBuff()), tostring(C.hasWand))
  add("events refused: %s", #C.refused > 0 and table.concat(C.refused, " ") or "none")
  add("errors logged: %d (see ClassCoachDB.log after /reload)", ClassCoachDB.log and #ClassCoachDB.log or 0)
  for _, l in ipairs(out) do print("|cff9aa0a8" .. l .. "|r") end
  ClassCoachDB.report = out
end

local HELP = {
  "/coach lock | unlock — stop or allow dragging the panel",
  "/coach scale 1.2 — panel size",
  "/coach spec <name> | auto — pick a profile (e.g. /coach spec Enhancement)",
  "/coach last — repeat the last fight report",
  "/coach chat on | off — fight tips in chat",
  "/coach food on | off — remind about buff food",
  "/coach hide | show | reset — panel visibility and position",
  "/coach check — what the addon can read on this client (for bug reports)",
}

SLASH_CLASSCOACH1, SLASH_CLASSCOACH2 = "/coach", "/classcoach"
SlashCmdList.CLASSCOACH = function(msg)
  local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  local db = ClassCoachDB
  if cmd == "lock" then db.locked = true; say("Panel locked.")
  elseif cmd == "unlock" then db.locked = false; say("Panel unlocked: drag it where you like.")
  elseif cmd == "scale" and tonumber(arg) then db.scale = math.max(0.5, math.min(2, tonumber(arg))); ns.Panel.setScale(db.scale)
  elseif cmd == "hide" then db.hidden = true; ns.Panel.toggle(false)
  elseif cmd == "show" then db.hidden = false; ns.Panel.toggle(true)
  elseif cmd == "reset" then ns.Panel.resetPosition()
  elseif cmd == "chat" then db.chat = arg ~= "off"; say("Fight tips in chat: " .. (db.chat and "on" or "off"))
  elseif cmd == "food" then db.food = arg ~= "off"; say("Food reminder: " .. (db.food and "on" or "off"))
  elseif cmd == "spec" then
    if arg == "" then
      local specs = {}
      for _, p in ipairs(Profiles.forClass(C.class)) do specs[#specs + 1] = p.spec end
      say("Profile: " .. C.profile.spec .. ". Available: " .. (#specs > 0 and table.concat(specs, ", ") or "none yet (general coaching)"))
    else
      ClassCoachCharDB.spec = (arg:lower() ~= "auto") and arg or nil
      chooseProfile(); rescanSoon()
      say("Profile: " .. C.profile.spec .. " (" .. tostring(C.profileWhy) .. ")")
    end
  elseif cmd == "last" then
    local r = C.lastReport
    if not r then say("No fight yet.") return end
    say(r.headline)
    if r.casts then say(r.casts) end
    for _, tip in ipairs(r.tips) do say("• " .. tip) end
  elseif cmd == "check" then check()
  else
    say("Coach for " .. C.profile.spec .. ". Commands:")
    for _, l in ipairs(HELP) do print("  " .. l) end
  end
end
