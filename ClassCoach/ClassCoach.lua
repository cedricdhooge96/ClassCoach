-- Start-up, events, the update loop and the /coach commands.
-- This file glues the game (API) to the engine and the panel.
local ADDON, ns = ...
local API, Mana, Tracker, Engine, Profiles = ns.API, ns.Mana, ns.Tracker, ns.Engine, ns.Profiles

-- Every option and its default lives in UI/Options.lua (the settings screen).
local KILL_SAMPLES = 3   -- fights needed before the "enemy nearly dead" guess is used

local C = {}            -- runtime state
ns.C = C

local function say(text) print("|cff8fc7ffClassCoach:|r " .. text) end
ns.say = say

-- Notes a problem in the saved log (see /coach errors). The same problem
-- repeating is counted, not stored again, so the log can never flood.
local lastLogged, repeats = nil, 0
local function keep(db, line)
  db.log[#db.log + 1] = line
  while #db.log > 100 do table.remove(db.log, 1) end
end
local function log(fmt, ...)
  local db = ClassCoachDB
  if type(db) ~= "table" then return end
  if type(db.log) ~= "table" then db.log = {} end
  local ok, line = pcall(string.format, fmt, ...)
  line = ok and line or tostring(fmt)
  if #line > 400 then line = line:sub(1, 400) .. "..." end
  if line == lastLogged then
    repeats = repeats + 1
    if repeats == 10 or repeats == 100 or repeats == 1000 then
      keep(db, ("  (the line above has now happened %d times)"):format(repeats))
    end
    return
  end
  lastLogged, repeats = line, 1
  local timed, stamp = pcall(date, "%H:%M:%S")
  keep(db, ((timed and type(stamp) == "string") and stamp or "") .. " " .. line)
end
API.log = log

-- Runs something of ours so that it can never raise an error in the game.
local function safely(what, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then log("%s: %s", what, tostring(err)) end
  return ok, err
end
ns.safely = safely

---------------------------------------------------------------------------
-- Profile and spell scanning
---------------------------------------------------------------------------

local function chooseProfile()
  local class = API.classToken() or "ANY"
  local choice = ClassCoachCharDB.specChoice
  C.specSeen = choice
  local profile, why = Profiles.choose(class, API.talentPoints(), choice ~= "auto" and choice or nil)
  if profile ~= C.profile then C.manaLevel = nil end
  C.profile, C.profileWhy, C.class = profile, why, class
end

-- Shows each spell with the picture the game shows for it (see API.iconFor).
local function refreshIcons()
  for _, sp in pairs(C.spells or {}) do
    sp.icon = API.iconFor(sp.name, sp.id) or sp.icon
  end
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
  refreshIcons()
  C.hasWand = API.equipped(18)
  C.usesMana = API.usesMana()
  C.syncMacros(true)
  C.barPending = true   -- newly learned spells may want their place on your bars (see tick)
end

-- Only the keys on your bars changed: no need to read the spellbook again.
local function rescanKeys()
  if API.inCombat() then C.rescanDue = true return end
  C.keys = API.scanKeys()
  refreshIcons()
  C.lendMacroKeys()
end

-- Events ask for a rescan here. However many ask, and however fast, the work
-- runs at most once every two seconds: an event storm cannot slow the game.
C.rescanGap = 2
local rescanQueued, rescanWant, lastRescan = nil, nil, -100
local function clockNow()
  local now = API.plain(GetTime())
  return type(now) == "number" and now == now and now or 0
end
local function rescanSoon(keysOnly)
  if keysOnly ~= true then rescanWant = "full" elseif not rescanWant then rescanWant = "keys" end
  local now = clockNow()
  -- A queued rescan that never ran (its timer was lost) is forgotten after ten seconds.
  if rescanQueued and now >= rescanQueued and now - rescanQueued < 10 then return end
  local wait = (C.rescanGap or 2) - (now - lastRescan)
  if wait ~= wait or wait < 0.5 then wait = 0.5 elseif wait > 5 then wait = 5 end
  local queued = pcall(C_Timer.After, wait, function()
    rescanQueued = nil
    local want = rescanWant
    rescanWant = nil
    lastRescan = clockNow()
    safely("rescan", want == "keys" and rescanKeys or rescan)
  end)
  rescanQueued = queued and now or nil
end
local function rescanKeysSoon() rescanSoon(true) end

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
-- A macro on your bar lends its key to the spells inside it.
function C.lendMacroKeys()
  for name, body in pairs(C.macroBodies or {}) do
    local key = C.keys and C.keys["macro:" .. name]
    if key and API.macroExists(name) then
      for _, sp in pairs(C.spells or {}) do
        if C.keys[sp.name] == nil and body:find(sp.name, 1, true) then C.keys[sp.name] = key end
      end
    end
  end
end

-- Automatic macro rewrites are rationed. If something ever made the addon
-- want to rewrite macros again and again, it stops doing so by itself for the
-- rest of the session rather than hammer the game. /coach macros still works.
local AUTO_EDITS_PER_MINUTE = 12
local autoEdits, autoEditsSince = 0, 0

function C.syncMacros(onlyExisting)
  local s = C.lastState
  if not s or API.inCombat() then return {} end
  if onlyExisting and (ClassCoachDB.autoMacros == false or C.macrosPaused) then return {} end
  local now = GetTime()
  if onlyExisting then
    if C.macrosAt and now - C.macrosAt < (C.macroGap or 1.5) then return {} end   -- just done
    if now - autoEditsSince > 60 then autoEdits, autoEditsSince = 0, now end
  end
  C.macrosAt = now
  local results = {}
  C.macroBodies = C.macroBodies or {}
  for _, m in ipairs(Engine.macros(C.profile, s)) do
    local result = API.saveMacro(m.name, m.body, onlyExisting)
    results[#results + 1] = { name = m.name, result = result, about = m.about, smart = m.smart }
    if result == "created" or result == "updated" or result == "same" then C.macroBodies[m.name] = m.body end
    if onlyExisting and result == "updated" then
      autoEdits = autoEdits + 1
      if autoEdits > AUTO_EDITS_PER_MINUTE then
        C.macrosPaused = true
        log("macros were being rewritten too often: automatic updates paused until /reload")
        break
      end
    end
  end
  C.lendMacroKeys()
  C.syncSmart()
  return results
end

-- Loads the coach's current pull plan into the smart key (out of combat only).
function C.syncSmart()
  local s = C.lastState
  if not s or ClassCoachDB.smartKey == false or API.inCombat() then return false end
  -- The secure button is only made once you use it: a key bound to it, or /coach smart.
  if not ns.Smart.button and not C.smartWanted and not ns.Smart.status().keys.next then return false end
  if not ns.Smart.create() then return false end
  local steps, gate = Engine.smartSteps(C.profile, s, { macro = API.macroExists })
  return ns.Smart.load(steps, gate)
end

-- Lays out the profile's suggested bars: the fight on your main bar, reactions
-- on Action Bar 2, preparation on Action Bar 3. mode:
--   nil        fill only empty buttons; a taken spot sends the entry to the
--              next free button of the same bar
--   "replace"  put every entry on its own button, overwriting what is there
--   "preview"  only say what would go where
local BAR_OF = { fight = 1, react = 2, prep = 3 }
local BAR_TITLE = { fight = "Fight", react = "React", prep = "Prepare" }
local autoBarRuns, autoBarSince = 0, 0
function C.setupBar(mode, quiet)
  if quiet then
    -- the automatic pass: at most three a minute, then it stops for the session
    local now = GetTime()
    if C.barPaused then return 0 end
    if now - autoBarSince > 60 then autoBarRuns, autoBarSince = 0, now end
    autoBarRuns = autoBarRuns + 1
    if autoBarRuns > 3 then
      C.barPaused = true
      log("the action bars were being filled too often: automatic filling paused until /reload")
      return 0
    end
  end
  local s = C.lastState
  local report = quiet and function() end or say
  if not (C.profile.bars or C.profile.bar) then report("No bar layout for " .. C.profile.spec .. " yet.") return end
  if not s then report("Still loading: try again in a moment.") return end
  if API.inCombat() then report("The action bars can only be changed out of combat.") return end
  if mode ~= "preview" and not quiet then C.syncMacros(false) end   -- the layout uses the CC macros
  local supplies = s.journey and s.journey.supplies
  -- A button of ours holding an item that is used up, or a weaker one of the
  -- same kind (old water, a smaller bandage), may be refreshed.
  local function stale(slot, e)
    local old = e.item and API.slotItem(slot)
    if not old or old == e.item then return false end
    local count = API.itemCount(old)
    return count == 0 or (supplies and supplies.kindOf[old] == e.kindOfItem)
  end
  local plan = Engine.bars(C.profile, s, {
    macro = API.macroExists,
    book = function(name) local entry = C.book and C.book[name]; return entry and entry.ids[#entry.ids] or nil end,
    item = function(kind) return supplies and supplies.best[kind] end,
  })
  local total, off = 0, {}
  for _, group in ipairs(Engine.BAR_GROUPS) do
    local entries, bar = plan[group], BAR_OF[group]
    local info = API.barInfo(bar)
    if #entries > 0 and API.barShown(bar) == false then
      off[#off + 1] = ("%s (%d buttons for %s)"):format(info.name, #entries, BAR_TITLE[group]:lower())
    elseif #entries > 0 then
      local placed, moved, already, full = {}, {}, {}, {}
      if mode == "preview" then
        for _, e in ipairs(entries) do placed[#placed + 1] = ("%d %s"):format(e.index, e.label) end
      else
        local waiting = {}
        for _, e in ipairs(entries) do
          local slot = info.first + e.index - 1
          local onBar = C.keys and C.keys[e.item and ("item:" .. e.item) or e.macro and ("macro:" .. e.macro) or e.label] ~= nil
          if mode ~= "replace" and onBar then
            already[#already + 1] = e.label
          elseif mode == "replace" or API.slotEmpty(slot) or stale(slot, e) then
            if API.placeAction(slot, e) then placed[#placed + 1] = ("%d %s"):format(e.index, e.label) end
          else
            waiting[#waiting + 1] = e
          end
        end
        -- its own button was taken: the next free one on the same bar
        for _, e in ipairs(waiting) do
          local put
          for i = 1, 12 do
            if API.slotEmpty(info.first + i - 1) then
              if API.placeAction(info.first + i - 1, e) then put = i end
              break
            end
          end
          if put then moved[#moved + 1] = ("%d %s"):format(put, e.label) else full[#full + 1] = e.label end
        end
      end
      total = total + #placed + #moved
      local parts = {}
      if #placed > 0 then parts[#parts + 1] = table.concat(placed, ", ") end
      if #moved > 0 then parts[#parts + 1] = "moved to a free button: " .. table.concat(moved, ", ") end
      if #already > 0 then parts[#parts + 1] = "already on your bars: " .. table.concat(already, ", ") end
      if #full > 0 then parts[#parts + 1] = "no room for: " .. table.concat(full, ", ") end
      if #parts > 0 then report(("%s, %s: %s."):format(BAR_TITLE[group], info.name, table.concat(parts, "; "))) end
    end
  end
  if #off > 0 then
    report("Switched off: " .. table.concat(off, "; ") .. ". Turn it on in Esc > Options > Action Bars, then run /coach bar again.")
  end
  if mode == "preview" then report("That is the plan. /coach bar fills empty buttons; /coach bar replace overwrites.")
  elseif total == 0 and #off == 0 then report("Your bars already have everything.") end
  if mode ~= "preview" and total > 0 then rescanKeysSoon() end
  return total
end

---------------------------------------------------------------------------
-- Mana
---------------------------------------------------------------------------

local function readMana(now, inCombat)
  local cur, max = API.mana()
  if max then C.manaMax = max end
  if cur and C.manaMax and C.manaMax > 0 then
    C.lastMana = cur
    return math.max(0, math.min(100, cur / C.manaMax * 100)), true
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
  -- Reading every bag slot is the costly part: only when the bags changed.
  if not C.suppliesCache or C.suppliesStale then
    C.suppliesCache, C.suppliesStale = API.supplies(C.level or API.level()), false
  end
  j = { at = now, xp = API.xp(), talentPoints = API.unspentTalents(), durability = API.durability(),
    freeSlots = API.freeBagSlots(), hasItem = API.hasItem, supplies = C.suppliesCache,
    atVendor = C.atVendor == true, canRepair = C.atVendor and API.canRepair() or false }
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
    killTime = ClassCoachDB.smartDots ~= false and kill and kill.n >= KILL_SAMPLES and kill.avg or nil,
    now = now, level = C.level or API.level(), inCombat = inCombat, inGroup = API.inGroup(),
    usesMana = C.usesMana, manaPct = manaPct, manaExact = exact, manaLevel = C.manaLevel,
    healthPct = (not inCombat) and API.healthPct() or nil, hasPet = hasPet,
    target = currentTarget(), hasWand = C.hasWand, buffs = buffs, mainHandBuff = mainHand,
    keys = C.keys, spells = C.spells, bookReady = next(C.spells) ~= nil, tracker = C.tracker, fightTime = C.tracker:fightTime(now),
    check = { ready = API.ready, usable = API.usable, repeating = API.repeating }, barPage = API.barPage(),
    itemCount = API.itemCount, equipped = API.equipped, faction = C.faction, journey = (not inCombat) and C.journeyData(now) or nil,
  })
end

local function tick()
  local now = GetTime()
  -- the profile was changed on the settings screen
  if C.specSeen ~= ClassCoachCharDB.specChoice then
    chooseProfile()
    rescanSoon()
  end
  local profile = C.profile
  local s = buildState(now)
  C.lastState = s
  local view = {
    title = ("%s · %s · level %d"):format(profile.spec, profile.class == "ANY" and (C.class or "") or profile.class:sub(1, 1) .. profile.class:sub(2):lower(), s.level),
    usesMana = s.usesMana, manaPct = s.manaPct, manaExact = s.manaExact, manaLevel = s.manaLevel,
  }
  if C.bagsChanged and not s.inCombat then
    C.bagsChanged = false
    C.journey = nil
    s.journey = C.journeyData(now)
    safely("macros after a bag change", C.syncMacros, true)
    C.barPending = true
  end
  if C.barPending and not s.inCombat then
    C.barPending = false
    if ClassCoachDB.autoBar then safely("automatic bar fill", C.setupBar, nil, true) end
  end
  view.next = Engine.next(profile, s)
  view.chain = Engine.chain(profile, s, 3)
  view.planning = view.next == nil
  -- The smart key: when its next step is what the coach wants, show that key.
  -- After a resist the coach wants the same spell again: that is the Again key.
  local now1 = view.chain[1]
  local smart = ClassCoachDB.smartKey ~= false and now1 and ns.Smart.status() or nil
  if smart and smart.ready then
    if now1.retry and smart.keys.again and smart.lastLabel == now1.label then
      now1.keybind, now1.viaSmart = smart.keys.again, "again"
    elseif smart.keys.next and smart.nextLabel == now1.label then
      now1.keybind, now1.viaSmart = smart.keys.next, "next"
    end
  end
  view.drawMana = API.drawMana
  -- What you already did to this enemy, and what is still ticking on it.
  local key = s.target and s.target.key
  view.done, view.dots = {}, {}
  if key then
    for _, c in ipairs(C.tracker:recent(key, 2, now, 30)) do
      local sp = s.spells[c.name]
      view.done[#view.done + 1] = { label = sp and sp.name or c.name, icon = sp and sp.icon, missed = c.missed,
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
    view.statusKind = (s.manaLevel == "low" or (s.barPage and s.barPage ~= 1)) and "warn" or nil
  else
    local missing = Engine.checklist(profile, s, { drinkAt = ClassCoachDB.drinkAt, threat = ClassCoachDB.threat })
    view.missing = missing
    if #missing > 0 then
      -- the panel shows each as the icon of what fixes it; the line under them explains the first
      view.status = missing[1].hint
      view.statusKind = "warn"
    else
      view.status = "Ready to pull."
      view.statusKind = "ok"
    end
    -- The journey panel is a separate thing: if it ever fails, the coach panel still draws.
    safely("journey panel", function()
      local db = ClassCoachDB
      local journey = Engine.journey(profile, s, { food = db.food, rested = db.remindRested, train = db.remindTrain, gear = db.remindGear,
        supplies = db.remindSupplies, roadmap = db.roadmap, data = ns.JourneyData })
      journey.title = ("Journey · level %d"):format(s.level)
      for _, line in ipairs(journey.lines) do
        if type(line.icon) == "table" then   -- { spell = key }: that spell's own icon, learned or not
          local sp, meta = s.spells[line.icon.spell], profile.spells[line.icon.spell]
          line.icon = (sp and sp.icon) or (meta and meta.ids and API.texture(meta.ids[1])) or nil
        end
      end
      C.lastJourney = journey
      ns.Journey.render(journey)
    end)
  end
  if s.inCombat then safely("journey panel", ns.Journey.render, { inCombat = true }) end
  if C.trouble then view.status, view.statusKind = C.trouble, "warn" end
  ns.Panel.render(view)
end

-- The update loop protects the game from the addon:
--   * a refresh that fails is caught; after ten in a row the addon slows
--     itself to one try every five seconds until it works again
--   * a refresh that takes long makes the addon refresh less often
--   * nothing here can raise an error into the game
local elapsed, failures, slowRuns, stretch = 0, 0, 0, 1
local clock = debugprofilestop
local function onUpdate(_, dt)
  if type(dt) ~= "number" then return end
  elapsed = elapsed + dt
  local fast = C.tracker and C.tracker.fight ~= nil
  local wait = (fast and 0.1 or 0.4) * stretch
  if failures >= 10 then wait = 5 end
  if elapsed < wait then return end
  elapsed = 0
  local began = clock and clock() or nil
  local ok, err = pcall(tick)
  if ok then
    if failures >= 10 then log("refresh works again") end
    failures, C.trouble = 0, nil
  else
    failures = failures + 1
    err = tostring(err)
    if err ~= C.lastError then C.lastError = err end
    log("refresh error: %s", err)
    if failures == 10 then
      C.trouble = "ClassCoach hit a problem and slowed itself down. Type /coach errors."
      pcall(ns.Panel.render, { status = C.trouble, statusKind = "warn", chain = {} })
    end
  end
  -- more than 20 ms for one refresh is too much: halve the pace, up to four times slower
  if began and clock then
    local took = clock() - began
    if took > 20 then
      slowRuns = slowRuns + 1
      if slowRuns >= 5 and stretch < 4 then
        stretch, slowRuns = stretch * 2, 0
        log("a refresh took %d ms: refreshing %dx less often", took, stretch)
      end
    elseif took < 5 and slowRuns > 0 then
      slowRuns = slowRuns - 1
    end
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

-- The game reports "something was resisted on your target" without saying
-- what. Right after one of your harmful casts it is that cast: undo it, so the
-- coach asks for it again (or skips it on an immune enemy).
local SPELL_FAILS = { RESIST = "resist", IMMUNE = "immune", EVADE = "resist", REFLECT = "resist", DEFLECT = "resist" }
function handlers.UNIT_COMBAT(unit, action)
  if API.plain(unit) ~= "target" then return end
  local kind = SPELL_FAILS[API.plain(action) or ""]
  if not kind then return end
  local c = C.tracker:castMissed(GetTime(), kind == "immune")
  C.stats = C.stats or { resists = 0, unmatched = 0 }
  if c then C.stats.resists = C.stats.resists + 1 else C.stats.unmatched = C.stats.unmatched + 1 end
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
    safely("fight report", finishFight)
    if C.rescanDue then rescanSoon() end
  end)
end

-- The game blocked something and blames an addon. If it blames us, keep the
-- details: this is how a "my bars vanished" report gets a cause.
local function blocked(kind, addon, func)
  addon, func = tostring(API.plain(addon)), tostring(API.plain(func))
  C.blocked = C.blocked or {}
  local line = ("%s: %s -> %s"):format(kind, addon, func)
  if #C.blocked < 20 then C.blocked[#C.blocked + 1] = line end
  if addon == ADDON then
    log("%s", line)
    if not C.blockedSaid then
      C.blockedSaid = true
      say("The game blocked an action and blames this addon (" .. func .. "). Type /coach check and send the result, please.")
    end
  end
end
function handlers.ADDON_ACTION_BLOCKED(addon, func) blocked("blocked", addon, func) end
function handlers.ADDON_ACTION_FORBIDDEN(addon, func) blocked("forbidden", addon, func) end

-- Bags changed (bought water, used the last bandage): the rest macro and the
-- item buttons follow on the next refresh out of combat.
function handlers.BAG_UPDATE_DELAYED() C.bagsChanged = true; C.suppliesStale = true end

-- At a vendor the journey panel checks your supplies.
function handlers.MERCHANT_SHOW() C.atVendor = true; C.journey = nil end
function handlers.MERCHANT_CLOSED() C.atVendor = false; C.journey = nil end

function handlers.PLAYER_LEVEL_UP(level)
  level = API.plain(level)
  if type(level) ~= "number" then return end
  C.level = level
  C.suppliesStale = true   -- what you can use changes with your level
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

for _, e in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" }) do
  handlers[e] = function() rescanSoon() end
end
-- These fire in bursts (every step of a sequence macro changes a button): keys only.
for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "UPDATE_MACROS" }) do
  handlers[e] = rescanKeysSoon
end
for _, e in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED" }) do
  handlers[e] = talentsChanged
end

local function start()
  ClassCoachDB = ClassCoachDB or {}
  ClassCoachCharDB = ClassCoachCharDB or {}
  local db = ClassCoachDB
  -- settings saved by older versions
  if db.hidden ~= nil then db.showCoach = not db.hidden; db.hidden = nil end
  if ClassCoachCharDB.spec ~= nil then ClassCoachCharDB.specChoice = ClassCoachCharDB.spec; ClassCoachCharDB.spec = nil end
  if ClassCoachCharDB.specChoice == nil then ClassCoachCharDB.specChoice = "auto" end
  for k, v in pairs(ns.Options.defaults()) do if db[k] == nil then db[k] = v end end
  ns.Options.sanitize(db, ClassCoachCharDB)
  for _, problem in ipairs(Profiles.problems or {}) do log("%s", problem) end
  C.tracker = Tracker.new()
  C.level = API.level()
  C.faction = API.faction()
  chooseProfile()
  local ok, err = pcall(rescan)
  if not ok then log("first scan error: %s", tostring(err)) end
  local mana, max = API.mana()
  C.lastMana, C.manaMax = mana, max
  ns.Panel.create(ClassCoachCharDB, ClassCoachDB)
  ns.Journey.create(ClassCoachCharDB, ClassCoachDB)
  C.optionsReady = ns.Options.build(ClassCoachDB, ClassCoachCharDB, {
    macros = function() SlashCmdList.CLASSCOACH("macros") end,
    reset = function() SlashCmdList.CLASSCOACH("reset") end,
    bar = function() SlashCmdList.CLASSCOACH("bar") end,
  })
end

local frame = CreateFrame("Frame")
C.refused = {}
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    if not API.forever then   -- any other version of the game: say so once and stay off
      self:SetScript("OnEvent", nil)
      print(API.NOT_FOREVER)
      return
    end
    local ok, err = pcall(start)
    if not ok then print("ClassCoach failed to start: " .. tostring(err)) return end
    -- The update loop runs on this always-shown frame, so hiding a panel never stops the coach.
    C.driver = self
    self:SetScript("OnUpdate", onUpdate)
    for e in pairs(handlers) do
      local fine
      if e == "UNIT_SPELLCAST_SUCCEEDED" or e == "UNIT_AURA" then
        fine = pcall(self.RegisterUnitEvent, self, e, "player")
      elseif e == "UNIT_COMBAT" then
        -- only your target: this event fires for every unit around you otherwise
        fine = pcall(self.RegisterUnitEvent, self, e, "target")
      else
        fine = pcall(self.RegisterEvent, self, e)
      end
      if not fine then C.refused[#C.refused + 1] = e end
    end
    return
  end
  local h = handlers[event]
  if not h or not C.profile then return end
  safely(event, h, ...)
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
  add("client build %s interface %s, project %s; WoW Forever: %s", describe(build), describe(interface), describe(WOW_PROJECT_ID),
    API.forever and "yes" or "NO")
  local gone = API.missing()
  add("Forever functions missing on this client: %s", #gone > 0 and table.concat(gone, ", ") or "none")
  add("class %s, level %s, profile %s %s (%s)", tostring(C.class), tostring(C.level), C.profile.class, C.profile.spec, tostring(C.profileWhy))
  local pts = API.talentPoints()
  add("talent points %s", pts and table.concat({ pts[1] or 0, pts[2] or 0, pts[3] or 0 }, "/") or "unreadable")
  add("mana now %s / %s (combat %s)", describe(API.try(UnitPower, "player", 0)), describe(API.try(UnitPowerMax, "player", 0)), tostring(API.inCombat()))
  local names = {}
  for key, sp in pairs(C.spells) do
    local usable, short = API.usable(sp.id)
    names[#names + 1] = ("%s id %s cost %s ready %s usable %s short %s key %s"):format(key, tostring(sp.id), tostring(sp.cost),
      tostring(API.ready(sp.id)), tostring(usable), tostring(short), tostring(C.keys[sp.name]))
    local own, book, bar = API.texture(sp.id), API.bookIcons[sp.name], API.barIcons[sp.name]
    if (book and book ~= own) or (bar and bar ~= own) then
      names[#names] = names[#names] .. (" | icon: id %s, spellbook %s, bar %s"):format(tostring(own), tostring(book), tostring(bar))
    end
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
  local st = ns.Smart.status()
  add("smart key: button %s, %s steps, at step %s, keys next=%s again=%s restart=%s", tostring(ns.Smart.button ~= nil), st.count,
    tostring(st.step), tostring(st.keys.next), tostring(st.keys.again), tostring(st.keys.restart))
  add("main bar page %s; Shift+1..6 switch pages: %s", tostring(API.barPage()),
    tostring(API.plain(API.try(GetBindingAction, "SHIFT-2")) == "ACTIONPAGE2"))
  add("actions the game blocked this session: %s", C.blocked and table.concat(C.blocked, " | ") or "none")
  add("resists seen: %s matched to a cast, %s not", C.stats and C.stats.resists or 0, C.stats and C.stats.unmatched or 0)
  add("mana bar drawn by the game: %s; percent function %s, readable %s", tostring(not ns.Panel.manaRefused),
    tostring(UnitPowerPercent ~= nil), tostring(API.manaPct() ~= nil))
  add("buffs readable %s, weapon buff %s, wand %s", tostring(C.buffs ~= nil), tostring(API.mainHandBuff()), tostring(C.hasWand))
  add("events refused: %s", #C.refused > 0 and table.concat(C.refused, " ") or "none")
  add("errors logged: %d (see ClassCoachDB.log after /reload)", ClassCoachDB.log and #ClassCoachDB.log or 0)
  for _, l in ipairs(out) do print("|cff9aa0a8" .. l .. "|r") end
  ClassCoachDB.report = out
end

local HELP = {
  "/coach set — change a setting from chat (the full page: Esc > Options > AddOns > ClassCoach)",
  "/coach pages — stop Shift+number from switching your main bar to an empty page",
  "/coach macros — create or refresh this class's helper macros (out of combat)",
  "/coach bar — lay out three bars by purpose: fight (main bar), react (Action Bar 2), prepare (Action Bar 3). Empty buttons only; \"preview\" just lists, \"replace\" overwrites",
  "/coach smart — the smart key: one key that walks the coach's plan (shows its steps and keys)",
  "/coach last — repeat the last fight report",
  "/coach reset — put both panels back where they started",
  "/coach hide | show — the coach panel",
  "/coach errors — problems the addon caught itself (for bug reports)",
  "/coach check — what the addon can read on this client (for bug reports)",
}

-- The settings page is opened by you, through the game's own menu. The addon
-- never opens it itself: an addon showing one of the game's panels is a known
-- way to make protected frames (action bars, the pet bar) misbehave in combat.
local function openSettings()
  say("Settings: press Esc, then Options > AddOns > ClassCoach. Or type /coach set to change one here.")
end

-- The minimap's addon menu (the client looks these up by name)
function ClassCoach_OnAddonCompartmentClick() safely("addon menu", openSettings) end
function ClassCoach_OnAddonCompartmentEnter(_, button)
  safely("addon menu", function()
    if not GameTooltip or not button then return end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("ClassCoach", 1, 0.82, 0.2)
    GameTooltip:AddLine("Esc > Options > AddOns > ClassCoach, or /coach set.", 0.9, 0.9, 0.9)
    GameTooltip:Show()
  end)
end
function ClassCoach_OnAddonCompartmentLeave() safely("addon menu", function() if GameTooltip then GameTooltip:Hide() end end) end

SLASH_CLASSCOACH1, SLASH_CLASSCOACH2 = "/coach", "/classcoach"
local function command(msg)
  if not C.profile or type(ClassCoachDB) ~= "table" then say("Still loading: try again in a moment.") return end
  local cmd, arg = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd, arg = (cmd or ""):lower(), arg or ""
  local db = ClassCoachDB
  if cmd == "" or cmd == "options" or cmd == "config" or cmd == "settings" then
    openSettings()
    for _, l in ipairs(HELP) do print("  " .. l) end
  elseif cmd == "set" then
    -- /coach set compact on     /coach set opacity 40     /coach set (lists them)
    local key, value = arg:match("^(%S+)%s*(.*)$")
    local option = key and ns.Options.find(key)
    if not option then
      say("Options: " .. table.concat(ns.Options.keys(), ", ") .. ". Example: /coach set compact on")
    else
      local store = option.perChar and ClassCoachCharDB or db
      local v = value:lower()
      if option.kind == "check" then
        if v == "" then store[option.key] = not store[option.key] else store[option.key] = (v == "on" or v == "1" or v == "true" or v == "yes") end
      elseif option.kind == "slider" then
        local n = tonumber(v)
        if n then store[option.key] = math.max(option.min, math.min(option.max, n)) end
      elseif value ~= "" then
        store[option.key] = value
      end
      say(("%s = %s"):format(option.name, tostring(store[option.key])))
    end
  elseif cmd == "errors" then
    -- "/coach errors on": let the game show Lua errors, with the addon's name on each
    if arg:lower() == "on" or arg:lower() == "off" then
      local shown = arg:lower() == "on"
      local now = API.showErrors(shown)
      if now ~= shown then
        say("The game did not accept that. Type this instead: /console scriptErrors " .. (shown and "1" or "0"))
      elseif shown then
        say("The game will now show errors as they happen. The window names the addon and the line: a screenshot of the first one is all I need.")
      else
        say("The game no longer shows error windows.")
      end
      return
    end
    -- what the addon itself caught, for a screenshot
    local list = db.log or {}
    say(("%d problem(s) recorded by the addon%s."):format(#list, #list > 0 and "; the latest" or ""))
    for i = math.max(1, #list - 7), #list do print("  " .. tostring(list[i])) end
    if C.lastError then print("  last refresh error: " .. tostring(C.lastError)) end
    if C.refused and #C.refused > 0 then print("  events the game refused: " .. table.concat(C.refused, ", ")) end
    if C.blocked then print("  blocked actions: " .. table.concat(C.blocked, " | ")) end
    if ns.Smart.error then print("  smart key: " .. tostring(ns.Smart.error)) end
    if C.macrosPaused then print("  automatic macro updates are paused until /reload") end
    if C.barPaused then print("  automatic bar filling is paused until /reload") end
    print("  To see errors from any addon as they happen: /coach errors on")
  elseif cmd == "pages" then
    if API.inCombat() then say("Key bindings can only be changed out of combat.") return end
    local freed = API.freePageKeys()
    if #freed > 0 then say("Shift+number no longer switches bar pages (" .. table.concat(freed, ", ") .. "), and your main bar is back on page 1.")
    else say("Shift+number was not switching pages (or you already changed those keys). Main bar set to page 1.") end
  elseif cmd == "lock" then db.locked = true; say("Panels locked.")
  elseif cmd == "unlock" then db.locked = false; say("Panels unlocked: drag each where you like.")
  elseif cmd == "scale" and tonumber(arg) then db.scale = math.max(0.6, math.min(1.6, tonumber(arg)))
  elseif cmd == "hide" then db.showCoach = false
  elseif cmd == "show" then db.showCoach = true
  elseif cmd == "reset" then ns.Panel.resetPosition(); ns.Journey.reset(); say("Both panels are back where they started.")
  elseif cmd == "journey" then
    if arg == "reset" then ns.Journey.reset() else db.journey = arg ~= "off" end
  elseif cmd == "spec" then
    local wanted = arg:lower()
    local choice = (wanted == "" or wanted == "auto") and "auto" or nil
    for _, p in ipairs(Profiles.forClass(C.class)) do
      if p.spec:lower() == wanted then choice = p.spec end
    end
    if not choice then
      local specs = {}
      for _, p in ipairs(Profiles.forClass(C.class)) do specs[#specs + 1] = p.spec end
      say("No profile called \"" .. arg .. "\". Available: auto" .. (#specs > 0 and (", " .. table.concat(specs, ", ")) or ""))
    else
      ClassCoachCharDB.specChoice = choice
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
  elseif cmd == "bar" then
    local mode = arg:lower()
    C.setupBar((mode == "replace" or mode == "preview") and mode or nil)
  elseif cmd == "smart" then
    local what, key = arg:match("^(%S+)%s+(%S+)$")
    if API.inCombat() then say("The smart key can only be set up out of combat.") return end
    C.smartWanted = true
    C.syncMacros(false)   -- it uses a few CC macros (wand, demon, attack)
    if not C.syncSmart() then say("The smart key could not be set up on this client. /coach check shows why.") return end
    if what then
      if ns.Smart.bind(what:lower(), key:upper()) then say(("Smart key: %s is now on %s."):format(what:lower(), key:upper()))
      else say("Use: /coach smart next 1   (or again / restart, then the key)") end
    end
    local st = ns.Smart.status()
    say("Smart key steps: " .. table.concat(ns.Smart.describe(), ", ") .. ".")
    say(("Keys: next %s, again %s, restart %s."):format(st.keys.next or "not bound", st.keys.again or "not bound", st.keys.restart or "not bound"))
    if not st.keys.next then
      say("Bind them in Esc > Options > Keybindings > AddOns > ClassCoach, or type /coach smart next 1 (then again, restart).")
    end
  elseif cmd == "check" then check()
  else
    say("Coach for " .. C.profile.spec .. ". Commands:")
    for _, l in ipairs(HELP) do print("  " .. l) end
  end
end

-- A command can never raise an error into the game either.
SlashCmdList.CLASSCOACH = function(msg)
  if not API.forever then print(API.NOT_FOREVER) return end
  local ok = safely("command /coach " .. tostring(msg), command, msg)
  if not ok then say("That command hit a problem. Type /coach errors to see it.") end
end
