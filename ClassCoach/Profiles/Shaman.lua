-- Shaman profiles. Spell ids are the Classic ranks, lowest first; if Forever
-- changed an id, the addon falls back to the English spell name.
local _, ns = ...

local function n(summary, key) return summary.castCount[key] or 0 end

-- Spells shared by every Shaman spec ------------------------------------
local SHAMAN_SPELLS = {
  ["Lightning Bolt"]   = { ids = { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208 } },
  ["Earth Shock"]      = { ids = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 } },
  ["Flame Shock"]      = { ids = { 8050, 8052, 8053, 10447, 10448, 29228 }, debuff = 12 },
  ["Frost Shock"]      = { ids = { 8056, 8058, 10472, 10473 } },
  ["Lightning Shield"] = { ids = { 324, 325, 905, 945, 8134, 10431, 10432 } },
  ["Water Shield"]     = {},  -- new in Forever (Restoration talent): looked up by name
  ["Rockbiter Weapon"] = { ids = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 } },
  ["Flametongue Weapon"] = { ids = { 8024, 8027, 8030, 16339, 16341, 16342 } },
  ["Windfury Weapon"]  = { ids = { 8232, 8235, 10486, 16362 } },
  ["Searing Totem"]    = { ids = { 3599, 6363, 6364, 6365, 10437, 10438 }, totem = "fire", lasts = 30 },
  ["Strength of Earth Totem"] = { ids = { 8075, 8160, 8161, 10442, 25361 }, totem = "earth", lasts = 120 },
  ["Stoneskin Totem"]  = { ids = { 8071, 8154, 8155, 10406, 10407, 10408 }, totem = "earth", lasts = 120 },
  ["Mana Spring Totem"] = { ids = { 5675, 10495, 10496, 10497 }, totem = "water", lasts = 60 },
  ["Healing Stream Totem"] = { ids = { 5394, 6375, 6377, 10462, 10463 }, totem = "water", lasts = 60 },
  ["Windfury Totem"]   = { ids = { 8512, 10613, 10614 }, totem = "air", lasts = 120 },
  ["Healing Wave"]     = { ids = { 331, 332, 547, 913, 939, 959, 8005, 10395, 10396, 25357 } },
  ["Lesser Healing Wave"] = { ids = { 8004, 8008, 8010, 10466, 10467, 10468 } },
  ["Chain Heal"]       = { ids = { 1064, 10622, 10623 } },
  ["Reincarnation"]    = { ids = { 20608 } },
}

local function spells(extra)
  local t = {}
  for k, v in pairs(SHAMAN_SPELLS) do
    local copy = {}
    for a, b in pairs(v) do copy[a] = b end
    t[k] = copy
  end
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

-- What the trainer teaches (from WoW Forever leveling guides).
local TRAINER = {
  [1] = "Lightning Bolt, Rockbiter Weapon, Healing Wave",
  [4] = "Earth Shock (also do your Earth totem quest)",
  [6] = "Earthbind Totem",
  [8] = "Stoneclaw Totem, Lightning Shield",
  [10] = "Flame Shock, Strength of Earth Totem, Flametongue Weapon (and the Fire totem quest)",
  [12] = "Fire Nova, Purge, Ancestral Spirit",
  [16] = "Cure Poison",
  [18] = "Tremor Totem",
  [20] = "Ghost Wolf, Lesser Healing Wave, Frost Shock, Call of the Elements (and the Water totem quest)",
  [22] = "Cure Disease, Poison Cleansing Totem, Totemic Call",
  [26] = "Magma Totem, Mana Spring Totem",
  [28] = "Flametongue Totem",
  [30] = "Windfury Weapon, Reincarnation, Astral Recall, Grounding Totem (and the Air totem quest)",
  [32] = "Chain Lightning, Windfury Totem",
  [38] = "Disease Cleansing Totem",
  [40] = "Chain Heal, Mail armour, riding and Dual Specialization",
}

-- Shared checks before a pull.
local CHECKLIST = {
  { buff = { "Lightning Shield", "Water Shield" }, label = "No shield", hint = "Cast Lightning Shield (or Water Shield) before the pull." },
  { weapon = { "Windfury Weapon", "Flametongue Weapon", "Rockbiter Weapon" }, label = "No weapon buff",
    hint = "Put your weapon buff on: Rockbiter early, Windfury from level 30." },
  { item = 17030, needs = "Reincarnation", label = "No Ankh", hint = "Buy Ankhs at a reagent vendor so Reincarnation works." },
}

