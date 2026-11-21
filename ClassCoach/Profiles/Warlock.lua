-- Warlock profiles for WoW Forever. Spell ids are each rank's, lowest first; a
-- spell Forever added or re-numbered is found by its English name instead.
-- Forever renamed Curse of Agony to Bane of Agony (a Bane no longer takes the
-- place of your Curse) and added Wrack.
-- `learn` = the level Forever's trainer sells it.
local _, ns = ...

local function n(f, key) return f.castCount[key] or 0 end

local WARLOCK_SPELLS = {
  ["Shadow Bolt"]    = { ids = { 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307 }, harm = true, travel = true },
  -- worth = 0.25: much of Immolate is its first hit, so it is still worth it closer to the end
  ["Immolate"]       = { ids = { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309 }, debuff = 15, worth = 0.25, learn = 1 },
  ["Corruption"]     = { ids = { 172, 6222, 6223, 7648, 11671, 11672, 25311 }, debuff = 15, core = true, learn = 4 },
  ["Bane of Agony"]  = { ids = { 980, 1014, 6217, 11711, 11712, 11713 }, debuff = 24, core = true, learn = 8 },
  ["Siphon Life"]    = { ids = { 18265, 18879, 18880, 18881 }, debuff = 30 },          -- talent, from 30
  ["Curse of the Elements"] = { ids = { 1490, 11721, 11722 }, debuff = 300 },         -- 20 in Forever
  ["Wrack"]          = { cd = true, harm = true },   -- new Forever talent (from 40): by name
  ["Life Tap"]       = { ids = { 1454, 1455, 1456, 11687, 11688, 11689 }, core = true, learn = 6, restores = 0.15 },
  ["Drain Life"]     = { ids = { 689, 699, 709, 7651, 11699, 11700 }, learn = 14, harm = true },
  ["Drain Soul"]     = { ids = { 1120, 8288, 8289, 11675 }, learn = 10, harm = true },
  ["Fear"]           = { ids = { 5782, 6213, 6215 }, harm = true },
  ["Demon Skin"]     = { self = true, ids = { 687, 696 } },
  ["Demon Armor"]    = { self = true, ids = { 706, 1086, 11733, 11734, 11735 }, learn = 20 },
  -- `summons`: which demon it brings out, so the coach knows who is at your side
  ["Summon Imp"]     = { ids = { 688 }, summons = "Imp" },                -- class quest, level 1
  ["Summon Voidwalker"] = { ids = { 697 }, summons = "Voidwalker" },      -- class quest, level 10
  ["Summon Succubus"] = { ids = { 712 }, summons = "Succubus" },          -- class quest, level 20
  ["Summon Incubus"] = { summons = "Incubus" },                           -- class quest, level 20 (by name)
  ["Summon Felhunter"] = { ids = { 691 }, summons = "Felhunter" },        -- class quest, level 30
  ["Shoot"]          = { ids = { 5019 }, core = true, auto = true },
}

local DEMONS = { "Summon Imp", "Summon Voidwalker", "Summon Succubus", "Summon Incubus", "Summon Felhunter" }

-- What Forever's trainer teaches at each level.
local TRAINER = {
  [1] = "Immolate (10 copper); do your trainer's quest for the Imp",
  [4] = "Corruption, Curse of Weakness",
  [6] = "Life Tap",
  [8] = "Bane of Agony, Fear",
  [10] = "Drain Soul, Create Healthstone; do the Voidwalker class quest",
  [12] = "Health Funnel",
  [14] = "Drain Life, Curse of Recklessness",
  [16] = "Unending Breath",
  [18] = "Searing Pain, Create Soulstone",
  [20] = "Demon Armor, Curse of the Elements, Rain of Fire, Ritual of Summoning; Succubus/Incubus class quest",
  [22] = "Eye of Kilrogg",
  [24] = "Drain Mana, Sense Demons",
  [26] = "Curse of Tongues, Detect Invisibility",
  [28] = "Banish, Create Firestone",
  [30] = "Hellfire, Subjugate Demon; Felhunter class quest",
  [32] = "Shadow Ward",
  [36] = "Create Spellstone",
  [40] = "Howl of Terror; Felsteed class quest, riding and Dual Specialization",
  [42] = "Death Coil",
  [48] = "Soul Fire",
  [50] = "Inferno",
  [60] = "Bane of Doom, Ritual of Doom, Portal of Summoning; Dreadsteed quest chain",
}

