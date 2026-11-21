-- Shaman profiles for WoW Forever (Dwarves can be Shamans here). Spell ids are
-- each rank's, lowest first; a spell Forever added or re-numbered is found by
-- its English name when it has no ids.
-- `learn` = the level the trainer sells it; `cd` = it has a cooldown (a string
-- = a cooldown shared by every spell with that string); `cdTime` = that
-- cooldown in seconds, so the coach can count it itself when the game hides it
-- in a fight; `lasts` = how long a totem stands.
--
-- Rotation, totems, imbues and talents follow Icy Veins' Forever guides,
-- read level by level on 22 November 2026:
--   https://www.icy-veins.com/wow-forever/enhancement-shaman-leveling
--   https://www.icy-veins.com/wow-forever/restoration-shaman-leveling
-- Spell ranks: Method's and ConquestCapped's Forever spell lists.
local _, ns = ...

local function n(summary, key) return summary.castCount[key] or 0 end

-- Spells shared by every Shaman spec ------------------------------------
local SHAMAN_SPELLS = {
  ["Lightning Bolt"]   = { ids = { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208 }, harm = true, travel = true },
  ["Chain Lightning"]  = { ids = { 421, 930, 2860, 10605 }, cd = true, learn = 32, harm = true },
  -- the shocks share one 6 second cooldown
  ["Earth Shock"]      = { ids = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 }, cd = "shock", cdTime = 6, learn = 4, harm = true },
  ["Flame Shock"]      = { ids = { 8050, 8052, 8053, 10447, 10448, 29228 }, debuff = 12, cd = "shock", cdTime = 6, learn = 10 },
  ["Frost Shock"]      = { ids = { 8056, 8058, 10472, 10473 }, cd = "shock", cdTime = 6, learn = 20, harm = true },
  -- Forever's Fire Nova: a spell that bursts from your Fire totem (not the old totem)
  ["Fire Nova"]        = { ids = { 408341, 408342, 408343, 408344, 408345 }, cd = true, learn = 12 },
  ["Lightning Shield"] = { self = true, ids = { 324, 325, 905, 945, 8134, 10431, 10432 }, learn = 8 },
  ["Water Shield"]     = { self = true, ids = { 408510 } },   -- Restoration talent (Enhancement takes it at 46)
  ["Rockbiter Weapon"] = { self = true, ids = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 } },
  ["Flametongue Weapon"] = { self = true, ids = { 8024, 8027, 8030, 16339, 16341, 16342 }, learn = 10 },
  ["Frostbrand Weapon"] = { self = true, ids = { 8033, 8038, 10456, 16355, 16356 }, learn = 20 },
  ["Windfury Weapon"]  = { self = true, ids = { 8232, 8235, 10486, 16362 }, learn = 30 },
  -- Totems. Forever made the support totems last 5 minutes.
  ["Searing Totem"]    = { ids = { 3599, 6363, 6364, 6365, 10437, 10438 }, totem = "fire", lasts = 30 },
  ["Magma Totem"]      = { ids = { 8190, 10585, 10586, 10587 }, totem = "fire", lasts = 20, learn = 26 },
  ["Flametongue Totem"] = { ids = { 8227, 8249, 10526, 16387 }, totem = "fire", lasts = 120, learn = 28 },
  ["Strength of Earth Totem"] = { ids = { 8075, 8160, 8161, 10442, 25361 }, totem = "earth", lasts = 300 },
  ["Stoneskin Totem"]  = { ids = { 8071, 8154, 8155, 10406, 10407, 10408 }, totem = "earth", lasts = 300 },
  ["Stoneclaw Totem"]  = { ids = { 5730, 6390, 6391, 6392, 10427, 10428 }, totem = "earth", lasts = 15, cd = true },
  ["Earthbind Totem"]  = { ids = { 2484 }, totem = "earth", lasts = 45, cd = true },
  ["Mana Spring Totem"] = { ids = { 5675, 10495, 10496, 10497 }, totem = "water", lasts = 60, learn = 26 },
  ["Healing Stream Totem"] = { ids = { 5394, 6375, 6377, 10462, 10463 }, totem = "water", lasts = 60 },
  ["Mana Tide Totem"]  = { ids = { 16190, 17354, 17359, 1325256 }, totem = "water", lasts = 12, cd = true },
  ["Windfury Totem"]   = { ids = { 8512, 10613, 10614 }, totem = "air", lasts = 300, learn = 32 },
  ["Grace of Air Totem"] = { ids = { 8835, 10627, 25359 }, totem = "air", lasts = 300, learn = 42 },
  ["Grounding Totem"]  = { ids = { 8177 }, totem = "air", lasts = 45, cd = true, learn = 30 },
  ["Totemic Recall"]   = { self = true, ids = { 36936 } },
  ["Call of the Elements"] = { self = true, ids = { 66842 } },
  -- Heals (on yourself while leveling)
  ["Healing Wave"]     = { self = true, ids = { 331, 332, 547, 913, 939, 959, 8005, 10395, 10396, 25357 } },
  ["Lesser Healing Wave"] = { self = true, ids = { 8004, 8008, 8010, 10466, 10467, 10468 } },
  ["Chain Heal"]       = { self = true, ids = { 1064, 10622, 10623 } },
  ["Riptide"]          = { self = true, ids = { 408521, 1239242, 1239243 }, cd = true, cdTime = 6 },
  ["Nature's Swiftness"] = { self = true, ids = { 16188 }, cd = true },
  ["Ghost Wolf"]       = { self = true, ids = { 2645 } },
  ["Reincarnation"]    = { self = true, ids = { 20608 } },
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

