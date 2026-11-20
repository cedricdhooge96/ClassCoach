-- Remembers what you did: casts, swings, damage-over-time spells on each
-- enemy, totems, and a running record of the current fight.
-- The game hides most of this from addons in combat, so we count it ourselves
-- from your own casts. Pure Lua with no game calls, so it can be tested.
local _, ns = ...

local Tracker = {}
Tracker.__index = Tracker
ns.Tracker = Tracker

local PRECAST_WINDOW = 3   -- a cast this soon before combat belongs to the fight
-- How long after a cast its "resisted" can still arrive. Live play (see the
-- sigil addon) showed an ability's result comes the instant it is cast; a
-- spell that flies to the enemy reports when it lands.
local RESULT_WINDOW, FLIGHT_WINDOW = 0.35, 1.6

function Tracker.new()
  return setmetatable({ lastCast = {}, dots = {}, totems = {}, pre = {}, recentCasts = {}, immune = {}, fight = nil, last = nil }, Tracker)
end

local function record(f, c)
  f.casts[c.name] = (f.casts[c.name] or 0) + 1
  -- Spells that give mana back (Life Tap): a rough share of your maximum.
  if c.meta.restores and f.manaMax then f.restored = (f.restored or 0) + c.meta.restores * f.manaMax end
  if c.cost and c.cost > 0 then
    f.spent = f.spent + c.cost
    f.spentBy[c.name] = (f.spentBy[c.name] or 0) + c.cost
  end
  local on = f.onTarget[c.target]
  if not on then
    on = {}
    f.onTarget[c.target] = on
    f.engaged[c.target] = c.at
    f.targets = f.targets + 1
  end
  on[c.name] = (on[c.name] or 0) + 1
end

-- info: target, targetLevel, elite, manaStart, manaMax, hasPet, demon
function Tracker:startFight(now, info)
  info = info or {}
  local f = {
    start = now, target = info.target, targetLevel = info.targetLevel, elite = info.elite,
    manaStart = info.manaStart, manaMax = info.manaMax, hadPet = info.hasPet, demon = info.demon,
    casts = {}, spent = 0, spentBy = {}, swings = 0, onTarget = {}, engaged = {}, targets = 0,
  }
  self.fight = f
  -- The spell you pulled with landed just before combat started: count it.
  for _, c in ipairs(self.pre) do
    if now - c.at <= PRECAST_WINDOW then
      f.precast = true
      if f.manaStart and c.cost then f.manaStart = f.manaStart + c.cost end
      record(f, c)
    end
  end
  self.pre = {}
end

