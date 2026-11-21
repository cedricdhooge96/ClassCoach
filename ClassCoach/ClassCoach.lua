-- Start-up, events, the update loop and the /coach commands.
-- This file glues the game (API) to the engine and the panel.
local ADDON, ns = ...
local API, Mana, Tracker, Engine, Profiles = ns.API, ns.Mana, ns.Tracker, ns.Engine, ns.Profiles

-- Every option and its default lives in UI/Options.lua (the settings screen).
local KILL_SAMPLES = 5   -- fights needed before the "enemy nearly dead" guess is used
local KILL_KEEP = 7      -- the usual kill time is the middle one of your last this many

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
  if ns.Trace then pcall(ns.Trace.add, "log", "%s", line) end
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
  C.slots = API.barSlots or {}
  C.lendMacroKeys()   -- also when the macros are not rewritten now (automatic updates off, or just done)
  refreshIcons()
  safely("talents", C.refreshTalents)
  C.talentsStale = false
  C.hasWand = API.equipped(18)
  C.usesMana = API.usesMana()
  C.syncMacros(true)
  C.barPending = true   -- newly learned spells may want their place on your bars (see tick)
end

-- Only the keys on your bars changed: no need to read the spellbook again.
local function rescanKeys()
  if API.inCombat() then C.rescanDue = true return end
  C.keys = API.scanKeys()
  C.slots = API.barSlots or {}
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
-- Talents: the build you follow and where you are in it
---------------------------------------------------------------------------

