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
local function layout()
  return {
    { header = "Coach panel (the fight)" },
    { key = "showCoach", kind = "check", name = "Show the coach panel", default = true,
      tip = "The carousel: what you did, what to press now and what comes next." },
    { key = "scale", kind = "slider", name = "Size", default = 1, min = 0.6, max = 1.6, step = 0.05, unit = "x",
      tip = "Size of the coach panel." },
    { key = "compact", kind = "check", name = "Compact: icons only", default = false,
      tip = "Hides the explanation and the names of the next steps. For when you know your spells by their icons." },
    { key = "showDone", kind = "check", name = "Show what you already cast (left icons)", default = true,
      tip = "Your last two casts on this enemy, with the seconds left on damage over time." },
    { key = "showDots", kind = "check", name = "Show the timers line", default = true,
      tip = "\"On this enemy: Corruption 9s\" under the carousel." },
    { key = "showMana", kind = "check", name = "Show the mana bar", default = true,
      tip = "Your real mana, drawn by the game." },

    { key = "threat", kind = "check", name = "Warn about enemies I shouldn't fight", default = true,
      tip = "Before a pull: enemies far above your level, elites when you are alone, and grey ones that give no XP." },

    { header = "Journey panel (outside the fight)" },
    { key = "journey", kind = "check", name = "Show the journey panel", default = true,
      tip = "XP, rested XP and a short to-do list. It hides itself in combat." },
    { key = "journeyScale", kind = "slider", name = "Size", default = 1, min = 0.6, max = 1.6, step = 0.05, unit = "x",
      tip = "Size of the journey panel." },
    { key = "food", kind = "check", name = "Remind me: food buff", default = true,
      tip = "Cooked food gives +5% XP from kills for 15 minutes." },
    { key = "remindRested", kind = "check", name = "Remind me: rested XP, tent and sleeping bag", default = true,
      tip = "Rested XP doubles XP from kills. Logging out in an inn or city builds it." },
    { key = "remindTrain", kind = "check", name = "Remind me: trainer and talent points", default = true,
      tip = "Spells you can learn now, unspent talent points, and the next level with something new." },
    { key = "remindGear", kind = "check", name = "Remind me: repairs and full bags", default = true,
      tip = "Gear below 25% durability, or two bag slots left." },
    { key = "remindSupplies", kind = "check", name = "Remind me: food, water and reagents", default = true,
      tip = "At a vendor when you are running low, and anywhere when you have run out." },
    { key = "roadmap", kind = "check", name = "Show milestones, zones and dungeons", default = true,
      tip = "Class quests and other milestones for your level, where to quest, and which dungeon is in range." },

    { header = "Look" },
    { key = "opacity", kind = "slider", name = "Background", default = 75, min = 0, max = 100, step = 5, unit = "%",
      tip = "How dark the panels are. 0% leaves only the icons and text." },
    { key = "border", kind = "check", name = "Thin border", default = true, tip = "A hairline around each panel." },
    { key = "accent", kind = "check", name = "Class colour line", default = true, tip = "A thin line in your class colour along the top." },
    { key = "locked", kind = "check", name = "Lock the panels in place", default = false,
      tip = "Unlocked, you can drag each panel on its own." },

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
