-- The list of class profiles and the rule for picking one.
--
-- A profile is a plain table that describes one class + spec: its spells,
-- what to check before a fight, what to press, and how to coach. The engine
-- knows nothing about any class; everything class-specific lives in
-- Profiles/<Class>.lua. See docs/EXTENDING.md for the full format.
local _, ns = ...

local Profiles = { list = {} }
ns.Profiles = Profiles

local function fail(p, msg)
  local who = tostring(p and p.class) .. " " .. tostring(p and p.spec)
  error("ClassCoach profile " .. who .. ": " .. msg, 3)
end

-- Called from each Profiles/<Class>.lua file.
function ns.RegisterProfile(p)
  if type(p) ~= "table" then fail(p, "must be a table") end
  if type(p.class) ~= "string" then fail(p, "needs class (e.g. \"SHAMAN\", or \"ANY\")") end
  if type(p.spec) ~= "string" then fail(p, "needs spec (e.g. \"Enhancement\")") end
  p.spells = p.spells or {}
  for key, data in pairs(p.spells) do
    if type(data) ~= "table" then fail(p, "spell " .. key .. " must be a table") end
    data.name = data.name or key
  end
  for i, entry in ipairs(p.priority or {}) do
    if not entry.spell then fail(p, "priority entry " .. i .. " needs spell") end
    if not p.spells[entry.spell] then fail(p, "priority entry " .. i .. " uses unknown spell " .. entry.spell) end
  end
  p.priority = p.priority or {}
  p.opener = p.opener or {}
  p.checklist = p.checklist or {}
  p.tips = p.tips or {}
  p.advice = p.advice or {}
  p.trainer = p.trainer or {}
  p.talents = p.talents or {}
  p.mana = p.mana or {}
  p.mana.low = p.mana.low or 25
  p.mana.medium = p.mana.medium or 55
  Profiles.list[#Profiles.list + 1] = p
  return p
end

function Profiles.forClass(class)
  local out = {}
  for _, p in ipairs(Profiles.list) do
    if p.class == class then out[#out + 1] = p end
  end
  return out
end

local function generic()
  for _, p in ipairs(Profiles.list) do
    if p.class == "ANY" then return p end
  end
end

-- override: a spec name the player picked with /coach spec, or nil for automatic.
-- points: talent points per tree { [1] = n, [2] = n, [3] = n } or nil.
function Profiles.choose(class, points, override)
  local mine = Profiles.forClass(class)
  if #mine == 0 then return generic(), "generic" end
  if override then
    for _, p in ipairs(mine) do
      if p.spec:lower() == override:lower() then return p, "chosen" end
    end
  end
  if points then
    local bestTab, bestPoints = nil, 0
    for tab, n in pairs(points) do
      if n > bestPoints then bestTab, bestPoints = tab, n end
    end
    if bestTab then
      for _, p in ipairs(mine) do
        if p.tab == bestTab then return p, "talents" end
      end
    end
  end
  for _, p in ipairs(mine) do
    if p.default then return p, "default" end
  end
  return mine[1], "default"
end
