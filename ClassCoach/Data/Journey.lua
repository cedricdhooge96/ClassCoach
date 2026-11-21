-- What the leveling guides say to do when: milestones every class shares,
-- and where to quest and which dungeon fits your level. Class milestones live
-- in each profile (`milestones = { ... }`).
--
-- A milestone: { level, text, hint, icon, done = function(s) }
--   with `done`    it stays on the list from that level until it is done
--   without        it shows for that level and the next (the addon can't tell)
local _, ns = ...

local ICON = "Interface\\Icons\\"

-- Everything here is WoW Forever's own: Blizzard's dungeon list for Forever,
-- Forever's zone levels (they differ from the original game's in places) and
-- Forever's systems (camping, the sleeping bag, Dual Specialization).
ns.JourneyData = {
  milestones = {
    { level = 10, text = "First talent point", icon = ICON .. "Ability_Marksmanship",
      hint = "From level 10 you get one talent point per level. Press N to spend it: the talent to take has a gold frame.",
      -- done once you have spent a point or have none to spend; gone by level 12 if the game won't say
      done = function(s)
        local j = s.journey
        if s.level >= 12 or not j then return s.level >= 12 end
        return j.talentPoints == 0 or (type(j.talentsSpent) == "number" and j.talentsSpent > 0)
      end },
    { level = 14, text = "Cozy Sleeping Bag quest chain", icon = ICON .. "INV_Misc_Bag_10",
      hint = "From level 14. It starts at a Nailed Plank on Alexston Farmstead in Westfall (Horde: Burned-Out Remains in the Barrens). Resting on the bag gives +1% XP per minute, up to 3%.",
      done = function(s) return s.journey and s.journey.hasItem and s.journey.hasItem("Cozy Sleeping Bag") end },
    { level = 40, text = "Mount and Dual Specialization", icon = ICON .. "Ability_Mount_RidingHorse",
      hint = "At 40 a riding trainer teaches Apprentice Riding, and your class trainer sells Dual Specialization (50 gold). Start saving around level 30." },
  },

  -- Where to quest, per faction: { from, to, zones }. Forever's zone levels.
  zones = {
    Alliance = {
      { 1, 10, "Your starting zone (Dun Morogh, Elwynn Forest or Teldrassil)" },
      { 10, 20, "Loch Modan, Westfall or Darkshore" },
      { 15, 25, "Redridge Mountains" },
      { 18, 30, "Duskwood or Ashenvale" },
      { 20, 30, "Wetlands" },
      { 30, 40, "Arathi Highlands or Desolace" },
      { 30, 45, "Stranglethorn Vale" },
      { 35, 45, "Riverglades (new in Forever), Badlands or Dustwallow Marsh" },
      { 40, 50, "The Hinterlands, Tanaris or Feralas" },
      { 45, 50, "Searing Gorge" },
      { 48, 55, "Un'Goro Crater or Felwood" },
      { 50, 58, "Burning Steppes or Western Plaguelands" },
      { 53, 60, "Eastern Plaguelands" },
      { 55, 60, "Winterspring or Silithus" },
      { 60, 60, "Mount Hyjal (new in Forever)" },
    },
  },

  -- What innkeepers and food vendors sell, by the level you can use it: { level, name }.
  -- Forever's vendors sell the original game's bread and drinks at the same levels.
  drinks = {
    { 1, "Refreshing Spring Water" }, { 5, "Ice Cold Milk" }, { 15, "Melon Juice" }, { 25, "Sweet Nectar" },
    { 35, "Moonberry Juice" }, { 45, "Morning Glory Dew" },
  },
  foods = {
    { 1, "Tough Hunk of Bread" }, { 5, "Freshly Baked Bread" }, { 15, "Moist Cornbread" }, { 25, "Mulgore Spice Bread" },
    { 35, "Soft Banana Bread" }, { 45, "Homemade Cherry Pie" },
  },

  -- Dungeons by level range: { from, to, name }. The nine new ones use the
  -- levels Blizzard published for Forever; the returning ones use Forever's too.
  dungeons = {
    Alliance = {
      { 13, 18, "Hall of Thanes (new)" }, { 18, 23, "The Deadmines" }, { 22, 30, "The Stockade" },
      { 24, 29, "Excavation Site: Wetlands (new)" }, { 24, 32, "Blackfathom Deeps" }, { 28, 33, "City of Dalaran (new)" },
      { 28, 39, "Scarlet Monastery: Graveyard or Library" }, { 29, 38, "Gnomeregan" },
      { 32, 45, "Scarlet Monastery: Armory or Cathedral" }, { 35, 40, "The Drowned City (new)" },
      { 40, 45, "Krol'dok Stronghold (new)" }, { 42, 52, "Uldaman" }, { 44, 54, "Zul'Farrak" }, { 45, 57, "Maraudon" },
      { 48, 53, "Alcaz Prison (new)" }, { 50, 60, "Temple of Atal'Hakkar (Sunken Temple)" }, { 52, 60, "Blackrock Depths" },
      { 55, 60, "Blackmaw Hold (new) or Lower Blackrock Spire" },
      { 58, 60, "Shaper's Terrace (new), Scholomance, Stratholme or Dire Maul" },
    },
  },
}

-- /coach tips: preparation habits that Forever guides agree on. Each is one
-- line a beginner can act on. Sources, read in November 2026: Gfinity Esports
-- "Beginner's Tips For World of Warcraft: Forever"; Icy Veins "Veteran Players
-- Share What They Wish They Knew Before WoW Forever" and "Healing Potions Now
-- Crafted by First Aid in WoW Forever"; Warcraft Tavern "First Aid Overview";
-- Dving "WoW Forever Beginner Guide". Numbers come from those pages and are
-- not checked in the game by this addon.
ns.JourneyData.tips = {
  "Use your potions. Veterans' advice to new players: don't save consumables for a perfect moment.",
  "Carry a healing potion. It is instant and works in a fight. In Forever First Aid makes them: Minor from skill 55, Lesser from 85, Healing from 135.",
  "Learn First Aid on every character. Bandages heal you between fights at no mana cost, so you drink and eat less often.",
  "Buy bags with your first silver. The backpack fills fast; trade vendors and the auction house sell small bags.",
  "Set your Hearthstone at the inn of the quest hub you are working from, from level 10 on. It saves a lot of walking.",
  "Don't buy every spell rank. Take your main damage spells and core utility first, and save gold for riding at level 40.",
  "Sell ore, herbs, leather and spare cloth on the auction house from level 1. It is steady money for your mount.",
  "Eat cooked food before you go out: the Well Fed buff adds XP from kills. The journey list reminds you.",
  "Run each dungeon once for its quests. Grinding enemies inside gives less XP than questing outside.",
  "Finish a zone's quest chapters. Guides say that earns Legacy Points; the non-combat branches give perks such as more rested XP.",
}