-- meta: the profile's data for this spell (debuff, totem, lasts, optional...)
-- duration: how long its damage over time lasts, when known better than meta.debuff
function Tracker:cast(now, name, cost, meta, targetKey, duration)
  self.lastCast[name] = now
  meta = meta or {}
  targetKey = targetKey or "target"
  local lasts = meta.debuff and (duration or meta.debuff)
  local dotKey = targetKey .. "|" .. name
  local before = self.dots[dotKey]            -- kept so a resisted recast can be undone
  if before and now >= before.expires then before = nil end
  if lasts then
    self.dots[dotKey] = { target = targetKey, name = name, expires = now + lasts, duration = lasts }
    -- outside a fight nothing clears old timers: drop the ones that ran out
    self.dotCount = (self.dotCount or 0) + 1
    if self.dotCount > 40 then
      self.dotCount = 0
      for key, d in pairs(self.dots) do if now >= d.expires then self.dots[key] = nil end end
      for key in pairs(self.immune) do self.immune[key] = nil end
    end
  end
  if meta.totem then self.totems[meta.totem] = { name = name, expires = now + (meta.lasts or 60) } end
  local c = { name = name, cost = cost, meta = meta, target = targetKey, at = now, dotKey = lasts and dotKey or nil, before = before }
  local list = self.recentCasts
  list[#list + 1] = c
  if #list > 12 then table.remove(list, 1) end
  if self.fight then
    record(self.fight, c)
  else
    self.pre[#self.pre + 1] = c
    while self.pre[1] and now - self.pre[1].at > PRECAST_WINDOW do table.remove(self.pre, 1) end
  end
end

-- The game said "something was resisted on your target" just now. It does
-- not say what, so we take your most recent harmful cast that could still be
-- waiting for its result, and undo it: its damage over time is not running,
-- and it does not count as cast on that enemy. `immune` also remembers that
-- this enemy cannot be affected by it. Returns the cast, or nil.
function Tracker:castMissed(now, immune)
  for i = #self.recentCasts, 1, -1 do
    local c = self.recentCasts[i]
    local window = c.meta.travel and FLIGHT_WINDOW or RESULT_WINDOW
    if now - c.at > FLIGHT_WINDOW then break end
    if not c.missed and (c.meta.debuff or c.meta.harm) and now - c.at <= window then
      c.missed = immune and "immune" or "resist"
      if c.dotKey then self.dots[c.dotKey] = c.before end
      if immune then self.immune[c.target .. "|" .. c.name] = true end
      local f = self.fight
      if f then
        local on = f.onTarget[c.target]
        if on and on[c.name] and on[c.name] > 0 then on[c.name] = on[c.name] - 1 end
        f.missed = (f.missed or 0) + 1
        f.missedBy = f.missedBy or {}
        f.missedBy[c.name] = (f.missedBy[c.name] or 0) + 1
      end
      self.lastMiss = { name = c.name, target = c.target, at = now, immune = immune == true }
      return c
    end
  end
end

function Tracker:isImmune(targetKey, name)
  return self.immune[(targetKey or "target") .. "|" .. name] == true
end

function Tracker:swing()
  if self.fight then self.fight.swings = self.fight.swings + 1 end
end

function Tracker:spent()
  return self.fight and self.fight.spent or 0
end

function Tracker:fightTime(now)
  return self.fight and (now - self.fight.start) or 0
end

-- Seconds since you first hit this enemy in the current fight.
function Tracker:timeOnTarget(targetKey, now)
  local f = self.fight
  if not f then return 0 end
  local at = f.engaged[targetKey or "target"]
  return at and (now - at) or 0
end

-- Seconds left on your damage-over-time spell on that enemy (0 when gone).
function Tracker:debuffLeft(targetKey, name, now)
  local d = self.dots[(targetKey or "target") .. "|" .. name]
  if not d or now >= d.expires then return 0 end
  return d.expires - now
end

function Tracker:debuffUp(targetKey, name, now)
  return self:debuffLeft(targetKey, name, now) > 0
end

-- Your running damage-over-time spells on one enemy, soonest to expire first.
function Tracker:dotsOn(targetKey, now)
  targetKey = targetKey or "target"
  local list = {}
  for _, d in pairs(self.dots) do
    if d.target == targetKey and now < d.expires then
      list[#list + 1] = { name = d.name, left = d.expires - now, duration = d.duration }
    end
  end
  table.sort(list, function(a, b) return a.left < b.left end)
  return list
end

-- How many other enemies still carry one of your damage-over-time spells.
function Tracker:otherDotted(targetKey, now)
  targetKey = targetKey or "target"
  local seen, count = {}, 0
  for _, d in pairs(self.dots) do
    if d.target ~= targetKey and now < d.expires and not seen[d.target] then
      seen[d.target] = true
      count = count + 1
    end
  end
  return count
end

-- Your last few casts on this enemy, oldest first.
function Tracker:recent(targetKey, count, now, maxAge)
  targetKey = targetKey or "target"
  local out = {}
  for i = #self.recentCasts, 1, -1 do
    local c = self.recentCasts[i]
    if c.target == targetKey and (not maxAge or now - c.at <= maxAge) then
      table.insert(out, 1, c)
      if #out >= count then break end
    end
  end
  return out
end

function Tracker:totemUp(element, now)
  local t = self.totems[element]
  return t ~= nil and now < t.expires
end

-- Totem state read from the game out of combat beats our own timer.
function Tracker:setTotem(element, up, now)
  if up == false then self.totems[element] = nil
  elseif up == true and not self:totemUp(element, now) then
    self.totems[element] = { name = "?", expires = now + 30 }
  end
end

function Tracker:sinceCast(name, now)
  local at = self.lastCast[name]
  if not at then return math.huge end
  return now - at
end

function Tracker:castsOnTarget(targetKey, name)
  local f = self.fight
  if not f then return 0 end
  local on = f.onTarget[targetKey or "target"]
  return on and on[name] or 0
end

-- Ends the fight and returns its summary.
function Tracker:endFight(now, manaEnd, manaMax)
  local f = self.fight
  self.fight = nil
  if not f then return nil end
  local list = {}
  for name, n in pairs(f.casts) do
    list[#list + 1] = { name = name, count = n, mana = f.spentBy[name] or 0 }
  end
  table.sort(list, function(a, b)
    if a.mana ~= b.mana then return a.mana > b.mana end
    return a.name < b.name
  end)
  local max = manaMax or f.manaMax
  local summary = {
    duration = now - f.start, target = f.target, targetLevel = f.targetLevel, elite = f.elite,
    casts = list, castCount = f.casts, spent = f.spent, spentBy = f.spentBy, swings = f.swings,
    manaStart = f.manaStart, manaEnd = manaEnd, manaMax = max, hadPet = f.hadPet, demon = f.demon,
    targets = math.max(1, f.targets), precast = f.precast == true,
    missed = f.missed or 0, missedBy = f.missedBy or {},
  }
  if max and max > 0 then
    if f.manaStart then summary.startPct = f.manaStart / max * 100 end
    if manaEnd then summary.endPct = manaEnd / max * 100 end
    summary.spentPct = f.spent / max * 100
  end
  self.last = summary
  -- Combat is over: every enemy you were fighting is dead or has reset.
  self.dots = {}
  self.recentCasts = {}
  self.immune = {}
  self.lastMiss = nil
  return summary
end
