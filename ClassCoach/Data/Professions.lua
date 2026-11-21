-- Professions in WoW Forever: what to do next in each, and which two suit a class.
--
-- steps = { fromSkill, toSkill, "what" }: one line per stretch, the guide's main
-- path. tiers = the skill caps and what the next rank needs. verb = the word
-- that goes in front of a step ("craft", "mine", "pick", "skin", "cook", "fish in").
--
-- The steps follow wow-professions.com's Forever guides
-- (https://www.wow-professions.com/forever), which say they are based on the
-- Forever beta: the higher stretches are not proven on the live game yet.
-- Materials, amounts, alternatives and trainer locations are in the guides.
-- Zones are the Alliance ones, like the rest of the journey panel.
--
-- In Forever, Cooking, First Aid and Fishing do not use one of your two
-- profession slots, healing potions are made with First Aid, and the first
-- rank of every profession has no level requirement (same guides).
local _, ns = ...

local SOURCE = "wow-professions.com"
local function craft(extraArtisan)
  return {
    { cap = 75, name = "Journeyman", needs = "skill 50 and level 10" },
    { cap = 150, name = "Expert", needs = "skill 125, level 20 and 50 silver" },
    { cap = 225, name = "Artisan", needs = "skill 200 and level 35" .. (extraArtisan or "") },
  }
end
local GATHER = {
  { cap = 75, name = "Journeyman", needs = "skill 50. The junior trainers in starting areas cannot teach it: see one in a capital city" },
  { cap = 150, name = "Expert", needs = "skill 125" },
  { cap = 225, name = "Artisan", needs = "skill 200" },
}

ns.ProfessionData = {
  Alchemy = {
    source = SOURCE, verb = "craft", about = "Potions and elixirs. Pairs with Herbalism.", tiers = craft(),
    steps = {
      { 1, 10, "Elixir of Minor Force" }, { 10, 55, "Elixir of Minor Defense" }, { 55, 65, "Minor Mana Potion" },
      { 65, 90, "Elixir of Minor Fortitude" }, { 90, 120, "Elixir of Wisdom" }, { 120, 130, "Lesser Mana Potion" },
      { 130, 150, "Fire Oil" }, { 150, 165, "Elixir of Fire Power" }, { 165, 195, "Mana Potion" },
      { 195, 235, "Nature Protection Potion" }, { 235, 250, "Elixir of Greater Intellect" }, { 250, 260, "Stonescale Oil" },
      { 260, 265, "Elixir of Greater Intellect" }, { 265, 300, "Elixir of Greater Defense" },
    },
  },
  Blacksmithing = {
    source = SOURCE, verb = "craft", about = "Mail and plate armor and weapons. Pairs with Mining.", tiers = craft(),
    steps = {
      { 1, 25, "Rough Sharpening Stone" }, { 25, 50, "Rough Grinding Stone" }, { 50, 75, "Coarse Grinding Stone" },
      { 75, 80, "Silver Rod" }, { 80, 95, "Runed Copper Belt" }, { 95, 100, "Patterned Bronze Bracers" },
      { 100, 112, "Heavy Grinding Stone" }, { 112, 125, "Patterned Bronze Bracers" }, { 125, 140, "Bronze Shortsword" },
      { 140, 150, "Bronze Warhammer" }, { 150, 175, "Green Iron Bracers" }, { 175, 180, "Solid Grinding Stone" },
      { 180, 195, "Golden Scale Bracers" }, { 195, 210, "Mithril Plate Pants" }, { 210, 215, "Heavy Mithril Axe" },
      { 215, 225, "Heavy Mithril Breastplate" }, { 225, 230, "Dense Sharpening Stone" }, { 230, 240, "Heavy Mithril Boots" },
      { 240, 245, "Imperial Plate Belt" }, { 245, 270, "Imperial Plate Bracers" }, { 270, 290, "Imperial Plate Boots" },
      { 290, 300, "Imperial Plate Leggings" },
    },
  },
  Enchanting = {
    source = SOURCE, verb = "craft", about = "Enchants for your gear, from items you take apart. Needs no gathering profession.",
    tiers = craft(". Only Annora, inside Uldaman, teaches it"),
    steps = {
      { 1, 2, "Runed Copper Rod" }, { 2, 20, "Enchant Bracer - Inferior Stamina" }, { 20, 70, "Enchant Chest - Inferior Stamina" },
      { 70, 85, "Enchant Chest - Minor Absorption" }, { 85, 100, "Enchant Bracer - Minor Stamina" },
      { 100, 109, "Enchant Cloak - Minor Protection" }, { 109, 110, "Runed Silver Rod" }, { 110, 125, "Greater Magic Wand" },
      { 125, 150, "Enchant Boots - Minor Stamina" }, { 150, 151, "Runed Golden Rod" }, { 151, 165, "Minor Mana Oil" },
      { 165, 200, "Enchant Boots - Lesser Agility" }, { 200, 201, "Runed Truesilver Rod" }, { 201, 220, "Lesser Wizard Oil" },
      { 220, 225, "Enchant Cloak - Greater Defense" }, { 225, 250, "Enchant Gloves - Agility" }, { 250, 270, "Lesser Mana Oil" },
      { 270, 275, "Enchant Shield - Greater Stamina" }, { 275, 295, "Wizard Oil" }, { 295, 299, "Enchant Shield - Greater Stamina" },
      { 299, 300, "Runed Arcanite Rod" },
    },
  },
  Engineering = {
    source = SOURCE, verb = "craft", about = "Bombs, gadgets and scopes. Pairs with Mining.", tiers = craft(),
    steps = {
      { 1, 30, "Rough Blasting Powder" }, { 30, 50, "Handful of Copper Bolts" }, { 50, 51, "Arclight Spanner" },
      { 51, 75, "Rough Copper Bomb" }, { 75, 90, "Coarse Blasting Powder" }, { 90, 100, "Coarse Dynamite" },
      { 100, 105, "Silver Contact" }, { 105, 125, "Bronze Tube" }, { 125, 135, "Standard Scope" },
      { 135, 150, "Whirring Bronze Gizmo" }, { 150, 160, "Bronze Framework" }, { 160, 175, "Explosive Sheep" },
      { 175, 194, "Solid Blasting Powder" }, { 194, 195, "Gyromatic Micro-Adjustor" }, { 195, 200, "Mithril Tube" },
      { 200, 215, "Unstable Trigger" }, { 215, 238, "Mithril Casing" }, { 238, 250, "Hi-Explosive Bomb" },
      { 250, 260, "Dense Blasting Powder" }, { 260, 280, "Thorium Widget" }, { 280, 300, "Thorium Tube" },
    },
  },
  Leatherworking = {
    source = SOURCE, verb = "craft", about = "Leather and mail armor. Pairs with Skinning.", tiers = craft(),
    steps = {
      { 1, 30, "Light Leather (from Ruined Leather Scraps)" }, { 30, 50, "Cured Light Hide" }, { 50, 60, "Embossed Leather Gloves" },
      { 60, 80, "Embossed Leather Pants" }, { 80, 95, "Cured Medium Hide" }, { 95, 105, "Fine Leather Belt" },
      { 105, 125, "Dark Leather Belt" }, { 125, 130, "Heavy Leather" }, { 130, 143, "Cured Heavy Hide" },
      { 143, 150, "Hillman's Leather Gloves" }, { 150, 165, "Barbaric Shoulders" }, { 165, 175, "Guardian Gloves" },
      { 175, 185, "Barbaric Harness" }, { 185, 205, "Nightscape Headband" }, { 205, 235, "Nightscape Pants" },
      { 235, 265, "Wicked Leather Gauntlets" }, { 265, 300, "Runic Leather Headband" },
    },
  },
  Tailoring = {
    source = SOURCE, verb = "craft", about = "Cloth armor and bags, from cloth that enemies drop. Needs no gathering profession.", tiers = craft(),
    steps = {
      { 1, 30, "Bolt of Linen Cloth" }, { 30, 55, "Linen Belt" }, { 55, 80, "Bolt of Woolen Cloth" }, { 80, 95, "Woolen Cape" },
      { 95, 100, "Double-stitched Woolen Shoulders" }, { 100, 120, "Bolt of Silk Cloth" }, { 120, 140, "Gloves of Meditation" },
      { 140, 150, "Bolt of Mageweave" }, { 150, 170, "Crimson Silk Vest" }, { 170, 190, "Crimson Silk Pantaloons" },
      { 190, 200, "Black Mageweave Leggings" }, { 200, 205, "Black Mageweave Shoulders" }, { 205, 215, "Bolt of Runecloth" },
      { 215, 225, "Red Mageweave Bag" }, { 225, 240, "Runecloth Belt" }, { 240, 250, "Runecloth Gloves" },
      { 250, 280, "Runecloth Cuffs" }, { 280, 300, "Runecloth Shoulders" },
    },
  },

  -- Gathering: you level these by doing them where the right nodes or animals are.
  Mining = {
    source = SOURCE, verb = "mine", gather = true, about = "Ore from veins, smelted into bars. Sells well, and feeds Blacksmithing and Engineering.", tiers = GATHER,
    steps = {
      { 1, 65, "Copper in Elwynn Forest, Dun Morogh or Teldrassil" }, { 65, 125, "Tin and Silver in the Wetlands or Westfall" },
      { 125, 155, "Iron in the Arathi Highlands or Thousand Needles" }, { 155, 175, "Gold and Iron in the Arathi Highlands or Thousand Needles" },
      { 175, 230, "Mithril in The Hinterlands or Tanaris" }, { 230, 245, "Truesilver in The Hinterlands or Tanaris" },
      { 245, 275, "Small Thorium Veins in Un'Goro Crater or Felwood" }, { 275, 300, "Rich Thorium Veins in Un'Goro Crater or Winterspring" },
    },
  },
  Herbalism = {
    source = SOURCE, verb = "pick", gather = true, about = "Herbs. Sells well, and feeds Alchemy.", tiers = GATHER,
    steps = {
      { 1, 70, "Peacebloom, Silverleaf and Earthroot in your starting zone" }, { 70, 115, "Mageroyal and Briarthorn in Loch Modan or Darkshore" },
      { 115, 170, "Bruiseweed, Wild Steelbloom and Kingsblood in Hillsbrad Foothills or the Stonetalon Mountains" },
      { 170, 205, "Fadeleaf, Goldthorn and Khadgar's Whisker in Stranglethorn Vale or the Arathi Highlands" },
      { 205, 230, "Purple Lotus and Firebloom in Tanaris or Searing Gorge" }, { 230, 270, "Sungrass and Golden Sansam in The Hinterlands" },
      { 270, 300, "Dreamfoil, Gromsblood and Plaguebloom in Felwood" },
    },
  },
  Skinning = {
    source = SOURCE, verb = "skin", gather = true, about = "Leather from the beasts you kill anyway. Easy gold, and feeds Leatherworking.", tiers = GATHER,
    steps = {
      { 1, 75, "wolves and boars in your starting zone" }, { 75, 130, "boars, bears and crocodiles in Loch Modan" },
      { 130, 150, "raptors at Whelgar's Excavation Site in the Wetlands" }, { 150, 160, "bears and mountain lions in Hillsbrad Foothills" },
      { 160, 225, "yetis in the Foothill Caverns in Hillsbrad Foothills" }, { 225, 280, "yetis in Feral Scar Vale in Feralas" },
      { 280, 300, "diemetradons and pterrordaxes in the west of Un'Goro Crater" },
    },
  },

  -- Secondary: every character can learn all three; they use no profession slot.
  ["First Aid"] = {
    source = SOURCE, verb = "make", secondary = true, about = "Bandages, and in Forever also the healing potions.",
    tiers = {
      { cap = 75, name = "Journeyman", needs = "skill 50; every First Aid trainer teaches it" },
      { cap = 150, name = "Expert", needs = "skill 125 and the book Expert First Aid - Under Wraps, sold by Deneb Walker in the Arathi Highlands" },
      { cap = 225, name = "Artisan", needs = "skill 225, level 35 and the quest Triage from Doctor Gustaf VanHowzen in Theramore" },
    },
    steps = {
      { 1, 40, "Linen Bandage" }, { 40, 80, "Heavy Linen Bandage" }, { 80, 115, "Wool Bandage" }, { 115, 150, "Heavy Wool Bandage" },
      { 150, 180, "Silk Bandage" }, { 180, 210, "Heavy Silk Bandage" }, { 210, 240, "Mageweave Bandage" },
      { 240, 260, "Heavy Mageweave Bandage" }, { 260, 275, "Runecloth Bandage" }, { 275, 300, "Major Healing Potion" },
    },
  },
  Cooking = {
    source = SOURCE, verb = "cook", secondary = true, about = "Food that restores health and gives the Well Fed buff. It also teaches the campfire kit.",
    tiers = {
      { cap = 75, name = "Journeyman", needs = "skill 50; your Cooking trainer teaches it" },
      { cap = 150, name = "Expert", needs = "skill 125 and the Expert Cookbook, sold by Shandrina at Mystral Lake in Ashenvale" },
      { cap = 225, name = "Artisan", needs = "skill 225, level 35 and the quest Clamlette Surprise from Dirge Quikcleave in Gadgetzan" },
    },
    steps = {
      { 1, 50, "Charred Wolf Meat or Roasted Boar Meat" }, { 50, 75, "Smoked Bear Meat or Longjaw Mud Snapper" },
      { 75, 100, "Rainbow Fin Albacore or Strider Stew" }, { 100, 130, "Cooked Crab Claw or Bristle Whisker Catfish" },
      { 130, 175, "Curiously Tasty Omelet or Goblin Deviled Clams" }, { 175, 225, "Roast Raptor or Soothing Turtle Bisque" },
      { 225, 285, "Spotted Yellowtail" }, { 285, 300, "Nightfin Soup" },
    },
  },
  Fishing = {
    source = SOURCE, verb = "fish in", secondary = true, gather = true, about = "Fish for Cooking, and a calm way to earn a little.",
    tiers = {
      { cap = 75, name = "Journeyman", needs = "skill 50 and level 10; every Fishing trainer teaches it" },
      { cap = 150, name = "Expert", needs = "skill 125, level 20 and the book Expert Fishing - The Bass and You, sold by Old Man Heming in Booty Bay" },
      { cap = 225, name = "Artisan", needs = "skill 225, level 35 and the quest Nat Pagle, Angler Extreme in Dustwallow Marsh" },
    },
    steps = {
      { 1, 75, "any water in your starting zone" }, { 75, 150, "Stormwind, Ironforge, Darkshore, Loch Modan or Westfall" },
      { 150, 225, "Dustwallow Marsh, with Bright Baubles on your line" }, { 225, 300, "Feralas, The Hinterlands or Tanaris, with Bright Baubles" },
    },
  },
}

-- Which two professions suit a class, by what you want from them.
--
-- The leveling pairs are the ones two Forever guides agree on (Gfinity Esports'
-- "best profession pairings for every class" and RankedBoost's "best professions",
-- both checked in November 2026): the crafter that makes your armor type plus
-- what feeds it. The level 60 pairs are RankedBoost's raid picks. "Gold" is the
-- same guides' advice to take two gatherers; Mining and Skinning are named
-- because neither depends on the other and Skinning needs no searching.
-- These are recommendations, not rules: the settings let you pick your own two.
local CLOTH = { gear = { "Tailoring", "Enchanting" }, balanced = { "Tailoring", "Herbalism" }, gold = { "Mining", "Skinning" }, endgame = { "Tailoring", "Enchanting" } }
local function leather(endgame) return { gear = { "Skinning", "Leatherworking" }, balanced = { "Skinning", "Leatherworking" }, gold = { "Mining", "Skinning" }, endgame = endgame } end
local function plate() return { gear = { "Mining", "Blacksmithing" }, balanced = { "Mining", "Blacksmithing" }, gold = { "Mining", "Skinning" }, endgame = { "Mining", "Engineering" } } end

ns.ProfessionPicks = {
  primary = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking", "Mining", "Skinning", "Tailoring" },
  secondary = { "First Aid", "Cooking", "Fishing" },
  goals = {
    { "gear", "Make my own gear while leveling" }, { "balanced", "Gear and some gold" },
    { "gold", "Gold: gather and sell" }, { "endgame", "Ready for level 60 dungeons and raids" },
  },
  why = {
    gear = "You make armor your class wears as you level, from what the second profession or your kills supply.",
    balanced = "One profession makes gear for you; the other gathers things that sell on the auction house.",
    gold = "Two gathering professions: everything you pick up on the way sells on the auction house, and nothing costs you materials.",
    endgame = "The pair guides recommend for this class at level 60. It costs more to level than a leveling pair.",
  },
  byClass = {
    MAGE = CLOTH, PRIEST = CLOTH, WARLOCK = CLOTH,
    DRUID = { gear = { "Skinning", "Leatherworking" }, balanced = { "Skinning", "Leatherworking" }, gold = { "Herbalism", "Skinning" }, endgame = { "Herbalism", "Alchemy" } },
    ROGUE = leather({ "Mining", "Engineering" }), HUNTER = leather({ "Mining", "Engineering" }), SHAMAN = leather({ "Herbalism", "Alchemy" }),
    WARRIOR = plate(), PALADIN = plate(),
  },
  any = { gear = { "Mining", "Skinning" }, balanced = { "Mining", "Skinning" }, gold = { "Mining", "Skinning" }, endgame = { "Mining", "Engineering" } },
}