-- What Forever's trainer teaches at each level.
local TRAINER = {
  [1] = "Lightning Bolt, Rockbiter Weapon, Healing Wave",
  [4] = "Earth Shock, Stoneskin Totem (and your Earth totem quest)",
  [6] = "Earthbind Totem",
  [8] = "Lightning Shield, Stoneclaw Totem",
  [10] = "Flame Shock, Searing Totem, Flametongue Weapon, Strength of Earth Totem (and the Fire totem quest)",
  [12] = "Fire Nova, Purge, Ancestral Spirit",
  [16] = "Cure Poison",
  [18] = "Tremor Totem",
  [20] = "Ghost Wolf, Lesser Healing Wave, Frost Shock, Frostbrand Weapon, Healing Stream Totem, Call of the Elements, Totemic Recall (and the Water totem quest)",
  [22] = "Cure Disease, Poison Cleansing Totem, Totemic Call, Water Breathing",
  [24] = "Frost Resistance Totem",
  [26] = "Magma Totem, Mana Spring Totem, Far Sight",
  [28] = "Flametongue Totem, Fire Resistance Totem, Water Walking",
  [30] = "Windfury Weapon, Grounding Totem, Astral Recall, Reincarnation, Nature Resistance Totem (and the Air totem quest)",
  [32] = "Chain Lightning, Windfury Totem",
  [34] = "Sentry Totem",
  [36] = "Windwall Totem",
  [38] = "Disease Cleansing Totem",
  [40] = "Chain Heal, riding and Dual Specialization (50 gold, at any class trainer)",
  [42] = "Grace of Air Totem",
}

-- The weapon buff Icy Veins says to keep up: Rockbiter alone, Flametongue in a
-- group, Windfury always from 30.
local function bestImbue(s)
  if s:known("Windfury Weapon") then return "Windfury Weapon" end
  if s.inGroup and s:known("Flametongue Weapon") then return "Flametongue Weapon" end
  return "Rockbiter Weapon"
end

-- Lightning Shield until you have Water Shield (Restoration talent; Enhancement takes it at 46).
local function bestShield(s)
  return s:known("Water Shield") and "Water Shield" or "Lightning Shield"
end

-- Shared checks before a pull.
local CHECKLIST = {
  { buff = { "Lightning Shield", "Water Shield" }, label = "No shield",
    fix = bestShield,
    hint = function(s) return "Cast " .. bestShield(s) .. " before the pull." end },
  { weapon = { "Windfury Weapon", "Flametongue Weapon", "Rockbiter Weapon", "Frostbrand Weapon" }, label = "No weapon buff",
    fix = bestImbue,
    hint = function(s) return "Put " .. bestImbue(s) .. " on your weapon before the pull." end },
  { tip = true, item = 17030, needs = "Reincarnation", label = "No Ankh", icon = "Interface\\Icons\\INV_Jewelry_Talisman_06", hint = "Buy Ankhs at a reagent vendor so Reincarnation works." },
}

