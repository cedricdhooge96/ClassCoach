-- What the leveling guides say to do when: milestones every class shares,
-- and where to quest and which dungeon fits your level. Class milestones live
-- in each profile (`milestones = { ... }`).
--
-- A milestone: { level, text, hint, icon, done = function(s) }
--   with `done`    it stays on the list from that level until it is done
--   without        it shows for that level and the next (the addon can't tell)
local _, ns = ...

local ICON = "Interface\\Icons\\"

ns.JourneyData = {
  milestones = {
    { level = 10, text = "First talent point", icon = ICON .. "Ability_Marksmanship",
      hint = "From level 10 you get one talent point per level. Press N to spend it." },
    { level = 14, text = "Cozy Sleeping Bag quest chain", icon = ICON .. "INV_Misc_Bag_10",
      hint = "A quest chain from level 14 rewards a sleeping bag: rest on it for up to +3% XP.",
      done = function(s) return s.journey and s.journey.hasItem and s.journey.hasItem("Cozy Sleeping Bag") end },
    { level = 40, text = "Mount and Dual Specialization", icon = ICON .. "Ability_Mount_RidingHorse",
      hint = "At 40 you can learn riding and buy a second talent setup. Start saving gold around level 30." },
  },

  -- Where to quest, per faction: { from, to, zones }. From the Alliance route in the roadmap.
  zones = {
    Alliance = {
      { 1, 11, "Your starting zone (Dun Morogh, Elwynn Forest or Teldrassil)" },
      { 10, 19, "Loch Modan or Westfall" },
      { 15, 24, "Redridge Mountains" },
      { 20, 29, "Wetlands, Duskwood or Ashenvale" },
      { 30, 39, "Arathi Highlands or Stranglethorn Vale" },
      { 35, 44, "Riverglades (new), Badlands or Dustwallow Marsh" },
      { 40, 49, "The Hinterlands, Tanaris or Feralas" },
      { 48, 54, "Un'Goro Crater or Searing Gorge" },
      { 50, 57, "Burning Steppes or Western Plaguelands" },
      { 53, 60, "Eastern Plaguelands, Winterspring or Silithus" },
    },
  },

  -- What innkeepers and food vendors sell, by the level you can use it: { level, name }.
  -- Names from Classic; Forever keeps the old world's vendors.
  drinks = {
    { 1, "Refreshing Spring Water" }, { 5, "Ice Cold Milk" }, { 15, "Melon Juice" }, { 25, "Sweet Nectar" },
    { 35, "Moonberry Juice" }, { 45, "Morning Glory Dew" },
  },
  foods = {
    { 1, "Tough Hunk of Bread" }, { 5, "Freshly Baked Bread" }, { 15, "Moist Cornbread" }, { 25, "Mulgore Spice Bread" },
    { 35, "Soft Banana Bread" }, { 45, "Homemade Cherry Pie" },
  },

  -- Dungeons by level range: { from, to, name }.
  dungeons = {
    Alliance = {
      { 13, 20, "Hall of Thanes" }, { 17, 26, "Deadmines" }, { 24, 32, "The Stockade or Blackfathom Deeps" },
      { 26, 33, "Excavation Site: Wetlands" }, { 28, 35, "City of Dalaran" }, { 30, 40, "Gnomeregan or Scarlet Monastery" },
      { 35, 42, "The Drowned City" }, { 40, 47, "Krol'Dok Stronghold" }, { 41, 51, "Uldaman" }, { 44, 54, "Zul'Farrak" },
      { 46, 55, "Maraudon" }, { 48, 55, "Alcaz Island Prison" }, { 50, 60, "Sunken Temple" }, { 52, 60, "Blackrock Depths" },
      { 55, 60, "Blackmaw Hold" }, { 58, 60, "Shaper's Terrace" },
    },
  },
}
