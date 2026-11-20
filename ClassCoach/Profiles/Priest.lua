-- Priest profiles. Spell ids are the Classic ranks, lowest first; if Forever
-- changed an id, the addon falls back to the English spell name.
local _, ns = ...

local function n(summary, key) return summary.castCount[key] or 0 end

local PRIEST_SPELLS = {
  ["Smite"]              = { ids = { 585, 591, 598, 984, 1004, 6060, 10933, 10934 } },
  ["Shadow Word: Pain"]  = { ids = { 589, 594, 970, 992, 2767, 10892, 10893, 10894 }, debuff = 18, core = true },
  ["Mind Blast"]         = { ids = { 8092, 8102, 8103, 8104, 8105, 8106, 10945, 10946, 10947 } },
  ["Holy Fire"]          = { ids = { 14914, 15262, 15263, 15264, 15265, 15266, 15267, 15261 } },
  ["Penance"]            = {},   -- Forever Discipline talent: looked up by name
  ["Power Word: Shield"] = { ids = { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 } },
  ["Power Word: Fortitude"] = { ids = { 1243, 1244, 1245, 2791, 10937, 10938 } },
  ["Inner Fire"]         = { ids = { 588, 7128, 602, 1006, 10951, 10952 } },
  ["Renew"]              = { ids = { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 } },
  ["Lesser Heal"]        = { ids = { 2050, 2052, 2053 } },
  ["Flash Heal"]         = { ids = { 2061, 9472, 9473, 9474, 10915, 10916, 10917 } },
  ["Shoot"]              = { ids = { 5019 }, core = true },
}

-- Classic trainer levels. Forever also gives every Priest Devouring Plague,
-- Fear Ward and Shadow Word: Death; their levels may differ.
local TRAINER = {
  [1] = "Smite, Lesser Heal, Power Word: Fortitude",
  [4] = "Shadow Word: Pain",
  [6] = "Power Word: Shield",
  [8] = "Renew, Fade",
  [10] = "Mind Blast, Resurrection",
  [12] = "Inner Fire",
  [14] = "Psychic Scream",
  [16] = "Heal",
  [18] = "Dispel Magic",
  [20] = "Flash Heal, Shackle Undead, Mind Soothe",
  [24] = "Mana Burn",
  [30] = "Prayer of Healing, Mind Control, Shadow Protection",
  [32] = "Abolish Disease",
  [34] = "Levitate",
  [40] = "Greater Heal, riding and Dual Specialization",
}

---------------------------------------------------------------------------
-- Discipline: wand + damage-over-time leveling, shields and Penance
---------------------------------------------------------------------------
ns.RegisterProfile({
  class = "PRIEST", spec = "Discipline", tab = 1, default = true,
  freeDamage = "your wand",
  mana = { low = 30, medium = 60 },
  spells = PRIEST_SPELLS,

  priority = {
    { spell = "Power Word: Shield", mana = "medium",
      when = function(s) return s.fightTime < 4 and s:sinceCast("Power Word: Shield") > 15 end,
      why = "Shield first, so hits don't slow your casts." },
    { spell = "Shadow Word: Pain", mana = "medium", when = function(s) return not s:debuffUp("Shadow Word: Pain") end,
      why = "Keep Shadow Word: Pain on the enemy." },
    { spell = "Mind Blast", mana = "medium", when = function(s) return s:castsOnTarget("Mind Blast") == 0 end,
      why = "One Mind Blast per enemy." },
    { spell = "Penance", mana = "medium", why = "Penance hits hard for its cost." },
    { spell = "Smite", mana = "high", when = function(s) return s:castsOnTarget("Smite") < 2 end,
      why = "Spare mana: a Smite or two, then wand." },
  },
  filler = {
    { spell = "Shoot", when = function(s) return s.hasWand end,
      why = "Wand: free damage, and your mana comes back while you shoot." },
    { label = "Melee", why = "No wand yet: melee to save mana. Get a wand soon." },
  },

  opener = {
    { spell = "Mind Blast", mana = "medium", why = "Open with Mind Blast from range." },
    { spell = "Smite", mana = "medium", why = "Open with Smite from range." },
  },

  checklist = {
    { buff = "Power Word: Fortitude", label = "No Fortitude", hint = "Cast Power Word: Fortitude on yourself." },
    { buff = "Inner Fire", label = "No Inner Fire", hint = "Cast Inner Fire before the pull." },
    { slot = 18, needs = "Shoot", label = "No wand", hint = "Equip a wand: it's your free damage while leveling." },
  },

  advice = {
    low = "Mana low: wand (Shoot) until it dies, then drink.",
    medium = "Shadow Word: Pain, then wand. Skip extra Smites.",
  },

  tips = {
    function(f, s)
      if s.hasWand and n(f, "Shoot") == 0 and f.duration > 8 and (f.endPct or 100) < 60 then
        return "Finish enemies with your wand: it costs nothing and your mana comes back while you shoot."
      end
    end,
    function(f)
      if n(f, "Smite") >= 3 and (f.endPct or 100) < 45 then
        return ("Smite ×%d cost %d mana. One or two per fight, then wand."):format(n(f, "Smite"), f.spentBy["Smite"] or 0)
      end
    end,
    function(f)
      if n(f, "Power Word: Shield") >= 2 and f.duration < 20 then
        return "Two shields in a short fight is expensive. One at the start is enough on normal enemies."
      end
    end,
  },

  trainer = TRAINER,

  -- Suggested leveling path; check your guide (Penance is a Discipline talent).
  talents = {
    { 10, 11, "Wand Specialization" },
    { 12, 16, "Spirit Tap (Shadow): mana back after kills" },
    { 17, 60, "Discipline: rush Meditation and Penance" },
  },
})
