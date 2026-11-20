-- Loads ClassCoach into the fake client and plays through a few sessions.
-- Run with: python3 tests/run.py   (uses LuaJIT, the same Lua 5.1 dialect as WoW)
local ROOT = ROOT or "."
local M = dofile(ROOT .. "/tests/mock.lua")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1 else failed = failed + 1; print_real("FAIL " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local function load(extra)
  local ns = {}
  local toc = io.open(ROOT .. "/ClassCoach/ClassCoach.toc"):read("*a")
  local files = {}
  for line in toc:gmatch("[^\n]+") do
    if not line:match("^#") and line:match("%.lua%s*$") then
      files[#files + 1] = ROOT .. "/ClassCoach/" .. line:gsub("\\", "/"):gsub("%s+$", "")
    end
  end
  if extra then table.insert(files, #files - 1, ROOT .. "/" .. extra) end   -- before the panel and main file
  for _, path in ipairs(files) do
    local chunk = assert(loadfile(path))
    chunk("ClassCoach", ns)
  end
  M.fire("ADDON_LOADED", "ClassCoach")
  M.fire("PLAYER_ENTERING_WORLD")
  M.advance(1)
  return ns
end

local function panel() return ClassCoachPanelRef end
local function tick(ns)
  local driver = ns.C.driver
  driver.scripts.OnUpdate(driver, 1)
  return ns.Panel.frame
end
local function cast(id, cost)
  M.P.mana = M.P.mana - (cost or M.P.spells[id].cost or 0)
  M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", id)
end
-- Selecting an enemy fires the game's event, like a real click does.
local function target(t)
  M.P.target = t
  M.fire("PLAYER_TARGET_CHANGED")
end
-- What the coach panel shows as missing before a pull (the icons' titles).
local function missing(ns)
  local parts = {}
  for _, s in ipairs(ns.Panel.frame.missing) do if s.shown and rawget(s, "title") then parts[#parts + 1] = rawget(s, "title") end end
  return table.concat(parts, " | ")
end
-- The same without lines about later levels ("At level 25: ..."), which name things on purpose.
local function journeyNow(ns)
  local f, parts = ns.Journey.frame, {}
  if not f.shown then return "" end
  for _, r in ipairs(f.rows) do
    if r.shown and r.label.text ~= "" and not r.label.text:find("^At level ") then parts[#parts + 1] = r.label.text end
  end
  parts[#parts + 1] = f.hint.text
  return table.concat(parts, " | ")
end
-- Everything the journey panel is showing, as one string.
local function journey(ns)
  local f, parts = ns.Journey.frame, {}
  if not f.shown then return "(hidden)" end
  parts[#parts + 1] = f.barText.text
  for _, r in ipairs(f.rows) do if r.shown and r.label.text ~= "" then parts[#parts + 1] = r.label.text end end
  parts[#parts + 1] = f.hint.text
  return table.concat(parts, " | ")
end
local function errors() return ClassCoachDB.log and #ClassCoachDB.log or 0 end

local SCENARIO = SCENARIO

---------------------------------------------------------------------------
if SCENARIO == "shaman" then
  M.player({
    class = "SHAMAN", className = "Shaman", level = 12, mana = 300, maxMana = 300,
    spells = {
      [403] = { name = "Lightning Bolt", cost = 15 }, [529] = { name = "Lightning Bolt", cost = 30 },
      [8042] = { name = "Earth Shock", cost = 30 }, [8044] = { name = "Earth Shock", cost = 50 },
      [8050] = { name = "Flame Shock", cost = 55 }, [324] = { name = "Lightning Shield", cost = 45 },
      [8017] = { name = "Rockbiter Weapon", cost = 40 }, [3599] = { name = "Searing Totem", cost = 25 },
      [8075] = { name = "Strength of Earth Totem", cost = 32 }, [331] = { name = "Healing Wave", cost = 25 },
    },
    book = { 403, 529, 8042, 8044, 8050, 324, 8017, 3599, 8075, 331 },
    actions = { [1] = 529, [2] = 8044, [3] = 8050 },
    bindings = { ACTIONBUTTON1 = "1", ACTIONBUTTON2 = "2", ACTIONBUTTON3 = "SHIFT-3" },
    talents = { 0, 3, 0 },
  })
  local ns = load()
  check("shaman profile chosen", ns.C.profile.spec == "Enhancement", ns.C.profile.spec)
  check("rank 1 Earth Shock found", ns.C.spells["Earth Shock"] and ns.C.spells["Earth Shock"].lowest == 8042)
  check("highest Lightning Bolt", ns.C.spells["Lightning Bolt"].id == 529)
  check("keybind found", ns.C.keys["Flame Shock"] == "S3", tostring(ns.C.keys["Flame Shock"]))

  local f = tick(ns)
  check("missing shown as icons: shield and weapon buff", missing(ns) == "No shield | No weapon buff", missing(ns))
  local slot1, slot2 = f.missing[1], f.missing[2]
  check("the icon is the spell that fixes it", slot1.spell == "Lightning Shield" and slot1.icon.texture == ns.C.spells["Lightning Shield"].icon, tostring(slot1.spell))
  check("with its key, when it is on your bar", slot1.key.text == (ns.C.keys["Lightning Shield"] or ""), tostring(slot1.key.text))
  check("weapon buff: the best one you know", slot2.spell == "Rockbiter Weapon", tostring(slot2.spell))
  check("one line explains the first", f.status.text == "Cast Lightning Shield before the pull.", f.status.text)
  check("no missing list in words", not f.status.text:find("No shield"), f.status.text)
  check("food is a journey to-do, not a pull blocker", journey(ns):find("No food buff") ~= nil and not f.status.text:find("food"), journey(ns))
  check("journey: xp and rested", journey(ns):find("XP 0%% · not rested") ~= nil and journey(ns):find("No rested XP") ~= nil, journey(ns))
  check("journey rows carry icons", ns.Journey.frame.rows[1].icon.texture == "Interface\\Icons\\INV_Misc_Food_15", tostring(ns.Journey.frame.rows[1].icon.texture))
  check("journey: next trainer level", journey(ns):find("New spells at level 16") ~= nil, journey(ns))
  M.P.xp, M.P.rested, M.P.talentPoints, M.P.durability, M.P.freeSlots = 430, 180, 1, 12, 1
  M.P.buffs["Well Fed XP Boost"] = true; M.fire("UNIT_AURA", "player")
  M.advance(3); f = tick(ns)
  check("journey: rested amount", journey(ns):find("XP 43%% · rested 18%% of a level") ~= nil, journey(ns))
  check("journey: talent point with the suggested talent", journey(ns):find("1 talent point to spend") ~= nil and journey(ns):find("Thundering Strikes") ~= nil, journey(ns))
  check("journey: repair and bags", journey(ns):find("Gear at 12%% durability") ~= nil and journey(ns):find("Bags nearly full %(1 free%)") ~= nil, journey(ns))
  check("journey: any Well Fed buff counts", not journey(ns):find("No food buff"), journey(ns))
  M.P.talentPoints, M.P.durability, M.P.freeSlots = 0, nil, 10
  M.P.items["Cozy Sleeping Bag"] = 1; M.P.items["Camp Tent"] = 1; M.P.rested = 20
  M.advance(3); f = tick(ns)
  check("journey: sleeping bag reminder when you own one", journey(ns):find("Sleeping bag buff missing") ~= nil, journey(ns))
  check("journey: tent reminder when rested is low", journey(ns):find("Rested XP low %(2%% of a level%)") ~= nil, journey(ns))
  M.P.items["Cozy Sleeping Bag"] = nil; M.P.items["Camp Tent"] = nil

  M.P.buffs = { ["Lightning Shield"] = true, ["Well Fed"] = true }
  M.P.mainHand = true
  M.fire("UNIT_AURA", "player")
  f = tick(ns)
  check("ready to pull", f.status.text:find("^Ready to pull%.") ~= nil and missing(ns) == "", f.status.text .. " / " .. missing(ns))

  target({ name = "Rockjaw Trogg", level = 11, hostile = true, guid = "Creature-1" })
  f = tick(ns)
  check("opener is Flame Shock", f.name.text == "Flame Shock", f.name.text)
  check("opener keybind", f.key.text == "S3", f.key.text)
  check("chain after the opener", f.chainText.text == "Searing Totem > Melee", f.chainText.text)
  check("chain label", f.chainLabel.text == "Then", f.chainLabel.text)
  check("mana bar exact out of combat", f.bar.value == 300 and f.barText.text == "Mana 100%", f.barText.text)

  -- Fight (the game already hides the enemy's name when combat starts)
  M.P.combat = true; M.fire("PLAYER_REGEN_DISABLED")
  cast(529)
  M.advance(1.5); f = tick(ns)
  check("in combat: Flame Shock next", f.name.text == "Flame Shock", f.name.text)
  check("journey panel hides in combat", journey(ns) == "(hidden)", journey(ns))
  check("mana bar is handed the real hidden value", f.bar.value == M.SECRET)
  check("mana text written by the game", f.barText.secretText == true and f.barText.text == "Mana %.0f%%", f.barText.text)
  cast(8050)
  M.advance(1.5); f = tick(ns)
  check("then Searing Totem (mana high)", f.name.text == "Searing Totem", f.name.text .. " / " .. f.barText.text)
  cast(3599)
  M.advance(1.5); f = tick(ns)
  check("then Earth Shock (no Stormstrike yet)", f.name.text == "Earth Shock", f.name.text .. " / " .. f.barText.text)
  cast(8044); M.P.cooldowns[8044] = M.now + 6; M.P.cooldowns[8042] = M.now + 6
  M.advance(1.5); f = tick(ns)
  check("shock on cooldown: melee", f.name.text == "Melee", f.name.text)
  M.advance(6); cast(8044); M.advance(4); cast(8044); M.advance(2)
  f = tick(ns)
  check("mana now medium or low", ns.C.lastState.manaPct < 55 and ns.C.lastState.manaLevel ~= "high", ns.C.lastState.manaPct)
  check("advice shown in combat", f.status.text ~= "" , f.status.text)
  M.P.mana = 20
  M.advance(2); f = tick(ns)
  check("low mana: probes pull the level down", ns.C.lastState.manaLevel == "low", ns.C.lastState.manaPct)
  M.percentReadable = true; M.P.mana = 240; M.advance(1); f = tick(ns)
  check("readable percent wins over the guess", ns.C.lastState.manaExact == true and ns.C.lastState.manaPct == 80, ns.C.lastState.manaPct)
  M.percentReadable = false; M.P.mana = 20; M.advance(1); f = tick(ns)
  check("low mana advice", f.status.text:find("melee only") ~= nil, f.status.text)
  check("low mana: melee", f.name.text == "Melee", f.name.text)

  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  local r = ns.C.lastReport
  check("fight report made", r ~= nil)
  check("report headline without the hidden name", r and r.headline:find("^Fight: ") ~= nil, r and r.headline)
  local tips = r and table.concat(r.tips, " | ") or ""
  check("Earth Shock tip", tips:find("Earth Shock") ~= nil, tips)
  check("report casts line", r and r.casts and r.casts:find("Earth Shock ×3") ~= nil, r and r.casts)

  M.fire("PLAYER_LEVEL_UP", 16)
  local flashed = ns.Panel.frame.msg.text
  check("level-up trainer tip", flashed:find("Cure Poison") ~= nil, flashed)
  check("level-up talent tip", flashed:find("Mental Dexterity") ~= nil, flashed)

  -- Should I fight this?
  local function facing(level, elite)
    target({ name = "Ogre", level = level, hostile = true, elite = elite, guid = "Creature-30-" .. level .. tostring(elite) })
    M.advance(1); return tick(ns)
  end
  M.P.mana = 300; M.P.buffs = { ["Lightning Shield"] = true, ["Well Fed"] = true }; M.P.mainHandBuff = true
  M.fire("UNIT_AURA", "player")
  M.P.level = 12; M.fire("PLAYER_LEVEL_UP", 12); M.advance(1)
  f = facing(13)
  check("fair fight: no warning", missing(ns) == "", missing(ns))
  f = facing(15)
  check("3 levels above: warned, with the gap on the icon", missing(ns) == "3 levels above you" and f.missing[1].timer.text == "+3", missing(ns))
  f = facing(17)
  check("5 levels above: walk away", missing(ns) == "5 levels above you" and f.missing[1].hint:find("Walk away") ~= nil, missing(ns))
  f = facing(-1)
  check("skull enemy", missing(ns) == "Far above your level" and f.missing[1].timer.text == "??", missing(ns))
  f = facing(12, true)
  check("elite when alone", missing(ns) == "Elite enemy", missing(ns))
  f = facing(6)
  check("grey enemy gives no XP", missing(ns) == "Grey to you: no XP", missing(ns))
  f = facing(7)
  check("green enemy is fine", missing(ns) == "", missing(ns))
  ClassCoachDB.threat = false; f = facing(17)
  check("enemy warning can be switched off", missing(ns) == "", missing(ns))
  ClassCoachDB.threat = true
  target(nil)

  -- The roadmap on the journey panel
  M.advance(3); tick(ns)
  check("journey: where to quest", journey(ns):find("Quest in: Loch Modan or Westfall") ~= nil, journey(ns))
  check("journey: next milestone", journey(ns):find("At level 14: Cozy Sleeping Bag quest chain") ~= nil, journey(ns))
  M.P.level = 20; M.fire("PLAYER_LEVEL_UP", 20); M.advance(3); tick(ns)
  check("journey: class milestone due now", journey(ns):find("Water totem quest and Ghost Wolf") ~= nil, journey(ns))
  check("journey: dungeon in range", journey(ns):find("Dungeon: Hall of Thanes") ~= nil, journey(ns))
  ClassCoachDB.roadmap = false; M.advance(3); tick(ns)
  check("roadmap can be switched off", not journey(ns):find("Quest in:"), journey(ns))
  ClassCoachDB.roadmap = true
  M.P.level = 12; M.fire("PLAYER_LEVEL_UP", 12); M.advance(3); tick(ns)

  -- Supplies: quiet on the road unless you are out, loud at a vendor
  M.P.bag = { { id = 159, count = 2, class = 0, sub = 5, use = "Drink" }, { id = 2318, count = 20, class = 7, sub = 6 } }
  M.P.durability = 54
  M.advance(3); tick(ns)
  check("out of food is always said", journey(ns):find("Out of food") ~= nil and not journey(ns):find("water"), journey(ns))
  M.P.vendorRepairs = true; M.fire("MERCHANT_SHOW"); tick(ns)
  check("at a vendor: low water and repairs", journey(ns):find("Buy water: 2 left") ~= nil and journey(ns):find("Repair here %(gear at 54%%%)") ~= nil, journey(ns))
  M.fire("MERCHANT_CLOSED"); tick(ns)
  check("away from the vendor it goes quiet again", not journey(ns):find("Buy water"), journey(ns))
  M.P.bag, M.P.durability = nil, nil

  -- /coach bar
  M.P.actions = { [1] = 529, [2] = 8044 }
  M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(1); tick(ns)
  SlashCmdList.CLASSCOACH("bar")
  check("bar: a taken button is left alone", M.P.actions[1] == 529 and M.P.actions[2] == 8044)
  check("bar: empty buttons are filled", M.P.actions[4] == 8050 and M.P.actions[5] == 3599 and M.P.actions[9] == 324,
    tostring(M.P.actions[4]) .. "/" .. tostring(M.P.actions[5]) .. "/" .. tostring(M.P.actions[9]))
  check("bar: nothing is put on twice", M.P.actions[3] == nil and M.P.actions[7] == nil, tostring(M.P.actions[3]))
  SlashCmdList.CLASSCOACH("bar replace")
  check("bar replace: the pull macro takes button 1", type(M.P.actions[1]) == "table" and M.P.actions[1].macro == "CC Pull", tostring(M.P.actions[1]))
  check("bar replace: every known entry placed", M.P.actions[3] == 8044 and M.P.actions[7] == 529 and M.P.actions[10] == 8017, tostring(M.P.actions[3]))
  M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(1); tick(ns)

  -- The settings screen
  local S = M.settings
  check("settings page registered with the game", S.category ~= nil and S.category.name == "ClassCoach")
  local count = 0
  for _ in pairs(S.list) do count = count + 1 end
  check("every option made it onto the page", count == 25 and #ns.Options.registered == 25, count)
  check("sections and action buttons", #S.headers == 5 and #S.buttons == 3, #S.headers .. "/" .. #S.buttons)
  check("options write to the saved settings", S.list.compact.tbl == ClassCoachDB and S.list.specChoice.tbl == ClassCoachCharDB)
  check("slider shows its unit", S.list.opacity.opts.format(75) == "75%" and S.list.scale.opts.format(1.1) == "1.10x")
  local specs = S.list.specChoice.getOptions()
  check("profile choices for this class", #specs == 2 and specs[1].value == "auto" and specs[2].value == "Enhancement", #specs)
  SlashCmdList.CLASSCOACH("")
  check("/coach opens the settings", S.opened == 77, tostring(S.opened))
  ClassCoach_OnAddonCompartmentClick()
  -- Changing an option shows on the next refresh, with no reload.
  target({ name = "Trogg", level = 11, hostile = true, guid = "Creature-20" })
  M.P.mana = 300; M.advance(1); f = tick(ns)
  check("explanation shown by default", f.why.text ~= "" and f.why.shown, f.why.text)
  ClassCoachDB.compact = true; f = tick(ns)
  check("compact hides the explanation", f.why.text == "" and f.chainText.text == "")
  ClassCoachDB.compact = false
  ClassCoachDB.showMana = false; f = tick(ns)
  check("mana bar can be switched off", f.bar.shown == false)
  ClassCoachDB.showMana = true
  ClassCoachDB.showCoach = false; f = tick(ns)
  check("coach panel can be hidden", f.shown == false)
  check("hidden coach panel does not stop the journey panel", journey(ns) ~= "(hidden)", journey(ns))
  ClassCoachDB.showCoach = true; f = tick(ns)
  check("and shown again", f.shown == true)
  ClassCoachDB.journey = false; tick(ns)
  check("journey panel can be switched off", journey(ns) == "(hidden)")
  ClassCoachDB.journey = true
  ClassCoachDB.food = false; M.P.buffs = {}; M.fire("UNIT_AURA", "player"); M.advance(2); tick(ns)
  check("food reminder can be switched off", not journey(ns):find("No food buff"), journey(ns))
  ClassCoachDB.food = true
  ClassCoachCharDB.specChoice = "Enhancement"; tick(ns)
  check("profile picked on the settings screen", ns.C.profileWhy == "chosen", tostring(ns.C.profileWhy))
  ClassCoachCharDB.specChoice = "auto"; tick(ns)
  target(nil)

  SlashCmdList.CLASSCOACH("check")
  SlashCmdList.CLASSCOACH("spec")
  SlashCmdList.CLASSCOACH("last")
  check("no errors logged", errors() == 0, ClassCoachDB.log and table.concat(ClassCoachDB.log, " || "))
  check("no tick error", ns.C.lastError == nil, ns.C.lastError)

---------------------------------------------------------------------------
elseif SCENARIO == "priest" then
  M.player({
    class = "PRIEST", className = "Priest", level = 14, mana = 400, maxMana = 400,
    spells = {
      [585] = { name = "Smite", cost = 20 }, [591] = { name = "Smite", cost = 30 },
      [589] = { name = "Shadow Word: Pain", cost = 25 }, [17] = { name = "Power Word: Shield", cost = 45 },
      [8092] = { name = "Mind Blast", cost = 50 }, [1243] = { name = "Power Word: Fortitude", cost = 60 },
      [588] = { name = "Inner Fire", cost = 20 }, [5019] = { name = "Shoot", cost = 0 },
      [2050] = { name = "Lesser Heal", cost = 30 },
    },
    book = { 585, 591, 589, 17, 8092, 1243, 588, 5019, 2050 },
    equipped = { [18] = 5240 },
    talents = { 2, 0, 0 },
  })
  local ns = load()
  check("priest profile chosen", ns.C.profile.spec == "Discipline", ns.C.profile.spec)
  local f = tick(ns)
  check("checklist: Fortitude", missing(ns):find("No Fortitude") ~= nil and f.missing[1].spell == "Power Word: Fortitude", missing(ns))
  M.P.buffs = { ["Power Word: Fortitude"] = true, ["Inner Fire"] = true, ["Well Fed"] = true }
  M.fire("UNIT_AURA", "player")
  target({ name = "Kobold", level = 13, hostile = true, guid = "Creature-2" })
  f = tick(ns)
  check("shield before the pull", f.name.text == "Power Word: Shield", f.name.text)
  check("priest chain", f.chainText.text == "Shadow Word: Pain > Mind Blast", f.chainText.text)
  cast(17); M.advance(1.5); f = tick(ns)
  check("opener Mind Blast", f.name.text == "Mind Blast", f.name.text)
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  f = tick(ns)
  check("then Shadow Word: Pain", f.name.text == "Shadow Word: Pain", f.name.text)
  cast(589); M.advance(1.5); f = tick(ns)
  check("then Mind Blast", f.name.text == "Mind Blast", f.name.text)
  cast(8092); M.P.cooldowns[8092] = M.now + 8; M.advance(1.5); f = tick(ns)
  check("then Smite (mana high)", f.name.text == "Smite", f.name.text .. " / " .. f.barText.text)
  cast(591); cast(591); M.advance(1.5); f = tick(ns)
  check("then wand", f.name.text == "Shoot", f.name.text)
  M.P.mana = 60; M.advance(3); f = tick(ns)
  check("low mana advice: wand", f.status.text:find("wand") ~= nil, f.status.text)
  M.advance(10)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  local tips = table.concat(ns.C.lastReport.tips, " | ")
  check("wand tip", tips:find("wand") ~= nil, tips)
  check("no errors logged", errors() == 0, ClassCoachDB.log and table.concat(ClassCoachDB.log, " || "))
  check("no tick error", ns.C.lastError == nil, ns.C.lastError)

---------------------------------------------------------------------------
elseif SCENARIO == "warlock" then
  M.player({
    class = "WARLOCK", className = "Warlock", level = 12, mana = 300, maxMana = 300,
    spells = {
      [686] = { name = "Shadow Bolt", cost = 25 }, [695] = { name = "Shadow Bolt", cost = 40 },
      [348] = { name = "Immolate", cost = 25 }, [172] = { name = "Corruption", cost = 35, text = "Corrupts the target, causing 40 Shadow damage over 12 sec." },
      [980] = { name = "Bane of Agony", cost = 25 }, [1454] = { name = "Life Tap", cost = 0 },
      [1120] = { name = "Drain Soul", cost = 55 }, [5782] = { name = "Fear", cost = 40 },
      [687] = { name = "Demon Skin", cost = 50 }, [688] = { name = "Summon Imp", cost = 60 },
      [697] = { name = "Summon Voidwalker", cost = 100 }, [5019] = { name = "Shoot", cost = 0 },
    },
    book = { 686, 695, 348, 172, 980, 1454, 1120, 5782, 687, 688, 697, 5019 },
    equipped = { [18] = 11287 },
    talents = { 3, 0, 0 },
  })
  local ns = load()
  check("warlock profile chosen", ns.C.profile.spec == "Affliction", ns.C.profile.spec)
  local f = tick(ns)
  check("checklist: no demon, fixed by the Voidwalker", missing(ns):find("No demon") ~= nil and f.missing[1].spell == "Summon Voidwalker", missing(ns) .. " / " .. tostring(f.missing[1].spell))
  M.P.pet = { family = "Voidwalker" }
  M.P.buffs = { ["Demon Skin"] = true, ["Well Fed"] = true }
  M.P.items[6265] = 2
  M.fire("UNIT_AURA", "player")
  f = tick(ns)
  check("checklist clear with pet", not missing(ns):find("demon"), missing(ns))
  M.P.health = 80; f = tick(ns)
  check("low health check, with the number on the icon", missing(ns):find("Health 40%%") ~= nil and f.missing[1].timer.text == "40", missing(ns))
  M.P.health = 200
  target({ name = "Gnoll", level = 11, hostile = true, guid = "Creature-5" })
  f = tick(ns)
  check("opener Bane of Agony", f.name.text == "Bane of Agony", f.name.text)
  check("opener is told for the Voidwalker", f.why.text:find("Voidwalker in, let it hit first") ~= nil, f.why.text)
  check("warlock chain", f.chainText.text == "Corruption > Immolate", f.chainText.text)
  check("durations read from the spell text", ns.C.spells["Corruption"].duration == 12 and ns.C.spells["Bane of Agony"].duration == 24,
    tostring(ns.C.spells["Corruption"].duration))

  -- The pull lands a moment before combat starts: it still counts.
  cast(980); M.advance(0.4)
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  f = tick(ns)
  check("pull spell counted in the fight", ns.C.tracker:castsOnTarget("g:Creature-5", "Bane of Agony") == 1)
  check("mana start includes the pull spell", ns.C.tracker.fight.manaStart == 300, ns.C.tracker.fight.manaStart)
  check("then Corruption", f.name.text == "Corruption", f.name.text)
  check("done slot shows Bane ticking", f.done[2].shown and f.done[2].timer.text == "24", f.done[2].timer.text)
  check("dot line", f.dots.text:find("On this enemy: Bane of Agony 24s") ~= nil, f.dots.text)
  cast(172); M.advance(2); f = tick(ns)
  check("then Immolate (mana high)", f.name.text == "Immolate", f.name.text)
  cast(348); M.advance(2); f = tick(ns)
  check("then wand", f.name.text == "Shoot", f.name.text)
  check("chain says when Corruption comes back", f.chainText.text == "Corruption in 8s", f.chainText.text)
  check("two done slots", f.done[1].timer.text == "8" and f.done[2].timer.text == "13", f.done[1].timer.text .. "/" .. f.done[2].timer.text)
  M.advance(8.5); f = tick(ns)
  check("Corruption ran out: cast it again", f.name.text == "Corruption", f.name.text)
  cast(172); M.advance(1.5)

  -- A second enemy joins: its own timers, and the first one keeps ticking.
  target({ name = "Gnoll", level = 11, hostile = true, guid = "Creature-6" })
  f = tick(ns)
  check("new enemy needs its own Bane", f.name.text == "Bane of Agony", f.name.text)
  check("other enemy still ticking", f.dots.text == "1 other enemy still ticking", f.dots.text)
  check("no done slots on a fresh enemy", not f.done[1].shown and not f.done[2].shown)
  target({ name = "Gnoll", level = 11, hostile = true, guid = "Creature-5" })
  f = tick(ns)
  check("back on the first: its timers are remembered", f.name.text == "Shoot" and f.dots.text:find("Corruption") ~= nil, f.name.text .. " / " .. f.dots.text)

  M.P.mana = 50; M.advance(3); f = tick(ns)
  check("low mana: Life Tap", f.name.text == "Life Tap", f.name.text)
  check("low mana advice", f.status.text:find("Life Tap") ~= nil, f.status.text)
  M.advance(10)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  local tips = table.concat(ns.C.lastReport.tips, " | ")
  check("tip: cast before the Voidwalker", tips:find("before your Voidwalker") ~= nil, tips)
  check("dots forgotten after the fight", #ns.C.tracker:dotsOn("g:Creature-5", M.now) == 0)
  check("kill time learned", ClassCoachCharDB.kill and ClassCoachCharDB.kill.n == 1 and ClassCoachCharDB.kill.avg > 10, ClassCoachCharDB.kill and ClassCoachCharDB.kill.avg)

  -- Enemy nearly dead (by your usual kill time): no new damage over time.
  ClassCoachCharDB.kill = { avg = 8, n = 5 }
  M.P.mana = 300; target({ name = "Wolf", level = 11, hostile = true, guid = "Creature-7" })
  M.advance(1); f = tick(ns)
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  f = tick(ns)
  check("short fights: Bane of Agony is skipped", f.name.text == "Corruption", f.name.text)
  cast(172); M.advance(6); f = tick(ns)
  check("late in the fight: no Immolate, just wand", f.name.text == "Shoot", f.name.text)
  check("and it says why", f.status.text:find("nearly dead") ~= nil, f.status.text)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  ClassCoachCharDB.kill = nil

  -- Enemy ids hidden: every target change is a new enemy, timers never leak across.
  M.secretGuid = true
  target({ name = "Boar", level = 11, hostile = true, guid = "Creature-8" })
  M.advance(1); f = tick(ns)
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  cast(980); cast(172); M.advance(1.5); f = tick(ns)
  check("hidden ids: timers on the current enemy work", f.dots.text:find("Bane of Agony") ~= nil, f.dots.text)
  target({ name = "Boar", level = 11, hostile = true, guid = "Creature-9" })
  f = tick(ns)
  check("hidden ids: the next enemy starts clean", f.name.text == "Bane of Agony", f.name.text)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  M.secretGuid = false
  target(nil)

  -- The Imp: no waiting, and a nudge towards the Voidwalker when solo.
  M.P.pet = { family = "Imp" }; M.advance(1); f = tick(ns)
  check("Imp out: nudge to the Voidwalker", missing(ns):find("Imp is out") ~= nil, missing(ns))
  target({ name = "Boar", level = 11, hostile = true, guid = "Creature-10" })
  f = tick(ns)
  check("Imp pull text", f.why.text:find("Imp out: cast Bane of Agony right away") ~= nil, f.why.text)
  target(nil)
  -- Family hidden: the last summon you cast is remembered.
  M.P.pet = {}; cast(697); M.advance(1); f = tick(ns)
  check("demon known from the summon cast", ns.C.lastState.demon == "Voidwalker", tostring(ns.C.lastState.demon))

  -- A fight without the demon
  M.P.pet = nil; M.P.mana = 300; M.advance(1); f = tick(ns)
  target({ name = "Boar", level = 11, hostile = true, guid = "Creature-11" })
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  cast(980); M.advance(10)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  tips = table.concat(ns.C.lastReport.tips, " | ")
  check("no-demon tip", tips:find("demon") ~= nil, tips)
  target(nil)

  -- Macros
  M.P.pet = { family = "Voidwalker" }; M.advance(1); tick(ns)
  SlashCmdList.CLASSCOACH("macros")
  local pull = M.macros[GetMacroIndexByName("CC Pull")]
  check("pull macro made", pull ~= nil and pull.perChar == true)
  check("pull macro: demon in, Voidwalker goes first, spells in order", pull and pull.body ==
    "#showtooltip\n/petattack [harm,nodead]\n/stopmacro [pet:Voidwalker,nocombat]\n/castsequence reset=target/combat Bane of Agony, Corruption, Immolate",
    pull and pull.body)
  check("wand and demon macros", GetMacroIndexByName("CC Wand") > 0 and GetMacroIndexByName("CC Demon") > 0)
  check("macros fit the game's limit", #pull.body <= 255)
  -- The macro follows the coach: short kills drop the long spell, and it rewrites itself after a fight.
  ClassCoachCharDB.kill = { avg = 7, n = 5 }
  target({ name = "Boar", level = 11, hostile = true, guid = "Creature-12" })
  M.advance(1); tick(ns)
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  cast(172); M.advance(6)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  pull = M.macros[GetMacroIndexByName("CC Pull")]
  check("macro rewritten from the new plan", pull.body:find("reset=target/combat Bane of Agony, Corruption$") ~= nil, pull.body)
  ClassCoachCharDB.kill = nil; target(nil)
  -- No wand: the filler spell rides along so one key carries the fight.
  M.P.equipped = {}; M.fire("PLAYER_EQUIPMENT_CHANGED"); M.advance(1); tick(ns); M.advance(1)
  SlashCmdList.CLASSCOACH("macros")
  pull = M.macros[GetMacroIndexByName("CC Pull")]
  check("no wand: filler added to the sequence", pull.body:find("Bane of Agony, Corruption, Immolate, Shadow Bolt, Shadow Bolt, Shadow Bolt$") ~= nil, pull.body)

  -- A resisted spell: the game only says "something was resisted on your target".
  M.P.equipped = { [18] = 11287 }; M.fire("PLAYER_EQUIPMENT_CHANGED"); M.advance(1); tick(ns)
  M.P.mana = 300
  target({ name = "Murloc", level = 12, hostile = true, guid = "Creature-40" })
  M.advance(1); tick(ns)
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  cast(980); M.fire("UNIT_COMBAT", "target", "RESIST", "", 0, 32)
  M.advance(0.1); f = tick(ns)
  check("resisted: the coach asks for the same spell again", f.name.text == "Bane of Agony", f.name.text)
  check("and says why", f.why.text == "Bane of Agony was resisted. Cast it again.", f.why.text)
  check("the done icon shows the miss", f.done[2].timer.text == "miss", tostring(f.done[2].timer.text))
  check("a resisted cast does not count as on the enemy", ns.C.tracker:castsOnTarget("g:Creature-40", "Bane of Agony") == 0
    and not f.dots.text:find("Bane of Agony"), f.dots.text)
  cast(980); M.advance(1.5); f = tick(ns)
  check("it landed the second time", f.name.text == "Corruption" and f.dots.text:find("Bane of Agony") ~= nil, f.name.text)
  cast(172); M.advance(1.2)
  M.fire("UNIT_COMBAT", "target", "RESIST", "", 0, 32); f = tick(ns)
  check("a resist long after your cast is someone else's", f.name.text ~= "Corruption" and f.dots.text:find("Corruption") ~= nil, f.name.text)
  -- a resisted refresh keeps the old one running
  M.advance(1); local left = ns.C.tracker:debuffLeft("g:Creature-40", "Corruption", M.now)
  cast(172); M.fire("UNIT_COMBAT", "target", "RESIST", "", 0, 32)
  check("a resisted recast leaves the running one alone", math.abs(ns.C.tracker:debuffLeft("g:Creature-40", "Corruption", M.now) - left) < 0.01)
  -- immune
  cast(348); M.fire("UNIT_COMBAT", "target", "IMMUNE", "", 0, 4)
  M.advance(0.2); f = tick(ns)
  check("immune: not suggested again on this enemy", f.name.text ~= "Immolate" and not f.chainText.text:find("Immolate"), f.name.text .. " / " .. f.chainText.text)
  check("immune: explained", f.status.text:find("immune to Immolate") ~= nil, f.status.text)
  check("immune: marked on the done icon", f.done[2].timer.text == "imm", tostring(f.done[2].timer.text))
  M.advance(12)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  check("the report counts resists", ns.C.lastReport.headline:find("3 resisted") ~= nil, ns.C.lastReport.headline)
  check("and puts them in perspective", table.concat(ns.C.lastReport.tips, " | "):find("3 of your 5 casts were resisted") ~= nil, table.concat(ns.C.lastReport.tips, " | "))
  target(nil); M.advance(1); tick(ns)

  -- The smart key: one key walks the plan, inside the game's secure code.
  SlashCmdList.CLASSCOACH("smart")
  local b = ns.Smart.button
  check("smart key: secure button made and loaded", b ~= nil and b:GetAttribute("cc-count") == 4, b and b:GetAttribute("cc-count"))
  check("smart key: resets when no living enemy is targeted", M.drivers.ccreset.conditions == "[@target,harm,nodead] keep; reset")
  local steps = table.concat(ns.Smart.describe(), ", ")
  check("smart key: steps are the coach's plan", steps == "1 Bane of Agony, 2 Corruption, 3 Immolate, 4 Shoot (stays here)", steps)
  target({ name = "Crab", level = 12, hostile = true, guid = "Creature-41" })
  M.advance(1); tick(ns)
  local kind, what = M.press(b)
  check("Voidwalker out, no fight yet: the first press only sends it in", kind == "macro" and what == "CC Send" and b:GetAttribute("cc-step") == 1, tostring(what))
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  kind, what = M.press(b)
  check("then the opening spell, with the demon", kind == "macro" and what == "CC Open", tostring(what))
  check("the opening macro", M.macros[GetMacroIndexByName("CC Open")].body == "#showtooltip\n/petattack [harm,nodead]\n/cast Bane of Agony")
  kind, what = M.press(b)
  check("next press: Corruption", kind == "spell" and what == "Corruption", tostring(what))
  kind, what = M.press(b, "RightButton")
  check("Again key: Corruption once more", kind == "spell" and what == "Corruption" and b:GetAttribute("cc-step") == 3, tostring(what))
  kind, what = M.press(b)
  check("next press: Immolate", what == "Immolate", tostring(what))
  kind, what = M.press(b)
  check("then the wand", kind == "macro" and what == "CC Wand", tostring(what))
  kind, what = M.press(b)
  check("and it stays on the wand: no looping back", what == "CC Wand" and b:GetAttribute("cc-step") == 4, tostring(what))
  M.channeling = true; kind = M.press(b); M.channeling = false
  check("never cuts off a channel", kind == nil)
  kind, what = M.press(b, "MiddleButton")
  check("Restart key: back to the opening", what == "CC Open", tostring(what))
  M.press(b); M.secureReset(b)
  check("enemy dead: back to step one by itself", b:GetAttribute("cc-step") == 1)
  local ok = pcall(b.SetAttribute, b, "cc-step", 3)
  check("the addon cannot touch the key during a fight", ok == false and ns.C.syncSmart() == false)

  -- The panel shows which key to press: Next, or Again after a resist.
  M.P.bindings["CLICK ClassCoachSmartButton:LeftButton"] = "1"
  M.P.bindings["CLICK ClassCoachSmartButton:RightButton"] = "2"
  M.advance(0.5); f = tick(ns)
  check("panel: Bane of Agony is on the smart key", f.name.text == "Bane of Agony" and f.key.text == "1", f.name.text .. "/" .. tostring(f.key.text))
  M.press(b); cast(980); M.fire("UNIT_COMBAT", "target", "RESIST", "", 0, 32)
  M.advance(0.1); f = tick(ns)
  check("panel: after a resist it points at the Again key", f.name.text == "Bane of Agony" and f.key.text == "2", f.name.text .. "/" .. tostring(f.key.text))
  M.press(b, "RightButton"); cast(980); M.advance(1.5); f = tick(ns)
  check("panel: then on with the Next key", f.name.text == "Corruption" and f.key.text == "1", f.name.text .. "/" .. tostring(f.key.text))
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  target(nil)
  SlashCmdList.CLASSCOACH("check")
  check("no errors logged", errors() == 0, ClassCoachDB.log and table.concat(ClassCoachDB.log, " || "))
  check("no tick error", ns.C.lastError == nil, ns.C.lastError)

---------------------------------------------------------------------------
-- Every level 1-60: only suggest what the character has at that level.
elseif SCENARIO == "sweep" then
  local CLASSES = {
    WARLOCK = { name = "Warlock", wand = true, pet = true, learn = {
      ["Shadow Bolt"] = 1, ["Demon Skin"] = 1, ["Immolate"] = 1, ["Summon Imp"] = 1, ["Shoot"] = 1, ["Corruption"] = 4,
      ["Life Tap"] = 6, ["Bane of Agony"] = 8, ["Fear"] = 8, ["Drain Soul"] = 10, ["Summon Voidwalker"] = 10,
      ["Drain Life"] = 14, ["Demon Armor"] = 20, ["Curse of the Elements"] = 20, ["Summon Succubus"] = 20,
      ["Summon Felhunter"] = 30, ["Siphon Life"] = 37, ["Wrack"] = 47 } },
    SHAMAN = { name = "Shaman", learn = {
      ["Lightning Bolt"] = 1, ["Rockbiter Weapon"] = 1, ["Healing Wave"] = 1, ["Earth Shock"] = 4, ["Stoneskin Totem"] = 4,
      ["Lightning Shield"] = 8, ["Flame Shock"] = 10, ["Searing Totem"] = 10, ["Flametongue Weapon"] = 10,
      ["Strength of Earth Totem"] = 10, ["Frost Shock"] = 20, ["Lesser Healing Wave"] = 20, ["Healing Stream Totem"] = 20,
      ["Stormstrike"] = 25, ["Mana Spring Totem"] = 26, ["Windfury Weapon"] = 30, ["Reincarnation"] = 30,
      ["Windfury Totem"] = 32, ["Chain Heal"] = 40, ["Rage of the Farseer"] = 40 } },
    PRIEST = { name = "Priest", wand = true, learn = {
      ["Smite"] = 1, ["Lesser Heal"] = 1, ["Power Word: Fortitude"] = 1, ["Shoot"] = 1, ["Shadow Word: Pain"] = 4,
      ["Power Word: Shield"] = 6, ["Renew"] = 8, ["Mind Blast"] = 10, ["Inner Fire"] = 12, ["Flash Heal"] = 20,
      ["Holy Fire"] = 20, ["Penance"] = 30 } },
  }
  local WANT = SWEEP_CLASS
  local def = CLASSES[WANT]
  M.player({ class = WANT, className = def.name, level = 1, spells = {}, book = {} })
  local ns = load()
  local profile = ns.C.profile
  check(WANT .. " has a profile", profile.class == WANT, profile.class)
  for key in pairs(def.learn) do check(WANT .. " test knows " .. key, profile.spells[key] ~= nil) end
  for key in pairs(profile.spells) do
    if key ~= "Water Shield" and key ~= "Summon Incubus" then check(WANT .. " learn level for " .. key, def.learn[key] ~= nil) end
  end
  local idOf, fake = {}, 90000
  for key, meta in pairs(profile.spells) do
    fake = fake + 1
    idOf[key] = meta.ids and meta.ids[1] or fake
  end

  local samples = {}
  local function setup(level, opts)
    local spells, book = {}, {}
    for key, at in pairs(def.learn) do
      if level >= at and not (opts.noImp and key == "Summon Imp") and key ~= opts.skip then
        spells[idOf[key]] = { name = key, cost = (key == "Shoot" or key == "Life Tap") and 0 or 20 }
        book[#book + 1] = idOf[key]
      end
    end
    M.player({ class = WANT, className = def.name, level = level, mana = opts.mana, maxMana = 300, spells = spells, book = book,
      equipped = opts.wand and { [18] = 5240 } or {}, pet = opts.pet and {} or nil })
    M.P.buffs = { ["Well Fed"] = true }
    M.fire("PLAYER_LEVEL_UP", level); M.fire("SPELLS_CHANGED"); M.fire("PLAYER_EQUIPMENT_CHANGED"); M.advance(1)
    ns.Panel.msgUntil = nil
    return spells
  end
  local function look(level, opts, spells, where)
    local f = tick(ns)
    local tag = ("%s L%d %s wand=%s pet=%s mana=%d"):format(WANT, level, where, tostring(opts.wand), tostring(opts.pet), opts.mana)
    local shown = { f.name.text, f.why.text, f.status.text, f.chainText.text, f.dots.text, journeyNow(ns), missing(ns) }
    for _, s in ipairs(f.missing) do if s.shown and rawget(s, "spell") then shown[#shown + 1] = rawget(s, "spell") end end
    for key in pairs(profile.spells) do
      if not spells[idOf[key]] then
        for _, t in ipairs(shown) do
          if type(t) ~= "string" then error(tag .. ": a shown value is a " .. type(t)) end
          if t:find(key, 1, true) then check(tag .. ": mentions " .. key .. " before it is learned", false, t) end
        end
      end
    end
    if not opts.pet and def.pet then
      check(tag .. ": no demon talk without one", not (f.why.text:find("demon") or f.chainText.text:find("demon")), f.why.text)
    end
    if not opts.wand then
      check(tag .. ": no Shoot without a wand", f.name.text ~= "Shoot" and not f.chainText.text:find("Shoot"), f.name.text)
    end
    check(tag .. ": no error", ns.C.lastError == nil, ns.C.lastError)
    return f
  end

  for level = 1, 60 do
    for _, wand in ipairs(def.wand and { false, true } or { false }) do
      for _, pet in ipairs(def.pet and { false, true } or { false }) do
        for _, mana in ipairs({ 300, 120, 30 }) do
          local opts = { wand = wand and level >= 5, pet = pet, mana = mana, noImp = def.pet and not pet and level < 10 }
          local spells = setup(level, opts)
          local f = look(level, opts, spells, "idle")
          check(("%s L%d: a pull plan is shown"):format(WANT, level), f.chainLabel.text == "Pull" and f.name.text ~= "" and f.name.text ~= "Ready", f.name.text)
          if opts.noImp then
            check(("%s L%d: points at the Imp quest, not at a missing demon"):format(WANT, level),
              journey(ns):find("No Imp yet") ~= nil and not missing(ns):find("No demon"), journey(ns) .. " / " .. missing(ns))
          end
          target({ name = "Boar", level = level, hostile = true, guid = ("Creature-%d-%s-%s-%d"):format(level, tostring(wand), tostring(pet), mana) })
          f = look(level, opts, spells, "pull")
          if mana == 300 then
            check(("%s L%d: pulls with a spell, not melee"):format(WANT, level), f.name.text ~= "Melee", f.name.text)
          end
          local line = { f.name.text }
          M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
          local reachedFiller = false
          for _ = 1, 5 do
            local id
            for key in pairs(profile.spells) do if key == f.name.text then id = idOf[key] end end
            if id then cast(id) end
            M.advance(1.5)
            f = look(level, opts, spells, "fight")
            line[#line + 1] = f.name.text
            if f.name.text == "Melee" or f.name.text == "Shoot" then reachedFiller = true break end
            if not id then break end
          end
          M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
          target(nil)
          if mana == 300 then samples[#samples + 1] = ("L%-2d wand=%-5s pet=%-5s  %s"):format(level, tostring(opts.wand), tostring(pet), table.concat(line, " > ")) end
        end
      end
    end
  end
  if WANT == "WARLOCK" then
    setup(4, { mana = 300, pet = true, skip = "Corruption" })
    local f = tick(ns)
    check("trainer reminder for an unlearned spell", journey(ns):find("Not trained: Corruption") ~= nil, journey(ns))
    check("and it is not suggested", not f.chainText.text:find("Corruption"), f.chainText.text)
    setup(12, { mana = 60, pet = true })
    f = tick(ns)
    check("low mana out of combat: Life Tap icon and hint", missing(ns):find("Mana 20%%") ~= nil and f.missing[2].spell == "Life Tap" and f.missing[2].timer.text == "20" and f.missing[2].hint:find("Life Tap") ~= nil, missing(ns) .. " / " .. tostring(f.missing[2].spell))
  end
  check("no errors logged", errors() == 0, ClassCoachDB.log and table.concat(ClassCoachDB.log, " || "))
  if SWEEP_PRINT then
    local last = {}
    for _, l in ipairs(samples) do
      local variant, body = l:sub(5, 26), l:sub(27)
      if last[variant] ~= body then print_real(WANT .. " " .. l) end
      last[variant] = body
    end
  end

---------------------------------------------------------------------------
elseif SCENARIO == "template" then
  M.player({ class = "MAGE", className = "Mage", level = 12, mana = 400, maxMana = 400,
    spells = { [116] = { name = "Frostbolt", cost = 25 }, [205] = { name = "Frostbolt", cost = 35 },
      [2136] = { name = "Fire Blast", cost = 40 }, [168] = { name = "Frost Armor", cost = 60 }, [5019] = { name = "Shoot", cost = 0 } },
    book = { 116, 205, 2136, 168, 5019 }, equipped = { [18] = 1 }, talents = { 0, 0, 4 } })
  local ns = load("docs/ProfileTemplate.lua")
  check("template profile loads and is picked", ns.C.profile.spec == "Frost", ns.C.profile.spec)
  target({ name = "Murloc", level = 11, hostile = true, guid = "Creature-4" })
  M.P.combat = true; M.fire("PLAYER_REGEN_DISABLED")
  local f = tick(ns)
  check("template priority works", f.name.text == "Fire Blast", f.name.text)
  check("no errors logged", errors() == 0, ClassCoachDB.log and table.concat(ClassCoachDB.log, " || "))

---------------------------------------------------------------------------
elseif SCENARIO == "warrior" then
  M.player({ class = "WARRIOR", className = "Warrior", level = 8, powerType = 1, mana = 0, maxMana = 0,
    spells = { [78] = { name = "Heroic Strike", cost = 0 } }, book = { 78 } })
  Settings = nil   -- a client without the Settings system: the addon must still run
  local ns = load()
  check("runs without a settings screen", ns.C.optionsReady == false and ClassCoachDB.showCoach == true)
  SlashCmdList.CLASSCOACH("")
  check("generic profile", ns.C.profile.class == "ANY", ns.C.profile.class)
  local f = tick(ns)
  check("no mana bar for rage users", ns.C.usesMana == false)
  target({ name = "Wolf", level = 7, hostile = true, guid = "Creature-3" })
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  M.advance(5); f = tick(ns); cast(78); M.advance(5)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  check("report for any class", ns.C.lastReport ~= nil)
  check("no errors logged", errors() == 0, ClassCoachDB.log and table.concat(ClassCoachDB.log, " || "))
  check("no tick error", ns.C.lastError == nil, ns.C.lastError)
end

print_real(("%s: %d passed, %d failed"):format(SCENARIO, passed, failed))
return failed
