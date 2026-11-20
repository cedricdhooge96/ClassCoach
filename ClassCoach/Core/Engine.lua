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

-- fields: level, now, inCombat, inGroup, usesMana, manaPct, manaExact,
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

function State:debuffUp(key)
  return self.tracker:debuffUp(self.target and self.target.key, key, self.now)
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

local function pick(list, profile, s)
  for _, entry in ipairs(list) do
    local sp = s.spells[entry.spell]
    local ok = sp ~= nil
      and (not entry.minLevel or s.level >= entry.minLevel)
      and s:manaAtLeast(entry.mana)
      and s:ready(entry.spell) ~= false
      and s:usable(entry.spell) ~= false
    if ok and entry.when then
      local fine, result = pcall(entry.when, s)
      ok = fine and result and true or false
    end
    if ok then
      return { key = entry.spell, label = sp.name, icon = sp.icon, keybind = s.keys and s.keys[sp.name],
        why = entry.why }
    end
  end
end

local function filler(profile, s)
  for _, f in ipairs(profile.filler or {}) do
    local sp = f.spell and s.spells[f.spell]
    local fine, ok = true, true
    if f.when then fine, ok = pcall(f.when, s) end
    if (not f.spell or sp) and fine and ok then
      return { key = f.spell or "attack", label = f.label or (sp and sp.name), icon = (sp and sp.icon) or f.icon or ATTACK_ICON,
        keybind = sp and s.keys and s.keys[sp.name], why = f.why, filler = true }
    end
  end
  return { key = "attack", label = "Melee", icon = ATTACK_ICON, why = "Auto attack costs no mana.", filler = true }
end

-- In combat: the priority list. Out of combat with an enemy targeted: the opener.
function Engine.next(profile, s)
  if s.inCombat then
    return pick(profile.priority, profile, s) or filler(profile, s)
  end
  if s.target and s.target.exists and s.target.hostile and not s.target.dead then
    local open = pick(profile.opener, profile, s)
    if open then
      open.why = open.why or "Pull with this."
      return open
    end
    local f = filler(profile, s)
    f.why = "Walk in and attack."
    return f
  end
  return nil
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

-- Returns a list of { text = "...", hint = "..." } for things to fix.
function Engine.checklist(profile, s, options)
  options = options or {}
  local missing = {}
  if s.inCombat then return missing end
  for _, entry in ipairs(profile.checklist) do
    if needsMet(entry, s) then
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
      if isMissing then missing[#missing + 1] = { text = entry.label, hint = entry.hint } end
    end
  end
  -- Generic checks every class gets.
  if s.healthPct and s.healthPct < 50 then
    missing[#missing + 1] = { text = ("Health %d%%"):format(math.floor(s.healthPct)), hint = "Eat or bandage before the next pull." }
  end
  if s.usesMana and s.manaPct and s.manaPct < (options.drinkAt or 60) then
    missing[#missing + 1] = { text = ("Mana %d%%"):format(math.floor(s.manaPct)), hint = profile.restHint or "Drink before the next pull." }
  end
  if options.food and s.level >= 5 and s.buffs and not s.buffs["Well Fed"] then
    missing[#missing + 1] = { text = "No food buff", hint = "Eat buff food: +5% XP from kills." }
  end
  return missing
end

---------------------------------------------------------------------------
-- Live advice line
---------------------------------------------------------------------------

local GENERIC_ADVICE = {
  low = "Mana low: stop the extra spells. Let your free attacks finish the enemy, then drink.",
  medium = "Mana half: use your main spells only.",
}

function Engine.advice(profile, s)
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