-- No shield before a pull: it goes first on the pull plan, so the pull macro
-- and the smart key start with it. Only when your buffs can be read (out of
-- combat) and the mana allows it; the plan is rebuilt out of combat, so once
-- the shield is up it drops out again. A macro cannot check buffs or mana in a
-- fight: a shield that runs out mid-fight is the coach's ring, not the key.
local function noShield(s)
  return s:buff("Lightning Shield") == false and s:buff("Water Shield") == false
end
local PREPULL_SHIELD = {
  { spell = "Water Shield", mana = "medium", when = noShield, why = "No shield: Water Shield first." },
  { spell = "Lightning Shield", mana = "medium", when = function(s) return noShield(s) and not s:known("Water Shield") end,
    why = "No shield: Lightning Shield first." },
}

-- Totems before the pull (Icy Veins: "Drop Totems before engaging"). Each one
-- only while that element has none standing; they are 5-minute totems, so
-- usually only the Fire totem is new on a pull.
local PREPULL_TOTEMS = {
  { spell = "Strength of Earth Totem", when = function(s) return not s:totemUp("earth") end,
    why = "Earth totem first: Strength of Earth (5 minutes). Stoneskin instead if you take a lot of hits." },
  { spell = "Stoneskin Totem", when = function(s) return not s:totemUp("earth") end,
    why = "Earth totem first: Stoneskin (5 minutes)." },
  { spell = "Windfury Totem", when = function(s) return not s:totemUp("air") end,
    why = "Air totem: Windfury (5 minutes). Grounding Totem instead against casters." },
  { spell = "Mana Spring Totem", when = function(s) return not s:totemUp("water") end,
    why = "Water totem: Mana Spring." },
  { spell = "Magma Totem", mana = "high", when = function(s) return s.inGroup and not s:totemUp("fire") end,
    why = "Fire totem: Magma against a group of enemies." },
  { spell = "Searing Totem", mana = "medium", when = function(s) return not s:totemUp("fire") end,
    why = "Fire totem: Searing. It also lets Fire Nova burst." },
}