---------------------------------------------------------------------------
-- Enhancement: melee leveling spec
---------------------------------------------------------------------------
ns.RegisterProfile({
  class = "SHAMAN", spec = "Enhancement", tab = 2, default = true,
  freeDamage = "your melee swings",
  mana = { low = 25, medium = 55 },
  spells = spells({
    ["Stormstrike"] = { ids = { 17364 }, core = true },
    ["Rage of the Farseer"] = {},   -- Forever talent (level 40): by name
  }),

  -- In combat: first entry that is known, ready, affordable and allowed wins.
  priority = {
    { spell = "Rage of the Farseer", when = function(s) return s.target.elite end,
      why = "Big cooldown: use it on elites and tough fights." },
    { spell = "Stormstrike", why = "Your main attack. Press it every time it lights up." },
    { spell = "Flame Shock", mana = "medium", when = function(s) return not s:debuffUp("Flame Shock") end,
      why = "Put Flame Shock on the enemy once." },
    { spell = "Searing Totem", mana = "medium",
      when = function(s) return not s:totemUp("fire") and (s.target.elite or s.manaLevel == "high") end,
      why = "Drop Searing Totem on tougher fights." },
    { spell = "Earth Shock", mana = "high", when = function(s) return not s:known("Stormstrike") end,
      why = "Spare mana: one Earth Shock. Keep some for interrupts." },
  },
  filler = {
    { label = "Melee", why = "Your swings cost nothing. Let them work." },
  },

  -- Out of combat, enemy targeted: how to pull.
  opener = {
    { spell = "Lightning Bolt", mana = "medium", when = function(s) return s.level < 20 end,
      why = "Pull with one Lightning Bolt, then melee." },
  },

  checklist = CHECKLIST,

  advice = {
    low = "Mana low: melee only. Earth Shock only to interrupt a caster.",
    medium = "Stormstrike and Flame Shock only. Skip extra shocks.",
  },

  -- After-fight coaching. Return a sentence or nil.
  tips = {
    function(f)
      if n(f, "Earth Shock") >= 2 and (f.endPct or 100) < 45 then
        return ("Earth Shock ×%d cost %d mana. Keep it for interrupts and runners; melee is free.")
          :format(n(f, "Earth Shock"), f.spentBy["Earth Shock"] or 0)
      end
    end,
    function(f)
      if n(f, "Searing Totem") > 0 and f.duration < 10 then
        return ("Searing Totem on a %ds fight wastes mana. Save it for tougher enemies."):format(math.floor(f.duration))
      end
    end,
    function(f, s)
      if s:known("Stormstrike") and n(f, "Stormstrike") == 0 and f.duration > 10 then
        return "Stormstrike wasn't used. Press it every time it lights up (every 8 seconds)."
      end
    end,
    function(f, s)
      if f.duration > 20 and n(f, "Lightning Bolt") >= 3 then
        return "Several Lightning Bolts in melee range: as Enhancement, one bolt to pull is enough."
      end
    end,
  },

  trainer = TRAINER,

  -- Talent order after the 12 November patch (All Things How).
  talents = {
    { 10, 14, "Thundering Strikes" }, { 15, 17, "Mental Dexterity" }, { 18, 19, "Improved Lightning Shield" },
    { 20, 20, "Shamanistic Focus" }, { 21, 23, "Elemental Weapons" }, { 24, 24, "Improved Lightning Shield" },
    { 25, 25, "Stormstrike" }, { 26, 30, "Flurry" }, { 31, 31, "Spirit Weapons" }, { 32, 33, "Improved Stormstrike" },
    { 34, 35, "Mental Quickness" }, { 36, 39, "Maelstrom Weapon" }, { 40, 40, "Rage of the Farseer" },
    { 41, 41, "Maelstrom Weapon" }, { 42, 46, "Toughness" }, { 47, 48, "Improved Ghost Wolf" },
    { 49, 51, "Anticipation" }, { 52, 53, "Guardian Totems" }, { 54, 55, "Earth's Grasp" }, { 56, 60, "Ancestral Knowledge" },
  },
})
