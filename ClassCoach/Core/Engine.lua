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
  if s:ready(entry.spell) == false or s:usable(entry.spell) == false then return nil end
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
  return { key = entry.spell, label = sp.name, icon = sp.icon, keybind = s.keys and s.keys[sp.name],
    why = text(entry.why, s) }
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
    return pick(profile.priority, s) or filler(profile, s)
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
-- Macros a profile offers (built from the spells you know)
---------------------------------------------------------------------------

-- The coach's plan for a fresh pull at full mana: the same steps the carousel
-- would walk through, ending with the filler. Macros are written from this,
-- so they follow the coach (your level, spells and usual kill time).
function Engine.plan(profile, s, max)
  local fresh = setmetatable({ manaLevel = "high", manaPct = 100, inCombat = false, fightTime = 0,
    target = { exists = false, key = "plan" } }, { __index = s })
  return Engine.chain(profile, fresh, max or 6)
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

function Engine.macros(profile, s)
  local out = {}
  local plan = Engine.plan(profile, s)
  local function build(v)
    if type(v) ~= "function" then return v end
    local fine, result = pcall(v, s, plan)
    return fine and result or nil
  end
  for _, def in ipairs(profile.macros or {}) do
    local body = build(def.body)
    if type(body) == "string" and body ~= "" and #body <= 255 then
      out[#out + 1] = { name = def.name, body = body, about = build(def.about) }
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

-- One checklist entry: { text, hint } when it needs fixing, else nil.
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
  if isMissing then return { text = text(entry.label, s), hint = text(entry.hint, s), icon = entry.icon } end
end

-- Before the pull: only what matters for the next fight. Entries marked
-- `tip = true` are advice for the journey panel instead (Engine.journey).
-- Returns a list of { text = "...", hint = "..." }.
function Engine.checklist(profile, s, options)
  options = options or {}
  local missing = {}
  if s.inCombat then return missing end
  for _, entry in ipairs(profile.checklist) do
    if not entry.tip then
      local item = evaluate(entry, s)
      if item then missing[#missing + 1] = item end
    end
  end
  if s.healthPct and s.healthPct < 50 then
    missing[#missing + 1] = { text = ("Health %d%%"):format(math.floor(s.healthPct)), hint = "Eat or bandage before the next pull." }
  end
  if s.usesMana and s.manaPct and s.manaPct < (options.drinkAt or 60) then
    missing[#missing + 1] = { text = ("Mana %d%%"):format(math.floor(s.manaPct)), hint = text(profile.restHint, s) or "Drink before the next pull." }
  end
  return missing
end

---------------------------------------------------------------------------
-- The journey: everything outside the fight that makes leveling smoother
---------------------------------------------------------------------------

local ICON = {
  talent = "Interface\\Icons\\Ability_Marksmanship", food = "Interface\\Icons\\INV_Misc_Food_15",
  rest = "Interface\\Icons\\Spell_Nature_Sleep", sleep = "Interface\\Icons\\INV_Misc_Bag_10",
  repair = "Interface\\Icons\\Trade_BlackSmithing", bags = "Interface\\Icons\\INV_Misc_Bag_08",
  trainer = "Interface\\Icons\\INV_Misc_Book_09",
}

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
  if train and j.talentPoints and j.talentPoints > 0 then
    local pick = Engine.talentFor(profile, s.level)
    add("do", j.talentPoints == 1 and "1 talent point to spend" or (j.talentPoints .. " talent points to spend"),
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
    add("do", "No food buff", "Eat cooked food for 10 seconds: +5% XP from kills for 15 minutes.", ICON.food)
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

  if restedOn and j.hasItem and j.hasItem("Cozy Sleeping Bag") and buffStarting(s, "Cozy") == false and s.level < 60 then
    add("do", "Sleeping bag buff missing", "Lie on your Cozy Sleeping Bag for up to 3 minutes: up to +3% XP.", ICON.sleep)
  end

  if gear and j.durability and j.durability < 25 then
    add("do", ("Gear at %d%% durability"):format(math.floor(j.durability)), "Repair at any vendor with an anvil icon before it breaks.", ICON.repair)
  end
  if gear and j.freeSlots and j.freeSlots <= 2 then
    add("do", j.freeSlots == 0 and "Bags full" or ("Bags nearly full (%d free)"):format(j.freeSlots), "Sell grey items at a vendor.", ICON.bags)
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

function Engine.talentFor(profile, level)
  for _, t in ipairs(profile.talents) do
    if level >= t[1] and level <= t[2] then return t[3] end
  end
end

function Engine.levelUp(profile, level)
  local lines = { ("Level %d!"):format(level) }
  local new = profile.trainer[level]
  if new then
    lines[#lines + 1] = "Train: " .. new .. "."
  elseif level % 2 == 0 then
    lines[#lines + 1] = "Visit your trainer for new spell ranks."
  end
  if level >= 10 then
    local t = Engine.talentFor(profile, level)
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
