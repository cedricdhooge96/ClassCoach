-- Remembers what you did: casts, swings, damage-over-time spells on each
-- enemy, totems, and a running record of the current fight.
-- The game hides most of this from addons in combat, so we count it ourselves
-- from your own casts. Pure Lua with no game calls, so it can be tested.
local _, ns = ...

local Tracker = {}
Tracker.__index = Tracker
ns.Tracker = Tracker

function Tracker.new()
  return setmetatable({ lastCast = {}, dots = {}, totems = {}, fight = nil, last = nil }, Tracker)
end

function Tracker:startFight(now, info)
  info = info or {}
  self.fight = {
    start = now, target = info.target, targetLevel = info.targetLevel,
    manaStart = info.manaStart, manaMax = info.manaMax, hadPet = info.hasPet,
    casts = {}, spent = 0, spentBy = {}, swings = 0, onTarget = {},
  }
end

-- meta: the profile's data for this spell (debuff, totem, lasts, optional...)
function Tracker:cast(now, name, cost, meta, targetKey)
  self.lastCast[name] = now
  meta = meta or {}
  targetKey = targetKey or "target"
  if meta.debuff then self.dots[targetKey .. "|" .. name] = now + meta.debuff end
  if meta.totem then self.totems[meta.totem] = { name = name, expires = now + (meta.lasts or 60) } end
  local f = self.fight
  if not f then return end
  f.casts[name] = (f.casts[name] or 0) + 1
  -- Spells that give mana back (Life Tap): a rough share of your maximum.
  if meta.restores and f.manaMax then f.restored = (f.restored or 0) + meta.restores * f.manaMax end
  if cost and cost > 0 then
    f.spent = f.spent + cost
    f.spentBy[name] = (f.spentBy[name] or 0) + cost
  end
  local on = f.onTarget[targetKey]
  if not on then on = {}; f.onTarget[targetKey] = on end
  on[name] = (on[name] or 0) + 1
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

function Tracker:debuffUp(targetKey, name, now)
  local untilTime = self.dots[(targetKey or "target") .. "|" .. name]
  return untilTime ~= nil and now < untilTime
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
    duration = now - f.start, target = f.target, targetLevel = f.targetLevel,
    casts = list, castCount = f.casts, spent = f.spent, spentBy = f.spentBy, swings = f.swings,
    manaStart = f.manaStart, manaEnd = manaEnd, manaMax = max, hadPet = f.hadPet,
  }
  if max and max > 0 then
    if f.manaStart then summary.startPct = f.manaStart / max * 100 end
    if manaEnd then summary.endPct = manaEnd / max * 100 end
    summary.spentPct = f.spent / max * 100
  end
  self.last = summary
  -- damage-over-time spells on dead enemies don't matter any more
  for k, untilTime in pairs(self.dots) do if now >= untilTime then self.dots[k] = nil end end
  return summary
end
