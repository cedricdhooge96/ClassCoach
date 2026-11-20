-- Start-up, events, the update loop and the /coach commands.
-- This file glues the game (API) to the engine and the panel.
local ADDON, ns = ...
local API, Mana, Tracker, Engine, Profiles = ns.API, ns.Mana, ns.Tracker, ns.Engine, ns.Profiles

local DEFAULTS = { scale = 1, locked = false, hidden = false, chat = true, food = true, drinkAt = 60, journey = true }
local KILL_SAMPLES = 3   -- fights needed before the "enemy nearly dead" guess is used

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
      if spec.debuff then sp.duration = API.dotDuration(sp.id) or spec.debuff end
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
  C.syncMacros(true)
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
-- Target, demon and macros
---------------------------------------------------------------------------

-- The current target, with a key that keeps enemies apart (see API.targetKey).
local function currentTarget()
  local t = API.target()
  if t.exists then
    if not C.targetKey then C.targetKey, C.targetMode = API.targetKey() end
    t.key = C.targetKey
  end
  return t
end

local DEMON_FAMILIES = { Imp = true, Voidwalker = true, Succubus = true, Incubus = true, Felhunter = true }

-- Which pet is out: what the game says, else the last one you summoned.
local function currentDemon(hasPet)
  if hasPet == false then return nil end
  local family = API.petFamily()
  if family and DEMON_FAMILIES[family] then
    ClassCoachCharDB.demon = family
    return family
  end
  if hasPet then return ClassCoachCharDB.demon end
  return nil
end