local function wandOrMelee(s) return s.hasWand and "wand" or "melee" end

-- How to pull depends on who is at your side:
--   Voidwalker  the tank: it goes in with your first spell (Cedric's choice: no waiting for its first hit)
--   Imp         ranged and fragile: the enemy comes to you, so just start casting
--   others      melee damage: send them in, let them land a hit, then cast
local function pullWith(key, alone)
  return function(s)
    local spell = s.spells[key] and s.spells[key].name or key
    if s.demon == "Voidwalker" then return "Send your Voidwalker in and cast " .. spell .. " at once: your pull key does both." end
    if s.demon == "Imp" then return "Imp out: cast " .. spell .. " right away. The enemy will come to you." end
    if s.hasPet then return "Send your demon in, let it land a hit, then " .. spell .. "." end
    return alone
  end
end

local function names(s, keys)
  local out = {}
  for _, k in ipairs(keys) do if s.spells[k] then out[#out + 1] = s.spells[k].name end end
  return out
end

---------------------------------------------------------------------------
-- Affliction: damage over time, a demon at your side, Life Tap instead of drinking
--   1-3   Shadow Bolt, Immolate, finish in melee (no wand yet)
--   4-7   Corruption and Immolate, then wand
--   8-9   Bane of Agony, Corruption, then wand
--   10+   demon in, Bane of Agony, Corruption, Immolate, then wand (Drain Life from 30)
---------------------------------------------------------------------------
ns.RegisterProfile({
  class = "WARLOCK", spec = "Affliction", tab = 1, default = true,
  freeDamage = "your demon and your wand",
  mana = { low = 25, medium = 55 },
  restFix = "Life Tap",
  restHint = function(s)
    if s:known("Life Tap") then return "Life Tap if your health is high, then eat to get the health back." end
    return "Drink before the next pull."
  end,
  spells = WARLOCK_SPELLS,

  priority = {
    { spell = "Bane of Agony", mana = "medium", when = function(s) return not s:debuffUp("Bane of Agony") end,
      why = "Bane of Agony: slow, cheap damage that keeps ticking." },
    { spell = "Corruption", mana = "medium", when = function(s) return not s:debuffUp("Corruption") end,
      why = "Corruption: damage over time does the work while you wait." },
    -- On every enemy that lives long enough (Method, Warcraft Tavern): only low mana holds it back.
    { spell = "Immolate", mana = "medium",
      when = function(s) return not s:debuffUp("Immolate") end,
      why = function(s) return s.level < 10 and "Immolate: your main damage at this level." or "Immolate: a big first hit, then it burns." end },
    { spell = "Siphon Life", mana = "medium", when = function(s) return not s:debuffUp("Siphon Life") end,
      why = "Siphon Life heals you while it ticks." },
    { spell = "Curse of the Elements", mana = "medium", minLevel = 40,
      when = function(s) return s.target.elite and not s:debuffUp("Curse of the Elements") end,
      why = "Tough enemy: Curse of the Elements makes your spells hit harder." },
    { spell = "Life Tap", when = function(s) return s.manaLevel == "low" end,
      why = "Mana low: Life Tap if your health is above half." },
    { spell = "Wrack", mana = "high", why = "Spare mana: channel Wrack." },
    { spell = "Drain Life", mana = "medium", minLevel = 30,
      why = "Drain Life is your filler from 30: damage and healing in one." },
  },
  filler = {
    { spell = "Shoot", when = function(s) return s.hasWand end,
      why = "Wand while your damage over time ticks. It costs no mana." },
    { spell = "Shadow Bolt", mana = "medium", when = function(s) return not s.hasWand end,
      why = "No wand yet: Shadow Bolt while you have mana." },
    { label = "Melee", why = function(s)
        if s.hasWand then return "Hit it with your weapon." end
        return s.level >= 5 and "Mana low and no wand: melee it down. Buy a Lesser Magic Wand."
          or "Mana low: finish it in melee."
      end },
  },

  opener = {
    { spell = "Bane of Agony", mana = "medium",
      why = pullWith("Bane of Agony", "Pull with Bane of Agony: instant, and it marks the enemy as yours.") },
    { spell = "Corruption", mana = "medium", why = pullWith("Corruption", "Pull with Corruption from max range.") },
    { spell = "Shadow Bolt", why = function(s)
        return s:known("Immolate") and "Pull with Shadow Bolt from max range, then Immolate."
          or "Pull with Shadow Bolt from max range."
      end },
  },

  checklist = {
    -- tip = true: advice for the journey panel, not something to fix before every pull
    { tip = true, check = function(s) return s.level < 10 and not s:known("Summon Imp") end,
      label = "No Imp yet", icon = "Interface\\Icons\\Spell_Shadow_SummonImp", hint = "Your class trainer has a short quest for your first helper, the Imp. Do it first." },
    { tip = true, check = function(s) return s.level >= 10 and s:known("Summon Imp") and not s:known("Summon Voidwalker") end,
      label = "No Voidwalker yet", icon = "Interface\\Icons\\Spell_Shadow_SummonVoidWalker", hint = "Do the level 10 class quest: the Voidwalker takes the hits for you." },
    { pet = true, needs = DEMONS, label = "No demon",
      -- Forever's guides: Imp to 10, Voidwalker to 20, then the Succubus or Incubus
      fix = function(s)
        return s:known("Summon Succubus") and "Summon Succubus" or s:known("Summon Incubus") and "Summon Incubus"
          or s:known("Summon Voidwalker") and "Summon Voidwalker" or "Summon Imp"
      end,
      hint = function(s)
        if s:known("Summon Succubus") or s:known("Summon Incubus") then
          return "Summon your " .. (s:known("Summon Succubus") and "Succubus" or "Incubus") .. " (costs a Soul Shard): your strongest demon from level 20."
        end
        if s:known("Summon Voidwalker") then return "Summon your Voidwalker (costs a Soul Shard): it takes the hits for you." end
        return "Summon your Imp and keep it out: free extra damage."
      end },
    { check = function(s) return s.demon == "Imp" and s:known("Summon Voidwalker") and not s.inGroup end,
      label = "Imp is out",
      fix = function(s)
        return s:known("Summon Succubus") and "Summon Succubus" or s:known("Summon Incubus") and "Summon Incubus" or "Summon Voidwalker"
      end,
      hint = function(s)
        if s:known("Summon Succubus") or s:known("Summon Incubus") then return "Solo, your level 20 demon hits much harder. The Imp is the pick for groups." end
        return "Solo, your Voidwalker is safer: it takes the hits. The Imp is the pick for groups."
      end },
    { buff = { "Demon Skin", "Demon Armor" }, label = "No armor",
      fix = function(s) return s:known("Demon Armor") and "Demon Armor" or "Demon Skin" end,
      hint = function(s) return "Cast " .. (s:known("Demon Armor") and "Demon Armor" or "Demon Skin") .. ": it lasts 30 minutes." end },
    { tip = true, item = 6265, needs = "Drain Soul", label = "No Soul Shard", icon = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02",
      hint = "Channel Drain Soul on a dying enemy to get a shard for summons and Healthstones." },
    { tip = true, slot = 18, needs = "Shoot", minLevel = 5, label = "No wand", icon = "Interface\\Icons\\INV_Wand_01",
      hint = "Get a wand (Lesser Magic Wand, level 5): your free damage while leveling." },
  },

  advice = {
    low = function(s)
      local tap = s:known("Life Tap") and "Life Tap if health is above half, then " or ""
      return "Mana low: " .. tap .. wandOrMelee(s) .. "."
    end,
    medium = function(s)
      local dots = s:have({ "Bane of Agony", "Corruption" }) or s:have({ "Immolate" })
      if not dots then return "Mana half: one more Shadow Bolt, then " .. wandOrMelee(s) .. "." end
      return dots .. ", then " .. wandOrMelee(s) .. "."
    end,
  },

  tips = {
    function(f, s)
      if f.hadPet == false and f.duration > 6 and s:have(DEMONS) then
        return "You fought without your demon. Summon it first: it adds free damage and takes hits."
      end
    end,
    function(f, s)
      if s:known("Corruption") and n(f, "Shadow Bolt") >= 3 and (f.endPct or 100) < 45 then
        return ("Shadow Bolt ×%d cost %d mana. Damage over time plus %s does the job for less.")
          :format(n(f, "Shadow Bolt"), f.spentBy["Shadow Bolt"] or 0, wandOrMelee(s))
      end
    end,
    function(f, s)
      if s.hasWand and n(f, "Shoot") == 0 and f.duration > 10 then
        return "After your damage over time is on, wand the enemy instead of standing idle."
      end
    end,
    function(f, s)
      if s:known("Life Tap") and (f.endPct or 100) < 30 and n(f, "Life Tap") == 0 then
        return "Low on mana: Life Tap between fights instead of drinking, then eat to heal."
      end
    end,
  },

  -- /coach macros builds these from the spells you know.
  macros = {
    { name = "CC Pull",
      about = function(s, plan)
        local dots = #ns.Engine.sequence(plan)
        local said = ("Follows the coach's pull plan, one spell per press (%d press%s)"):format(dots, dots == 1 and "" or "es")
        if s:known("Shoot") then said = said .. ", then use CC Wand" end
        if s:have(DEMONS) then said = said .. ". The first press also sends your demon in" end
        return said .. "."
      end,
      body = function(s, plan)
        -- without a wand the filler spell is added, so this one key carries the whole fight
        local order = ns.Engine.sequence(plan, nil, 3)
        if #order == 0 then return nil end
        local lines = { "#showtooltip" }
        if s:have(DEMONS) then
          lines[#lines + 1] = "/petattack [harm,nodead]"
        end
        lines[#lines + 1] = (#order == 1 and "/cast " or "/castsequence reset=target/combat ") .. table.concat(order, ", ")
        return table.concat(lines, "\n")
      end },
    { name = "CC Open", about = "Demon in, then your first spell.",
      body = function(s, plan)
        local first = ns.Engine.sequence(plan)[1]
        if not first or not s:have(DEMONS) then return nil end
        return "#showtooltip\n/petattack [harm,nodead]\n/cast " .. first
      end },
    { name = "CC Wand", about = "Starts your wand and keeps your demon on the enemy.",
      body = function(s)
        if not s:known("Shoot") then return nil end
        local shoot = s.spells["Shoot"].name
        return "#showtooltip " .. shoot .. "\n" .. (s:have(DEMONS) and "/petattack [harm,nodead]\n" or "") .. "/cast !" .. shoot
      end },
    { name = "CC Demon", about = "Summons your Voidwalker; hold Shift for the Imp.",
      body = function(s)
        if not (s:known("Summon Voidwalker") and s:known("Summon Imp")) then return nil end
        return ("#showtooltip\n/cast [mod:shift] %s; %s"):format(s.spells["Summon Imp"].name, s.spells["Summon Voidwalker"].name)
      end },
  },

  trainer = TRAINER,

  -- The smart key: every press also sends your demon at your target.
  smart = { pet = true },

  -- /coach bar: three bars by purpose, the entries in the order they belong on the bar, best candidate first.
  -- An entry you cannot use yet takes no button (or leaves a gap, with the "fixed buttons" setting).
  manaPotion = false,   -- Life Tap is the Warlock's mana potion
  bars = {
    fight = {
      { "macro:CC Pull", "Shadow Bolt" },
      { "macro:CC Wand", "Shoot" },
      { "Shadow Bolt" },
      { "Life Tap" },
      { "Drain Life" },
      { "Drain Soul" },
      { "Bane of Agony" },
      { "Corruption" },
      { "Immolate" },
      { "Siphon Life" },
      { "Curse of the Elements" },
      { "Wrack" },
    },
    react = {
      { "Fear" },
      { "book:Death Coil" },
      { "book:Howl of Terror" },
      { "book:Health Funnel" },
      { "book:Banish" },
      { "item:healingpotion", "book:Curse of Weakness" },   -- a potion you carry comes first: it is the emergency button
      { "book:Curse of Recklessness" },
      { "book:Shadow Ward" },
      { "book:Drain Mana" },
      { "item:healthstone" },
      { "book:Rain of Fire" },
      { "book:Hellfire" },
    },
    prep = {
      { "Demon Armor", "Demon Skin" },
      { "macro:CC Demon", "Summon Voidwalker", "Summon Imp" },
      { "Summon Imp" },
      { "Summon Succubus", "Summon Incubus" },
      { "Summon Felhunter" },
      { "book:Create Healthstone" },
      { "book:Create Soulstone" },
      { "book:Unending Breath" },
      { "book:Ritual of Summoning" },
      { "macro:CC Rest" },
      { "item:bandage" },
      { "item:hearth" },
    },
  },

  milestones = {
    { level = 20, text = "Succubus or Incubus quest", icon = "Interface\\Icons\\Spell_Shadow_SummonSuccubus",
      hint = "Your class trainer starts it. This demon hits hardest and replaces the Voidwalker for leveling; the Voidwalker stays the safe pick against several enemies.",
      done = function(s) return s:known("Summon Succubus") or s:known("Summon Incubus") end },
    { level = 30, text = "Felhunter quest", icon = "Interface\\Icons\\Spell_Shadow_SummonFelHunter",
      hint = "Your class trainer starts it. The Felhunter is the pick against casters.",
      done = function(s) return s:known("Summon Felhunter") end },
    { level = 40, text = "Felsteed quest", icon = "Interface\\Icons\\Spell_Nature_Swiftness",
      hint = "A short class quest for your free mount." },
  },

  -- Builds you can follow (/coach build). The first is the default; with points
  -- already spent, the one that fits them best is followed.
  talentsName = "Warcraft Tavern: Affliction leveling (41/7/3)",
  builds = {
    -- Icy Veins' Forever leveling guide (checked level by level against its level
    -- slider, 21 Nov 2026): Suppression 10-13, Improved Corruption 14-18, ... Wrack 51.
    { name = "Icy Veins: Affliction leveling (40/11/0)", first = true,
      link = "https://www.icy-veins.com/wow-forever/warlock-talent-calculator#tc-111122222366999bbaaadjjjjjllnnnqaa30fffffg0eee55577~70755-d1899b7d" },
    { name = "Icy Veins: Wrack Build (Affliction)",
      link = "https://www.icy-veins.com/wow-forever/warlock-talent-calculator#tc-00111112222266999aaaaabbdfffffgjjjjjllnnnqBBBBBeee8~70959-a8fe1dab" },
  },
  -- Warcraft Tavern's Affliction build for Forever (41/7/3): no respec needed.
  talents = {
    { 10, 14, "Improved Corruption" }, { 15, 17, "Suppression" }, { 18, 22, "Unholy Power (Demonology)" },
    { 23, 24, "Demonic Energies (Demonology)" }, { 25, 27, "Improved Drains" }, { 28, 28, "Amplify Curse" },
    { 29, 30, "Improved Bane of Agony" }, { 31, 32, "Suppression" }, { 33, 35, "Pandemic" },
    { 36, 36, "Improved Life Tap" }, { 37, 37, "Siphon Life" }, { 38, 40, "Soul Siphon" },
    { 41, 41, "Improved Life Tap" }, { 42, 46, "Shadow Mastery" }, { 47, 47, "Wrack" },
    { 48, 52, "Malevolence" }, { 53, 55, "Fel Concentration" }, { 56, 57, "Nightfall" }, { 58, 60, "Improved Shadow Bolt" },
  },
})
