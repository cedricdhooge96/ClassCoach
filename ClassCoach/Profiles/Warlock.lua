-- Warlock profiles. Spell ids are the Classic ranks, lowest first; if Forever
-- changed an id, the addon falls back to the English spell name.
-- Forever renamed Curse of Agony to Bane of Agony and added Wrack.
local _, ns = ...

local function n(f, key) return f.castCount[key] or 0 end

local WARLOCK_SPELLS = {
  ["Shadow Bolt"]    = { ids = { 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307 } },
  ["Immolate"]       = { ids = { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309 }, debuff = 15 },
  ["Corruption"]     = { ids = { 172, 6222, 6223, 7648, 11671, 11672, 25311 }, debuff = 15, core = true },
  ["Bane of Agony"]  = { ids = { 980, 1014, 6217, 11711, 11712, 11713 }, debuff = 24, core = true },
  ["Siphon Life"]    = { ids = { 18265, 18879, 18880, 18881 }, debuff = 30 },
  ["Curse of the Elements"] = { ids = { 1490, 11721, 11722 }, debuff = 300 },
  ["Wrack"]          = {},   -- new Forever talent (level 47): by name
  ["Life Tap"]       = { ids = { 1454, 1455, 1456, 11687, 11688, 11689 }, core = true },
  ["Drain Life"]     = { ids = { 689, 699, 709, 7651, 11699, 11700 } },
  ["Drain Soul"]     = { ids = { 1120, 8288, 8289, 11675 } },
  ["Fear"]           = { ids = { 5782, 6213, 6215 } },
  ["Demon Skin"]     = { ids = { 687, 696 } },
  ["Demon Armor"]    = { ids = { 706, 1086, 11733, 11734, 11735 } },
  ["Summon Imp"]     = { ids = { 688 } },
  ["Summon Voidwalker"] = { ids = { 697 } },
  ["Summon Succubus"] = { ids = { 712 } },
  ["Summon Felhunter"] = { ids = { 691 } },
  ["Shoot"]          = { ids = { 5019 }, core = true },
}

-- What the trainer teaches (Method and Warcraft Tavern Forever guides).
local TRAINER = {
  [1] = "Shadow Bolt, Immolate, Demon Skin, Summon Imp",
  [4] = "Corruption, Curse of Weakness",
  [6] = "Life Tap, Shadow Bolt rank 2",
  [8] = "Bane of Agony, Fear",
  [10] = "Drain Soul, Create Healthstone; do the Voidwalker class quest",
  [12] = "Health Funnel",
  [14] = "Drain Life, Curse of Recklessness",
  [16] = "Unending Breath, Life Tap rank 2",
  [18] = "Searing Pain, Create Soulstone",
  [20] = "Demon Armor, Curse of the Elements, Rain of Fire, Ritual of Summoning; Succubus/Incubus class quest",
  [22] = "Eye of Kilrogg",
  [24] = "Drain Mana",
  [30] = "Subjugate Demon, Hellfire, Soul Link; Felhunter class quest",
  [40] = "Felsteed class quest, riding and Dual Specialization",
  [42] = "Death Coil",
  [50] = "Inferno",
  [60] = "Ritual of Doom; Dreadsteed quest chain",
}

