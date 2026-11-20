-- Copy to ClassCoach/Profiles/<Class>.lua, fill in, and add it to ClassCoach.toc.
-- See docs/EXTENDING.md for every field.
local _, ns = ...

local function n(f, key) return f.castCount[key] or 0 end

ns.RegisterProfile({
  class = "MAGE",            -- class token
  spec = "Frost",            -- shown on the panel; /coach spec Frost
  tab = 3,                   -- talent tree number for automatic picking
  default = true,            -- used before level 10
  freeDamage = "your wand",
  mana = { low = 25, medium = 55 },

  spells = {
    ["Frostbolt"]   = { ids = { 116, 205, 837 } },          -- ranks, lowest first
    ["Fire Blast"]  = { ids = { 2136, 2137 } },
    ["Frost Armor"] = { ids = { 168, 7300 } },
    ["Shoot"]       = { ids = { 5019 }, core = true },
  },

  priority = {
    { spell = "Fire Blast", mana = "medium", why = "Instant damage while it moves to you." },
    { spell = "Frostbolt", mana = "medium", why = "Your main spell." },
  },
  filler = {
    { spell = "Shoot", when = function(s) return s.hasWand end, why = "Wand to save mana." },
    { label = "Melee" },
  },
  opener = {
    { spell = "Frostbolt", why = "Pull from max range with Frostbolt." },
  },

  checklist = {
    { buff = "Frost Armor", label = "No armor", hint = "Cast Frost Armor." },
    { slot = 18, needs = "Shoot", label = "No wand", hint = "Equip a wand." },
  },

  advice = {
    low = "Mana low: wand it down, then drink.",
  },

  tips = {
    function(f)
      if n(f, "Frostbolt") >= 5 and (f.endPct or 100) < 30 then
        return "Five Frostbolts emptied you. Wand the last part of each fight."
      end
    end,
  },

  trainer = { [4] = "Frostbolt rank 2", [6] = "Fire Blast" },
  talents = { { 10, 14, "Improved Frostbolt" } },
})
