-- Priest profiles for WoW Forever. Spell ids are each rank's, lowest first; a
-- spell Forever added or re-numbered is found by its English name instead.
local _, ns = ...

local function n(summary, key) return summary.castCount[key] or 0 end

local PRIEST_SPELLS = {
  ["Smite"]              = { ids = { 585, 591, 598, 984, 1004, 6060, 10933, 10934 }, harm = true },
  ["Shadow Word: Pain"]  = { ids = { 589, 594, 970, 992, 2767, 10892, 10893, 10894 }, debuff = 18, core = true, learn = 4 },
  ["Mind Blast"]         = { ids = { 8092, 8102, 8103, 8104, 8105, 8106, 10945, 10946, 10947 }, cd = true, learn = 10, harm = true },
  ["Holy Fire"]          = { ids = { 14914, 15262, 15263, 15264, 15265, 15266, 15267, 15261 }, harm = true },
  ["Penance"]            = { cd = true, harm = true },   -- Forever Discipline talent: looked up by name
  ["Power Word: Shield"] = { ids = { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 }, learn = 6 },
  ["Power Word: Fortitude"] = { ids = { 1243, 1244, 1245, 2791, 10937, 10938 } },
  ["Inner Fire"]         = { ids = { 588, 7128, 602, 1006, 10951, 10952 }, learn = 12 },
  ["Renew"]              = { ids = { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 } },
  ["Lesser Heal"]        = { ids = { 2050, 2052, 2053 } },
  ["Flash Heal"]         = { ids = { 2061, 9472, 9473, 9474, 10915, 10916, 10917 } },
  ["Shoot"]              = { ids = { 5019 }, core = true, auto = true },
}

-- What Forever's trainer teaches at each level (every Priest gets Devouring
-- Plague, Fear Ward and Shadow Word: Death here, whatever their race).
local TRAINER = {
  [1] = "Smite, Lesser Heal, Power Word: Fortitude",
  [4] = "Shadow Word: Pain",
  [6] = "Power Word: Shield",
  [8] = "Renew, Fade",
  [10] = "Mind Blast, Resurrection, and your racial spell",
  [12] = "Inner Fire",
  [14] = "Psychic Scream, Cure Disease",
  [16] = "Heal",
  [18] = "Dispel Magic",
  [20] = "Flash Heal, Holy Fire, Devouring Plague, Fear Ward, Shackle Undead, Mind Soothe",
  [22] = "Mind Vision",
  [24] = "Mana Burn",
  [30] = "Divine Spirit, Prayer of Healing, Mind Control, Shadow Protection",
  [32] = "Shadow Word: Death, Abolish Disease",
  [34] = "Levitate",
  [40] = "Greater Heal, Lightwell, riding and Dual Specialization",
  [48] = "Prayer of Fortitude",
  [56] = "Prayer of Shadow Protection",
  [60] = "Prayer of Spirit",
}

local function wandOrMelee(s) return s.hasWand and "wand" or "melee" end