---------------------------------------------------------------------------
-- Affliction: damage over time, a demon to tank, Life Tap instead of drinking
---------------------------------------------------------------------------
ns.RegisterProfile({
  class = "WARLOCK", spec = "Affliction", tab = 1, default = true,
  freeDamage = "your demon and your wand",
  mana = { low = 25, medium = 55 },
  restHint = "Life Tap if your health is high, then eat food to get the health back.",
  spells = WARLOCK_SPELLS,

  priority = {
    { spell = "Bane of Agony", mana = "medium", when = function(s) return not s:debuffUp("Bane of Agony") end,
      why = "Bane of Agony first: it tags the enemy and lets your demon take the hits." },
    { spell = "Corruption", mana = "medium", when = function(s) return not s:debuffUp("Corruption") end,
      why = "Corruption next. Damage over time does the work while you wait." },
    { spell = "Immolate", mana = "medium",
      when = function(s) return not s:debuffUp("Immolate") and (s.level < 8 or s.target.elite or s.manaLevel == "high") end,
      why = "Immolate on tougher enemies, or while you have spare mana." },
    { spell = "Siphon Life", mana = "medium", when = function(s) return not s:debuffUp("Siphon Life") end,
      why = "Siphon Life heals you while it ticks." },
    { spell = "Curse of the Elements", mana = "medium",
      when = function(s) return s.target.elite and not s:debuffUp("Curse of the Elements") end,
      why = "Elite: Curse of the Elements makes your spells hit harder." },
    { spell = "Life Tap", when = function(s) return s.manaLevel == "low" end,
      why = "Mana low: Life Tap if your health is above half. Drain Life or food gets it back." },
    { spell = "Wrack", mana = "high", why = "Spare mana: channel Wrack." },
    { spell = "Drain Life", mana = "medium", when = function(s) return s.level >= 30 end,
      why = "Drain Life is your filler from 30: damage and healing." },
    { spell = "Shadow Bolt", mana = "high", when = function(s) return s.level < 10 and s:castsOnTarget("Shadow Bolt") < 2 end,
      why = "Early levels: a Shadow Bolt while mana is high." },
  },
  filler = {
    { spell = "Shoot", when = function(s) return s.hasWand end,
      why = "Wand while your damage over time ticks. It costs no mana." },
    { label = "Melee", why = "No wand yet: get one soon (Lesser Magic Wand, level 5)." },
  },

  opener = {
    { spell = "Bane of Agony", why = "Send your demon in, then pull with Bane of Agony." },
    { spell = "Immolate", why = "Pull with Immolate, then Shadow Bolt and wand." },
  },

  checklist = {
    { pet = true, needs = { "Summon Imp", "Summon Voidwalker", "Summon Succubus", "Summon Felhunter" },
      label = "No demon", hint = "Summon your demon. The Voidwalker (from level 10) takes the hits for you." },
    { buff = { "Demon Skin", "Demon Armor" }, label = "No armor", hint = "Cast Demon Skin (Demon Armor from 20)." },
    { item = 6265, needs = "Drain Soul", minLevel = 10, label = "No Soul Shard",
      hint = "Finish an enemy with rank 1 Drain Soul to get a shard for summons and Healthstones." },
    { slot = 18, needs = "Shoot", label = "No wand", hint = "Equip a wand: your free damage while leveling." },
  },

  advice = {
    low = "Mana low: Life Tap if health is above half, then wand.",
    medium = "Bane of Agony and Corruption, then wand. Skip Shadow Bolt.",
  },

  tips = {
    function(f)
      if f.hadPet == false and f.duration > 6 then
        return "You fought without your demon. Summon it first; it takes the hits and adds free damage."
      end
    end,
    function(f)
      if n(f, "Shadow Bolt") >= 3 and (f.endPct or 100) < 45 then
        return ("Shadow Bolt ×%d cost %d mana. As Affliction, damage over time plus wand does the job for less.")
          :format(n(f, "Shadow Bolt"), f.spentBy["Shadow Bolt"] or 0)
      end
    end,
    function(f, s)
      if s.hasWand and n(f, "Shoot") == 0 and f.duration > 10 then
        return "After your damage over time is on, wand the enemy instead of standing idle."
      end
    end,
    function(f)
      if (f.endPct or 100) < 30 and n(f, "Life Tap") == 0 then
        return "Low on mana: Life Tap between fights instead of drinking, then eat to heal."
      end
    end,
  },

  trainer = TRAINER,

  -- Warcraft Tavern's Affliction build (41/7/3): no respec needed.
  talents = {
    { 10, 14, "Improved Corruption" }, { 15, 17, "Suppression" }, { 18, 22, "Unholy Power (Demonology)" },
    { 23, 24, "Demonic Energies (Demonology)" }, { 25, 27, "Improved Drains" }, { 28, 28, "Amplify Curse" },
    { 29, 30, "Improved Bane of Agony" }, { 31, 32, "Suppression" }, { 33, 35, "Pandemic" },
    { 36, 36, "Improved Life Tap" }, { 37, 37, "Siphon Life" }, { 38, 40, "Soul Siphon" },
    { 41, 41, "Improved Life Tap" }, { 42, 46, "Shadow Mastery" }, { 47, 47, "Wrack" },
    { 48, 52, "Malevolence" }, { 53, 55, "Fel Concentration" }, { 56, 57, "Nightfall" }, { 58, 60, "Improved Shadow Bolt" },
  },
})
