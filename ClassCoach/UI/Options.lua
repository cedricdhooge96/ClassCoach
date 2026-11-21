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
    { header = "Coach (the fight)" },
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
    { key = "showDots", kind = "check", name = "Show timers the icons don't", default = true,
      tip = "A line for damage over time that is not on one of the icons, and for other enemies that are still ticking." },
    { key = "showMana", kind = "check", name = "Show the mana bar", default = true,
      tip = "Your real mana, drawn by the game. It turns amber, then red, as the coach's advice changes." },
    { key = "cue", kind = "check", name = "Pulse the ring when a new key is needed", default = true,
      tip = "Most of a fight is one steady key. When something else comes up, or a spell was resisted, the ring pulses." },
    { key = "cueSound", kind = "choice", fixed = true, name = "Sound with the pulse", default = "click",
      tip = "A short sound when the ring pulses.",
      choices = function() return { { "off", "None" }, { "click", "Soft click" }, { "ready", "Ready check" } } end },
    { key = "barGlow", kind = "choice", fixed = true, name = "Light up the button to press on my action bars", default = "glow",
      tip = "Marks the action-bar button of the step to press now. Works on the game's own action bars.",
      choices = function() return ns.BarGlow.STYLES end },
    { key = "clickable", kind = "check", name = "Click an icon to cast it (before a fight)", default = true,
      tip = "Out of combat, click an amber icon to cast what fixes it, or the ring to start the pull. In a fight the game does not let an addon do this, so the icons are pictures again." },

    { key = "threat", kind = "check", name = "Warn about enemies I shouldn't fight", default = true,
      tip = "Before a pull: enemies far above your level, elites when you are alone, and grey ones that give no XP." },

    { header = "Journey panel (outside the fight)" },
    { key = "journey", kind = "check", name = "Show the journey panel", default = true,
      tip = "XP, rested XP and a short to-do list." },
    { key = "journeyInCombat", kind = "check", name = "Keep it visible in combat", default = true,
      tip = "The panel stays up during a fight, showing what it showed before the pull. It updates again when the fight ends. Turn off to hide it in combat." },
    { key = "journeyScale", kind = "slider", name = "Size", default = 1, min = 0.6, max = 1.6, step = 0.05, unit = "x",
      tip = "Size of the journey panel." },
    { key = "talentMarks", kind = "check", name = "Mark my next talent in the talent window", default = true,
      tip = "In the game's talent window (N), the next talent of your build gets a gold frame and the ones after it a number. Pick the build with /coach build." },
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

    { header = "Coaching" },
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
      tip = "Bind its three keys under Options > Keybindings > AddOns > ClassCoach: Next, Again (after a resist) and Restart. One press still casts one spell. Type /coach smart to see its steps." },
    { key = "autoBar", kind = "check", name = "Put newly learned spells on my bars", default = false,
      tip = "When you train a spell, it goes to its button on the fight, react or prepare bar if that button is free. Nothing is ever overwritten." },
    { key = "autoMacros", kind = "check", name = "Keep my CC macros up to date", default = true,
      tip = "Rewrites the macros made by /coach macros when you learn spells or the pull plan changes." },
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
    page:AddInitializer(CreateSettingsButtonInitializer("Helper macros", "Create or refresh", actions.macros,
      "Makes this class's CC macros from the spells you know. Out of combat only.", true))
    page:AddInitializer(CreateSettingsButtonInitializer("Action bar", "Fill empty buttons", actions.bar,
      "Lays out three bars by purpose: the fight on your main bar, reactions on Action Bar 2, preparation on Action Bar 3. Buttons that already hold something are left alone.", true))
    page:AddInitializer(CreateSettingsButtonInitializer("Panel positions", "Reset", actions.reset,
      "Puts both panels back where they started.", true))
  end)
  Settings.RegisterAddOnCategory(category)
  Options.category = category
  return true
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
