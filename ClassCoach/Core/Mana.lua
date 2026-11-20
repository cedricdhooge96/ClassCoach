-- Works out roughly how much mana you have during combat.
--
-- The mana BAR on the panel is always true: the game draws it for us. But the
-- addon may not read the number in combat, so to decide what to suggest
-- (high / medium / low) we combine two clues:
--   1. mana at the start of the fight minus the cost of every spell you cast;
--   2. which of your spells the game says you can still afford, which brackets
--      the real value between the dearest affordable and cheapest unaffordable spell.
-- Pure Lua with no game calls, so it can be tested outside the game.
local _, ns = ...

local Mana = {}
ns.Mana = Mana

-- probes: list of { cost = number, affordable = boolean }
-- Returns floor (you have at least this much) and ceiling (less than this), or nil.
function Mana.bracket(probes)
  local floor, ceiling = 0, nil
  for _, p in ipairs(probes or {}) do
    if p.cost and p.cost > 0 then
      if p.affordable then
        if p.cost > floor then floor = p.cost end
      elseif not ceiling or p.cost < ceiling then
        ceiling = p.cost
      end
    end
  end
  return floor, ceiling
end

-- start: mana when the fight began (exact), spent: total cost of your casts,
-- max: your maximum mana. Returns the estimate and a percentage.
function Mana.estimate(start, spent, max, probes)
  local floor, ceiling = Mana.bracket(probes)
  local est
  if start then
    est = start - (spent or 0)
  elseif ceiling then
    est = (floor + ceiling) / 2
  else
    est = max
  end
  if est and max and est > max then est = max end
  if est and ceiling and est >= ceiling then est = ceiling - 1 end
  if est and est < floor then est = floor end
  if est and est < 0 then est = 0 end
  local pct
  if est and max and max > 0 then pct = math.min(100, est / max * 100) end
  return est, pct, floor, ceiling
end

-- "high", "medium" or "low". The level only rises again once you are a few
-- percent clear of the line, so it doesn't flicker.
function Mana.level(pct, thresholds, previous)
  if not pct then return previous or "high" end
  local low, medium = thresholds.low or 25, thresholds.medium or 55
  local pad = 4
  if previous == "low" and pct < low + pad then return "low" end
  if previous == "medium" and pct < medium + pad and pct >= low then return "medium" end
  if pct < low then return "low" end
  if pct < medium then return "medium" end
  return "high"
end
