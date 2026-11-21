-- What to craft next in a profession, for WoW Forever.
--
-- steps = { fromSkill, toSkill, "what to craft" }; tiers = the skill caps and
-- what the trainer wants for the next rank. Only Tailoring has steps so far;
-- every other profession still gets the "you are at the cap" reminder.
--
-- Tailoring follows wow-professions.com's Forever guide
-- (https://www.wow-professions.com/forever/tailoring-leveling-guide), which
-- says it is based on the Forever beta: the higher steps are not proven on the
-- live game yet. Materials, amounts and trainer locations are in the guide.
local _, ns = ...

ns.ProfessionData = {
  Tailoring = {
    source = "wow-professions.com",
    tiers = {
      { cap = 75, name = "Journeyman", needs = "skill 50 and level 10" },
      { cap = 150, name = "Expert", needs = "skill 125, level 20 and 50 silver" },
      { cap = 225, name = "Artisan", needs = "skill 200 and level 35" },
    },
    steps = {
      { 1, 30, "Bolt of Linen Cloth" }, { 30, 55, "Linen Belt" }, { 55, 80, "Bolt of Woolen Cloth" }, { 80, 95, "Woolen Cape" },
      { 95, 100, "Double-stitched Woolen Shoulders" }, { 100, 120, "Bolt of Silk Cloth" }, { 120, 140, "Gloves of Meditation" },
      { 140, 150, "Bolt of Mageweave" }, { 150, 170, "Crimson Silk Vest" }, { 170, 190, "Crimson Silk Pantaloons" },
      { 190, 200, "Black Mageweave Leggings" }, { 200, 205, "Black Mageweave Shoulders" }, { 205, 215, "Bolt of Runecloth" },
      { 215, 225, "Red Mageweave Bag" }, { 225, 240, "Runecloth Belt" }, { 240, 250, "Runecloth Gloves" },
      { 250, 280, "Runecloth Cuffs" }, { 280, 300, "Runecloth Shoulders" },
    },
  },
}
