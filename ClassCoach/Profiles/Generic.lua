-- The fallback for every class without its own profile yet.
-- It still gives the mana coach, the drink and food checks, the fight
-- summary and level-up reminders; it just doesn't suggest spells.
local _, ns = ...

ns.RegisterProfile({
  class = "ANY",
  spec = "General",
  freeDamage = "your auto attack",
  spells = {},
  priority = {},
  filler = {
    { label = "Your main attacks", why = "No class profile yet: ClassCoach only coaches mana and buffs for this class." },
  },
})
