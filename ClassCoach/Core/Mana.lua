-- Works out roughly how much mana you have when the game won't say.
--
-- The mana BAR on the panel is always true: the game draws it for us. But the
-- addon may not read the number, so to plan (what to cast, when to drink) it
-- keeps its own count, the ledger below.
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

-- The ledger: ClassCoach's own running count of your mana, for a client that
-- hides it (Forever hides it in combat, and on some clients out of combat too).
--   spent      what each of your casts cost (exact: the game says what a spell costs)
--   given      what Life Tap and the like give back
--   regen      mana comes back once five seconds have passed since you last spent
--              any (the "five-second rule"); faster while you drink
--   bracket    which spells the game says you can still afford fences it in
-- L = { mana, max, at, lastSpend }. mana is nil until there is anything to go on.
local FSR = 5
local FALLBACK_REGEN = 0.006   -- share of your maximum per second, when the game won't say
local DRINK_SECONDS = 20       -- water for your level fills you up in about this long

function Mana.ledger() return {} end

-- An exact reading: the count starts again from it.
function Mana.set(L, now, mana, max)
  if max then L.max = max end
  L.mana, L.at = mana, now
end

-- One of your casts. cost and given are mana points.
function Mana.spend(L, now, cost, given)
  if (cost or 0) > 0 then L.lastSpend = now end
  if not L.mana then return end
  L.mana = math.max(0, L.mana - (cost or 0)) + (given or 0)
  if L.max and L.mana > L.max then L.mana = L.max end
end

-- Brings the count up to `now`. rates = { idle = per second outside the rule,
-- casting = per second inside it, drinking = true }; unknown rates are guessed.
function Mana.tick(L, now, rates)
  rates = rates or {}
  local from = L.at or now
  L.at = now
  if not L.max or L.max <= 0 then return end
  if not L.mana then L.mana = L.max end   -- nothing to go on yet: a fresh character is full
  local dt = math.min(now - from, 900)
  if dt <= 0 then return end
  local idle = rates.idle or L.max * FALLBACK_REGEN
  local casting = rates.casting or 0
  local quietFrom = (L.lastSpend or -math.huge) + FSR   -- when the rule stops holding regen back
  local inside = math.max(0, math.min(now, quietFrom) - from)
  local gain = inside * casting + (dt - inside) * idle
  if rates.drinking then gain = gain + dt * L.max / DRINK_SECONDS end
  L.mana = math.min(L.max, L.mana + gain)
end

-- Keeps the count between what you can and cannot afford (see Mana.bracket).
function Mana.fence(L, floor, ceiling)
  if not L.mana then return end
  if ceiling and L.mana >= ceiling then L.mana = ceiling - 1 end
  if floor and L.mana < floor then L.mana = floor end
end

-- The count as a percentage of your maximum, or nil.
function Mana.pct(L)
  if L.mana and L.max and L.max > 0 then return math.max(0, math.min(100, L.mana / L.max * 100)) end
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
