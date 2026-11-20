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
  local f = ns.Panel.frame
  f.scripts.OnUpdate(f, 1)
  return f
end
local function cast(id, cost)
  M.P.mana = M.P.mana - (cost or M.P.spells[id].cost or 0)
  M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", id)
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
  check("checklist: shield missing", f.status.text:find("No shield") ~= nil, f.status.text)
  check("checklist: weapon buff missing", f.status.text:find("No weapon buff") ~= nil, f.status.text)
  check("checklist: food", f.status.text:find("No food") ~= nil, f.status.text)

  M.P.buffs = { ["Lightning Shield"] = true, ["Well Fed"] = true }
  M.P.mainHand = true
  M.fire("UNIT_AURA", "player")
  f = tick(ns)
  check("ready to pull", f.status.text == "Ready to pull.", f.status.text)

  M.P.target = { name = "Rockjaw Trogg", level = 11, hostile = true, guid = "Creature-1" }
  f = tick(ns)
  check("opener is Lightning Bolt", f.name.text == "Lightning Bolt", f.name.text)
  check("opener keybind", f.key.text == "1", f.key.text)

  -- Fight (the game already hides the enemy's name when combat starts)
  M.P.combat = true; M.fire("PLAYER_REGEN_DISABLED")
  cast(529)
  M.advance(1.5); f = tick(ns)
  check("in combat: Flame Shock next", f.name.text == "Flame Shock", f.name.text)
  check("mana shown as estimate", f.barText.text:find("estimate") ~= nil, f.barText.text)
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
  check("mana now medium or low", f.bar.value and f.bar.value < 55, f.bar.value)
  check("advice shown in combat", f.status.text ~= "" , f.status.text)
  M.P.mana = 20
  M.advance(2); f = tick(ns)
  check("low mana: probes pull the estimate down", f.bar.value and f.bar.value < 25, f.bar.value)
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
  check("checklist: Fortitude", f.status.text:find("Fortitude") ~= nil, f.status.text)
  M.P.buffs = { ["Power Word: Fortitude"] = true, ["Inner Fire"] = true, ["Well Fed"] = true }
  M.fire("UNIT_AURA", "player")
  M.P.target = { name = "Kobold", level = 13, hostile = true, guid = "Creature-2" }
  f = tick(ns)
  check("opener Mind Blast", f.name.text == "Mind Blast", f.name.text)
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  f = tick(ns)
  check("shield first", f.name.text == "Power Word: Shield", f.name.text)
  cast(17); M.advance(1.5); f = tick(ns)
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
      [348] = { name = "Immolate", cost = 25 }, [172] = { name = "Corruption", cost = 35 },
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
  check("checklist: no demon", f.status.text:find("demon") ~= nil, f.status.text)
  M.P.pet = {}
  M.P.buffs = { ["Demon Skin"] = true, ["Well Fed"] = true }
  M.P.items[6265] = 2
  M.fire("UNIT_AURA", "player")
  f = tick(ns)
  check("checklist clear with pet", not f.status.text:find("demon"), f.status.text)
  M.P.health = 80; f = tick(ns)
  check("low health check", f.status.text:find("Health") ~= nil, f.status.text)
  M.P.health = 200
  M.P.target = { name = "Gnoll", level = 11, hostile = true, guid = "Creature-5" }
  f = tick(ns)
  check("opener Bane of Agony", f.name.text == "Bane of Agony", f.name.text)
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  f = tick(ns)
  check("bane first", f.name.text == "Bane of Agony", f.name.text)
  cast(980); M.advance(1.5); f = tick(ns)
  check("then Corruption", f.name.text == "Corruption", f.name.text)
  cast(172); M.advance(2); f = tick(ns)
  check("then Immolate (mana high)", f.name.text == "Immolate", f.name.text)
  cast(348); M.advance(2); f = tick(ns)
  check("then wand", f.name.text == "Shoot", f.name.text)
  M.P.mana = 50; M.advance(3); f = tick(ns)
  check("low mana: Life Tap", f.name.text == "Life Tap", f.name.text)
  check("low mana advice", f.status.text:find("Life Tap") ~= nil, f.status.text)
  M.advance(10)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  local tips = table.concat(ns.C.lastReport.tips, " | ")
  check("life tap tip", tips:find("Life Tap") ~= nil, tips)
  -- a fight without the demon
  M.P.pet = nil; M.P.mana = 300; f = tick(ns)
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  cast(980); M.advance(10)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  tips = table.concat(ns.C.lastReport.tips, " | ")
  check("no-demon tip", tips:find("demon") ~= nil, tips)
  check("no errors logged", errors() == 0, ClassCoachDB.log and table.concat(ClassCoachDB.log, " || "))
  check("no tick error", ns.C.lastError == nil, ns.C.lastError)

---------------------------------------------------------------------------
elseif SCENARIO == "template" then
  M.player({ class = "MAGE", className = "Mage", level = 12, mana = 400, maxMana = 400,
    spells = { [116] = { name = "Frostbolt", cost = 25 }, [205] = { name = "Frostbolt", cost = 35 },
      [2136] = { name = "Fire Blast", cost = 40 }, [168] = { name = "Frost Armor", cost = 60 }, [5019] = { name = "Shoot", cost = 0 } },
    book = { 116, 205, 2136, 168, 5019 }, equipped = { [18] = 1 }, talents = { 0, 0, 4 } })
  local ns = load("docs/ProfileTemplate.lua")
  check("template profile loads and is picked", ns.C.profile.spec == "Frost", ns.C.profile.spec)
  M.P.target = { name = "Murloc", level = 11, hostile = true, guid = "Creature-4" }
  M.P.combat = true; M.fire("PLAYER_REGEN_DISABLED")
  local f = tick(ns)
  check("template priority works", f.name.text == "Fire Blast", f.name.text)
  check("no errors logged", errors() == 0, ClassCoachDB.log and table.concat(ClassCoachDB.log, " || "))

---------------------------------------------------------------------------
elseif SCENARIO == "warrior" then
  M.player({ class = "WARRIOR", className = "Warrior", level = 8, powerType = 1, mana = 0, maxMana = 0,
    spells = { [78] = { name = "Heroic Strike", cost = 0 } }, book = { 78 } })
  local ns = load()
  check("generic profile", ns.C.profile.class == "ANY", ns.C.profile.class)
  local f = tick(ns)
  check("no mana bar for rage users", ns.C.usesMana == false)
  M.P.target = { name = "Wolf", level = 7, hostile = true, guid = "Creature-3" }
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  M.advance(5); f = tick(ns); cast(78); M.advance(5)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  check("report for any class", ns.C.lastReport ~= nil)
  check("no errors logged", errors() == 0, ClassCoachDB.log and table.concat(ClassCoachDB.log, " || "))
  check("no tick error", ns.C.lastError == nil, ns.C.lastError)
end

print_real(("%s: %d passed, %d failed"):format(SCENARIO, passed, failed))
return failed
