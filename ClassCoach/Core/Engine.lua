-- The coach's decisions: what to press next, what is missing before a pull,
-- live mana advice, the after-fight report and level-up tips.
--
-- The engine only reads a "state" table (see Engine.newState) and a profile.
-- It never calls the game itself, so it can be tested outside the game.
local _, ns = ...

local Engine = {}
ns.Engine = Engine

---------------------------------------------------------------------------
-- State: one picture of the moment, with helper methods for profiles
---------------------------------------------------------------------------

local State = {}
State.__index = State

-- fields: meta (the profile's spell table), killTime (average seconds per kill, or nil), demon,
-- level, now, inCombat, inGroup, usesMana, manaPct, manaExact,
-- manaLevel, healthPct (nil in combat), hasPet, target, hasWand, buffs (set or nil), mainHandBuff, keys,
-- spells (resolved by key), tracker, fightTime, check (ready/usable functions)
function Engine.newState(fields)
  return setmetatable(fields, State)
end

function State:spell(key) return self.spells[key] end
function State:known(key) return self.spells[key] ~= nil end

-- true / false / nil (unknown). Unknown is treated as "probably fine".
function State:ready(key)
  local sp = self.spells[key]
  if not sp then return false end
  return self.check.ready(sp.id)
end

function State:usable(key)
  local sp = self.spells[key]
  if not sp then return false end
  local usable, short = self.check.usable(sp.id)
  if short == true then return false end
  return usable
end

-- Seconds left on your damage-over-time spell on the current enemy (0 = gone).
function State:debuffLeft(key)
  return self.tracker:debuffLeft(self.target and self.target.key, key, self.now)
end

function State:debuffUp(key)
  return self:debuffLeft(key) > 0
end

-- This enemy cannot be affected by that spell (the game said "immune").
function State:immune(key)
  return self.tracker:isImmune(self.target and self.target.key, key)
end

-- Your last cast on this enemy that was resisted, while it is still news.
function State:justMissed()
  local m = self.tracker.lastMiss
  if m and m.target == (self.target and self.target.key or "target") and self.now - m.at <= 8 then return m end
end

-- Seconds since you first hit the current enemy this fight.
function State:timeOnTarget()
  return self.tracker:timeOnTarget(self.target and self.target.key, self.now)
end

function State:duration(key)
  local sp, meta = self.spells[key], self.meta and self.meta[key]
  return (sp and sp.duration) or (meta and meta.debuff) or nil
end

-- Is a new damage-over-time spell still worth its mana on this enemy?
-- The enemy's health is hidden, so we go by how long your recent kills took
-- (killTime). Unknown, elite or in a group: always yes.
function State:worthDot(key)
  local lasts = self:duration(key)
  if not lasts or not self.killTime or not self.inCombat then return true end
  if self.inGroup or (self.target and self.target.elite) then return true end
  return self.killTime - self:timeOnTarget() >= lasts * 0.4
end

function State:totemUp(element)
  return self.tracker:totemUp(element, self.now)
end

function State:sinceCast(key)
  return self.tracker:sinceCast(key, self.now)
end

function State:castsOnTarget(key)
  return self.tracker:castsOnTarget(self.target and self.target.key, key)
end

-- Buff check by profile spell key or plain name. nil when buffs can't be read.
function State:buff(keyOrName)
  if not self.buffs then return nil end
  local sp = self.spells[keyOrName]
  local name = sp and sp.name or keyOrName
  return self.buffs[name] == true or self.buffs[keyOrName] == true
end

-- The names of the spells in `keys` you know, e.g. "Corruption and Immolate".
function State:have(keys)
  local names = {}
  for _, k in ipairs(keys) do
    local sp = self.spells[k]
    if sp then names[#names + 1] = sp.name end
  end
  if #names == 0 then return nil end
  if #names == 1 then return names[1] end
  return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

function State:manaAtLeast(level)
  if level == nil or level == "any" then return true end
  if not self.usesMana then return true end
  local order = { low = 1, medium = 2, high = 3 }
  return (order[self.manaLevel] or 3) >= (order[level] or 1)
end

---------------------------------------------------------------------------
-- What to press next
---------------------------------------------------------------------------

local ATTACK_ICON = "Interface\\Icons\\INV_Sword_04"

-- Profile texts may be a string or a function(s) returning one.
local function text(v, s)
  if type(v) == "function" then
    local fine, result = pcall(v, s)
    return fine and result or nil
  end
  return v
end
Engine.text = text

-- The spell behind an entry when it is known, ready, affordable and allowed.
local function allowed(entry, s)
  local sp = s.spells[entry.spell]
  if not sp then return nil end
  if entry.minLevel and s.level < entry.minLevel then return nil end
  if entry.maxLevel and s.level > entry.maxLevel then return nil end
  if not s:manaAtLeast(entry.mana) then return nil end
  if s:immune(entry.spell) then return nil end
  -- A spell that repeats by itself (your wand) reads as "on cooldown" while it
  -- is firing. That is it working, not a reason to stop suggesting it.
  local repeats = s.meta and s.meta[entry.spell] and s.meta[entry.spell].auto
  if not repeats and (s:ready(entry.spell) == false or s:usable(entry.spell) == false) then return nil end
  if entry.when then
    local fine, result = pcall(entry.when, s)
    if not (fine and result) then return nil end
  end
  local meta = s.meta and s.meta[entry.spell]
  if meta and meta.debuff and not entry.always and not s:worthDot(entry.spell) then
    s.skippedDot = true
    return nil
  end
  return sp
end

local function step(entry, sp, s)
  local out = { key = entry.spell, label = sp.name, icon = sp.icon, keybind = s.keys and s.keys[sp.name],
    why = text(entry.why, s) }
  if s.check and s.check.repeating and s.meta and s.meta[entry.spell] and s.meta[entry.spell].auto
    and s.check.repeating(sp.id) == true then
    out.running = true
    out.why = "Firing. Leave it running until something else comes up."
  end
  return out
end

local function pick(list, s)
  for _, entry in ipairs(list) do
    local sp = allowed(entry, s)
    if sp then return step(entry, sp, s) end
  end
end

local function filler(profile, s)
  for _, f in ipairs(profile.filler or {}) do
    if f.spell then
      local sp = allowed(f, s)
      if sp then
        local out = step(f, sp, s)
        out.filler = true
        return out
      end
    else
      local fine, ok = true, true
      if f.when then fine, ok = pcall(f.when, s) end
      if fine and ok then
        return { key = "attack", label = f.label or "Melee", icon = f.icon or ATTACK_ICON, why = text(f.why, s),
          filler = true, melee = true }
      end
    end
  end
  return { key = "attack", label = "Melee", icon = ATTACK_ICON, why = "Auto attack costs no mana.", filler = true, melee = true }
end

local function opening(profile, s)
  local open = pick(profile.opener, s)
  if open then
    open.why = open.why or "Pull with this."
    return open
  end
  local f = filler(profile, s)
  if f.melee then f.why = "Walk in and attack." end
  return f
end

-- In combat: the priority list. Out of combat with an enemy targeted: the opener.
function Engine.next(profile, s)
  if s.inCombat then
    local step = pick(profile.priority, s) or filler(profile, s)
    -- The cast before this one was resisted and the coach wants it again: say so.
    local missed = s:justMissed()
    if missed and not missed.immune and step.key == missed.name then
      step.retry = true
      step.why = step.label .. " was resisted. Cast it again."
    end
    return step
  end
  if s.target and s.target.exists and s.target.hostile and not s.target.dead then
    return opening(profile, s)
  end
  return nil
end

---------------------------------------------------------------------------
-- The chain: what follows, assuming you press each step
---------------------------------------------------------------------------

local STEP = 1.5   -- seconds one press takes (the global cooldown)

local Sim = {}
function Sim:pressed(key)
  local meta = self.profile.spells[key]
  self.virtual[key] = (self.virtual[key] or 0) + 1
  self.virtualAt[key] = self.now
  if meta and meta.totem then self.virtualTotems[meta.totem] = true end
  if meta and meta.cd then self.virtualCd[meta.cd == true and key or meta.cd] = true end
  self:advance(STEP)
end
function Sim:advance(seconds)
  self.now = self.now + seconds
  self.fightTime = self.fightTime + seconds
end
function Sim:debuffLeft(key)
  local at, lasts = self.virtualAt[key], self:duration(key)
  if at and lasts then return math.max(0, at + lasts - self.now) end
  return State.debuffLeft(self, key)
end
function Sim:timeOnTarget()
  local real = self.base:timeOnTarget()
  return real + (self.now - self.base.now)
end
function Sim:totemUp(element)
  if self.virtualTotems[element] then return true end
  return State.totemUp(self, element)
end
function Sim:sinceCast(key)
  if self.virtualAt[key] then return self.now - self.virtualAt[key] end
  return State.sinceCast(self, key)
end
function Sim:castsOnTarget(key)
  return self.base:castsOnTarget(key) + (self.virtual[key] or 0)
end
function Sim:ready(key)
  local meta = self.profile.spells[key]
  if meta and meta.cd and self.virtualCd[meta.cd == true and key or meta.cd] then return false end
  return self.base:ready(key)
end

local function simulate(profile, s)
  local sim = { base = s, profile = profile, virtual = {}, virtualAt = {}, virtualTotems = {}, virtualCd = {},
    now = s.now, inCombat = true, fightTime = s.inCombat and (s.fightTime or 0) or 0 }
  return setmetatable(sim, { __index = function(_, k)
    local own = Sim[k]
    if own ~= nil then return own end
    return s[k]
  end })
end

-- When the filler is all that is left: the next moment something better
-- comes up again (a damage-over-time spell running out).
local function later(profile, s, sim)
  local times = {}
  for _, d in ipairs(s.tracker:dotsOn(s.target and s.target.key, sim.now)) do
    if not sim.virtualAt[d.name] then times[#times + 1] = sim.now + d.left end
  end
  for key, at in pairs(sim.virtualAt) do
    local lasts = sim:duration(key)
    if lasts and at + lasts > sim.now then times[#times + 1] = at + lasts end
  end
  table.sort(times)
  for _, t in ipairs(times) do
    sim:advance(t + 0.1 - sim.now)
    local found = pick(profile.priority, sim)
    if found then
      found.inSeconds = t - s.now
      return found
    end
  end
end

-- Up to `max` steps. Step 1 is what Engine.next shows; with nothing targeted
-- out of combat it is the plan for your next pull. A step with `inSeconds`
-- is not due yet: it comes up again in that many seconds.
function Engine.chain(profile, s, max)
  max = max or 3
  local steps = {}
  local first = Engine.next(profile, s) or opening(profile, s)
  local sim = simulate(profile, s)
  local current = first
  while current and #steps < max do
    steps[#steps + 1] = current
    if current.filler then
      if #steps < max and s.inCombat then
        local again = later(profile, s, sim)
        if again then steps[#steps + 1] = again end
      end
      break
    end
    sim:pressed(current.key)
    local nextStep = pick(profile.priority, sim) or filler(profile, sim)
    if nextStep.key == current.key then break end   -- would repeat: nothing new to show
    current = nextStep
  end
  return steps
end

---------------------------------------------------------------------------
-- The action bar a profile suggests
---------------------------------------------------------------------------

-- Three bars, each with one job, so a key always means the same kind of thing:
--   fight  the main bar: what you press during a fight, in the order you use it
--   react  Action Bar 2: emergencies, heals, interrupts, crowd control
--   prep   Action Bar 3: buffs, summons and other things for between fights
-- profile.bars = { fight = {...}, react = {...}, prep = {...} }: up to 12
-- entries each, one per button. An entry is a list of candidates, best first:
-- a spell key, "macro:CC Pull", "book:Ghost Wolf" for a spell that is not
-- part of the rotation, or "item:bandage" / "item:healthstone" / "item:hearth"
-- for the best such item in your bags. Positions are fixed, so a button keeps its place as
-- you level and gaps fill in when you learn the spell.
Engine.BAR_GROUPS = { "fight", "react", "prep" }

-- Returns { fight = { { index, label, macro = name } | { index, label, spell = id } }, react = ..., prep = ... }.
-- Nothing appears twice.
function Engine.bars(profile, s, has)
  local layout = profile.bars or (profile.bar and { fight = profile.bar }) or {}
  local out, seen = {}, {}
  for _, group in ipairs(Engine.BAR_GROUPS) do
    local list = {}
    for index, candidates in ipairs(layout[group] or {}) do
      for _, c in ipairs(type(candidates) == "table" and candidates or { candidates }) do
        local macro, book, item = c:match("^macro:(.+)$"), c:match("^book:(.+)$"), c:match("^item:(.+)$")
        local entry
        if item then
          -- "item:bandage": the best one of that kind in your bags
          local found = has.item and has.item(item)
          if found then entry = { index = index, label = found.name or item, item = found.id, kindOfItem = item } end
        elseif macro then
          if has.macro(macro) then entry = { index = index, label = macro, macro = macro } end
        elseif book then
          local id = has.book(book)
          if id then entry = { index = index, label = book, spell = id } end
        elseif s.spells[c] then
          entry = { index = index, label = s.spells[c].name, spell = s.spells[c].id }
        end
        if entry and not seen[entry.label] then
          seen[entry.label] = true
          list[#list + 1] = entry
          break
        end
      end
    end
    out[group] = list
  end
  return out
end

---------------------------------------------------------------------------
-- The smart key's steps (see UI/Smart.lua)
---------------------------------------------------------------------------

-- Turns the pull plan into steps for the secure button: the plan's spells in
-- order, then one last step it stays on (wand, a filler spell, or attacking).
-- profile.smart may adjust it:
--   open  = "CC Open"   a macro to use for the first step (it sends the pet too)
--   tail  = "CC Strike" a macro to stay on at the end, for melee classes
--   gate  = { when = "[pet:Voidwalker,nocombat]", macro = "CC Send" }
--   skip  = { ["Power Word: Shield"] = true }   steps that have their own key
-- has.macro(name) says whether a macro exists.
function Engine.smartSteps(profile, s, has)
  local smart = profile.smart or {}
  local steps, tail = {}, nil
  for _, st in ipairs(Engine.plan(profile, s)) do
    if not (smart.skip and smart.skip[st.key]) then
      if not st.filler then
        steps[#steps + 1] = { kind = "spell", value = st.label, label = st.label }
      elseif st.key == "Shoot" then
        tail = has.macro("CC Wand") and { kind = "macro", value = "CC Wand", label = st.label }
          or { kind = "spell", value = st.label, label = st.label }
      elseif not st.melee then
        tail = { kind = "spell", value = st.label, label = st.label }
      end
    end
  end
  if not tail then
    local name = smart.tail and has.macro(smart.tail) and smart.tail or (has.macro("CC Attack") and "CC Attack" or nil)
    if name then tail = { kind = "macro", value = name, label = name == "CC Attack" and "Attack" or name } end
  end
  if tail then steps[#steps + 1] = tail end
  if #steps > 0 and smart.open and steps[1].kind == "spell" and has.macro(smart.open) then
    steps[1] = { kind = "macro", value = smart.open, label = steps[1].label }
  end
  local gate = smart.gate
  if gate and not has.macro(gate.macro) then gate = nil end
  -- What to know about the step the key stays on. A wand cast as a plain spell
  -- switches off again on the next press, and a key that ends on a spell casts
  -- that spell on every further press.
  local warn
  local last = steps[#steps]
  if last and last.kind == "spell" and last.value == (s.spells["Shoot"] and s.spells["Shoot"].name) then
    warn = "Without the CC Wand macro, a second press on the wand step stops your wand. Type /coach macros."
  elseif last and not tail then
    warn = "The key stays on " .. last.label .. " and casts it again on every press. Follow the coach when it moves you to another key."
  end
  return steps, gate, warn
end

---------------------------------------------------------------------------
-- Macros a profile offers (built from the spells you know)
---------------------------------------------------------------------------

-- The coach's plan for a fresh pull at full mana: the same steps the carousel
-- would walk through, ending with the filler. Macros are written from this,
-- so they follow the coach (your level, spells and usual kill time).
function Engine.plan(profile, s, max)
  local fresh = setmetatable({ manaLevel = "high", manaPct = 100, inCombat = false, fightTime = 0,
    target = { exists = false, key = "plan" } }, { __index = s })
  return Engine.chain(profile, fresh, max or 8)
end

-- Spell names of a plan, in order, for a /castsequence. Steps in `skip` are
-- left out. When the filler is a spell you cast (not a wand or melee), it is
-- added `tail` times so one key can carry the whole fight.
function Engine.sequence(plan, skip, tail)
  local names = {}
  for _, st in ipairs(plan) do
    if not (skip and skip[st.key]) then
      if not st.filler then
        names[#names + 1] = st.label
      elseif not st.melee and st.key ~= "Shoot" then
        for _ = 1, tail or 0 do names[#names + 1] = st.label end
      end
    end
  end
  return names
end

-- Macros every class gets.
Engine.GENERIC_MACROS = {
  -- One key to rest: drinks and eats the best you carry. It rewrites itself
  -- when your bags change, so the button on your bar is always current.
  { name = "CC Rest", about = "Drinks and eats the best you carry, in one press.",
    body = function(s)
      local sup = s.journey and s.journey.supplies
      local best = sup and sup.best
      if not best then return nil end
      local lines = { "#showtooltip" }
      if s.usesMana and best.drink then lines[#lines + 1] = "/use item:" .. best.drink.id end
      if best.food and not (best.drink and best.food.id == best.drink.id and s.usesMana) then
        lines[#lines + 1] = "/use item:" .. best.food.id
      end
      if #lines == 1 then return nil end
      return table.concat(lines, "\n")
    end },
}

function Engine.macros(profile, s)
  local out = {}
  local plan = Engine.plan(profile, s)
  local function build(v)
    if type(v) ~= "function" then return v end
    local fine, result = pcall(v, s, plan)
    return fine and result or nil
  end
  local defs = {}
  for _, def in ipairs(profile.macros or {}) do defs[#defs + 1] = def end
  for _, def in ipairs(Engine.GENERIC_MACROS) do defs[#defs + 1] = def end
  for _, def in ipairs(defs) do
    local body = build(def.body)
    if type(body) == "string" and body ~= "" and #body <= 255 then
      out[#out + 1] = { name = def.name, body = body, about = build(def.about), smart = def.smart }
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Before the pull: what is missing
---------------------------------------------------------------------------

local function needsMet(entry, s)
  if entry.minLevel and s.level < entry.minLevel then return false end
  if entry.needs then
    if type(entry.needs) == "table" then
      for _, k in ipairs(entry.needs) do if s:known(k) then return true end end
      return false
    end
    return s:known(entry.needs)
  end
  return true
end

local function anyBuff(s, list)
  if type(list) ~= "table" then list = { list } end
  local unknown = false
  for _, k in ipairs(list) do
    local has = s:buff(k)
    if has == true then return true end
    if has == nil then unknown = true end
  end
  if unknown then return nil end
  return false
end

-- Icons for things that are not spells.
local ICON = {
  talent = "Interface\\Icons\\Ability_Marksmanship", food = "Interface\\Icons\\INV_Misc_Food_15",
  rest = "Interface\\Icons\\Spell_Nature_Sleep", sleep = "Interface\\Icons\\INV_Misc_Bag_10",
  repair = "Interface\\Icons\\Trade_BlackSmithing", bags = "Interface\\Icons\\INV_Misc_Bag_08",
  trainer = "Interface\\Icons\\INV_Misc_Book_09", drink = "Interface\\Icons\\INV_Drink_07",
  skull = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", elite = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
  grey = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", map = "Interface\\Icons\\INV_Misc_Map_01",
  potion = "Interface\\Icons\\INV_Potion_51", manaPotion = "Interface\\Icons\\INV_Potion_72", bandage = "Interface\\Icons\\INV_Misc_Bandage_15",
  page = "Interface\\Icons\\INV_Misc_Book_11", dungeon = "Interface\\Icons\\INV_Misc_Key_03", quest = "Interface\\Icons\\INV_Misc_Note_01",
}

-- The spell that fixes a checklist entry: `fix` on the entry (a key, or a
-- function(s) returning one), else the first spell of its list that you know.
local function fixFor(entry, s)
  local fix = entry.fix
  if type(fix) == "function" then
    local fine, result = pcall(fix, s)
    fix = fine and result or nil
  end
  if fix then return s.spells[fix] end
  local list = entry.buff or entry.weapon or (entry.pet and entry.needs) or nil
  if type(list) == "string" then list = { list } end
  for _, key in ipairs(list or {}) do
    if s.spells[key] then return s.spells[key] end
  end
end

-- One checklist entry: { text, hint, icon, keybind, spell } when it needs fixing, else nil.
-- The icon is the spell that fixes it, so the panel can show what to press.
local function evaluate(entry, s)
  if not needsMet(entry, s) then return nil end
  local isMissing = false
  if entry.buff then
    -- only nag about buffs you actually know
    local list = type(entry.buff) == "table" and entry.buff or { entry.buff }
    local knowsOne = false
    for _, k in ipairs(list) do if s:known(k) then knowsOne = true end end
    if knowsOne then isMissing = anyBuff(s, list) == false end
  elseif entry.weapon then
    local knowsOne = false
    for _, k in ipairs(entry.weapon) do if s:known(k) then knowsOne = true end end
    if knowsOne then isMissing = s.mainHandBuff == false end
  elseif entry.item then
    local count = s.itemCount and s.itemCount(entry.item)
    isMissing = count ~= nil and count < (entry.min or 1)
  elseif entry.slot then
    local has = s.equipped and s.equipped(entry.slot)
    isMissing = has == false
  elseif entry.pet then
    isMissing = s.hasPet == false
  elseif entry.check then
    local fine, result = pcall(entry.check, s)
    isMissing = fine and result == true
  end
  if isMissing then
    local sp = fixFor(entry, s)
    return { text = text(entry.label, s), hint = text(entry.hint, s), icon = entry.icon or (sp and sp.icon),
      spell = sp and sp.name, keybind = sp and s.keys and s.keys[sp.name] or nil }
  end
end

-- The highest enemy level that gives you no XP ("grey").
local function greyLevel(level)
  if level <= 5 then return 0 end
  if level <= 39 then return level - math.floor(level / 10) - 5 end
  if level <= 59 then return level - math.floor(level / 5) - 1 end
  return 51
end
Engine.greyLevel = greyLevel

-- "Should I fight this?": the targeted enemy against your level.
-- Returns one checklist item, or nil when it is a fair fight (or unknown).
function Engine.threat(s)
  local t = s.target
  if not t or not t.exists or not t.hostile or t.dead or type(t.level) ~= "number" then return nil end
  local diff = t.level - s.level
  if t.level < 0 or diff >= 5 then
    return { kind = "danger", text = t.level < 0 and "Far above your level" or (diff .. " levels above you"),
      badge = t.level < 0 and "??" or ("+" .. diff), icon = ICON.skull,
      hint = "Red: most of your attacks will miss or be resisted. Walk away." }
  end
  if t.elite and not s.inGroup and diff >= -3 then
    return { kind = "danger", text = "Elite enemy", badge = diff > 0 and ("+" .. diff) or nil, icon = ICON.elite,
      hint = "Elites are far tougher than a normal enemy of the same level. Skip it or bring a friend." }
  end
  if diff >= 3 then
    return { text = diff .. " levels above you", badge = "+" .. diff, icon = ICON.skull,
      hint = "Orange: you will miss more and it hits harder. Go in at full health and mana, or pick something closer to your level." }
  end
  if t.level <= greyLevel(s.level) then
    return { kind = "info", text = "Grey to you: no XP", icon = ICON.grey,
      hint = "Too low to give any XP. Only worth it for a quest or for its skin." }
  end
end

-- Before the pull: only what matters for the next fight. Entries marked
-- `tip = true` are advice for the journey panel instead (Engine.journey).
-- Returns a list of { text = "...", hint = "..." }.
function Engine.checklist(profile, s, options)
  options = options or {}
  local missing = {}
  if s.inCombat then return missing end
  if s.barPage and s.barPage ~= 1 then
    missing[#missing + 1] = { kind = "danger", text = "Main bar is on page " .. s.barPage, badge = "P" .. s.barPage, icon = ICON.page,
      hint = "Your spells are on page 1. Press Shift+1 to go back. /coach pages stops Shift+number from switching pages." }
  end
  if options.threat ~= false then
    local threat = Engine.threat(s)
    if threat then missing[#missing + 1] = threat end
  end
  for _, entry in ipairs(profile.checklist) do
    if not entry.tip then
      local item = evaluate(entry, s)
      if item then missing[#missing + 1] = item end
    end
  end
  if s.healthPct and s.healthPct < 50 then
    missing[#missing + 1] = { text = ("Health %d%%"):format(math.floor(s.healthPct)), hint = "Eat or bandage before the next pull.",
      icon = ICON.food, badge = ("%d"):format(math.floor(s.healthPct)), use = "rest" }
  end
  if s.usesMana and s.manaPct and s.manaPct < (options.drinkAt or 60) then
    -- restFix: a spell that gets mana back without drinking (Life Tap)
    local sp = profile.restFix and s.spells[profile.restFix]
    missing[#missing + 1] = { text = ("Mana %d%%"):format(math.floor(s.manaPct)), hint = text(profile.restHint, s) or "Drink before the next pull.",
      icon = sp and sp.icon or ICON.drink, spell = sp and sp.name, keybind = sp and s.keys and s.keys[sp.name] or nil,
      badge = ("%d"):format(math.floor(s.manaPct)), use = not sp and "rest" or nil }
  end
  return missing
end

---------------------------------------------------------------------------
-- Professions: which two to take, and what to do next in each
---------------------------------------------------------------------------

local function listed(list, name)
  for _, v in ipairs(list or {}) do if v == name then return true end end
  return false
end

local function sentence(names)
  if #names <= 1 then return names[1] or "" end
  return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- The two primary professions to suggest for a class.
--   picks   ns.ProfessionPicks (see Data/Professions.lua)
--   goal    "gear", "balanced", "gold" or "endgame"
--   first, second   a profession you chose yourself, or "auto"
-- Returns { name, name }, why. A profession you chose always comes first; the
-- goal's pair fills what is left.
function Engine.professionPair(class, picks, goal, first, second)
  picks = picks or {}
  local byGoal = (picks.byClass and picks.byClass[class]) or picks.any or {}
  local suggested = byGoal[goal] or byGoal.gear or {}
  local pair, chosen = {}, 0
  for _, own in ipairs({ first, second }) do
    if type(own) == "string" and own ~= "auto" and listed(picks.primary, own) and not listed(pair, own) then
      pair[#pair + 1] = own
      chosen = chosen + 1
    end
  end
  for _, name in ipairs(suggested) do
    if #pair < 2 and not listed(pair, name) then pair[#pair + 1] = name end
  end
  local why = (picks.why and picks.why[byGoal[goal] and goal or "gear"]) or ""
  if chosen == 2 then why = "Your own choice." elseif chosen == 1 then why = "Your own choice, plus one that fits your goal." end
  return pair, why
end

-- The stretch of a guide your skill is in: { from, to, what }, or nil.
function Engine.professionStep(guide, skill)
  for _, step in ipairs(guide and guide.steps or {}) do
    if skill >= step[1] and skill < step[2] then return step end
  end
end

-- The whole plan in words, for /coach professions.
--   mine   what you have learned (as for professionLines); who = "Affliction Warlock"
function Engine.professionReport(mine, who, options)
  local picks, guides = options.professionPicks, options.professionData or {}
  local goal, goalName = options.goal or "gear", nil
  for _, g in ipairs(picks.goals or {}) do if g[1] == goal then goalName = g[2] end end
  local pair, why = Engine.professionPair(options.class, picks, goal, options.first, options.second)
  local out = { ("Professions for your %s. Goal: %s."):format(who, goalName or "Make my own gear while leveling"),
    ("  Suggested: %s. %s"):format(table.concat(pair, " and "), why) }
  for _, name in ipairs(pair) do if guides[name] then out[#out + 1] = ("  %s: %s"):format(name, guides[name].about) end end
  out[#out + 1] = "  Change the goal or pick your own two: Esc > Options > AddOns > ClassCoach > Professions."
  if #mine == 0 then out[#out + 1] = "  You have not learned a profession yet. Trainers are in every capital city: ask a guard." end
  local has = {}
  for _, p in ipairs(mine) do
    has[p.name] = true
    local guide = guides[p.name]
    local step = guide and Engine.professionStep(guide, p.skill)
    out[#out + 1] = ("  %s %d%s%s"):format(p.name, p.skill, p.max and (" of " .. p.max) or "",
      step and (": %s %s (to %d)"):format(guide.verb, step[3], step[2]) or (p.skill >= 300 and ": finished" or ""))
    for _, st in ipairs(guide and guide.steps or {}) do
      if st[1] > p.skill and st[1] < p.skill + 60 then out[#out + 1] = ("    from %d: %s %s"):format(st[1], guide.verb, st[3]) end
    end
  end
  local free = {}
  for _, name in ipairs(picks.secondary or {}) do if not has[name] then free[#free + 1] = name end end
  if #free > 0 then out[#out + 1] = "  Free to learn, they use no profession slot: " .. table.concat(free, ", ") .. "." end
  out[#out + 1] = "  Steps follow the Forever guides on wow-professions.com (based on the beta)."
  return out
end

-- Lines for the journey panel.
--   professions   what you have learned: { { name, skill, max, icon, primary } }, or nil when unreadable
--   options       professionData, professionPicks, class, goal, first, second, secondary (false = don't suggest them)
-- At most: one line on what to learn, one on the secondary professions, a line
-- for each profession at its cap, and two "what next" lines (your two main
-- professions before the secondary ones).
function Engine.professionLines(professions, level, options)
  local lines = {}
  local guides, picks = options.professionData or {}, options.professionPicks
  if not professions and not picks then return lines end
  professions = professions or {}
  local have, primaries = {}, 0
  for _, p in ipairs(professions) do
    have[p.name] = true
    if p.primary then primaries = primaries + 1 end
  end

  -- What to learn. Only for a slot that is still free: a profession you already took is your choice.
  if picks and options.readable ~= false and (level or 1) >= 5 then
    if primaries < 2 then
      local pair, why = Engine.professionPair(options.class, picks, options.goal or "gear", options.first, options.second)
      local wanted = {}
      for _, name in ipairs(pair) do
        if not have[name] and #wanted < 2 - primaries then wanted[#wanted + 1] = name end
      end
      if #wanted > 0 then
        local about = {}
        for _, name in ipairs(wanted) do if guides[name] and guides[name].about then about[#about + 1] = name .. ": " .. guides[name].about end end
        lines[#lines + 1] = { kind = "do", text = "Learn " .. sentence(wanted),
          hint = ("%s %s Trainers are in every capital city: ask a guard. /coach professions shows the plan."):format(why, table.concat(about, " ")) }
      end
    end
    if options.secondary ~= false then
      local missing = {}
      for _, name in ipairs(picks.secondary or {}) do if not have[name] then missing[#missing + 1] = name end end
      if #missing > 0 then
        lines[#lines + 1] = { kind = "info", text = "Also learn " .. sentence(missing),
          hint = "These use no profession slot, so every character can have all three. First Aid also makes healing potions in Forever, and cooked food gives the Well Fed buff." }
      end
    end
  end

  -- At the cap: a trainer visit. Then what to do next, main professions first.
  local nextLines = 0
  local function consider(p)
    local guide = guides[p.name]
    if p.max and p.max < 300 and p.skill >= p.max - 5 then
      local tier
      for _, t in ipairs(guide and guide.tiers or {}) do if t.cap == p.max then tier = t end end
      lines[#lines + 1] = { kind = "do", text = ("%s %d of %d: train the next rank"):format(p.name, p.skill, p.max), icon = p.icon,
        hint = tier and ("%s %s needs %s. At %d you stop gaining skill until you have it."):format(tier.name, p.name, tier.needs, p.max)
          or ("At %d you stop gaining skill. A %s trainer teaches the next rank."):format(p.max, p.name) }
    elseif guide and nextLines < 2 and p.skill < 300 then
      local step = Engine.professionStep(guide, p.skill)
      if step then
        nextLines = nextLines + 1
        lines[#lines + 1] = { kind = "info", text = ("%s %d: %s %s"):format(p.name, p.skill, guide.verb or "craft", step[3]), icon = p.icon,
          hint = ("That takes you from %d to %d. From the Forever guide on %s; materials and amounts are there."):format(step[1], step[2], guide.source or "the web") }
      end
    end
  end
  for _, p in ipairs(professions) do if p.primary then consider(p) end end
  for _, p in ipairs(professions) do if not p.primary then consider(p) end end
  return lines
end

---------------------------------------------------------------------------
-- The journey: everything outside the fight that makes leveling smoother
---------------------------------------------------------------------------


-- A buff whose name starts with `prefix` (names differ a little between
-- foods and clients). nil when buffs can't be read.
local function buffStarting(s, prefix)
  if not s.buffs then return nil end
  for name in pairs(s.buffs) do
    if name:sub(1, #prefix) == prefix then return true end
  end
  return false
end
Engine.buffStarting = buffStarting

-- s.journey = { xp = { cur, max, rested, resting }, talentPoints, durability (lowest %),
--   freeSlots, hasItem(name) }. Every field may be nil when the game won't say.
-- Returns { xp = { pct, restedPct, resting }, lines = { { kind, text, hint } } }
-- kind: "do" (worth acting on now), "info" (good to know).
function Engine.journey(profile, s, options)
  options = options or {}
  local j = s.journey or {}
  local out = { lines = {} }
  -- icon: a texture path, or { spell = key } for that spell's own icon
  local function add(kind, line, hint, icon) out.lines[#out.lines + 1] = { kind = kind, text = line, hint = hint, icon = icon } end

  local train, restedOn, gear = options.train ~= false, options.rested ~= false, options.gear ~= false
  -- a number, or true when the game says "some" without a count
  local unspent = j.talentPoints
  if train and (unspent == true or (type(unspent) == "number" and unspent > 0)) then
    -- from the build you follow and the talents you already have; by level only when the game hides them
    local pick = (s.talent and s.talent.plan.readable and Engine.nextTalent(s.talent.plan)) or Engine.talentFor(profile, s.level)
    add("do", unspent == true and "Talent points to spend" or unspent == 1 and "1 talent point to spend" or (unspent .. " talent points to spend"),
      pick and ("Suggested: " .. pick .. ".") or "Open your talents (N) and spend it.", ICON.talent)
  end

  if train and s.bookReady then
    local untrained = {}
    for key, meta in pairs(profile.spells) do
      if meta.learn and s.level >= meta.learn and not s:known(key) then untrained[#untrained + 1] = key end
    end
    if #untrained > 0 then
      table.sort(untrained)
      add("do", "Not trained: " .. table.concat(untrained, ", "), "Visit your class trainer: you can learn it now.", { spell = untrained[1] })
    end
  end

  for _, entry in ipairs(profile.checklist) do
    if entry.tip then
      local item = evaluate(entry, s)
      if item then add("do", item.text, item.hint, item.icon) end
    end
  end

  if options.food and s.level >= 5 and buffStarting(s, "Well Fed") == false then
    add("do", "No food buff", "Eat cooked food (marked Nutritious) for 10 seconds: Well Fed gives +5% XP from kills for 15 minutes.", ICON.food)
  end

  local xp = j.xp
  if xp and xp.max and xp.max > 0 and s.level < 60 then
    out.xp = { pct = (xp.cur or 0) / xp.max * 100, resting = xp.resting == true }
    local rested = xp.rested or 0
    out.xp.restedPct = rested / xp.max * 100
    if not restedOn then
      -- the bar still shows it; just no reminders
    elseif xp.resting then
      add("info", "In a rest area", "Log out here: rested XP builds while you are away, and doubles XP from kills.", ICON.rest)
    elseif rested <= 0 then
      add("do", "No rested XP", j.hasItem and j.hasItem("Camp Tent")
        and "Pitch your Camp Tent at a campfire (once an hour), or log out in an inn or city."
        or "Log out in an inn or city: rested XP doubles XP from kills. A Camp Tent (Leatherworking 20) tops it up on the road.", ICON.rest)
    elseif out.xp.restedPct < 5 and j.hasItem and j.hasItem("Camp Tent") then
      add("info", ("Rested XP low (%d%% of a level)"):format(math.floor(out.xp.restedPct)),
        "Your Camp Tent tops it up to 5% at a campfire, once an hour.", ICON.rest)
    end
  end

  -- Forever calls the sleeping bag's buff "Well-Rested"
  if restedOn and j.hasItem and j.hasItem("Cozy Sleeping Bag") and buffStarting(s, "Well-Rested") == false and s.level < 60 then
    add("do", "Sleeping bag buff missing", "Lie on your Cozy Sleeping Bag: +1% XP per minute, up to 3% after 3 minutes. Once an hour.", ICON.sleep)
  end

  if gear and j.durability and j.durability < 25 then
    add("do", ("Gear at %d%% durability"):format(math.floor(j.durability)), "Repair at any vendor with an anvil icon before it breaks.", ICON.repair)
  end
  if gear and j.freeSlots and j.freeSlots <= 2 then
    add("do", j.freeSlots == 0 and "Bags full" or ("Bags nearly full (%d free)"):format(j.freeSlots), "Sell grey items at a vendor.", ICON.bags)
  end

  -- Supplies: shout at a vendor, stay quiet elsewhere unless you are out.
  local sup = options.supplies ~= false and j.supplies
  if sup and s.level >= 5 then
    -- what vendors usually sell for your level: { level, name }
    local function forLevel(list)
      local pick
      for _, row in ipairs(list or {}) do if s.level >= row[1] then pick = row end end
      return pick
    end
    local data = options.data or {}
    local function stock(count, what, icon, low, suggestion)
      if count == nil then return end
      local buy = suggestion and (" For your level: " .. suggestion .. ".") or ""
      if j.atVendor and count < low then
        add("do", ("Buy %s: %d left"):format(what, count), "You are at a vendor. If this one doesn't sell it, an innkeeper does." .. buy, icon)
      elseif count == 0 then
        add("do", "Out of " .. what, "Buy some at the next innkeeper or general goods vendor." .. buy, icon)
      end
    end
    local water, bread = forLevel(data.drinks), forLevel(data.foods)
    if s.usesMana then stock(sup.drink, "water", ICON.drink, 5, water and water[2]) end
    stock(sup.food, "food", ICON.food, 5, bread and (bread[2] .. " fills you up; cooked food also gives the XP buff"))
    -- carrying water far below your level: say what would be better
    local best = sup.best and sup.best.drink
    if s.usesMana and best and water and sup.drink > 0 and best.level < water[1] and water[1] - best.level >= 10 then
      add(j.atVendor and "do" or "info", "Better water exists for your level",
        ("You carry %s. %s restores much more."):format(best.name or "low-level water", water[2]), ICON.drink)
    end
    for _, want in ipairs(profile.supplies or {}) do
      if (not want.needs or s:known(want.needs)) and s.itemCount then
        local count = s.itemCount(want.item)
        if type(count) == "number" then stock(count, want.name, want.icon, want.low or 2) end
      end
    end
    -- For emergencies: a healing potion (instant, works in a fight), a mana potion, bandages.
    -- In Forever healing potions are First Aid recipes: Minor at skill 55, Lesser at 85, Healing at 135.
    if s.level >= 10 and sup.best then
      local firstAid
      for _, p in ipairs(j.professions or {}) do if p.name == "First Aid" then firstAid = p end end
      if not sup.best.healingpotion then
        local how = not firstAid and "First Aid makes them in Forever (from skill 55), or buy a few on the auction house."
          or firstAid.skill >= 55 and "You can make them yourself with First Aid: Minor Healing Potion from skill 55, Lesser from 85, Healing from 135."
          or ("First Aid makes them in Forever from skill 55 (yours is %d)."):format(firstAid.skill)
        add("info", "No healing potion", "Instant, and it works in a fight: your emergency button. " .. how
          .. " Use them: don't save potions for a perfect moment. /coach bar puts yours on the react bar.", ICON.potion)
      end
      if s.usesMana and s.level >= 15 and profile.manaPotion ~= false and not sup.best.manapotion then
        add("info", "No mana potion", "For a long fight or a bad pull. Alchemists make them: buy a few on the auction house. /coach bar puts yours on the react bar.",
          ICON.manaPotion)
      end
      if firstAid and not sup.best.bandage then
        add("info", "No bandages", "Make some from cloth with First Aid. They heal you between fights at no mana cost.", ICON.bandage)
      end
    end
    if j.emptyBagSlots and j.emptyBagSlots > 0 then
      add(j.atVendor and "do" or "info", j.emptyBagSlots == 1 and "A bag slot is empty" or (j.emptyBagSlots .. " bag slots are empty"),
        "Buy bags early: your backpack fills fast. Trade vendors and the auction house sell small bags for a few silver.", ICON.bags)
    end
    if j.atVendor and j.canRepair and j.durability and j.durability < 90 then
      add("do", ("Repair here (gear at %d%%)"):format(math.floor(j.durability)), "This vendor repairs: click the anvil button.", ICON.repair)
    end
  end

  -- Professions: which to learn, a trainer visit at the skill cap, and what to do next in each.
  if options.professions ~= false then
    for _, line in ipairs(Engine.professionLines(j.professions, s.level, options)) do
      add(line.kind, line.text, line.hint, line.icon or ICON.trainer)
    end
  end

  -- The roadmap: milestones due now, the next one coming, and where to be.
  if options.roadmap ~= false then
    local data = options.data or {}
    local due, upcoming = 0, nil
    local function consider(m)
      if s.level >= m.level then
        local show
        if m.done then
          local fine, finished = pcall(m.done, s)
          show = fine and not finished and s.level - m.level <= 10
        else
          show = s.level - m.level <= 1
        end
        if show and due < 2 then
          due = due + 1
          add(m.done and "do" or "info", text(m.text, s), text(m.hint, s), m.icon or ICON.quest)
        end
      elseif not upcoming or m.level < upcoming.level then
        upcoming = m
      end
    end
    for _, m in ipairs(data.milestones or {}) do consider(m) end
    for _, m in ipairs(profile.milestones or {}) do consider(m) end
    if upcoming then
      add("info", ("At level %d: %s"):format(upcoming.level, text(upcoming.text, s)), text(upcoming.hint, s), upcoming.icon or ICON.quest)
    end
    local function fitting(list)
      local names = {}
      for _, row in ipairs(list or {}) do
        if s.level >= row[1] and s.level <= row[2] then names[#names + 1] = row[3] end
      end
      return names
    end
    local faction = s.faction or "none"
    local zones = fitting(data.zones and data.zones[faction])
    if #zones > 0 then
      add("info", "Quest in: " .. zones[#zones], #zones > 1 and ("Also fine at your level: " .. table.concat(zones, "; ", 1, #zones - 1) .. ".") or nil, ICON.map)
    end
    local dungeons = fitting(data.dungeons and data.dungeons[faction])
    if #dungeons > 0 then
      add("info", "Dungeon: " .. dungeons[1], #dungeons > 1 and ("Also in range: " .. table.concat(dungeons, ", ", 2) .. ".") or "In range for your level. Bring friends.", ICON.dungeon)
    end
  end

  local nextLevel = Engine.nextTraining(profile, s.level)
  if train and nextLevel then
    add("info", ("New spells at level %d"):format(nextLevel), profile.trainer[nextLevel] and ("Your trainer will teach: " .. profile.trainer[nextLevel] .. ".") or nil, ICON.trainer)
  end
  return out
end

---------------------------------------------------------------------------
-- Live advice line
---------------------------------------------------------------------------

local GENERIC_ADVICE = {
  low = "Mana low: stop the extra spells. Let your free attacks finish the enemy, then drink.",
  medium = "Mana half: use your main spells only.",
}

function Engine.advice(profile, s)
  if s.inCombat and s.barPage and s.barPage ~= 1 then
    return ("Your main bar is on page %d, so your buttons look gone. Press Shift+1 to get them back."):format(s.barPage)
  end
  local missed = s.inCombat and s:justMissed()
  if missed and missed.immune then
    local sp = s.spells[missed.name]
    return "This enemy is immune to " .. (sp and sp.name or missed.name) .. ": the coach will skip it here."
  end
  if s.inCombat and s.skippedDot and (not s.usesMana or s.manaLevel == "high") then
    return "This enemy is nearly dead: no new damage over time, just finish it."
  end
  if not s.usesMana or not s.inCombat then return nil end
  local a = profile.advice[s.manaLevel]
  if type(a) == "function" then
    local fine, text = pcall(a, s)
    a = fine and text or nil
  end
  if a == nil then a = GENERIC_ADVICE[s.manaLevel] end
  return a
end

---------------------------------------------------------------------------
-- After the fight
---------------------------------------------------------------------------

local function fmtTime(sec) return ("%ds"):format(math.floor(sec + 0.5)) end

-- Returns { headline = "...", casts = "...", tips = { ... } }
function Engine.report(profile, summary, s)
  local out = { tips = {} }
  local parts = { fmtTime(summary.duration) }
  local castTotal = 0
  for _, c in ipairs(summary.casts) do castTotal = castTotal + c.count end
  parts[#parts + 1] = castTotal .. (castTotal == 1 and " cast" or " casts")
  if summary.swings and summary.swings > 0 then parts[#parts + 1] = summary.swings .. " swings" end
  if (summary.missed or 0) > 0 then parts[#parts + 1] = summary.missed .. " resisted" end
  if s.usesMana and summary.spent and summary.spent > 0 then
    if summary.spentPct then
      parts[#parts + 1] = ("%d mana (%d%%)"):format(math.floor(summary.spent), math.floor(summary.spentPct))
    else
      parts[#parts + 1] = math.floor(summary.spent) .. " mana"
    end
  end
  local who = summary.target and (summary.target .. (summary.targetLevel and (" (" .. summary.targetLevel .. ")") or "")) or "Fight"
  out.headline = who .. ": " .. table.concat(parts, " · ")
  local castsText = {}
  local function label(key) local sp = s.spells and s.spells[key]; return sp and sp.name or key end
  for i, c in ipairs(summary.casts) do
    if i > 4 then break end
    castsText[#castsText + 1] = ("%s ×%d%s"):format(label(c.name), c.count, (c.mana > 0) and (" (" .. c.mana .. " mana)") or "")
  end
  out.casts = #castsText > 0 and table.concat(castsText, ", ") or nil

  local function add(text) if text and #out.tips < 2 then out.tips[#out.tips + 1] = text end end
  -- A lot resisted: that is the enemy's level, not your play.
  local missed = summary.missed or 0
  if missed >= 2 and castTotal > 0 and missed / castTotal >= 0.25 then
    local above = summary.targetLevel and summary.targetLevel > 0 and summary.targetLevel - s.level or 0
    add(("%d of your %d casts were resisted. %s"):format(missed, castTotal, above >= 2
      and ("That enemy was %d levels above you: higher enemies resist far more. Pick ones nearer your level."):format(above)
      or "Bad luck this time; nothing you did wrong."))
  end
  for _, rule in ipairs(profile.tips) do
    local fine, text = pcall(rule, summary, s)
    if fine then add(text) end
  end
  -- Generic coaching every class gets.
  if s.usesMana then
    local top = summary.casts[1]
    if top and summary.spent > 0 and top.mana >= summary.spent * 0.5 and summary.endPct and summary.endPct < 40 then
      local meta = profile.spells[top.name]
      if not (meta and meta.core) then
        add(("Most of your mana went on %s. Use it less and let %s do the work."):format(label(top.name), profile.freeDamage or "your attacks"))
      end
    end
    if summary.endPct and summary.endPct < 30 then add("Drink before the next pull.") end
  end
  return out
end

---------------------------------------------------------------------------
-- Level up
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Talent builds: an ordered list of points, followed from what you have
---------------------------------------------------------------------------

local function talentKey(name) return (tostring(name):lower():gsub("[^%a%d]", "")) end

-- A profile's talent list ({ fromLevel, toLevel, "Name (Tree): note" }) as one
-- entry per point: { name = "Name", label = the text as written }.
function Engine.talentOrder(list)
  local order = {}
  for _, t in ipairs(list or {}) do
    local label = tostring(t[3])
    local name = label:gsub("%s*%b()", ""):gsub(":.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local from, to = tonumber(t[1]) or 0, tonumber(t[2]) or 0
    for _ = from, math.min(to, from + 60) do order[#order + 1] = { name = name, label = label } end
  end
  return order
end

-- Reads a build out of a talent calculator link (Icy Veins or Warcraft Tavern).
-- `tables` is ns.TalentLinks. Returns order, site name - or nil, what is wrong.
function Engine.decodeBuild(link, class, tables)
  link = tostring(link or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if link == "" then return nil, "Paste a talent calculator link from Icy Veins or Warcraft Tavern." end
  local site, slug, symbols = "Icy Veins", link:match("wow%-forever/(%a+)%-talent%-calculator#tc%-([^~%s]+)")
  local keys = {}
  if slug then
    for i = 1, math.min(#symbols, 80) do keys[i] = symbols:sub(i, i) end
    tables = tables and tables.iv
  else
    site = "Warcraft Tavern"
    slug, symbols = link:match("talent%-calculator/(%a+)#%?t=(%w+)")
    if not slug then
      return nil, "I can read Icy Veins and Warcraft Tavern talent calculator links. This is not one of those."
    end
    local tree
    for i = 1, math.min(#symbols, 120) do
      local ch = symbols:sub(i, i)
      if ch:match("[ABC]") then tree = ch elseif tree then keys[#keys + 1] = tree .. ch end
    end
    tables = tables and tables.tavern
  end
  if slug:upper() ~= tostring(class) then
    return nil, ("That link is a %s build; your character is a %s."):format(slug:lower(), tostring(class):lower())
  end
  local names = tables and tables[class]
  if not names then return nil, "I have no talent list for this class." end
  if #keys == 0 then return nil, "That link has no talent points in it. Pick talents on the site first, then copy the link." end
  if #keys > 51 then return nil, "That link has more than 51 talent points, so it is not a level 60 build for Forever." end
  local order = {}
  for i, key in ipairs(keys) do
    local name = names[key]
    if not name then return nil, ("Point %d of that link is a talent I do not know. The site may have changed its links."):format(i) end
    order[i] = { name = name, label = name }
  end
  return order, site
end

-- Where you are in a build. `have` is API.talents() or nil.
--   steps[k] = { name, label, want (the rank this point gives), node, max, known, taken }
--   next     = the first step you have not taken (nil when the build is done)
--   extra    = points you spent that the build never asks for; offPlan lists them
--   ahead    = points you spent that the build only asks for later (taken out of its order)
--   unknown  = talents the build names that your talent window does not have
function Engine.talentPlan(order, have)
  local plan = { steps = {}, offPlan = {}, unknown = {}, extra = 0, taken = 0, ahead = 0 }
  local wanted, missing = {}, {}
  for k, step in ipairs(order or {}) do
    local key = talentKey(step.name)
    wanted[key] = (wanted[key] or 0) + 1
    local t = have and have.byName[key]
    local s = { name = t and t.name or step.name, label = step.label or step.name, want = wanted[key], node = t and t.node,
      max = t and t.max, known = t ~= nil, taken = t ~= nil and t.rank >= wanted[key] }
    if t and wanted[key] > t.max then s.known, s.taken = false, false end   -- the build asks for more ranks than exist
    plan.steps[k] = s
    if s.taken then
      plan.taken = plan.taken + 1
      if plan.next then plan.ahead = plan.ahead + 1 end
    end
    if not plan.next and not s.taken then plan.next = k end
    if have and not s.known and not missing[key] then
      missing[key] = true
      plan.unknown[#plan.unknown + 1] = step.name
    end
  end
  if have then
    for _, t in ipairs(have.list) do
      local extra = t.rank - (wanted[talentKey(t.name)] or 0)
      if extra > 0 then
        plan.offPlan[#plan.offPlan + 1] = { name = t.name, extra = extra, node = t.node }
        plan.extra = plan.extra + extra
      end
    end
  end
  plan.readable = have ~= nil
  return plan
end

-- "Suppression (1 of 5)" for the next point of a plan, or nil when it is done.
function Engine.nextTalent(plan)
  local s = plan and plan.next and plan.steps[plan.next]
  if not s then return nil end
  if not s.known then return s.label end
  return ("%s (%d of %d)"):format(s.name, s.want, s.max or s.want)
end

-- The points after the next one, as distinct talents in order: { { node, name, order = 2.. } }.
function Engine.upcomingTalents(plan, count)
  local out, seen = {}, {}
  if not plan or not plan.next then return out end
  local first = plan.steps[plan.next]
  if first.node then seen[first.node] = true end
  for k = plan.next + 1, #plan.steps do
    local s = plan.steps[k]
    if s.known and s.node and not s.taken and not seen[s.node] then
      seen[s.node] = true
      out[#out + 1] = { node = s.node, name = s.name, order = #out + 2 }
      if #out >= (count or 4) then break end
    end
  end
  return out
end

-- Which build to follow. builds = { { name, order } }, choice = "auto", a number,
-- or "custom" (then `custom` is used). On "auto" it is the build that fits the
-- points you already spent best: the fewest points outside it or ahead of its
-- order. The first one wins a tie, so it is the one you get with nothing spent.
function Engine.pickBuild(builds, custom, have, choice)
  if choice == "custom" and custom then return custom, "yours" end
  if type(choice) == "number" and builds[choice] then return builds[choice], "chosen" end
  local best, bestExtra
  for _, b in ipairs(builds) do
    local plan = have and Engine.talentPlan(b.order, have)
    local extra = plan and (plan.extra + plan.ahead) or 0
    if not best or extra < bestExtra then best, bestExtra = b, extra end
  end
  if not best then return custom, custom and "yours" or nil end
  return best, "auto"
end

function Engine.talentFor(profile, level)
  for _, t in ipairs(profile.talents) do
    if level >= t[1] and level <= t[2] then return t[3] end
  end
end

-- pick: the next talent of the build you follow, when the game told us your talents
function Engine.levelUp(profile, level, pick)
  local lines = { ("Level %d!"):format(level) }
  local new = profile.trainer[level]
  if new then
    lines[#lines + 1] = "Train: " .. new .. "."
  elseif level % 2 == 0 then
    lines[#lines + 1] = "Visit your trainer for new spell ranks."
  end
  if level >= 10 then
    local t = pick or Engine.talentFor(profile, level)
    lines[#lines + 1] = t and ("Talent point: " .. t .. ".") or "Spend your new talent point."
  end
  return lines
end

-- Next level where the trainer teaches something new.
function Engine.nextTraining(profile, level)
  for l = level + 1, 60 do
    if profile.trainer[l] then return l, profile.trainer[l] end
  end
end