---------------------------------------------------------------------------
-- Discipline: wand + damage-over-time leveling, shields and Penance
---------------------------------------------------------------------------
ns.RegisterProfile({
  class = "PRIEST", spec = "Discipline", tab = 1, default = true,
  freeDamage = "your wand",
  mana = { low = 30, medium = 60 },
  spells = PRIEST_SPELLS,

  --   1-3   Smite, then melee (no wand yet)
  --   4-5   Shadow Word: Pain to pull, Smite, then wand or melee
  --   6-9   Power Word: Shield before the pull
  --   10+   shield, Mind Blast, Shadow Word: Pain, then wand
  priority = {
    { spell = "Power Word: Shield", mana = "medium",
      when = function(s) return s.fightTime < 4 and s:sinceCast("Power Word: Shield") > 15 end,
      why = "Shield first, so hits don't slow your casts." },
    { spell = "Shadow Word: Pain", mana = "medium", when = function(s) return not s:debuffUp("Shadow Word: Pain") end,
      why = "Keep Shadow Word: Pain on the enemy." },
    { spell = "Mind Blast", mana = "medium", when = function(s) return s:castsOnTarget("Mind Blast") == 0 end,
      why = "One Mind Blast per enemy." },
    { spell = "Penance", mana = "medium", why = "Penance hits hard for its cost." },
    { spell = "Smite", mana = "high", when = function(s) return s.hasWand and s:castsOnTarget("Smite") < 2 end,
      why = "Spare mana: a Smite or two, then wand." },
  },
  filler = {
    { spell = "Shoot", when = function(s) return s.hasWand end,
      why = "Wand: free damage, and your mana comes back while you shoot." },
    { spell = "Smite", mana = "medium", when = function(s) return not s.hasWand end,
      why = "No wand yet: Smite while you have mana." },
    { label = "Melee", why = function(s)
        if s.hasWand then return "Hit it with your weapon." end
        return s.level >= 5 and "Mana low and no wand: melee it down. Buy a Lesser Magic Wand."
          or "Mana low: finish it in melee."
      end },
  },

  opener = {
    { spell = "Power Word: Shield", mana = "medium", when = function(s) return s:sinceCast("Power Word: Shield") > 15 end,
      why = "Shield yourself, then pull." },
    { spell = "Mind Blast", mana = "medium", why = "Open with Mind Blast from max range." },
    { spell = "Shadow Word: Pain", mana = "medium", why = "Pull with Shadow Word: Pain: instant, and it marks the enemy as yours." },
    { spell = "Smite", why = "Open with Smite from max range." },
  },

  checklist = {
    { buff = "Power Word: Fortitude", label = "No Fortitude", hint = "Cast Power Word: Fortitude on yourself." },
    { buff = "Inner Fire", label = "No Inner Fire", hint = "Cast Inner Fire before the pull." },
    { tip = true, slot = 18, needs = "Shoot", minLevel = 5, label = "No wand", icon = "Interface\\Icons\\INV_Wand_01",
      hint = "Get a wand (Lesser Magic Wand, level 5): your free damage while leveling." },
  },

  advice = {
    low = function(s) return "Mana low: " .. wandOrMelee(s) .. " until it dies, then drink." end,
    medium = function(s)
      local dot = s:have({ "Shadow Word: Pain" })
      return (dot and (dot .. ", then ") or "Then ") .. wandOrMelee(s) .. ". Skip extra Smites."
    end,
  },

  tips = {
    function(f, s)
      if s.hasWand and n(f, "Shoot") == 0 and f.duration > 8 and (f.endPct or 100) < 60 then
        return "Finish enemies with your wand: it costs nothing and your mana comes back while you shoot."
      end
    end,
    function(f, s)
      if s.hasWand and n(f, "Smite") >= 3 and (f.endPct or 100) < 45 then
        return ("Smite ×%d cost %d mana. One or two per fight, then wand."):format(n(f, "Smite"), f.spentBy["Smite"] or 0)
      end
    end,
    function(f)
      if n(f, "Power Word: Shield") >= 2 and f.duration < 20 then
        return "Two shields in a short fight is expensive. One at the start is enough on normal enemies."
      end
    end,
  },

  -- /coach macros builds these from the spells you know.
  macros = {
    { name = "CC Pull",
      about = function(s) return "Follows the coach's pull plan, one spell per press." .. (s:known("Shoot") and " Then use CC Wand." or "") end,
      body = function(s, plan)
        -- the shield has its own key: it targets you, the rest target the enemy
        local order = ns.Engine.sequence(plan, { ["Power Word: Shield"] = true }, 3)
        if #order == 0 then return nil end
        return "#showtooltip\n" .. (#order == 1 and "/cast " or "/castsequence reset=target/combat ") .. table.concat(order, ", ")
      end },
    { name = "CC Shield", about = "Shields you without dropping your target.",
      body = function(s)
        if not s:known("Power Word: Shield") then return nil end
        return "#showtooltip\n/cast [@player] " .. s.spells["Power Word: Shield"].name
      end },
    { name = "CC Wand", about = "Starts your wand; pressing it again won't stop it.",
      body = function(s)
        if not s:known("Shoot") then return nil end
        local shoot = s.spells["Shoot"].name
        return "#showtooltip " .. shoot .. "\n/cast !" .. shoot
      end },
  },

  trainer = TRAINER,

  -- The smart key leaves the shield to its own key: it targets you, not the enemy.
  smart = { skip = { ["Power Word: Shield"] = true } },

  -- /coach bar: three bars by purpose, one entry per button, best candidate first.
  bars = {
    fight = {
      { "macro:CC Pull", "Smite" },
      { "macro:CC Wand", "Shoot" },
      { "Smite" },
      { "Mind Blast" },
      { "Shadow Word: Pain" },
      { "Penance" },
      { "Holy Fire" },
      { "book:Devouring Plague" },
      { "book:Shadow Word: Death" },
      { "book:Mind Flay" },
      { "book:Mana Burn" },
      { "book:Holy Nova" },
    },
    react = {
      { "macro:CC Shield", "Power Word: Shield" },
      { "Renew" },
      { "Flash Heal", "Lesser Heal" },
      { "book:Greater Heal", "book:Heal", "Lesser Heal" },
      { "book:Psychic Scream" },
      { "book:Fade" },
      { "book:Dispel Magic" },
      { "book:Abolish Disease", "book:Cure Disease" },
      { "book:Desperate Prayer" },
      { "item:manapotion", "book:Prayer of Healing" },      -- a potion you carry comes first
      { "item:healingpotion", "book:Shackle Undead" },
      { "book:Prayer of Mending" },
    },
    prep = {
      { "Power Word: Fortitude" },
      { "Inner Fire" },
      { "book:Divine Spirit" },
      { "book:Shadow Protection" },
      { "book:Fear Ward" },
      { "book:Resurrection" },
      { "book:Levitate" },
      { "book:Mind Vision" },
      { "book:Prayer of Fortitude" },
      { "macro:CC Rest" },
      { "item:bandage" },
      { "item:hearth" },
    },
  },

  milestones = {
    { level = 5, text = "Get a wand", hint = "A Lesser Magic Wand (level 5) from an enchanter or the auction house: your free damage.",
      icon = "Interface\\Icons\\INV_Wand_01", done = function(s) return s.hasWand end },
    { level = 30, text = "Penance talent", hint = "A strong, cheap spell for damage and healing: take it as Discipline." },
  },

  -- Forever's wand build: Wand Specialization, Spirit Tap, then Discipline up to
  -- Meditation and Penance (Penance is a Discipline talent from level 30).
  talentsName = "Wand build: Wand Specialization, Spirit Tap, then Discipline",
  builds = {
    { name = "Icy Veins: The Mitigation Machine (Discipline)",
      link = "https://www.icy-veins.com/wow-forever/priest-talent-calculator#tc-22222555558777aaa999dfffffeggghkkkkkmmmmmiiinpppssq~70959-a8fe1dab" },
  },
  talents = {
    { 10, 11, "Wand Specialization" },
    { 12, 16, "Spirit Tap (Shadow): mana back after kills" },
    { 17, 60, "Discipline: rush Meditation and Penance" },
  },
})