-- Builds the profile's macros from the spells you know. With onlyExisting it
-- only refreshes macros you already made (after training new spells).
function C.syncMacros(onlyExisting)
  local s = C.lastState
  if not s or not C.profile.macros or API.inCombat() then return {} end
  local results = {}
  for _, m in ipairs(Engine.macros(C.profile, s)) do
    local result = API.saveMacro(m.name, m.body, onlyExisting)
    results[#results + 1] = { name = m.name, result = result, about = m.about }
    -- a macro on your bar lends its key to the spells inside it
    local key = C.keys and C.keys["macro:" .. m.name]
    if key and API.macroExists(m.name) then
      for _, sp in pairs(C.spells or {}) do
        if C.keys[sp.name] == nil and m.body:find(sp.name, 1, true) then C.keys[sp.name] = key end
      end
    end
  end
  return results
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

-- Slow-changing things for the journey panel: read every couple of seconds, never in combat.
function C.journeyData(now)
  local j = C.journey
  if j and now - j.at < 2 then return j end
  j = { at = now, xp = API.xp(), talentPoints = API.unspentTalents(), durability = API.durability(),
    freeSlots = API.freeBagSlots(), hasItem = API.hasItem }
  C.journey = j
  return j
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
  local hasPet = petState(inCombat)
  local demon
  if inCombat then demon = C.demonAtPull else demon = currentDemon(hasPet) end
  local kill = ClassCoachCharDB.kill
  return Engine.newState({
    meta = C.profile.spells, demon = demon,
    killTime = kill and kill.n >= KILL_SAMPLES and kill.avg or nil,
    now = now, level = C.level or API.level(), inCombat = inCombat, inGroup = API.inGroup(),
    usesMana = C.usesMana, manaPct = manaPct, manaExact = exact, manaLevel = C.manaLevel,
    healthPct = (not inCombat) and API.healthPct() or nil, hasPet = hasPet,
    target = currentTarget(), hasWand = C.hasWand, buffs = buffs, mainHandBuff = mainHand,
    keys = C.keys, spells = C.spells, bookReady = next(C.spells) ~= nil, tracker = C.tracker, fightTime = C.tracker:fightTime(now),
    check = { ready = API.ready, usable = API.usable },
    itemCount = API.itemCount, equipped = API.equipped, journey = (not inCombat) and C.journeyData(now) or nil,
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
  view.chain = Engine.chain(profile, s, 3)
  view.planning = view.next == nil
  view.drawMana = API.drawMana
  -- What you already did to this enemy, and what is still ticking on it.
  local key = s.target and s.target.key
  view.done, view.dots = {}, {}
  if key then
    for _, c in ipairs(C.tracker:recent(key, 2, now, 30)) do
      local sp = s.spells[c.name]
      view.done[#view.done + 1] = { label = sp and sp.name or c.name, icon = sp and sp.icon,
        left = profile.spells[c.name] and profile.spells[c.name].debuff and C.tracker:debuffLeft(key, c.name, now) or nil }
    end
    for _, d in ipairs(C.tracker:dotsOn(key, now)) do
      local sp = s.spells[d.name]
      view.dots[#view.dots + 1] = { label = sp and sp.name or d.name, left = d.left }
    end
  end
  view.otherDotted = C.tracker:otherDotted(key or "none", now)
  if s.inCombat then
    view.status = Engine.advice(profile, s)
    view.statusKind = s.manaLevel == "low" and "warn" or nil
  else
    local missing = Engine.checklist(profile, s, { drinkAt = ClassCoachDB.drinkAt })
    if #missing > 0 then
      local names = {}
      for _, m in ipairs(missing) do names[#names + 1] = m.text end
      view.status = "Before you pull: " .. table.concat(names, " · ") .. (missing[1].hint and ("\n" .. missing[1].hint) or "")
      view.statusKind = "warn"
    else
      view.status = "Ready to pull."
      view.statusKind = "ok"
    end
    local journey = Engine.journey(profile, s, { food = ClassCoachDB.food })
    journey.title = ("Journey · level %d"):format(s.level)
    for _, line in ipairs(journey.lines) do
      if type(line.icon) == "table" then   -- { spell = key }: that spell's own icon, learned or not
        local sp, meta = s.spells[line.icon.spell], profile.spells[line.icon.spell]
        line.icon = (sp and sp.icon) or (meta and meta.ids and API.texture(meta.ids[1])) or nil
      end
    end
    C.lastJourney = journey
    ns.Journey.render(journey)
  end
  if s.inCombat then ns.Journey.render({ inCombat = true }) end
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
  local meta = C.profile.spells[key]
  if meta and meta.summons then ClassCoachCharDB.demon = meta.summons end
  local t = currentTarget()
  local sp = C.spells[key]
  -- Out of combat the next exact reading may come after combat starts: keep our own count right.
  if not C.tracker.fight and C.lastMana and cost and cost > 0 then C.lastMana = math.max(0, C.lastMana - cost) end
  C.tracker:cast(GetTime(), key, cost or 0, meta, t.key, sp and sp.duration)
end

function handlers.PLAYER_TARGET_CHANGED()
  API.targetChanged()
  C.targetKey = nil
end
function handlers.NAME_PLATE_UNIT_ADDED(token)
  API.plateAdded(token)
  C.targetKey = nil
end
function handlers.NAME_PLATE_UNIT_REMOVED()
  C.targetKey = nil
end

function handlers.PLAYER_SWING()
  C.tracker:swing()
end

function handlers.PLAYER_REGEN_DISABLED()
  local t = API.target()
  C.petAtPull = C.lastState and C.lastState.hasPet
  C.demonAtPull = C.lastState and C.lastState.demon
  C.tracker:startFight(GetTime(), {
    target = t.hostile and t.name or nil, targetLevel = t.level, elite = t.elite,
    manaStart = C.lastMana, manaMax = C.manaMax, hasPet = C.petAtPull, demon = C.demonAtPull,
  })
end

local function finishFight()
  local cur, max = API.mana()
  local summary = C.tracker:endFight(GetTime(), cur, max)
  if not summary or summary.duration < 3 then return end
  -- Learn how long your kills take: it decides when a new damage-over-time spell is wasted.
  if not summary.elite and not API.inGroup() and summary.duration < 120 then
    local kill = ClassCoachCharDB.kill or { avg = 0, n = 0 }
    local per = summary.duration / summary.targets
    kill.avg = kill.n == 0 and per or (kill.avg * 0.7 + per * 0.3)
    kill.n = kill.n + 1
    ClassCoachCharDB.kill = kill
  end
  local s = C.lastState or buildState(GetTime())
  C.syncMacros(true)   -- the pull plan may have changed with what was learned this fight
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
  ns.Journey.create(ClassCoachCharDB, ClassCoachDB)
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
  local _, mode = API.targetKey()
  add("enemies told apart by: %s; pet family %s; saved demon %s", tostring(mode), tostring(API.petFamily()), tostring(ClassCoachCharDB.demon))
  local kill = ClassCoachCharDB.kill
  add("average kill time: %s (%s fights)", kill and ("%.1fs"):format(kill.avg) or "-", kill and kill.n or 0)
  local durations = {}
  for key, sp in pairs(C.spells or {}) do if sp.duration then durations[#durations + 1] = key .. " " .. sp.duration .. "s" end end
  table.sort(durations)
  add("damage over time: %s", table.concat(durations, ", "))
  add("built-in rotation assistant on this client: %s", tostring(C_AssistedCombat ~= nil))
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
  "/coach macros — create or refresh this class's helper macros (out of combat)",
  "/coach chat on | off — fight tips in chat",
  "/coach food on | off — remind about buff food",
  "/coach journey on | off | reset — the second panel: XP, rested XP and to-dos",
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
  elseif cmd == "scale" and tonumber(arg) then db.scale = math.max(0.5, math.min(2, tonumber(arg))); ns.Panel.setScale(db.scale); ns.Journey.setScale(db.scale)
  elseif cmd == "hide" then db.hidden = true; ns.Panel.toggle(false)
  elseif cmd == "show" then db.hidden = false; ns.Panel.toggle(true)
  elseif cmd == "reset" then ns.Panel.resetPosition(); ns.Journey.reset()
  elseif cmd == "chat" then db.chat = arg ~= "off"; say("Fight tips in chat: " .. (db.chat and "on" or "off"))
  elseif cmd == "journey" then
    if arg == "reset" then ns.Journey.reset(); say("Journey panel back at its starting spot.")
    else db.journey = arg ~= "off"; say("Journey panel: " .. (db.journey and "on" or "off")) end
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
  elseif cmd == "macros" then
    if not C.profile.macros then say("No macros for " .. C.profile.spec .. " yet.") return end
    if API.inCombat() then say("Macros can only be made out of combat. Try again after the fight.") return end
    local results = C.syncMacros(false)
    if #results == 0 then say("Nothing to make yet: you don't know the spells for them.") return end
    local WORDS = { created = "created", updated = "updated", same = "already up to date",
      full = "not made: your character macro list is full", combat = "not made: in combat" }
    for _, r in ipairs(results) do
      say(("%s: %s.%s"):format(r.name, WORDS[r.result] or "could not be made", r.about and (" " .. r.about) or ""))
    end
    say("Open /macro, pick your character's tab and drag them onto your action bar. They update themselves when you learn new spells.")
    rescanSoon()
  elseif cmd == "check" then check()
  else
    say("Coach for " .. C.profile.spec .. ". Commands:")
    for _, l in ipairs(HELP) do print("  " .. l) end
  end
end
