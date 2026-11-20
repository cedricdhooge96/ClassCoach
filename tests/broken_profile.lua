-- Profiles that are wrong in different ways. None of them may stop the addon loading.
local _, ns = ...
ns.RegisterProfile(nil)
ns.RegisterProfile("not a table")
ns.RegisterProfile({ spec = "No class" })
ns.RegisterProfile({ class = "WARLOCK", spec = "Bad list", priority = "oops" })
ns.RegisterProfile({ class = "WARLOCK", spec = "Unknown spell", priority = { { spell = "Nothing" } } })
ns.RegisterProfile({ class = "WARLOCK", spec = "Bad spells", spells = { Bolt = 5 } })