local function list(...)
  local out = {}
  for _, t in ipairs({ ... }) do
    for _, e in ipairs(t) do out[#out + 1] = e end
  end
  return out
end

local MILESTONES = {
  { level = 4, text = "Earth totem quest", hint = "Your trainer starts it. Without the totem you cannot drop Earth totems." },
  { level = 10, text = "Fire totem quest", hint = "Your trainer starts it; it continues outside your starting zone. Bring a friend for the last part." },
  { level = 20, text = "Water totem quest and Ghost Wolf", hint = "A long quest chain, but healing totems need it. Ghost Wolf makes the running faster." },
  { level = 25, text = "Stormstrike talent", hint = "Your main attack from here on. Put it on an easy key." },
  { level = 30, text = "Air totem quest and Windfury Weapon", hint = "Windfury replaces Rockbiter on your weapon." },
  { level = 32, text = "Windfury Totem", hint = "Your Air totem from here on, in groups and alone." },
  { level = 40, text = "Dual Specialization", hint = "50 gold at any class trainer: keep Enhancement for questing and add Restoration for dungeons." },
  { level = 43, text = "Maelstrom Weapon", hint = "At 5 stacks your next Lightning Bolt is instant: cast it at max rank." },
  { level = 46, text = "Water Shield", hint = "Replaces Lightning Shield: it gives mana back." },
}

---------------------------------------------------------------------------
-- Enhancement: melee leveling spec
---------------------------------------------------------------------------
ns.RegisterProfile({
  class = "SHAMAN", spec = "Enhancement", tab = 2, default = true,
  freeDamage = "your melee swings",
  mana = { low = 25, medium = 55 },
  spells = spells({
    -- Forever: 8 second cooldown since the 11 November 2026 hotfix
    ["Stormstrike"] = { ids = { 17364 }, core = true, cd = true, cdTime = 8 },
    ["Rage of the Farseer"] = { ids = { 425336 }, cd = true },   -- optional Forever talent (not in the Icy Veins build)
  }),

  -- In combat, Icy Veins' leveling priority. Each spell is pressed on its
  -- cooldown, so the plan stays the same press after press:
  --   Stormstrike, Earth Shock, Fire Nova (Fire totem up, spare mana), melee.
  -- In a group Flame Shock takes turns with Earth Shock.
  priority = {
    { spell = "Rage of the Farseer", why = "Your big cooldown: press it when it is ready." },
    { spell = "Stormstrike", why = function(s)
        if s.level >= 43 then
          return "Stormstrike on cooldown. At 5 Maelstrom Weapon stacks, an instant Lightning Bolt."
        end
        return "Your main attack: press it every time it is ready (every 8 seconds)."
      end },
    { spell = "Flame Shock", mana = "medium", when = function(s) return s.inGroup and not s:debuffUp("Flame Shock") end,
      why = "In a group: Flame Shock and Earth Shock take turns." },
    { spell = "Earth Shock", mana = "medium",
      why = function(s)
        if s.inGroup and s:known("Frost Shock") then return "Earth Shock on cooldown. Frost Shock instead if you pull threat." end
        return "Earth Shock every time it is ready."
      end },
    { spell = "Searing Totem", mana = "medium",
      when = function(s) return not s:totemUp("fire") and (s.target.elite or s.inGroup) end,
      why = "No Fire totem on a tough fight: drop Searing Totem." },
    { spell = "Fire Nova", mana = "high", when = function(s) return s:totemUp("fire") end,
      why = "Spare mana and a Fire totem up: Fire Nova." },
  },
  filler = {
    { label = "Melee", why = "Your swings cost nothing. Let them work until the next spell is ready." },
  },

  -- Out of combat, enemy targeted: totems first, then pull from range.
  opener = list(PREPULL_SHIELD, PREPULL_TOTEMS, {
    { spell = "Lightning Bolt", why = "Pull with Lightning Bolt from range (a low rank saves mana), then melee." },
  }),

  checklist = CHECKLIST,

  advice = {
    low = function(s)
      return "Mana low: melee only." .. (s:known("Earth Shock") and " Earth Shock only to interrupt a caster." or "")
    end,
    medium = function(s)
      local main = s:have({ "Stormstrike", "Earth Shock" })
      if not main then return "Mana half: melee, and skip the extra spells." end
      return "Mana half: " .. main .. " on cooldown" .. (s:known("Fire Nova") and ", no Fire Nova or extra totems." or ", no extra totems.")
    end,
  },

  -- After-fight coaching. Return a sentence or nil.
  tips = {
    function(f)
      if n(f, "Earth Shock") >= 3 and (f.endPct or 100) < 25 then
        return ("Earth Shock ×%d left you at %d%% mana. Once mana is low, melee only and drink after the fight.")
          :format(n(f, "Earth Shock"), math.floor(f.endPct or 0))
      end
    end,
    function(f)
      if n(f, "Searing Totem") > 0 and f.duration < 8 then
        return ("Searing Totem on a %ds fight wastes mana. Drop it on longer fights."):format(math.floor(f.duration))
      end
    end,
    function(f, s)
      if s:known("Stormstrike") and n(f, "Stormstrike") == 0 and f.duration > 10 then
        return "Stormstrike wasn't used. Press it every time it is ready (every 8 seconds)."
      end
    end,
    function(f, s)
      if s.level < 43 and f.duration > 20 and n(f, "Lightning Bolt") >= 3 then
        return "Several Lightning Bolts in melee range: as Enhancement, one bolt to pull is enough."
      end
    end,
    function(f, s)
      if s:known("Fire Nova") and n(f, "Fire Nova") > 0 and n(f, "Searing Totem") + n(f, "Magma Totem") == 0
        and f.duration < 30 then
        return "Fire Nova bursts from your Fire totem: drop one first, or the cast is wasted."
      end
    end,
  },

  -- /coach macros builds these from the spells you know.
  macros = {
    { name = "CC Pull",
      about = "Follows the coach's pull plan, one spell per press: a missing shield, the totems you need, then Lightning Bolt.",
      body = function(s, plan)
        -- the pull part of the plan: buffs and totems, up to the first spell on the enemy
        local part = {}
        for _, st in ipairs(plan or {}) do
          if st.filler then break end
          part[#part + 1] = st
          local m = st.key and SHAMAN_SPELLS[st.key]
          if not (m and (m.totem or m.self)) then break end
        end
        local order = ns.Engine.sequence(part)
        if #order == 0 then
          if not s:known("Lightning Bolt") then return nil end
          order = { s.spells["Lightning Bolt"].name }
        end
        return "#showtooltip\n" .. (#order == 1 and "/cast " or "/castsequence reset=target/combat ") .. table.concat(order, ", ")
      end },
    { name = "CC Attack", about = "Keeps you swinging.",
      body = function() return "/startattack" end },
    { name = "CC Strike", about = "Stormstrike, and it makes sure you are swinging.",
      body = function(s)
        if not s:known("Stormstrike") then return nil end
        return "#showtooltip\n/startattack\n/cast " .. s.spells["Stormstrike"].name
      end },
  },

  trainer = TRAINER,

  -- The smart key: every press also starts your auto attack, and it ends on Stormstrike once you have it.
  smart = { attack = true, finish = "Stormstrike" },

  -- /coach bar: three bars by purpose, the entries in the order they belong on the bar, best candidate first.
  -- An entry you cannot use yet takes no button (or leaves a gap, with the "fixed buttons" setting).
  bars = {
    fight = {
      { "macro:CC Pull", "Lightning Bolt" },
      { "macro:CC Strike", "Stormstrike" },
      { "Earth Shock" },
      { "Flame Shock" },
      { "Searing Totem" },
      { "Lightning Bolt" },
      { "Frost Shock" },
      { "Fire Nova" },
      { "Magma Totem" },
      { "Chain Lightning" },
      { "Rage of the Farseer" },
      { "Strength of Earth Totem", "Stoneskin Totem" },
    },
    react = {
      { "Lesser Healing Wave", "Healing Wave" },
      { "Healing Wave" },
      { "Stoneclaw Totem" },
      { "Earthbind Totem" },
      { "book:Purge" },
      { "item:healingpotion", "Grounding Totem" },     -- a potion you carry comes first
      { "item:manapotion", "book:Tremor Totem" },
      { "book:Cure Poison" },
      { "book:Cure Disease" },
      { "Healing Stream Totem" },
      { "Windfury Totem", "Mana Spring Totem" },
      { "Chain Heal" },
    },
    prep = {
      { "Lightning Shield", "Water Shield" },
      { "Windfury Weapon", "Rockbiter Weapon" },
      { "Ghost Wolf" },
      { "Flametongue Weapon" },
      { "Water Shield" },
      { "book:Ancestral Spirit" },
      { "book:Astral Recall" },
      { "Call of the Elements" },
      { "Totemic Recall" },
      { "macro:CC Rest" },
      { "item:bandage" },
      { "item:hearth" },
    },
  },

  supplies = {
    { item = 17030, name = "Ankhs", needs = "Reincarnation", low = 2, icon = "Interface\\Icons\\INV_Jewelry_Talisman_06" },
  },

  milestones = MILESTONES,

  -- Icy Veins' Enhancement leveling talents (checked level by level against the
  -- guide's level slider, 22 November 2026). It takes Water Shield at 46.
  talentsName = "Icy Veins: Enhancement leveling",
  builds = {
    { name = "Icy Veins: Enhancement leveling", first = true,
      link = "https://www.icy-veins.com/wow-forever/shaman-talent-calculator#tc-hhhhhkkkiionnnisllrrvvtzzzzzAAAuuwCCG11111222556rrr~70888-a4ca5259" },
    { name = "Icy Veins: Solo and Dungeon Level 60 Build (Enhancement)",
      link = "https://www.icy-veins.com/wow-forever/shaman-talent-calculator#tc-hhhhhiiikkknnnosrrvvuutzzzzzAAA11111222555633388llw~70959-a8fe1dab" },
  },
  talents = {
    { 10, 14, "Thundering Strikes" }, { 15, 17, "Mental Dexterity" }, { 18, 19, "Ancestral Knowledge" },
    { 20, 20, "Shamanistic Focus" }, { 21, 23, "Elemental Weapons" }, { 24, 24, "Ancestral Knowledge" },
    { 25, 25, "Stormstrike" }, { 26, 27, "Improved Ghost Wolf" }, { 28, 29, "Flurry" },
    { 30, 31, "Improved Stormstrike" }, { 32, 32, "Spirit Weapons" }, { 33, 37, "Tidal Focus" },
    { 38, 40, "Mindfulness" }, { 41, 42, "Mental Quickness" }, { 43, 43, "Maelstrom Weapon" },
    { 44, 45, "Totemic Focus" }, { 46, 46, "Water Shield" }, { 47, 51, "Concussion" },
    { 52, 54, "Elemental Devastation" }, { 55, 56, "Call of Flame" }, { 57, 57, "Elemental Focus" },
    { 58, 60, "Flurry" },
  },
})

---------------------------------------------------------------------------
-- Restoration: the healing spec (a dual spec from 40, or leveling as a healer)
-- Party health is hidden from addons in a fight, so the coach cannot say whom
-- to heal: in a group it reminds you of the healing order and keeps your
-- cooldowns and mana in view. Alone it is Icy Veins' leveling damage plan.
---------------------------------------------------------------------------
local HEAL_ORDER = "Riptide on the most hurt, Chain Heal on several hurt (start on the Riptide target), Healing Wave on one."

ns.RegisterProfile({
  class = "SHAMAN", spec = "Restoration", tab = 3,
  freeDamage = "your melee swings",
  mana = { low = 30, medium = 60 },
  spells = spells(),

  priority = {
    -- in a group: your healing cooldowns, then the reminder
    { spell = "Mana Tide Totem", when = function(s) return s.inGroup and s.manaLevel ~= "high" end,
      why = "Mana under about 80%: Mana Tide Totem now, so none of it is wasted." },
    { spell = "Riptide", when = function(s) return s.inGroup end,
      why = "Riptide is ready: on the most hurt player (also makes Chain Heal stronger)." },
    -- alone: shocks and bolts while mana lasts, then melee
    { spell = "Flame Shock", mana = "medium", when = function(s) return not s.inGroup and not s:debuffUp("Flame Shock") end,
      why = "Flame Shock on the enemy." },
    { spell = "Earth Shock", mana = "high", when = function(s) return not s.inGroup end,
      why = "Spare mana: Earth Shock." },
    { spell = "Lightning Bolt", mana = "high", when = function(s) return not s.inGroup and s:castsOnTarget("Lightning Bolt") < 3 end,
      why = "Spare mana: Lightning Bolt." },
  },
  filler = {
    { label = "Heal", icon = "Interface\\Icons\\Spell_Nature_MagicImmunity",
      when = function(s) return s.inGroup end, why = HEAL_ORDER },
    { label = "Melee", why = "Your swings cost nothing. Save mana for heals." },
  },

  opener = list(PREPULL_SHIELD, PREPULL_TOTEMS, {
    { spell = "Lightning Bolt", why = "Open from range with Lightning Bolt (Chain Lightning on a group)." },
  }),

  checklist = CHECKLIST,

  advice = {
    low = function(s)
      if s.inGroup then return "Mana low: Healing Wave at a low rank only, and drink after the fight." end
      return "Mana low: melee only, and drink after the fight."
    end,
    medium = function(s)
      if s.inGroup then return "Mana half: lower ranks of Healing Wave when damage is light." end
      return "Mana half: melee, keep the rest for a heal."
    end,
  },

  tips = {
    function(f, s)
      if s.inGroup and s:known("Riptide") and n(f, "Riptide") == 0 and f.duration > 15 then
        return "Riptide wasn't used. Keep it on cooldown on the most hurt player."
      end
    end,
    function(f, s)
      if not s.inGroup and n(f, "Lightning Bolt") >= 4 and (f.endPct or 100) < 30 then
        return ("Lightning Bolt ×%d left you low on mana. Alone, melee more and keep mana for a heal."):format(n(f, "Lightning Bolt"))
      end
    end,
  },

  macros = {
    { name = "CC Swift Heal", about = "Nature's Swiftness, then an instant Healing Wave: your emergency button.",
      body = function(s)
        if not (s:known("Nature's Swiftness") and s:known("Healing Wave")) then return nil end
        return "#showtooltip " .. s.spells["Healing Wave"].name .. "\n/cast " .. s.spells["Nature's Swiftness"].name
          .. "\n/cast " .. s.spells["Healing Wave"].name
      end },
    { name = "CC Interrupt", about = "Stops your cast and interrupts with Earth Shock.",
      body = function(s)
        if not s:known("Earth Shock") then return nil end
        return "#showtooltip\n/stopcasting\n/cast " .. s.spells["Earth Shock"].name
      end },
  },

  trainer = TRAINER,

  smart = { attack = true },

  bars = {
    fight = {
      { "Healing Wave" },
      { "Riptide" },
      { "Chain Heal" },
      { "Lesser Healing Wave" },
      { "macro:CC Swift Heal", "Nature's Swiftness" },
      { "Mana Tide Totem" },
      { "macro:CC Interrupt", "Earth Shock" },
      { "Lightning Bolt" },
      { "Flame Shock" },
      { "Chain Lightning" },
      { "Fire Nova" },
      { "Searing Totem", "Magma Totem" },
    },
    react = {
      { "Healing Stream Totem" },
      { "Mana Spring Totem" },
      { "Stoneclaw Totem" },
      { "Earthbind Totem" },
      { "book:Purge" },
      { "item:healingpotion", "Grounding Totem" },
      { "item:manapotion", "book:Tremor Totem" },
      { "book:Cure Poison" },
      { "book:Cure Disease" },
      { "book:Poison Cleansing Totem" },
      { "book:Disease Cleansing Totem" },
      { "Windfury Totem", "Strength of Earth Totem" },
    },
    prep = {
      { "Water Shield", "Lightning Shield" },
      { "Flametongue Weapon", "Rockbiter Weapon" },
      { "Ghost Wolf" },
      { "Call of the Elements" },
      { "Totemic Recall" },
      { "book:Ancestral Spirit" },
      { "book:Astral Recall" },
      { "macro:CC Rest" },
      { "item:bandage" },
      { "item:hearth" },
    },
  },

  supplies = {
    { item = 17030, name = "Ankhs", needs = "Reincarnation", low = 2, icon = "Interface\\Icons\\INV_Jewelry_Talisman_06" },
  },

  milestones = {
    { level = 20, text = "Water Shield and the Water totem quest", hint = "Water Shield replaces Lightning Shield: keep it up, in fights too." },
    { level = 25, text = "Mana Tide Totem", hint = "Drop it at about 80% mana in long fights." },
    { level = 30, text = "Nature's Swiftness", hint = "With Healing Wave: an instant big heal when the tank drops fast." },
    { level = 40, text = "Riptide, Chain Heal and Dual Specialization", hint = "Riptide on cooldown; Chain Heal from the Riptide target." },
  },

  -- Icy Veins' Restoration build (0/10/41), the order of its leveling page.
  talentsName = "Icy Veins: Restoration",
  builds = {
    { name = "Icy Veins: Restoration (0/10/41)", first = true,
      link = "https://www.icy-veins.com/wow-forever/shaman-talent-calculator#tc-zzzzzAAAyyGyyyFJHHHHLKKKHMMMMMNFFEEEhhhhhIIIIIiiiii~70755-d1899b7d" },
  },
  talents = {
    { 10, 14, "Tidal Focus" }, { 15, 17, "Mindfulness" }, { 18, 19, "Improved Healing Wave" },
    { 20, 20, "Water Shield" }, { 21, 23, "Improved Healing Wave" }, { 24, 24, "Healing Focus" },
    { 25, 25, "Mana Tide Totem" }, { 26, 29, "Tidal Mastery" }, { 30, 30, "Nature's Swiftness" },
    { 31, 33, "Healing Way" }, { 34, 34, "Tidal Mastery" }, { 35, 39, "Purification" },
    { 40, 40, "Riptide" }, { 41, 42, "Healing Focus" }, { 43, 45, "Ancestral Healing" },
    { 46, 50, "Thundering Strikes" }, { 51, 55, "Restorative Totems" }, { 56, 60, "Ancestral Knowledge" },
  },
})
