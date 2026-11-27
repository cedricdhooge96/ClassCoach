-- luacheck settings. The game runs Lua 5.1.
--
-- The game's functions are an allow-list: the NEEDS list in Core/API.lua (rule 1:
-- every Forever function ClassCoach calls is in it). A call to a game function
-- that is not in NEEDS shows up here as "accessing undefined variable".
std = "lua51"
max_line_length = false
codes = true

local function needs()
  local names = {}
  local file = io.open("ClassCoach/Core/API.lua") or io.open("../ClassCoach/Core/API.lua")
  if not file then return names end
  local source = file:read("*a")
  file:close()
  local list = source:match("local NEEDS = (%b{})") or ""
  local fields = {}
  for name in list:gmatch('"([%w_%.]+)"') do
    local space, fn = name:match("^([%w_]+)%.([%w_]+)$")
    if space then
      fields[space] = fields[space] or {}
      fields[space][fn] = {}
    else
      names[#names + 1] = name
    end
  end
  for space, f in pairs(fields) do names[space] = { fields = f } end
  return names
end

read_globals = needs()
-- Not functions, so not in NEEDS: the game's frames, font objects, tables and constants.
for _, name in ipairs({
  "CreateFrame", "UIParent", "GameTooltip", "GameFontNormal", "GameFontHighlightSmall", "ChatFontNormal",
  "STANDARD_TEXT_FONT", "SOUNDKIT", "RAID_CLASS_COLORS", "Enum", "CurveConstants", "MAX_CHARACTER_MACROS",
  "WOW_PROJECT_ID", "WOW_PROJECT_CAMELOT", "MinimalSliderWithSteppersMixin", "C_AssistedCombat", "date",
}) do read_globals[#read_globals + 1] = name end

-- What the addon itself puts in the global table: saved variables, the slash
-- command, the key binding header and the addon compartment's functions.
globals = {
  "ClassCoachDB", "ClassCoachCharDB", "ClassCoachTrace", "SlashCmdList",
  "SLASH_CLASSCOACH1", "SLASH_CLASSCOACH2", "BINDING_HEADER_CLASSCOACH",
  "ClassCoach_OnAddonCompartmentClick", "ClassCoach_OnAddonCompartmentEnter", "ClassCoach_OnAddonCompartmentLeave",
}

-- Handlers keep the game's argument list (self, event, ...) even when they use only some.
unused_args = false
-- A local that reuses the name of an outer function's local (text, step, pick) is
-- left alone: 17 of them, all read as meant. Shadowing inside one function (W421) still counts.
ignore = { "431" }

-- Only the addon is checked: the tests build a fake game in the global table on purpose.
include_files = { "ClassCoach/**/*.lua" }