-- The builds this character can follow: the profile's own list first, then the
-- guide links the profile names. Read once per profile.
local function buildsFor(profile)
  if C.buildList and C.buildListFor == profile then return C.buildList end
  local list = {}
  if profile.talents and #profile.talents > 0 then
    list[#list + 1] = { name = profile.talentsName or (profile.spec .. " leveling"), order = Engine.talentOrder(profile.talents) }
  end
  for _, b in ipairs(profile.builds or {}) do
    local order, problem = Engine.decodeBuild(b.link, C.class, ns.TalentLinks)
    if order then
      -- a build marked `first` goes before the profile's own: it is the default
      table.insert(list, b.first and 1 or #list + 1, { name = b.name, link = b.link, order = order })
    else
      log("build %s: %s", tostring(b.name), tostring(problem))
    end
  end
  C.buildList, C.buildListFor = list, profile
  return list
end
C.buildsFor = buildsFor

-- The build from a link you pasted with /coach build <link>, or nil.
local function customBuild()
  local link = ClassCoachCharDB.buildLink
  if type(link) ~= "string" or link == "" then return nil end
  if C.customBuild and C.customBuild.link == link then return C.customBuild end
  local order, site = Engine.decodeBuild(link, C.class, ns.TalentLinks)
  if not order then return nil end
  C.customBuild = { name = "Your " .. site .. " link", link = link, order = order }
  return C.customBuild
end

-- Reads your talents and works out the next point of your build. Cheap enough
-- to run while the talent window is open; otherwise it runs when talents change.
function C.refreshTalents()
  local profile = C.profile
  if not profile then return end
  local have = API.talents()
  local build, how = Engine.pickBuild(buildsFor(profile), customBuild(), have, ClassCoachCharDB.build)
  if not build then C.talentState = nil return end
  local unspent = API.unspentTalents()
  C.talentState = { build = build, how = how, have = have, plan = Engine.talentPlan(build.order, have),
    unspent = unspent == true and 1 or unspent }
  return C.talentState
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
-- A macro on your bar lends its key and its button to the spells inside it:
-- any macro on your bars (the coach's own, or one you wrote), read from the game.
function C.lendMacroKeys()
  local onBars = {}
  for k in pairs(C.keys or {}) do
    local name = type(k) == "string" and k:match("^macro:(.+)$")
    if name then onBars[name] = true end
  end
  for k in pairs(C.slots or {}) do
    local name = type(k) == "string" and k:match("^macro:(.+)$")
    if name then onBars[name] = true end
  end
  for name in pairs(onBars) do
    local body = API.macroBody(name) or (C.macroBodies and C.macroBodies[name])
    local key = C.keys and C.keys["macro:" .. name]
    local slot = C.slots and C.slots["macro:" .. name]
    if body and (key or slot) then
      for _, sp in pairs(C.spells or {}) do
        if body:find(sp.name, 1, true) then
          if key and C.keys[sp.name] == nil then C.keys[sp.name] = key end
          if slot and C.slots[sp.name] == nil then C.slots[sp.name] = slot end
        end
      end
    end
  end
end

-- The fight plan as one line ("Bane of Agony>Corruption>Shoot>..."), to notice when it changes.
local function planLine(s)
  local names = {}
  for _, st in ipairs(Engine.timeline(C.profile, s)) do names[#names + 1] = st.key end
  return table.concat(names, ">")
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
  if s then C.planSeen, C.planNext = planLine(s), nil end   -- what the macros and the key now hold
  return results
end

-- Loads the coach's current pull plan into the smart key (out of combat only).
function C.syncSmart()
  local s = C.lastState
  if not s or ClassCoachDB.smartKey == false or API.inCombat() then return false end
  -- The secure button is only made once you use it: a key bound to it, or /coach smart.
  if not ns.Smart.button and not C.smartWanted and not ns.Smart.status().keys.next then return false end
  if not ns.Smart.create() then return false end
  local built, gate = Engine.smartSteps(C.profile, s, { macro = API.macroExists, shoot = API.shootText() })
  return ns.Smart.load(built, gate)
end

-- What the coach would put on your three bars right now.
function C.barPlan(s)
  local supplies = s.journey and s.journey.supplies
  return Engine.bars(C.profile, s, {
    macro = API.macroExists,
    book = function(name) local entry = C.book and C.book[name]; return entry and entry.ids[#entry.ids] or nil end,
    item = function(kind) return supplies and supplies.best[kind] end,
  }, ClassCoachDB.barFixed)
end

local function sameAction(a, b)
  return a ~= nil and b ~= nil and ((a.spell ~= nil and a.spell == b.spell) or (a.macro ~= nil and a.macro == b.macro) or (a.item ~= nil and a.item == b.item))
end

-- Lays out the profile's suggested bars: the fight on your main bar, reactions
-- on Action Bar 2, preparation on Action Bar 3. mode:
--   nil        fill only empty buttons; a taken spot sends the entry to the
--              next free button of the same bar, so nothing you use moves
--   "replace"  put every entry on its own button, overwriting what is there,
--              and take away the copy it leaves on another button of that bar
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
  local fixed = ClassCoachDB.barFixed
  -- The button of an item entry that may be refreshed: one on this bar holding
  -- a weaker item of the same kind (old water, a smaller bandage), or the
  -- entry's own button when what is on it is used up.
  local function stale(info, e)
    if not e.item then return nil end
    for i = 1, 12 do
      local old = API.slotItem(info.first + i - 1)
      if old and old ~= e.item and supplies and supplies.kindOf[old] == e.kindOfItem then return i end
    end
    local old = API.slotItem(info.first + e.index - 1)
    return old and old ~= e.item and API.itemCount(old) == 0 and e.index or nil
  end
  local plan = C.barPlan(s)
  local total, off, unsorted = 0, {}, false
  for _, group in ipairs(Engine.BAR_GROUPS) do
    local entries, bar = plan[group], BAR_OF[group]
    local info = API.barInfo(bar)
    if #entries > 0 and API.barShown(bar) == false then
      off[#off + 1] = ("%s (%d buttons for %s)"):format(info.name, #entries, BAR_TITLE[group]:lower())
    elseif #entries > 0 then
      local placed, moved, already, full = {}, {}, {}, {}
      local function put(e, button, list)
        if not API.placeAction(info.first + button - 1, e) then return false end
        list[#list + 1] = ("%d %s"):format(button, e.label)
        unsorted = unsorted or button ~= e.index
        return true
      end
      if mode == "preview" then
        for _, e in ipairs(entries) do placed[#placed + 1] = ("%d %s"):format(e.index, e.label) end
      else
        local waiting = {}
        for _, e in ipairs(entries) do
          local onBar = C.keys and C.keys[e.item and ("item:" .. e.item) or e.macro and ("macro:" .. e.macro) or e.label] ~= nil
          if mode == "replace" then
            put(e, e.index, placed)
          elseif onBar then
            already[#already + 1] = e.label
          else
            -- with fixed buttons an entry goes to its own button when that is free
            local button = stale(info, e) or (fixed and API.slotEmpty(info.first + e.index - 1) and e.index)
            if button then put(e, button, placed) else waiting[#waiting + 1] = e end
          end
        end
        -- the rest, in the layout's order: the first free button of the bar, so
        -- a gap is filled first and nothing you already use has to move
        for _, e in ipairs(waiting) do
          local free
          for i = 1, 12 do
            if API.slotEmpty(info.first + i - 1) then free = i break end
          end
          if not (free and put(e, free, fixed and moved or placed)) then full[#full + 1] = e.label end
        end
        if mode == "replace" then
          -- an entry that came from another button of this bar would now be on it twice
          local own = {}
          for _, e in ipairs(entries) do own[e.index] = true end
          for i = 1, 12 do
            local had = not own[i] and API.slotContent(info.first + i - 1)
            for _, e in ipairs(had and entries or {}) do
              if sameAction(had, e) then API.clearAction(info.first + i - 1) break end
            end
          end
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
  if mode == "preview" then report("That is the plan. /coach bar fills empty buttons; /coach bar reset makes your bars exactly this.")
  elseif total == 0 and #off == 0 then report("Your bars already have everything.")
  elseif unsorted then report("Nothing you already use was moved, so the order is not the coach's. /coach bar reset sorts all three bars.") end
  if mode ~= "preview" and total > 0 then rescanKeysSoon() end
  return total
end

-- /coach bar reset: makes the three bars exactly the coach's layout: what you
-- can use right now, side by side from button 1 (or each on its fixed button,
-- with the "fixed buttons" setting). Every other button of those bars is emptied. What the bars
-- held before is remembered, so /coach bar undo puts it back. Nothing is lost
-- for good either way: a spell stays in your spellbook, a macro in /macro, an
-- item in your bags.
function C.resetBars()
  local s = C.lastState
  if not (C.profile.bars or C.profile.bar) then say("No bar layout for " .. C.profile.spec .. " yet.") return false end
  if not s then say("Still loading: try again in a moment.") return false end
  if API.inCombat() then say("The action bars can only be changed out of combat.") return false end
  C.syncMacros(false)   -- the layout uses the CC macros
  local plan = C.barPlan(s)
  local backup = { slots = {} }
  local off, lost, failed = {}, 0, {}
  for _, group in ipairs(Engine.BAR_GROUPS) do
    local entries, bar = plan[group], BAR_OF[group]
    local info = API.barInfo(bar)
    if #entries > 0 and API.barShown(bar) == false then
      off[#off + 1] = info.name
    elseif #entries > 0 then
      local wanted = {}
      for _, e in ipairs(entries) do wanted[e.index] = e end
      local set, kept, cleared = 0, 0, 0
      for i = 1, 12 do
        local slot = info.first + i - 1
        local had = API.slotContent(slot)
        backup.slots[slot] = had or false
        local e = wanted[i]
        if e and sameAction(had, e) then
          kept = kept + 1
        elseif e then
          if had and had.other then lost = lost + 1 end
          if API.placeAction(slot, e) then set = set + 1 else failed[#failed + 1] = e.label end
        elseif had then
          if had.other then lost = lost + 1 end
          if API.clearAction(slot) then cleared = cleared + 1 end
        end
      end
      say(("%s, %s: %d set, %d already right, %d emptied."):format(BAR_TITLE[group], info.name, set, kept, cleared))
    end
  end
  if next(backup.slots) then ClassCoachCharDB.barBackup = backup end
  if #failed > 0 then say("Could not be placed: " .. table.concat(failed, ", ") .. ".") end
  if #off > 0 then say("Switched off, so left alone: " .. table.concat(off, ", ") .. ". Turn it on in Esc > Options > Action Bars, then run this again.") end
  if lost > 0 then
    say(("%d button%s held something undo cannot put back (for example a mount): drag %s onto a bar again yourself."):format(lost,
      lost == 1 and "" or "s", lost == 1 and "it" or "those"))
  end
  say("Your bars are now the coach's layout. Changed your mind? /coach bar undo puts back what was there.")
  rescanKeysSoon()
  return true
end

function C.undoBars()
  local backup = ClassCoachCharDB.barBackup
  if type(backup) ~= "table" or type(backup.slots) ~= "table" or not next(backup.slots) then say("There is no bar reset to undo.") return false end
  if API.inCombat() then say("The action bars can only be changed out of combat.") return false end
  local restored, failed = 0, 0
  for slot, had in pairs(backup.slots) do
    if type(slot) == "number" and slot >= 1 and slot <= 180 then
      local now = API.slotContent(slot)
      if had == false then
        if now and API.clearAction(slot) then restored = restored + 1 end
      elseif type(had) == "table" and not had.other and not sameAction(now, had) then
        if API.placeAction(slot, had) then restored = restored + 1 else failed = failed + 1 end
      end
    end
  end
  ClassCoachCharDB.barBackup = nil
  say(("Put back: %d button%s as before the reset.%s"):format(restored, restored == 1 and "" or "s",
    failed > 0 and (" %d could not be put back (a deleted macro, or an item you no longer carry)."):format(failed) or ""))
  rescanKeysSoon()
  return true
end

---------------------------------------------------------------------------
-- The game's action bars: watched, never touched
---------------------------------------------------------------------------
-- ClassCoach does not hide, move or resize the game's bars. When they vanish
-- anyway (another addon, or the game blocking its own interface after an
-- addon interfered), this notices the moment, keeps what it could see, and
-- says so once, with what the game blamed.
local function barLines(state)
  local lines = {}
  for _, b in ipairs(state.bars) do
    lines[#lines + 1] = ("%s: %s"):format(b.name, not b.there and "not found on this client" or b.visible and "on screen" or ("NOT on screen: " .. b.why))
  end
  lines[#lines + 1] = ("in combat %s; main bar page %s; special bar: %s"):format(tostring(state.combat), tostring(state.page),
    #state.flags > 0 and table.concat(state.flags, ", ") or "none")
  local blocked = C.blocked or {}
  lines[#lines + 1] = "the game blocked: " .. (#blocked > 0 and table.concat(blocked, "; ") or "nothing this session")
  return lines
end

function C.watchBars(now)
  if now < (C.nextBarLook or 0) then return end
  C.nextBarLook = now + 1
  if API.plain(API.try(UIParent.IsShown, UIParent)) == false then return end   -- you hid the whole interface yourself (Alt+Z)
  local state = API.barState()
  local main = state.bars[1]
  if not main.there then return end
  if main.visible then
    C.barsSeen = true
    if C.barsGone then
      C.barsGone = nil
      log("action bars back on screen")
    end
  elseif C.barsSeen and not C.barsGone and #state.flags == 0 then
    -- they were there and now are not, and the game shows no special bar (vehicle and the like) in their place
    C.barsGone = state
    C.barsLost = (C.barsLost or 0) + 1
    for _, line in ipairs(barLines(state)) do log("bars gone: %s", line) end
    if not C.barsSaid then
      C.barsSaid = true
      local blamed = C.blocked and C.blocked[#C.blocked]
      say(("Your action bars left the screen (%s). ClassCoach did not do that: it never hides or moves them. %s /reload brings them back. Type /coach bars and send me the lines."):format(
        main.why, blamed and ("The game last blocked: " .. blamed .. ".") or "The game has not blamed any addon yet."))
    end
  end
end

---------------------------------------------------------------------------
-- Mana
---------------------------------------------------------------------------

-- Exact when the game lets us read it; otherwise ClassCoach's own count (Core/Mana.lua).
-- Returns a percentage (or nil) and whether it is exact.
local DRINKS = { ["Drink"] = true, ["Refreshment"] = true, ["Food & Drink"] = true }
local function readMana(now, inCombat)
  local L = C.ledger
  local cur, max = API.mana()
  if max then C.manaMax = max end
  if cur and C.manaMax and C.manaMax > 0 then
    C.lastMana = cur
    Mana.set(L, now, cur, C.manaMax)
    return math.max(0, math.min(100, cur / C.manaMax * 100)), true
  end
  local pct = API.manaPct()
  if pct then
    if C.manaMax then Mana.set(L, now, pct / 100 * C.manaMax, C.manaMax) end
    return pct, true
  end
  if C.manaAt and now - C.manaAt < 0.25 then return C.manaPct, false end
  C.manaAt = now
  L.max = L.max or C.manaMax
  local idle, casting = API.powerRegen()
  local drinking = false
  if not inCombat and C.buffs then
    for name in pairs(DRINKS) do if C.buffs[name] then drinking = true end end
  end
  Mana.tick(L, now, { idle = idle, casting = casting, drinking = drinking })
  local probes = {}
  for _, p in ipairs(C.probes or {}) do
    local _, short = API.usable(p.id)
    if short ~= nil then probes[#probes + 1] = { cost = p.cost, affordable = not short } end
  end
  Mana.fence(L, Mana.bracket(probes))
  C.manaPct = Mana.pct(L)
  return C.manaPct, false
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
  local talents = C.talentState
  j = { at = now, xp = API.xp(), talentPoints = API.unspentTalents(), durability = API.durability(),
    talentsSpent = talents and talents.have and talents.have.spent or nil, professions = API.professions(),
    freeSlots = API.freeBagSlots(), emptyBagSlots = API.emptyBagSlots(), hasItem = API.hasItem, supplies = C.suppliesCache,
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
    usesMana = C.usesMana, manaPct = manaPct, manaExact = exact, manaLevel = C.manaLevel, manaMax = C.manaMax,
    healthPct = (not inCombat) and API.healthPct() or nil, hasPet = hasPet,
    target = currentTarget(), hasWand = C.hasWand, buffs = buffs, mainHandBuff = mainHand,
    keys = C.keys, spells = C.spells, bookReady = next(C.spells) ~= nil, tracker = C.tracker, fightTime = C.tracker:fightTime(now),
    check = { ready = API.ready, usable = API.usable, repeating = API.repeating }, barPage = API.barPage(),
    itemCount = API.itemCount, equipped = API.equipped, faction = C.faction, journey = (not inCombat) and C.journeyData(now) or nil,
    talent = C.talentState,
  })
end

-- What the engine needs to know to talk about professions: the data, your class, and your settings.
function C.professionOptions()
  return { professionData = ns.ProfessionData, professionPicks = ns.ProfessionPicks, class = C.class, goal = ClassCoachDB.professionGoal,
    first = ClassCoachCharDB.professionA, second = ClassCoachCharDB.professionB, secondary = ClassCoachDB.remindSecondary,
    readable = API.professionsReadable }
end
function C.withOptions(options, more)
  for k, v in pairs(more) do options[k] = v end
  return options
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
    inCombat = s.inCombat,
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
  -- The pull plan follows your mana: when it changes between fights (you drank, or
  -- spent mana on a buff), the CC Pull macro and the smart key are loaded again.
  if not s.inCombat and now >= (C.planCheckAt or 0) then
    C.planCheckAt = now + 2
    local plan = planLine(s)
    if not C.planSeen then
      C.planSeen = plan
    elseif plan ~= C.planSeen and plan == C.planNext then   -- the same new plan two checks running
      safely("plan follows mana", C.syncMacros, true)
      safely("plan follows mana", C.syncSmart)   -- also when automatic macro updates are off
      C.planSeen = plan
    end
    C.planNext = plan
  end
  view.next = Engine.next(profile, s)
  local before, after = ns.Panel.steps(ClassCoachDB)
  view.chain = Engine.chain(profile, s, 1 + after)
  view.planning = view.next == nil
  -- The smart key: while you use it, the coach shows the key's own steps
  -- (Engine.followKey), so the two never disagree; it only takes over, with
  -- another key, when the key's step cannot be right.
  local smart = ClassCoachDB.smartKey ~= false and view.chain[1] and ns.Smart.status() or nil
  local tkey = s.target and s.target.exists and s.target.key
  local fresh = not tkey or (#C.tracker:dotsOn(tkey, now) == 0 and #C.tracker:recent(tkey, 1, now, 60) == 0)
  if smart and smart.ready and smart.keys.next and smart.step then
    view.chain, view.followsKey = Engine.followKey(profile, s, view.chain, ns.Smart.steps, smart.step, fresh, 1 + after)
  end
  -- When the ring shows the key's next step, it shows the key's binding.
  local now1 = view.chain[1]
  -- A wand that already fires is left alone: written plain "Shoot", a press would switch it off.
  local stopsWand = now1 and now1.running and smart and smart.nextText and smart.nextText:sub(1, 1) ~= "!"
  if smart and smart.ready and smart.keys.next and smart.nextLabel == now1.label and not stopsWand then
    now1.keybind, now1.viaSmart = smart.keys.next, "next"
  end
  view.drawMana = API.drawMana
  -- What you already did to this enemy, and what is still ticking on it.
  local key = s.target and s.target.key
  view.done, view.dots = {}, {}
  if key then
    local recent = before > 0 and C.tracker:recent(key, before + 1, now, 30) or {}
    -- a wand that is still firing is not done yet: it moves to the left once you cast something else
    local last = recent[#recent]
    if last and Tracker.REPEATS[last.name] then table.remove(recent) end
    if #recent > before then table.remove(recent, 1) end
    for _, c in ipairs(recent) do
      local sp = s.spells[c.name]
      view.done[#view.done + 1] = { label = sp and sp.name or c.name, icon = sp and sp.icon, missed = c.missed,
        left = profile.spells[c.name] and profile.spells[c.name].debuff and C.tracker:debuffLeft(key, c.name, now) or nil }
    end
    for _, d in ipairs(C.tracker:dotsOn(key, now)) do
      local sp = s.spells[d.name]
      view.dots[#view.dots + 1] = { label = sp and sp.name or d.name, icon = sp and sp.icon, left = d.left,
        duration = d.duration, start = now + d.left - d.duration }
    end
    -- in the order you cast them, as the game lines up an enemy's debuffs: an icon keeps its place
    table.sort(view.dots, function(a, b) return a.start < b.start end)
  end
  view.otherDotted = C.tracker:otherDotted(key or "none", now)
  if ns.Trace.recording() then safely("trace", C.traceView, view, s, smart) end
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
      local journey = Engine.journey(profile, s, C.withOptions({ food = db.food, rested = db.remindRested, train = db.remindTrain, gear = db.remindGear,
        supplies = db.remindSupplies, roadmap = db.roadmap, data = ns.JourneyData,
        professions = db.remindProfessions }, C.professionOptions()))
      journey.title = ("Level %d"):format(s.level)
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
  -- A step that is on none of your bars: say where to get it, once nothing more pressing is being said.
  -- (On a bar without a key is fine: its button is lit and can be clicked.)
  local slot = now1 and C.slots and C.slots[now1.label] or nil
  local missingSpell = now1 and not now1.keybind and not slot and not now1.melee and now1.label or nil
  -- ...and it lights up in your spellbook when that is open, ready to drag onto a bar
  local _, book = safely("spellbook", ns.Spellbook.update, ClassCoachDB.showCoach ~= false and missingSpell or nil, ClassCoachDB, s.inCombat)
  if missingSpell and not view.planning and (view.status == nil or view.statusKind == "ok") then
    if book == "lit" then
      view.status = "Drag the lit " .. missingSpell .. " from your spellbook onto an action bar."
    elseif book == "elsewhere" then
      view.status = missingSpell .. " is on another page of your spellbook: turn the pages until it lights up."
    else
      view.status = missingSpell .. " is not on your action bars. Open your spellbook (it lights up there), or type /coach bar."
    end
    view.statusKind = "warn"
  end
  if not s.inCombat then view.restMacro = API.macroExists("CC Rest") and "CC Rest" or nil end
  if C.trouble then view.status, view.statusKind = C.trouble, "warn" end
  safely("bar watch", C.watchBars, now)
  -- ClassCoach's own typefaces: put on or taken off when the setting changes, and tried again for a text that did not take one.
  local ownFonts = ClassCoachDB.ownFonts == true
  if now >= (C.fontsFrom or 0) and (ownFonts ~= (ns.Style.ownFonts == true) or (ownFonts and ns.Style.pending and now >= (C.nextDress or 0))) then
    C.nextDress = now + 2
    safely("fonts", ns.Style.dress, ownFonts)
  end
  C.lastView = view
  if C.demo then
    C.playDemo(now, view)
  else
    local shown = ClassCoachDB.showCoach ~= false
    ns.Panel.render(view)
    -- Before a fight the icons can be clicked; the buttons for that are only touched out of combat.
    safely("click to cast", ns.Click.update, ns.Panel.frame, shown and ns.Panel.clicks or {}, ClassCoachDB)
    -- The button to press now, lit up on your action bars. Not while it is only a plan, and not
    -- for a wand that is already firing: there is nothing to press then.
    safely("bar highlight", ns.BarGlow.update, slot and shown and not view.planning and not now1.running and slot or nil, ClassCoachDB)
  end
  -- The game's talent window: while it is open, keep the mark on the next talent of your build.
  safely("talent marks", function()
    if ClassCoachDB.talentMarks == false or not ns.Talents.open() then ns.Talents.hide() return end
    if C.talentsStale or not C.talentState or now - (C.talentsRead or 0) >= 0.5 then
      C.refreshTalents()
      C.talentsRead, C.talentsStale = now, false
    end
    ns.Talents.update(C.talentState, ClassCoachDB, C.level)
    if ns.Trace.recording() then ns.Trace.change("talents", "%s", ns.Talents.describe()) end
  end)
end

-- /coach demo: plays the coach's states with your own spells, out of combat,
-- so you can see and place it without fighting. It stops by itself when a
-- fight starts.
local function demoViews(real)
  local s = C.lastState
  local plan = s and Engine.plan(C.profile, s, 6) or {}
  local step, wait = {}, nil
  for _, st in ipairs(plan) do
    if st.filler then wait = wait or st elseif #step < 3 then step[#step + 1] = st end
  end
  local a = step[1] or wait
  if not a then return {} end
  local b, c = step[2] or a, step[3] or step[2] or a
  wait = wait or { key = "attack", label = "Attack", icon = "Interface\\Icons\\INV_Sword_04", filler = true, melee = true, why = "Auto attack costs no mana." }
  local function with(st, extra)
    local out = {}
    for k, v in pairs(st) do out[k] = v end
    for k, v in pairs(extra or {}) do out[k] = v end
    return out
  end
  local function did(st, left, missed) return { label = st.label, icon = st.icon, left = left, missed = missed } end
  -- a spell ticking on the enemy, for the icons above the ring
  local function ticking(st, left, lasts) return { label = st.label, icon = st.icon, left = left, duration = lasts, start = GetTime() + left - lasts } end
  local base = { usesMana = real.usesMana, drawMana = false, manaExact = true }
  local function view(fields)
    local v = {}
    for k, v0 in pairs(base) do v[k] = v0 end
    for k, v0 in pairs(fields) do v[k] = v0 end
    return v
  end
  local drink = { text = "Mana 35%", hint = "Drink before the next pull.", icon = "Interface\\Icons\\INV_Drink_07", badge = "35" }
  return {
    { "Before a fight: what to fix first", view({ chain = { a, b, c }, planning = true, manaPct = 35, manaLevel = "medium",
      missing = { drink }, status = drink.hint, statusKind = "warn" }) },
    { "An enemy targeted: how to pull", view({ chain = { with(a, { why = a.why or "Pull with this." }), b, c }, manaPct = 100, manaLevel = "high" }) },
    { "In the fight: next step", view({ inCombat = true, chain = { b, c, wait }, done = { did(a, 22) }, manaPct = 86, manaLevel = "high" }) },
    { "The steady part of a fight", view({ inCombat = true, chain = { wait, with(b, { inSeconds = 6 }) }, done = { did(a, 14), did(b, 6), did(c, 9) },
      dots = { ticking(a, 14, 24), ticking(b, 6, 12), ticking(c, 9, 15) },
      manaPct = 62, manaLevel = "high" }) },
    { "A spell ran out: the ring pulses", view({ inCombat = true, chain = { with(b, { why = b.label .. " ran out: cast it again." }), wait },
      done = { did(a, 8), did(b, 0), did(c, 3) }, manaPct = 48, manaLevel = "medium" }) },
    { "A spell was resisted", view({ inCombat = true, chain = { with(c, { retry = true, why = c.label .. " was resisted. Cast it again." }), wait },
      done = { did(a, 5), did(b, 12), did(c, nil, "miss") }, manaPct = 40, manaLevel = "medium" }) },
    { "Low mana: the advice changes", view({ inCombat = true, chain = { wait }, done = { did(b, 9), did(c, 4) }, manaPct = 14, manaLevel = "low",
      status = "Mana is low: stop casting and finish with " .. wait.label .. ".", statusKind = "warn" }) },
  }
end

function C.toggleDemo()
  if C.demo then
    C.demo = nil
    ns.Panel.showHint(false)
    say("Demo stopped.")
    return false
  end
  if API.inCombat() then say("The demo only plays out of combat.") return false end
  C.demo = { step = 0, untilTime = 0 }
  say("Demo: the coach plays its states with your own spells. Type /coach demo again to stop.")
  return true
end

-- One refresh of the demo. Leaves the bar highlight and the click buttons alone: nothing in it is real.
function C.playDemo(now, real)
  local demo = C.demo
  if real.inCombat then
    C.demo = nil
    ns.Panel.showHint(false)
    ns.Panel.render(real)
    return
  end
  if now >= demo.untilTime then
    demo.views = demo.views or demoViews(real)
    if #demo.views == 0 then
      C.demo = nil
      ns.Panel.showHint(false)
      say("Demo: no spells to show yet.")
      ns.Panel.render(real)
      return
    end
    demo.step = demo.step % #demo.views + 1
    demo.untilTime = now + 3.5
    ns.Panel.flash({ ("Demo %d of %d: %s"):format(demo.step, #demo.views, demo.views[demo.step][1]) }, 3.4)
  end
  ns.BarGlow.hide()
  safely("click to cast", ns.Click.update, ns.Panel.frame, {}, ClassCoachDB)
  ns.Panel.showHint(true)
  ns.Panel.render(demo.views[demo.step][2])
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
  local fast = (C.tracker and C.tracker.fight ~= nil) or C.demo ~= nil
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

-- A spell with a cast time lands on the enemy it was started on, also when you
-- pick another one before it lands: remember who that was.
function handlers.UNIT_SPELLCAST_START(unit, _, spellID)
  if API.plain(unit) ~= "player" then return end
  local id = API.plain(spellID)
  if not id then return end
  C.castStart = { id = id, key = currentTarget().key, at = GetTime() }
  API.noteCast(GetTime())
  ns.Trace.add("start", "%s on %s", tostring(castKey(id)), ns.Trace.unit("target"))
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
  if API.plain(unit) ~= "player" then return end
  local id = API.plain(spellID)
  if not id then return end
  API.noteCast(GetTime())
  local key = castKey(id)
  if not key then return end
  local cost = C.costById[id]
  if cost == nil then cost = API.cost(id); C.costById[id] = cost or false end
  local meta = C.profile.spells[key]
  if meta and meta.summons then ClassCoachCharDB.demon = meta.summons end
  local t = currentTarget()
  local onKey = t.key
  local started = C.castStart
  if started and started.id == id and GetTime() - started.at < 10 then onKey = started.key end
  C.castStart = nil
  local sp = C.spells[key]
  -- Out of combat the next exact reading may come after combat starts: keep our own count right.
  if not C.tracker.fight and C.lastMana and cost and cost > 0 then C.lastMana = math.max(0, C.lastMana - cost) end
  Mana.spend(C.ledger, GetTime(), cost or 0, meta and meta.restores and C.manaMax and meta.restores * C.manaMax or 0)
  C.tracker:cast(GetTime(), key, cost or 0, meta, onKey, sp and sp.duration)
  ns.Trace.add("cast", "%s on %s%s, cost %s, recorded on %s", key, ns.Trace.unit("target"), onKey ~= t.key and " (started on the one before)" or "",
    tostring(cost), onKey and (onKey == t.key and "this enemy" or "the enemy it started on") or "no enemy")
end

-- The game reports "something was resisted on your target" without saying
-- what. Right after one of your harmful casts it is that cast: undo it, so the
-- coach asks for it again (or skips it on an immune enemy).
local SPELL_FAILS = { RESIST = "resist", IMMUNE = "immune", EVADE = "resist", REFLECT = "resist", DEFLECT = "resist" }
function handlers.UNIT_COMBAT(unit, action)
  if API.plain(unit) ~= "target" then return end
  local kind = SPELL_FAILS[API.plain(action) or ""]
  if not kind then return end
  local c = C.tracker:castMissed(GetTime(), kind == "immune", currentTarget().key)
  ns.Trace.add("miss", "%s: %s", kind, c and c.name or "no cast of yours matched")
  C.stats = C.stats or { resists = 0, unmatched = 0 }
  if c then C.stats.resists = C.stats.resists + 1 else C.stats.unmatched = C.stats.unmatched + 1 end
end

function handlers.PLAYER_TARGET_CHANGED()
  API.targetChanged()
  C.targetKey = nil
  ns.Trace.add("target", "%s", ns.Trace.unit("target"))
  -- a new target between fights: the smart key starts from the beginning
  if not API.inCombat() then safely("smart key", ns.Smart.restart) end
end
-- Enemies told apart by nameplate: keep your target's key while it stays your
-- target, so a plate that hides and comes back never forgets its timers. Only a
-- key from the fallback count is looked at again (its plate may just have appeared).
function handlers.NAME_PLATE_UNIT_ADDED(token)
  API.plateAdded(token)
  if C.targetMode == "count" then C.targetKey = nil end
end
function handlers.NAME_PLATE_UNIT_REMOVED()
  if C.targetMode == "count" then C.targetKey = nil end
end

function handlers.PLAYER_SWING()
  C.tracker:swing()
end

function handlers.PLAYER_REGEN_DISABLED()
  safely("settings window", ns.Window.combat, true)
  local t = API.target()
  C.petAtPull = C.lastState and C.lastState.hasPet
  C.demonAtPull = C.lastState and C.lastState.demon
  C.tracker:startFight(GetTime(), {
    target = t.hostile and t.name or nil, targetLevel = t.level, elite = t.elite,
    manaStart = C.lastMana, manaMax = C.manaMax, hasPet = C.petAtPull, demon = C.demonAtPull,
  })
  local pct = C.lastState and tonumber(C.lastState.manaPct)
  ns.Trace.add("fight", "started on %s, mana %s, demon %s", ns.Trace.unit("target"), pct and ("%.0f%%"):format(pct) or "?", tostring(C.demonAtPull))
end

-- One line for the trace when what the coach shows changed: the ring, what comes
-- next, where the smart key is, mana and the timers on this enemy.
function C.traceView(view, s, smart)
  local function step(st)
    if not st then return "-" end
    return st.label .. (st.inSeconds and (" in %.0fs"):format(st.inSeconds) or "") .. (st.running and " (firing)" or "")
  end
  local nexts = {}
  for i = 2, #(view.chain or {}) do nexts[#nexts + 1] = step(view.chain[i]) end
  local dots = {}
  for _, d in ipairs(view.dots or {}) do dots[#dots + 1] = ("%s %.0fs"):format(d.label, d.left) end
  local keyText = "no smart key"
  if smart and smart.ready then
    keyText = ("key step %s %s%s"):format(tostring(smart.step), tostring(smart.nextLabel), view.followsKey and " (ring follows it)" or " (coach decides)")
  end
  ns.Trace.change("ring", "%s %s | next %s | %s | mana %s %s | on enemy: %s | %s",
    view.inCombat and "fight" or (view.planning and "plan" or "pull"), step(view.chain and view.chain[1]), table.concat(nexts, " > "), keyText,
    s.manaPct and ("%.0f%%"):format(s.manaPct) or "?", tostring(s.manaLevel), #dots > 0 and table.concat(dots, ", ") or "nothing",
    tostring(view.status or ""))
end

local function finishFight()
  local cur, max = API.mana()
  local summary = C.tracker:endFight(GetTime(), cur, max)
  ns.Trace.add("fight", "ended%s", summary and (", %.0fs, %d casts"):format(tonumber(summary.duration) or 0, type(summary.casts) == "table" and #summary.casts or 0) or "")
  if not summary or summary.duration < 3 then return end
  -- Learn how long your kills take: it decides when a new damage-over-time spell is wasted.
  -- Only fights against one enemy: with more, the time per enemy comes out far too short.
  if not summary.elite and not API.inGroup() and summary.duration < 120 and summary.targets == 1 then
    local kill = ClassCoachCharDB.kill or { avg = 0, n = 0, v = 2 }
    -- the middle one of your last few kills: one odd fight (a runner, a mob someone
    -- else hit first) moves it little
    local recent = type(kill.recent) == "table" and kill.recent or {}
    recent[#recent + 1] = summary.duration
    while #recent > KILL_KEEP do table.remove(recent, 1) end
    local sorted = {}
    for i, d in ipairs(recent) do sorted[i] = d end
    table.sort(sorted)
    kill.recent, kill.v = recent, 2
    kill.avg = sorted[math.floor((#sorted + 1) / 2)]
    kill.n = (kill.n or 0) + 1
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
  safely("settings window", ns.Window.combat, false)
  safely("smart key", ns.Smart.restart)   -- the next pull starts from the beginning
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
  safely("talents", C.refreshTalents)
  local state = C.talentState
  local lines = Engine.levelUp(C.profile, level, state and state.plan.readable and Engine.nextTalent(state.plan) or nil)
  ns.Panel.flash(lines, 25)
  for _, l in ipairs(lines) do say(l) end
  -- the talent to take, as a card at the top of the screen
  if state and state.plan.readable then
    -- the point may not be counted yet when the level-up arrives: a level-up from 10 on brings one
    local unspent = API.unspentTalents()
    unspent = math.max(type(unspent) == "number" and unspent or 1, 1)
    safely("talent toast", ns.Talents.toast, Engine.talentSchedule(state.plan, level, 1, unspent)[1], ClassCoachDB, level)
  end
  rescanSoon()
end

-- "Learn now" on the talent card or the toast: say how it went; the marks move on by themselves.
ns.Talents.onLearn = function(result, why)
  if result == "learned" then
    say("Talent learned. The talent window now marks the next one.")
  elseif why then
    say(why)
  end
  C.talentsStale = true
end

function handlers.UNIT_AURA(unit)
  if API.plain(unit) == "player" then C.aurasDirty = true end
end

local function talentsChanged()
  chooseProfile()
  C.talentsStale = true
  C.journey = nil
  rescanSoon()
end

for _, e in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" }) do
  handlers[e] = function() rescanSoon() end
end
-- These fire in bursts (every step of a sequence macro changes a button): keys only.
for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "UPDATE_MACROS" }) do
  handlers[e] = rescanKeysSoon
end
for _, e in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
  handlers[e] = talentsChanged
end

local function start()
  ClassCoachDB = ClassCoachDB or {}
  ClassCoachCharDB = ClassCoachCharDB or {}
  -- Kill times learned before 0.15.3 counted a fight against three enemies as three
  -- quick kills (and kept them in a running average): far too short, so the coach
  -- dropped Immolate from the pull. Start over.
  if type(ClassCoachCharDB.kill) == "table" and ClassCoachCharDB.kill.v ~= 2 then ClassCoachCharDB.kill = nil end
  local db = ClassCoachDB
  -- settings saved by older versions
  if db.hidden ~= nil then db.showCoach = not db.hidden; db.hidden = nil end
  if not db.ringLook then      -- the ring replaced the wide panel: its plate is lighter, and it has no border or colour line
    db.ringLook = true
    if db.opacity == 75 then db.opacity = 60 end
    db.border, db.accent = nil, nil
  end
  if db.showDone ~= nil then   -- "show what you already cast" became a number of steps
    if db.showDone == false and db.stepsBefore == nil then db.stepsBefore = 0 end
    db.showDone = nil
  end
  if ClassCoachCharDB.spec ~= nil then ClassCoachCharDB.specChoice = ClassCoachCharDB.spec; ClassCoachCharDB.spec = nil end
  if ClassCoachCharDB.specChoice == nil then ClassCoachCharDB.specChoice = "auto" end
  for k, v in pairs(ns.Options.defaults()) do if db[k] == nil then db[k] = v end end
  ns.Options.sanitize(db, ClassCoachCharDB)
  for _, problem in ipairs(Profiles.problems or {}) do log("%s", problem) end
  C.tracker = Tracker.new()
  C.ledger = Mana.ledger()
  C.level = API.level()
  C.faction = API.faction()
  chooseProfile()
  local ok, err = pcall(rescan)
  if not ok then log("first scan error: %s", tostring(err)) end
  local mana, max = API.mana()
  C.lastMana, C.manaMax = mana, max
  ClassCoachDB.gameFont = nil   -- 0.13.0's setting; the game's font is now the default
  C.fontsFrom = GetTime() + 3   -- ClassCoach's typefaces go on a few seconds after login, never while the addon loads
  ns.Panel.create(ClassCoachCharDB, ClassCoachDB)
  ns.Journey.create(ClassCoachCharDB, ClassCoachDB)
  C.optionsReady = ns.Options.build(ClassCoachDB, ClassCoachCharDB, {
    macros = function() SlashCmdList.CLASSCOACH("macros") end,
    reset = function() SlashCmdList.CLASSCOACH("reset") end,
    bar = function() SlashCmdList.CLASSCOACH("bar") end,
    barReset = function() SlashCmdList.CLASSCOACH("bar reset") end,
    window = function() safely("settings window", ns.Window.show, "Coach") end,
  })
  -- The debug trace: asks once, then records on this computer if you said yes (UI/Trace.lua)
  C_Timer.After(4, function()
    safely("trace", ns.Trace.onLogin, { version = API.addonVersion(),
      who = ("%s %s level %s"):format(C.profile and C.profile.spec or "?", C.class or "?", tostring(C.level)) })
  end)
  -- The first time: the setup page of the settings window, once, out of combat.
  if not db.welcomed then
    C_Timer.After(6, function()
      if db.welcomed or API.inCombat() then return end
      db.welcomed = true
      safely("settings window", ns.Window.show, "start")
    end)
  end
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
      if e == "UNIT_SPELLCAST_SUCCEEDED" or e == "UNIT_SPELLCAST_START" or e == "UNIT_AURA" then
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
  add("%s", ns.Talents.describe())
  local have = API.talents()
  add("talents read by name: %s; talent window found: %s; build: %s", have and (#have.list .. " (" .. have.spent .. " points spent)") or "none",
    tostring(ns.Talents.window() ~= nil), C.talentState and C.talentState.build.name or "none")
  local profs = {}
  for _, p in ipairs(API.professions() or {}) do profs[#profs + 1] = ("%s %s/%s"):format(p.name, tostring(p.skill), tostring(p.max)) end
  add("professions: %s", #profs > 0 and table.concat(profs, ", ") or "none read")
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
  add("smart key: button %s, %s steps, at step %s (%s), key %s, wand written as %s", tostring(ns.Smart.button ~= nil), st.count,
    tostring(st.step), tostring(st.nextLabel), tostring(st.keys.next), tostring(API.shootText()))
  add("global cooldown readable: %s", tostring(API.gcdReadable()))
  for _, line in ipairs(barLines(API.barState())) do add("bars: %s", line) end
  add("bars seen to leave the screen this session: %d", C.barsLost or 0)
  local clicks = ns.Click.describe()
  add("click to cast: buttons made %s%s; clickable now: %s", tostring(ns.Click.holder ~= nil), ns.Click.error and (" (" .. ns.Click.error .. ")") or "",
    #clicks > 0 and table.concat(clicks, ", ") or "nothing")
  add("bar highlight: style %s, on slot %s; cues played %s", tostring(ClassCoachDB.barGlow), tostring(ns.BarGlow.slot), tostring(ns.Panel.cues or 0))
  add("fonts: %s", not ns.Style.ownFonts and "the game's own (ClassCoach's typefaces are off: /coach set ownFonts on)"
    or ("ClassCoach's own on %d texts, the game's on %d; last refused: %s; put back because they drew nothing: %d"):format(ns.Style.dressed or 0,
      ns.Style.plain or 0, tostring(ns.Style.fontMissing or "none"), ns.Style.healed or 0))
  local pf, jf = ns.Panel.frame, ns.Journey.frame
  if pf and jf then
    for _, t in ipairs({ { "name", pf.name }, { "why", pf.why }, { "next key", pf.upcoming[1].key.text }, { "list line", jf.rows[1].label }, { "list hint", jf.hint } }) do
      add("  text %s: %s", t[1], ns.Style.describe(t[2]))
    end
  end
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
  "/coach — the settings window (/coach setup: the first-time setup; /coach share: your settings as one line)",
  "/coach set — change a setting from chat",
  "/coach pages — stop Shift+number from switching your main bar to an empty page",
  "/coach macros — create or refresh this class's helper macros (out of combat)",
  "/coach bar — lay out three bars by purpose: fight (main bar), react (Action Bar 2), prepare (Action Bar 3). Empty buttons only; \"preview\" just lists, \"replace\" overwrites",
  "/coach bar reset — make those three bars exactly the coach's layout: what you can use, side by side without gaps, and every other button emptied. /coach bar undo puts back what was there",
  "/coach bars — what ClassCoach can see of the game's action bars, for when they vanish",
  "/coach tips — ten preparation habits from Forever guides",
  "/coach build — the talent build you follow; paste an Icy Veins or Warcraft Tavern calculator link after it to follow that one",
  "/coach professions — which two professions suit your class and goal, and what to do next in each",
  "/coach fonts — a test card for ClassCoach's own typefaces: which sizes and uses this client draws",
  "/coach demo — play the coach's states with your own spells, out of combat, to see and place it",
  "/coach smart — the smart key: one key that walks the coach's plan (shows its steps and keys)",
  "/coach last — repeat the last fight report",
  "/coach reset — put both panels back where they started",
  "/coach hide | show — the coach panel",
  "/coach errors — problems the addon caught itself (for bug reports)",
  "/coach check — what the addon can read on this client (for bug reports)",
  "/coach trace — the debug trace kept on this computer, if you allowed it (export, clear, consent)",
}

-- The settings are ClassCoach's own window (UI/Window.lua). The addon never
-- opens the game's Settings window itself: an addon showing one of the game's
-- panels is a known way to make protected frames (action bars, the pet bar)
-- misbehave in combat. The game's page (Esc > Options > AddOns) is there too.
local function openSettings(page)
  safely("settings window", ns.Window.toggle, page)
end

-- The minimap's addon menu (the client looks these up by name)
function ClassCoach_OnAddonCompartmentClick() safely("addon menu", openSettings) end
function ClassCoach_OnAddonCompartmentEnter(_, button)
  safely("addon menu", function()
    if not GameTooltip or not button then return end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("ClassCoach", 1, 0.82, 0.2)
    GameTooltip:AddLine("Click for the settings. /coach help lists the commands.", 0.9, 0.9, 0.9)
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
  elseif cmd == "help" or cmd == "?" then
    for _, l in ipairs(HELP) do print("  " .. l) end
  elseif cmd == "setup" or cmd == "start" then
    safely("settings window", ns.Window.show, "start")
  elseif cmd == "share" then
    safely("settings window", ns.Window.show, "share")
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
        -- a setting with a list: take the value or its name, whatever the capitals
        local picked, names = nil, {}
        for _, choice in ipairs(option.choices()) do
          names[#names + 1] = choice[1]
          if choice[1]:lower() == v or choice[2]:lower() == v then picked = choice[1] end
        end
        if picked then store[option.key] = picked else say("Choose one of: " .. table.concat(names, ", ") .. ".") end
      end
      say(("%s = %s"):format(option.name, tostring(store[option.key])))
      safely("settings window", ns.Window.refresh)
    end
  elseif cmd == "trace" then
    ns.Trace.command(arg)
  elseif cmd == "talents" then
    -- what the marks on the talent window found, and anything that went wrong drawing them
    say(ns.Talents.describe())
    for _, line in ipairs(ClassCoachDB.log or {}) do
      if line:lower():find("talent", 1, true) then print("  " .. line) end
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
  elseif cmd == "build" then
    -- which talent build to follow: a number from the list, "auto", or a calculator link
    local list = buildsFor(C.profile)
    local wanted = arg:lower()
    if arg:find("://", 1, true) or arg:find("talent%-calculator") then
      local order, site = Engine.decodeBuild(arg, C.class, ns.TalentLinks)
      if not order then say(site) return end
      ClassCoachCharDB.buildLink, ClassCoachCharDB.build = arg, "custom"
      C.customBuild = nil
      say(("Following your %s link: %d talent points."):format(site, #order))
    elseif wanted == "auto" then
      ClassCoachCharDB.build = "auto"
    elseif wanted == "mine" or wanted == "custom" then
      if not customBuild() then say("You have not pasted a link yet. Type /coach build and the link.") return end
      ClassCoachCharDB.build = "custom"
    elseif tonumber(wanted) then
      if not list[tonumber(wanted)] then say("There is no build number " .. wanted .. ". Type /coach build to see the list.") return end
      ClassCoachCharDB.build = tonumber(wanted)
    elseif wanted ~= "" then
      say("Type /coach build to see the list, /coach build 2 to pick one, /coach build auto, or /coach build and a calculator link.")
      return
    end
    C.journey = nil
    local state = C.refreshTalents()
    if not state then
      say("No talent build for this class yet. Paste one: /coach build and an Icy Veins or Warcraft Tavern talent calculator link.")
      return
    end
    for i, b in ipairs(list) do
      print(("  %d. %s%s"):format(i, b.name, b == state.build and "   <- you follow this one" or ""))
    end
    local mine = customBuild()
    if mine then print(("  mine. %s%s"):format(mine.name, mine == state.build and "   <- you follow this one" or "")) end
    local plan = state.plan
    if state.how == "auto" then print("  Picked automatically: the build that fits the talents you already have.") end
    if not plan.readable then
      print("  The game did not give your talents, so I cannot tell where you are in it.")
    else
      local nextUp = Engine.nextTalent(plan)
      print(("  %d of %d points taken. %s"):format(plan.taken, #plan.steps, nextUp and ("Next: " .. nextUp .. ".") or "The build is complete."))
      if plan.extra > 0 then
        local names = {}
        for _, off in ipairs(plan.offPlan) do names[#names + 1] = ("%s x%d"):format(off.name, off.extra) end
        print(("  Outside this build: %s."):format(table.concat(names, ", ")))
      end
      if plan.ahead > 0 then print(("  %d point%s you took earlier than this build does."):format(plan.ahead, plan.ahead == 1 and "" or "s")) end
      if #plan.unknown > 0 then print("  Not in your talent window: " .. table.concat(plan.unknown, ", ") .. ".") end
    end
    print("  Open your talents (N): the next talent has a gold frame.")
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
    if mode == "reset" then C.resetBars()
    elseif mode == "undo" then C.undoBars()
    else C.setupBar((mode == "replace" or mode == "preview") and mode or nil) end
  elseif cmd == "bars" then
    say("The game's action bars, as ClassCoach sees them (it only looks, it never changes them):")
    for _, line in ipairs(barLines(API.barState())) do print("  " .. line) end
    print(("  seen to leave the screen this session: %d time%s"):format(C.barsLost or 0, (C.barsLost or 0) == 1 and "" or "s"))
    if C.barsGone then for _, line in ipairs(barLines(C.barsGone)) do print("  when they went: " .. line) end end
  elseif cmd == "tips" then
    say("Habits that Forever guides agree on:")
    for i, tip in ipairs(ns.JourneyData.tips or {}) do print(("  %d. %s"):format(i, tip)) end
  elseif cmd == "smart" then
    local what, key = arg:match("^(%S+)%s+(%S+)$")
    if not what and arg:match("^%S+$") then what, key = "next", arg end   -- /coach smart 1
    if API.inCombat() then say("The smart key can only be set up out of combat.") return end
    C.smartWanted = true
    C.syncMacros(false)   -- it uses a few CC macros (wand, demon, attack)
    if not C.syncSmart() then say("The smart key could not be set up on this client. /coach check shows why.") return end
    if what then
      -- a key can do one thing: say what it did before, so a bar button losing its key is no surprise
      local before = API.plain(API.try(GetBindingAction, key:upper()))
      if ns.Smart.bind(what:lower(), key:upper()) then
        say(("Smart key: %s is now on %s."):format(what:lower(), key:upper()))
        if type(before) == "string" and before ~= "" and not before:find("ClassCoachSmartButton", 1, true) then
          say(("%s used to be \"%s\". That no longer has this key; give it another under Esc > Options > Keybindings."):format(key:upper(), before))
        end
      else say("Use: /coach smart 1   (the key you want)") end
    end
    local st = ns.Smart.status()
    local steps = ns.Smart.describe()
    if #steps == 0 then
      say("There is no plan to put on the smart key yet for this class and level.")
      return
    end
    say("Smart key steps: " .. table.concat(steps, ", ") .. ".")
    say("It only moves on when a spell really went off: out of range or not ready, press it again. It starts over on a new target and after a fight.")
    say(("Key: %s."):format(st.keys.next or "not bound"))
    if not st.keys.next then
      say("Bind it in Esc > Options > Keybindings > AddOns > ClassCoach, or type /coach smart 1.")
    end
  elseif cmd == "professions" or cmd == "profession" or cmd == "prof" then
    local who = C.profile.class == "ANY" and (C.class or "character") or (C.profile.spec .. " " .. C.profile.class:sub(1, 1) .. C.profile.class:sub(2):lower())
    local lines = Engine.professionReport(API.professions(), who, C.professionOptions())
    say(lines[1])
    for i = 2, #lines do print(lines[i]) end
  elseif cmd == "fonts" then
    local lines = ns.Style.probe()
    if #lines > 0 then say("Font test card shown at the top of the screen. Its results:") end
    for _, line in ipairs(lines) do print("  " .. line) end
  elseif cmd == "demo" then C.toggleDemo()
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
