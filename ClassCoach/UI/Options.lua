-- The settings screen, built with the game's own Settings system so it looks
-- and behaves like every other options page (Esc > Options > AddOns > ClassCoach,
-- or /coach). Every option writes straight into the saved settings; the panels
-- read them on their next refresh, so changes show at once.
local _, ns = ...

local Options = {}
ns.Options = Options

-- Each entry: a section header, or one setting.
--   key      where it is stored (ClassCoachDB, or ClassCoachCharDB with perChar)
--   kind     "check", "slider" (min, max, step, unit) or "choice" (choices = function)
local function professionChoices()
  local list = { { "auto", "Suggest one for my class" } }
  for _, name in ipairs(ns.ProfessionPicks.primary) do list[#list + 1] = { name, name } end
  return list
end

local function layout()
  return {
    { header = "Coach" },
    { key = "showCoach", kind = "check", name = "Show the coach", default = true,
      tip = "The ring: what to press now, with what you already cast on its left and what comes next on its right." },
    { key = "scale", kind = "slider", name = "Size", default = 1, min = 0.6, max = 1.6, step = 0.05, unit = "x",
      tip = "Size of the coach. If the big icon looks soft on your screen, make it a little smaller." },
    { key = "compact", kind = "check", name = "Compact: no explanation", default = false,
      tip = "Hides the line that says why. For when you know your spells." },
    { key = "stepsBefore", kind = "slider", name = "Steps shown before the current one", default = 2, min = 0, max = 4, step = 1,
      tip = "How many of your last casts on this enemy stay on the left, with the seconds left on damage over time. 0 hides them." },
    { key = "stepsAfter", kind = "slider", name = "Steps shown after the current one", default = 2, min = 0, max = 4, step = 1,
      tip = "How many upcoming steps show on the right, each with its key." },
    { key = "showDots", kind = "check", name = "Show your damage over time on the enemy", default = true,
      tip = "Above the ring: an icon for each of your spells ticking on this enemy, with the time it has left, the way the game shows debuffs. And a line when other enemies are still ticking." },
    { key = "showMana", kind = "check", name = "Show the mana bar", default = true,
      tip = "Your real mana, drawn by the game. It turns amber, then red, as the coach's advice changes." },
    { key = "readyAlpha", kind = "slider", name = "Coach opacity when you are ready", default = 50, min = 20, max = 100, step = 5, unit = "%",
      tip = "With nothing targeted and nothing to prepare, the coach steps back to this. Anything to do before a pull brings it back to full." },
    { key = "lantern", kind = "check", name = "Soft light under the coach", default = true,
      tip = "A faint glow on the ground under the ring: your class colour, amber when something needs doing before a pull, orange in a fight." },
    { key = "cue", kind = "check", name = "Pulse the ring when a new key is needed", default = true,
      tip = "Most of a fight is one steady key. When something else comes up, or a spell was resisted, the ring pulses." },
    { key = "cueSound", kind = "choice", fixed = true, name = "Sound with the pulse", default = "click",
      tip = "A short sound when the ring pulses.",
      choices = function() return { { "off", "None" }, { "click", "Soft click" }, { "ready", "Ready check" } } end },
    { key = "clickable", kind = "check", name = "Click an icon to cast it (before a fight)", default = true,
      tip = "Out of combat, click an amber icon to cast what fixes it, or the ring to start the pull. In a fight the game does not let an addon do this, so the icons are pictures again." },
    { key = "threat", kind = "check", name = "Warn about enemies I shouldn't fight", default = true,
      tip = "Before a pull: enemies far above your level, elites when you are alone, and grey ones that give no XP." },
    { key = "specChoice", perChar = true, kind = "choice", name = "Profile for this character", default = "auto",
      tip = "Auto follows your talents. Pick one to force it.",
      choices = function()
        local list = { { "auto", "Auto (follow my talents)" } }
        for _, p in ipairs(ns.Profiles.forClass(ns.C.class or "ANY")) do list[#list + 1] = { p.spec, p.spec } end
        return list
      end },
    { key = "smartDots", kind = "check", name = "Skip damage over time on enemies about to die", default = true,
      tip = "Uses how long your kills usually take. Off: always suggest the full set." },
    { key = "drinkAt", kind = "slider", name = "Suggest drinking below", default = 60, min = 20, max = 90, step = 5, unit = "%",
      tip = "Out of combat, below this much mana the coach tells you to drink (or Life Tap) first." },
    { key = "chat", kind = "check", name = "Fight tips in chat", default = true,
      tip = "After a fight, also print the tips in the chat window." },
    { key = "smartKey", kind = "check", name = "Smart key: one key walks the coach's plan", default = true,
      tip = "Bind it under Options > Keybindings > AddOns > ClassCoach, or type /coach smart 1. It is the game's own cast sequence: it only moves on when a spell went off, and starts over on a new target. One press still casts one spell. Type /coach smart to see its steps." },

    { header = "Action bars" },
    { key = "barGlow", kind = "choice", fixed = true, name = "Light up the button to press on my action bars", default = "glow",
      tip = "Marks the action-bar button of the step to press now. Works on the game's own action bars.",
      choices = function() return ns.Glow.STYLES end },
    { key = "glowColor", kind = "choice", fixed = true, name = "Highlight colour", default = "gold",
      tip = "The colour of every ClassCoach highlight: the action-bar button, the next talent and a spell in your spellbook.",
      choices = function() return ns.Glow.COLORS end },
    { key = "spellbookGlow", kind = "check", name = "Light up a missing spell in my spellbook", default = true,
      tip = "When the coach's step is on none of your bars, open your spellbook: the spell lights up there, ready to drag onto a bar." },
    { key = "autoBar", kind = "check", name = "Put newly learned spells on my bars", default = false,
      tip = "When you train a spell, it goes to a free button on the fight, react or prepare bar. Nothing is overwritten or moved; /coach bar reset sorts the bars again." },
    { key = "barFixed", kind = "check", name = "Fixed buttons: leave a gap for spells I have not learned", default = false,
      tip = "Off: the spells you have sit side by side from button 1, so a bar has no gaps; after you learn a spell, /coach bar reset sorts it into place and the buttons after it move one up. On: every spell has its own button for good, so a key never changes, and gaps fill in as you level." },
    { key = "autoMacros", kind = "check", name = "Keep my CC macros up to date", default = true,
      tip = "Rewrites the macros made by /coach macros when you learn spells or the pull plan changes." },

    { header = "Talents" },
    { key = "talentMarks", kind = "check", name = "Guide me in the talent window", default = true,
      tip = "In the game's talent window, the next talent of your build is lit and the ones after it get a number. Pick the build with /coach build." },
    { key = "talentGlow", kind = "choice", fixed = true, name = "Look of the next talent", default = "glow",
      tip = "How the next talent of your build is marked in the talent window.",
      choices = function() return ns.Glow.STYLES end },
    { key = "talentDim", kind = "check", name = "Dim talents outside my build", default = true,
      tip = "Talents your build never takes are darkened, so the ones that matter stand out." },
    { key = "talentList", kind = "check", name = "Show my build beside the talent window", default = true,
      tip = "A card with your progress and the next five points, each with the level it comes at." },
    { key = "talentToast", kind = "check", name = "Name the talent to take when I level up", default = true,
      tip = "A short note at the top of the screen with the talent your build takes next." },
    { key = "learnNow", kind = "check", name = "Learn now button", default = false,
      tip = "Adds a button to the card and the level-up note that learns the next talent of your build when you click it. Out of combat only. Off: you click talents yourself." },

    { header = "Journey" },
    { key = "journey", kind = "check", name = "Show the journey panel", default = true,
      tip = "XP, rested XP and a short to-do list." },
    { key = "journeyInCombat", kind = "check", name = "Keep it visible in combat", default = true,
      tip = "The panel stays up during a fight, showing what it showed before the pull. It updates again when the fight ends. Turn off to hide it in combat." },
    { key = "journeyScale", kind = "slider", name = "Size", default = 1, min = 0.6, max = 1.6, step = 0.05, unit = "x",
      tip = "Size of the journey panel." },
    { key = "food", kind = "check", name = "Remind me: food buff", default = true,
      tip = "In Forever, cooked food (marked Nutritious) gives +5% XP from kills for 15 minutes." },
    { key = "remindRested", kind = "check", name = "Remind me: rested XP, tent and sleeping bag", default = true,
      tip = "Rested XP doubles XP from kills. Logging out in an inn or city builds it; Forever adds the Camp Tent and the Cozy Sleeping Bag." },
    { key = "remindTrain", kind = "check", name = "Remind me: trainer and talent points", default = true,
      tip = "Spells you can learn now, unspent talent points, and the next level with something new." },
    { key = "remindGear", kind = "check", name = "Remind me: repairs and full bags", default = true,
      tip = "Gear below 25% durability, or two bag slots left." },
    { key = "remindProfessions", kind = "check", name = "Remind me: professions", default = true,
      tip = "Which professions to learn, a trainer visit when one is at its skill cap, and what to do next in each. /coach professions shows the whole plan." },
    { key = "remindSupplies", kind = "check", name = "Remind me: food, water and reagents", default = true,
      tip = "At a vendor when you are running low, and anywhere when you have run out." },
    { key = "roadmap", kind = "check", name = "Show milestones, zones and dungeons", default = true,
      tip = "Class quests and other milestones for your level, where to quest, and which dungeon is in range." },

    { header = "Professions" },
    { key = "professionGoal", kind = "choice", fixed = true, name = "What I want from my professions", default = "gear",
      tip = "Decides which two professions the coach suggests for your class. The suggestion only shows while you have a profession slot free.",
      choices = function() return ns.ProfessionPicks.goals end },
    { key = "professionA", perChar = true, kind = "choice", fixed = true, name = "My first profession", default = "auto",
      tip = "Pick one yourself for this character, or leave it to the goal above.",
      choices = professionChoices },
    { key = "professionB", perChar = true, kind = "choice", fixed = true, name = "My second profession", default = "auto",
      tip = "Pick one yourself for this character, or leave it to the goal above.",
      choices = professionChoices },
    { key = "remindSecondary", kind = "check", name = "Suggest First Aid, Cooking and Fishing", default = true,
      tip = "In Forever these three use no profession slot, so every character can learn them all." },

    { header = "Look" },
    { key = "opacity", kind = "slider", name = "Background behind text", default = 60, min = 0, max = 100, step = 5, unit = "%",
      tip = "How dark the plate behind the coach's text and the journey list is. It keeps the words readable on bright ground." },
    { key = "ownFonts", kind = "check", name = "Use ClassCoach's own typefaces (being tested)", default = false,
      tip = "Inter and Marcellus instead of the game's font. Applies at once. A text that will not take its typeface keeps the game's font." },
    { key = "locked", kind = "check", name = "Lock the panels in place", default = false,
      tip = "Unlocked, drag the coach by its ring and the journey list anywhere on it. Locked, the ring lets clicks through." },
  }
end

-- Saved settings can be damaged (a crash while saving, an edit by hand, an
-- older version). Anything of the wrong kind or out of range goes back to its
-- default, so the panels never have to cope with it.
function Options.sanitize(db, charDB)
  for _, o in ipairs(layout()) do
    if o.key then
      local store = o.perChar and charDB or db
      local v = store[o.key]
      if type(v) ~= type(o.default) then
        store[o.key] = o.default
      elseif o.kind == "slider" then
        if v ~= v or v < o.min or v > o.max then store[o.key] = o.default end   -- v ~= v: not a number
      elseif o.kind == "choice" and o.fixed then
        -- a list that never changes: a value that is not on it is damage
        local known = false
        for _, choice in ipairs(o.choices()) do if choice[1] == v then known = true end end
        if not known then store[o.key] = o.default end
      end
    end
  end
  local function position(pos)
    if type(pos) ~= "table" then return nil end
    if type(pos[1]) ~= "string" or type(pos[2]) ~= "string" or type(pos[3]) ~= "number" or type(pos[4]) ~= "number" then return nil end
    if pos[3] ~= pos[3] or pos[4] ~= pos[4] or math.abs(pos[3]) > 20000 or math.abs(pos[4]) > 20000 then return nil end
    return pos
  end
  charDB.focusPos, charDB.journeyPos = position(charDB.focusPos), position(charDB.journeyPos)
  local card = db.talentCardPos
  if type(card) ~= "table" or type(card[1]) ~= "number" or type(card[2]) ~= "number" or card[1] ~= card[1] or card[2] ~= card[2]
    or math.abs(card[1]) > 20000 or math.abs(card[2]) > 20000 then
    db.talentCardPos = nil
  end
  local kill = charDB.kill
  if type(kill) ~= "table" or type(kill.avg) ~= "number" or type(kill.n) ~= "number" or kill.avg ~= kill.avg or kill.avg <= 0 or kill.avg > 600 then
    charDB.kill = nil
  end
  if type(charDB.demon) ~= "string" then charDB.demon = nil end
  if type(db.log) ~= "table" then db.log = nil end
end

function Options.defaults()
  local d = {}
  for _, o in ipairs(layout()) do
    if o.key and not o.perChar then d[o.key] = o.default end
  end
  return d
end

local function unitFormatter(unit)
  return function(value)
    if unit == "x" then return ("%.2fx"):format(value) end
    return ("%d%s"):format(value, unit or "")
  end
end

-- Builds the page. Returns true when the game's Settings system took it.
function Options.build(db, charDB, actions)
  if Options.category then return true end
  if not Settings or not Settings.RegisterVerticalLayoutCategory then return false end
  local category, page = Settings.RegisterVerticalLayoutCategory("ClassCoach")
  Options.registered = {}
  for _, o in ipairs(layout()) do
    local ok, err = pcall(function()
      if o.header then
        if page and CreateSettingsListSectionHeaderInitializer then
          page:AddInitializer(CreateSettingsListSectionHeaderInitializer(o.header))
        end
        return
      end
      local store = o.perChar and charDB or db
      if store[o.key] == nil then store[o.key] = o.default end
      local setting = Settings.RegisterAddOnSetting(category, "ClassCoach_" .. o.key, o.key, store,
        type(o.default), o.name, o.default)
      if o.kind == "check" then
        Settings.CreateCheckbox(category, setting, o.tip)
      elseif o.kind == "slider" then
        local opts = Settings.CreateSliderOptions(o.min, o.max, o.step)
        if opts.SetLabelFormatter and MinimalSliderWithSteppersMixin then
          opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, unitFormatter(o.unit))
        end
        Settings.CreateSlider(category, setting, opts, o.tip)
      elseif o.kind == "choice" then
        Settings.CreateDropdown(category, setting, function()
          local container = Settings.CreateControlTextContainer()
          for _, c in ipairs(o.choices()) do container:Add(c[1], c[2]) end
          return container:GetData()
        end, o.tip)
      end
      Options.registered[#Options.registered + 1] = o.key
    end)
    if not ok and ns.API.log then ns.API.log("settings: %s failed: %s", tostring(o.key or o.header), tostring(err)) end
  end
  -- Buttons for the things that are actions, not switches.
  pcall(function()
    if not (page and CreateSettingsButtonInitializer) then return end
    page:AddInitializer(CreateSettingsListSectionHeaderInitializer("Actions"))
    if actions.window then
      page:AddInitializer(CreateSettingsButtonInitializer("ClassCoach's own settings", "Open", actions.window,
        "The same settings with previews, a first-time setup and sharing. Also /coach.", true))
    end
    page:AddInitializer(CreateSettingsButtonInitializer("Helper macros", "Create or refresh", actions.macros,
      "Makes this class's CC macros from the spells you know. Out of combat only.", true))
    page:AddInitializer(CreateSettingsButtonInitializer("Action bar", "Fill empty buttons", actions.bar,
      "Lays out three bars by purpose: the fight on your main bar, reactions on Action Bar 2, preparation on Action Bar 3. Buttons that already hold something are left alone.", true))
    page:AddInitializer(CreateSettingsButtonInitializer("Action bar", "Reset to the coach's layout", actions.barReset,
      "Makes those three bars exactly the coach's layout: what you can use, side by side without gaps, and every other button emptied. /coach bar undo puts back what was there.", true))
    page:AddInitializer(CreateSettingsButtonInitializer("Panel positions", "Reset", actions.reset,
      "Puts both panels back where they started.", true))
  end)
  Settings.RegisterAddOnCategory(category)
  Options.category = category
  return true
end

-- The options grouped by section, in order: { { name, options = { ... } } }.
function Options.sections()
  local out, current = {}, nil
  for _, o in ipairs(layout()) do
    if o.header then
      current = { name = o.header, options = {} }
      out[#out + 1] = current
    elseif current then
      current.options[#current.options + 1] = o
    end
  end
  return out
end

-- A value checked against its option: the right kind, in range, on the list.
-- Returns the value to store, or nil when it does not fit.
function Options.valid(o, v)
  if type(v) ~= type(o.default) then return nil end
  if o.kind == "slider" then
    if v ~= v or v < o.min or v > o.max then return nil end
    return math.floor((v - o.min) / o.step + 0.5) * o.step + o.min
  elseif o.kind == "choice" then
    for _, c in ipairs(o.choices()) do if c[1] == v then return v end end
    return nil
  end
  return v
end

-- Writes one setting (the settings window and /coach set). Returns true when it was taken.
function Options.set(db, charDB, key, v)
  local o = Options.find(key)
  local value = o and Options.valid(o, v)
  if value == nil then return false end
  local store = o.perChar and charDB or db
  store[o.key] = value
  return true
end

-- Your settings as one line of text to share or keep: only what differs from the
-- defaults, and only what is the same for every character (not the profile or
-- professions picked for one character).
local EXPORT_TAG = "ClassCoach1"
local function encode(v)
  if v == true then return "on" elseif v == false then return "off" end
  if type(v) == "number" then return (("%.2f"):format(v):gsub("%.?0+$", "")) end
  return tostring(v)
end
function Options.export(db)
  local parts = { EXPORT_TAG }
  for _, o in ipairs(layout()) do
    if o.key and not o.perChar and db[o.key] ~= nil and db[o.key] ~= o.default then
      parts[#parts + 1] = o.key .. "=" .. encode(db[o.key])
    end
  end
  return table.concat(parts, " ")
end

-- Reads a line made by Options.export. Returns how many settings were taken,
-- and the names it could not use (unknown, or a value that does not fit).
function Options.import(text, db, charDB)
  text = tostring(text or "")
  if not text:find("^%s*" .. EXPORT_TAG) then return nil, {} end
  local taken, skipped = 0, {}
  for key, raw in text:gmatch("([%w_]+)=(%S+)") do
    local o = Options.find(key)
    local v = raw
    if o and o.kind == "check" then v = (raw == "on") or (raw ~= "off" and nil) end
    if o and o.kind == "slider" then v = tonumber(raw) end
    if o and not o.perChar and v ~= nil and Options.set(db, charDB, o.key, v) then taken = taken + 1 else skipped[#skipped + 1] = key end
    if taken + #skipped >= 100 then break end
  end
  return taken, skipped
end

-- For /coach set: look an option up by its key (case-insensitive).
function Options.find(key)
  key = tostring(key):lower()
  for _, o in ipairs(layout()) do
    if o.key and o.key:lower() == key then return o end
  end
end

function Options.keys()
  local list = {}
  for _, o in ipairs(layout()) do if o.key then list[#list + 1] = o.key end end
  return list
end
