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
  if not KEEP_LIMITS then ns.C.rescanGap, ns.C.macroGap = 0, 0 end   -- the rate limits have their own test
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
-- The steps to the right of the ring, nearest first: "Corruption > Immolate in 8s".
local function nextText(f)
  local parts = {}
  for _, s in ipairs(f.upcoming) do
    if s.shown and rawget(s, "title") then parts[#parts + 1] = rawget(s, "title") .. (s.timer.text ~= "" and (" " .. s.timer.text) or "") end
  end
  return table.concat(parts, " > ")
end
-- Every timer the coach shows for this enemy: on the icons left of the ring, and in the line for the rest.
local function timers(f)
  local parts = {}
  for _, s in ipairs(f.done) do
    if s.shown and rawget(s, "title") then parts[#parts + 1] = rawget(s, "title") .. " " .. s.timer.text end
  end
  parts[#parts + 1] = f.dots.text
  return table.concat(parts, " | ")
end
-- The key shown on a slot's badge ("" when it shows none).
local function keyOn(slot) return slot.key.shown and slot.key.text.text or "" end

-- What a bar holds from its first slot on, button by button: "CC Pull 8044 - item:1251" (trailing empty buttons left out).
local function barRow(first)
  local out = {}
  for i = 0, 11 do
    local a = M.P.actions[first + i]
    out[#out + 1] = a == nil and "-" or type(a) == "table" and (a.macro or (a.item and "item:" .. a.item) or "?") or tostring(a)
  end
  return (table.concat(out, " "):gsub("[ %-]+$", ""))
end

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
  check("with its key, when it is on your bar", keyOn(slot1) == (ns.C.keys["Lightning Shield"] or ""), keyOn(slot1))
  check("weapon buff: the best one you know", slot2.spell == "Rockbiter Weapon", tostring(slot2.spell))
  check("one line explains the first", f.status.text == "Cast Lightning Shield before the pull.", f.status.text)
  check("no missing list in words", not f.status.text:find("No shield"), f.status.text)
  check("food is a journey to-do, not a pull blocker", journey(ns):find("No food buff") ~= nil and not f.status.text:find("food"), journey(ns))
  check("journey: xp and rested", journey(ns):find("0%% · not rested") ~= nil and journey(ns):find("No rested XP") ~= nil, journey(ns))
  check("journey rows carry icons", ns.Journey.frame.rows[1].icon.texture == "Interface\\Icons\\INV_Misc_Food_15", tostring(ns.Journey.frame.rows[1].icon.texture))
  check("journey: next trainer level", journey(ns):find("New spells at level 16") ~= nil, journey(ns))
  M.P.xp, M.P.rested, M.P.talentPoints, M.P.durability, M.P.freeSlots = 430, 180, 1, 12, 1
  M.P.buffs["Well Fed XP Boost"] = true; M.fire("UNIT_AURA", "player")
  M.advance(3); f = tick(ns)
  check("journey: rested amount", journey(ns):find("43%% · rested 18%%") ~= nil, journey(ns))
  check("journey: talent point with the suggested talent", journey(ns):find("1 talent point to spend") ~= nil and journey(ns):find("Thundering Strikes") ~= nil, journey(ns))
  check("journey: repair and bags", journey(ns):find("Gear at 12%% durability") ~= nil and journey(ns):find("Bags nearly full %(1 free%)") ~= nil, journey(ns))
  check("journey: any Well Fed buff counts", not journey(ns):find("No food buff"), journey(ns))
  M.P.talentPoints, M.P.durability, M.P.freeSlots = 0, nil, 10
  M.P.items["Cozy Sleeping Bag"] = 1; M.P.items["Camp Tent"] = 1; M.P.rested = 20
  M.advance(3); f = tick(ns)
  check("journey: sleeping bag reminder when you own one", journey(ns):find("Sleeping bag buff missing") ~= nil, journey(ns))
  check("journey: tent reminder when rested is low", journey(ns):find("Rested XP low %(2%% of a level%)") ~= nil, journey(ns))
  M.P.buffs["Well-Rested"] = true; M.fire("UNIT_AURA", "player"); M.advance(3); f = tick(ns)
  check("journey: Forever's Well-Rested buff is the sleeping bag's", not journey(ns):find("Sleeping bag buff missing"), journey(ns))
  M.P.items["Cozy Sleeping Bag"] = nil; M.P.items["Camp Tent"] = nil
  -- talent points the game reports without a count
  M.P.talentPoints, M.P.noTalentCount = 2, true; ns.C.journey = nil; M.advance(3); f = tick(ns)
  check("journey: talent points without a count", journey(ns):find("Talent points to spend") ~= nil, journey(ns))
  M.P.talentPoints, M.P.noTalentCount = 0, nil; ns.C.journey = nil

  M.P.buffs = { ["Lightning Shield"] = true, ["Well Fed"] = true }
  M.P.permanentEnchant = true
  M.fire("UNIT_AURA", "player")
  f = tick(ns)
  check("a permanent weapon enchant is not a weapon buff", missing(ns):find("No weapon buff") ~= nil, missing(ns))
  M.P.mainHand = true
  M.fire("UNIT_AURA", "player")
  f = tick(ns)
  check("ready to pull: nothing missing, and the coach stays quiet about it", ns.C.lastView.status == "Ready to pull." and missing(ns) == "" and f.status.text == "", f.status.text .. " / " .. missing(ns))

  target({ name = "Rockjaw Trogg", level = 11, hostile = true, guid = "Creature-1" })
  f = tick(ns)
  check("opener is Flame Shock", f.name.text == "Flame Shock", f.name.text)
  check("opener keybind", f.key.text == "S3", f.key.text)
  check("chain after the opener", nextText(f) == "Searing Totem > Melee", nextText(f))
  check("chain label", f.chainLabel.text == "next", f.chainLabel.text)
  check("mana bar exact out of combat", f.bar.value == 300 and f.barText.text == "100%", f.barText.text)

  -- Fight (the game already hides the enemy's name when combat starts)
  local beforePull = journey(ns)
  M.P.combat = true; M.fire("PLAYER_REGEN_DISABLED")
  cast(529)
  M.advance(1.5); f = tick(ns)
  check("in combat: Flame Shock next", f.name.text == "Flame Shock", f.name.text)
  check("journey panel stays up in combat, as it was before the pull", journey(ns) ~= "(hidden)" and journey(ns) == beforePull, journey(ns))
  ClassCoachDB.journeyInCombat = false; tick(ns)
  check("unless you turn that off", journey(ns) == "(hidden)", journey(ns))
  ClassCoachDB.journeyInCombat = true; tick(ns)
  check("turned back on mid-fight it comes back", journey(ns) == beforePull, journey(ns))
  check("mana bar is handed the real hidden value", f.bar.value == M.SECRET)
  check("mana text written by the game", f.barText.secretText == true and f.barText.text == "%.0f%%", f.barText.text)
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
  check("3 levels above: warned, with the gap on the icon", missing(ns) == "3 levels above you" and f.missing[1].badgeText.text == "+3", missing(ns))
  f = facing(17)
  check("5 levels above: walk away", missing(ns) == "5 levels above you" and f.missing[1].hint:find("Walk away") ~= nil, missing(ns))
  f = facing(-1)
  check("skull enemy", missing(ns) == "Far above your level" and f.missing[1].badgeText.text == "??", missing(ns))
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
  check("journey: where to quest", journey(ns):find("Quest in: Loch Modan, Westfall or Darkshore", 1, true) ~= nil, journey(ns))
  check("journey: next milestone", journey(ns):find("At level 14: Cozy Sleeping Bag quest chain") ~= nil, journey(ns))
  M.P.level = 20; M.fire("PLAYER_LEVEL_UP", 20); M.advance(3); tick(ns)
  check("journey: class milestone due now", journey(ns):find("Water totem quest and Ghost Wolf") ~= nil, journey(ns))
  check("journey: dungeon in range (Forever's levels: Hall of Thanes ends at 18)", journey(ns):find("Dungeon: The Deadmines", 1, true) ~= nil, journey(ns))
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

  -- /coach bar: three bars by purpose
  M.P.actions = { [1] = 529, [2] = 8044, [4] = 8017 }
  M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(1); tick(ns)
  local before = M.P.actions
  SlashCmdList.CLASSCOACH("bar preview")
  check("bar preview changes nothing", M.P.actions[5] == nil and M.P.actions[49] == nil and M.P.actions[61] == nil)
  SlashCmdList.CLASSCOACH("bar")
  check("bar: taken buttons are left alone", M.P.actions[1] == 529 and M.P.actions[2] == 8044 and M.P.actions[4] == 8017)
  check("fight bar: what is new takes the free buttons in the layout's order, so no gap is left", barRow(1) == "529 8044 CC Pull 8017 8050 3599 8075", barRow(1))
  local bolts = 0
  for slot = 1, 12 do if M.P.actions[slot] == 529 then bolts = bolts + 1 end end
  check("fight bar: what is already on a bar is not doubled", bolts == 1, bolts)
  check("react bar (Action Bar 2): the heal", M.P.actions[61] == 331, tostring(M.P.actions[61]))
  check("prepare bar (Action Bar 3): shield first", M.P.actions[49] == 324, tostring(M.P.actions[49]))
  check("prepare bar: a spell already on a bar is not doubled, and leaves no gap either", barRow(49) == "324 CC Rest", barRow(49))
  M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(1); tick(ns)
  -- a bar that is switched off is not filled blindly
  M.P.actions = { [1] = 529 }; M.P.bars = { false, true }
  M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(1); tick(ns)
  SlashCmdList.CLASSCOACH("bar")
  check("a switched-off bar is skipped", M.P.actions[61] == nil and M.P.actions[49] == 324, tostring(M.P.actions[61]))
  M.P.bars = nil
  SlashCmdList.CLASSCOACH("bar replace")
  check("bar replace: the pull macro takes button 1", type(M.P.actions[1]) == "table" and M.P.actions[1].macro == "CC Pull", tostring(M.P.actions[1]))
  check("bar replace: what you know, side by side in the layout's order", barRow(1) == "CC Pull 8044 8050 3599 529 8075" and barRow(49) == "324 8017 CC Rest"
    and barRow(61) == "331", barRow(1) .. " / " .. barRow(49) .. " / " .. barRow(61))
  M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(1); tick(ns)
  -- Food, water, bandage and Hearthstone
  M.P.bag = {
    { id = 159, count = 4, class = 0, sub = 5, use = "Drink", name = "Refreshing Spring Water", min = 1 },
    { id = 1179, count = 10, class = 0, sub = 5, use = "Drink", name = "Ice Cold Milk", min = 5 },
    { id = 1645, count = 5, class = 0, sub = 5, use = "Drink", name = "Moonberry Juice", min = 35 },
    { id = 4540, count = 8, class = 0, sub = 5, use = "Food", name = "Tough Hunk of Bread", min = 1 },
    { id = 1251, count = 6, class = 0, sub = 7, name = "Linen Bandage", min = 1 },
    { id = 6948, count = 1, class = 15, sub = 0, name = "Hearthstone", min = 0 },
  }
  M.fire("BAG_UPDATE_DELAYED"); M.advance(1); tick(ns); M.advance(1); tick(ns)
  SlashCmdList.CLASSCOACH("bar")
  local rest = M.macros[GetMacroIndexByName("CC Rest")]
  check("rest macro: the best water you can use, then food", rest and rest.body == "#showtooltip\n/use item:1179\n/use item:4540", rest and rest.body)
  check("rest macro, bandage and Hearthstone on the prepare bar, right after the buffs", barRow(49) == "324 8017 CC Rest item:1251 item:6948", barRow(49))
  -- bags change: the macro follows, and a used-up or weaker item button is refreshed
  M.P.bag[2].count = 0; table.remove(M.P.bag, 2)
  M.P.bag[#M.P.bag + 1] = { id = 3530, count = 6, class = 0, sub = 7, name = "Wool Bandage", min = 1.5 }
  M.P.items[1251] = 6
  ClassCoachDB.autoBar = true
  M.fire("BAG_UPDATE_DELAYED"); M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(1); tick(ns); M.advance(1); tick(ns)
  rest = M.macros[GetMacroIndexByName("CC Rest")]
  check("rest macro rewrites itself when your bags change", rest.body == "#showtooltip\n/use item:159\n/use item:4540", rest.body)
  check("a better bandage replaces the old one on its button", barRow(49) == "324 8017 CC Rest item:3530 item:6948", barRow(49))
  ClassCoachDB.autoBar = false
  M.P.bag = { { id = 159, count = 2, class = 0, sub = 5, use = "Drink", name = "Refreshing Spring Water", min = 1 } }
  M.P.level = 16; M.fire("PLAYER_LEVEL_UP", 16); M.fire("MERCHANT_SHOW"); M.fire("BAG_UPDATE_DELAYED"); M.advance(3); tick(ns)
  check("vendor proposal: what to buy for your level", ns.C.lastJourney.lines and (function()
    for _, l in ipairs(ns.C.lastJourney.lines) do
      if l.text == "Buy water: 2 left" and l.hint:find("For your level: Melon Juice") then return true end
    end end)() == true)
  check("proposal: better water exists", journey(ns):find("Better water exists for your level") ~= nil, journey(ns))
  M.fire("MERCHANT_CLOSED"); M.P.bag = nil; M.P.level = 12; M.fire("PLAYER_LEVEL_UP", 12); M.advance(3); tick(ns)

  -- The panels must never grow over the action bars
  local pf, jf = ns.Panel.frame, ns.Journey.frame
  check("panels draw below the action bars", pf.strata == "LOW" and jf.strata == "LOW", tostring(pf.strata))
  check("the coach's frame is only the ring, so it never takes a click meant for the game", rawget(pf, "width") == 84 and rawget(pf.words, "mouse") == nil)
  check("the old wide panel's saved place is dropped: the ring starts from its own", ClassCoachCharDB.pos == nil and pf.point[1] == "CENTER" and pf.point[3] == "BOTTOM")
  pf.scripts.OnDragStop(pf)
  check("dragging the ring saves where you left it", ClassCoachCharDB.focusPos ~= nil and ClassCoachCharDB.focusPos[1] == "CENTER", tostring(ClassCoachCharDB.focusPos))
  ClassCoachDB.locked = true; tick(ns)
  check("locked: the ring lets clicks through", rawget(pf, "mouse") == false)
  ClassCoachDB.locked = false; tick(ns)
  check("unlocked: the ring can be dragged again", rawget(pf, "mouse") == true)
  SlashCmdList.CLASSCOACH("reset")
  check("/coach reset puts the ring back", ClassCoachCharDB.focusPos == nil and pf.point[3] == "BOTTOM")
  jf.left, jf.bottom, jf.top = 500, 120, 300
  jf.scripts.OnDragStop(jf)
  check("journey in the lower half of the screen: held by its bottom edge, so it grows upward", ClassCoachCharDB.journeyPos[1] == "BOTTOMLEFT"
    and ClassCoachCharDB.journeyPos[4] == 120 and jf.point[1] == "BOTTOMLEFT", ClassCoachCharDB.journeyPos[1])
  jf.left, jf.bottom, jf.top = 500, 500, 700
  jf.scripts.OnDragStop(jf)
  check("journey in the upper half: held by its top edge, so it grows downward", ClassCoachCharDB.journeyPos[1] == "TOPLEFT" and ClassCoachCharDB.journeyPos[4] == 700,
    ClassCoachCharDB.journeyPos[1])
  SlashCmdList.CLASSCOACH("reset")

  -- The main bar on another page looks like "my bars are gone"
  M.P.keyActions = { ["SHIFT-2"] = "ACTIONPAGE2", ["SHIFT-3"] = "ACTIONPAGE3" }
  M.P.page = 2; M.advance(1); f = tick(ns)
  check("bar page: flagged before a pull", missing(ns):find("Main bar is on page 2") ~= nil, missing(ns))
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true; f = tick(ns)
  check("bar page: said in a fight too", f.status.text:find("page 2") ~= nil and f.status.text:find("Shift%+1") ~= nil, f.status.text)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  SlashCmdList.CLASSCOACH("pages")
  check("/coach pages: Shift+number freed and back on page 1", M.P.page == 1 and M.P.keyActions["SHIFT-2"] == nil and M.P.keyActions["SHIFT-3"] == nil)
  -- the game blaming the addon is recorded
  M.fire("ADDON_ACTION_BLOCKED", "ClassCoach", "MultiBarBottomLeft:SetShown()")
  check("a blocked action blamed on us is kept for the report", ns.C.blocked[1] == "blocked: ClassCoach -> MultiBarBottomLeft:SetShown()", ns.C.blocked and ns.C.blocked[1])
  ClassCoachDB.log = nil

  -- new spells find their button by themselves when you ask for that
  ClassCoachDB.autoBar = true
  local prepBefore = barRow(49)
  M.P.spells[8024] = { name = "Flametongue Weapon", cost = 30 }; M.P.book[#M.P.book + 1] = 8024; M.P.knownIds[8024] = true
  M.fire("SPELLS_CHANGED"); M.advance(1); tick(ns); M.advance(1); tick(ns)
  check("a newly learned spell takes the first free button of its bar, and nothing else moves", not prepBefore:find("-", 1, true) and barRow(49) == prepBefore .. " 8024",
    prepBefore .. " -> " .. barRow(49))
  ClassCoachDB.autoBar = false

  -- The settings screen
  local S = M.settings
  check("settings page registered with the game", S.category ~= nil and S.category.name == "ClassCoach")
  local count = 0
  for _ in pairs(S.list) do count = count + 1 end
  check("every option made it onto the page", count == 46 and #ns.Options.registered == 46 and #ns.Options.keys() == 46, count)
  check("sections and action buttons", #S.headers == 7 and #S.buttons == 5, #S.headers .. "/" .. #S.buttons)
  check("options write to the saved settings", S.list.compact.tbl == ClassCoachDB and S.list.specChoice.tbl == ClassCoachCharDB)
  check("slider shows its unit", S.list.opacity.opts.format(60) == "60%" and S.list.scale.opts.format(1.1) == "1.10x")
  local specs = S.list.specChoice.getOptions()
  check("profile choices for this class", #specs == 2 and specs[1].value == "auto" and specs[2].value == "Enhancement", #specs)
  SlashCmdList.CLASSCOACH("")
  ClassCoach_OnAddonCompartmentClick()
  check("the addon never opens the game's settings panel itself", S.opened == nil, tostring(S.opened))
  SlashCmdList.CLASSCOACH("set compact on")
  check("/coach set: a switch", ClassCoachDB.compact == true)
  SlashCmdList.CLASSCOACH("set compact off"); SlashCmdList.CLASSCOACH("set opacity 400")
  check("/coach set: a number, kept in range", ClassCoachDB.compact == false and ClassCoachDB.opacity == 100, tostring(ClassCoachDB.opacity))
  SlashCmdList.CLASSCOACH("set opacity 75"); SlashCmdList.CLASSCOACH("set")
  -- Changing an option shows on the next refresh, with no reload.
  target({ name = "Trogg", level = 11, hostile = true, guid = "Creature-20" })
  M.P.mana = 300; M.advance(1); f = tick(ns)
  check("explanation shown by default", f.why.text ~= "" and f.why.shown, f.why.text)
  ClassCoachDB.compact = true; f = tick(ns)
  check("compact hides the explanation and keeps the icons", f.why.text == "" and nextText(f) ~= "", nextText(f))
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
  check("priest chain", nextText(f) == "Shadow Word: Pain > Mind Blast", nextText(f))
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
  -- While the wand fires, the game reports Shoot as on cooldown. It must not flip to melee.
  M.P.cooldowns[5019] = M.now + 60; M.P.repeating = 5019
  f = tick(ns)
  check("wanding: still the wand, not melee", f.name.text == "Shoot", f.name.text)
  check("wanding: says to leave it running", f.why.text:find("Leave it running") ~= nil, f.why.text)
  M.P.cooldowns[5019] = nil; M.P.repeating = nil
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
  -- Icons: the picture the game shows wins over the spell id's own picture
  local agony = function() return ns.C.spells["Bane of Agony"].icon end
  check("icon: the spell id's own when nothing better is known", agony() == "Interface\\Icons\\spell_980", tostring(agony()))
  M.P.bookIcons = { [980] = 136139 }
  M.fire("SPELLS_CHANGED"); M.advance(1)
  check("icon: the spellbook's picture comes before the id's", agony() == 136139, tostring(agony()))
  M.P.barIcons = { [980] = 237514 }
  M.P.actions[7] = 980; M.P.bindings.ACTIONBUTTON7 = "7"
  M.fire("ACTIONBAR_SLOT_CHANGED", 7); M.advance(1)
  check("icon: the action bar button's picture comes first", agony() == 237514, tostring(agony()))
  M.P.actions[7] = nil; M.P.bindings.ACTIONBUTTON7 = nil; M.P.barIcons, M.P.bookIcons = nil, nil
  M.fire("SPELLS_CHANGED"); M.advance(1)
  check("icon: back to the id's own when both are gone", agony() == "Interface\\Icons\\spell_980", tostring(agony()))
  local f = tick(ns)
  check("checklist: no demon, fixed by the Voidwalker", missing(ns):find("No demon") ~= nil and f.missing[1].spell == "Summon Voidwalker", missing(ns) .. " / " .. tostring(f.missing[1].spell))
  M.P.pet = { family = "Voidwalker" }
  M.P.buffs = { ["Demon Skin"] = true, ["Well Fed"] = true }
  M.P.items[6265] = 2
  M.fire("UNIT_AURA", "player")
  f = tick(ns)
  check("checklist clear with pet", not missing(ns):find("demon"), missing(ns))
  M.P.health = 80; f = tick(ns)
  check("low health check, with the number on the icon", missing(ns):find("Health 40%%") ~= nil and f.missing[1].badgeText.text == "40", missing(ns))
  M.P.health = 200
  target({ name = "Gnoll", level = 11, hostile = true, guid = "Creature-5" })
  f = tick(ns)
  check("opener Bane of Agony", f.name.text == "Bane of Agony", f.name.text)
  check("opener is told for the Voidwalker", f.why.text:find("Voidwalker in, let it hit first") ~= nil, f.why.text)
  check("warlock chain", nextText(f) == "Corruption > Immolate", nextText(f))
  check("durations read from the spell text", ns.C.spells["Corruption"].duration == 12 and ns.C.spells["Bane of Agony"].duration == 24,
    tostring(ns.C.spells["Corruption"].duration))

  -- The pull lands a moment before combat starts: it still counts.
  cast(980); M.advance(0.4)
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  f = tick(ns)
  check("pull spell counted in the fight", ns.C.tracker:castsOnTarget("g:Creature-5", "Bane of Agony") == 1)
  check("mana start includes the pull spell", ns.C.tracker.fight.manaStart == 300, ns.C.tracker.fight.manaStart)
  check("then Corruption", f.name.text == "Corruption", f.name.text)
  check("the step nearest the ring shows Bane ticking", f.done[1].shown and f.done[1].timer.text == "24s" and rawget(f.done[1], "title") == "Bane of Agony", f.done[1].timer.text)
  check("a timer shown on an icon is not repeated in words", f.dots.text == "" and f.leftLabel.text == "already cast", f.dots.text)
  cast(172); M.advance(2); f = tick(ns)
  check("then Immolate (mana high)", f.name.text == "Immolate", f.name.text)
  cast(348); M.advance(2); f = tick(ns)
  check("then wand", f.name.text == "Shoot", f.name.text)
  check("chain says when Corruption comes back", nextText(f) == "Corruption in 8s", nextText(f))
  check("two done slots, the latest nearest the ring", f.done[1].timer.text == "13s" and f.done[2].timer.text == "8s", f.done[1].timer.text .. "/" .. f.done[2].timer.text)
  check("a timer with no icon gets a line", f.dots.text == "Also on this enemy: Bane of Agony 20s", f.dots.text)
  -- How many steps show on each side is a setting (0 to 4)
  check("by default two before, two after", f.done[2].shown and not f.done[3].shown and not f.upcoming[3].shown)
  ClassCoachDB.stepsBefore, ClassCoachDB.stepsAfter = 4, 4
  f = tick(ns)
  check("four before: all three casts on this enemy show, the latest nearest", f.done[1].shown and f.done[2].shown and f.done[3].shown and not f.done[4].shown
    and f.done[1].timer.text == "13s" and f.done[2].timer.text == "8s" and f.done[3].timer.text == "20s" and f.dots.text == "",
    tostring(f.done[2].timer.text) .. "/" .. tostring(f.done[3].timer.text) .. "/" .. f.dots.text)
  check("steps further from the ring are smaller and sit higher", rawget(f.done[1], "width") == 34 and rawget(f.done[4], "width") == 22
    and f.done[1].point[5] == 0 and f.done[4].point[5] == 45 and f.upcoming[4].point[4] == 218, tostring(f.done[4].point[5]))
  check("the captions sit outside the outermost step, never over the ring", f.leftLabel.point[4] < -(170 + 13) and f.chainLabel.point[4] > 74 + 17,
    tostring(f.leftLabel.point[4]) .. "/" .. tostring(f.chainLabel.point[4]))
  ClassCoachDB.stepsBefore, ClassCoachDB.stepsAfter = 0, 1
  f = tick(ns)
  check("none before", not f.done[1].shown and not f.done[2].shown and not f.done[3].shown and not f.done[4].shown)
  check("one after: the list under the icon names one step at most", not f.upcoming[2].shown and not nextText(f):find(">", 1, true), nextText(f))
  ClassCoachDB.stepsAfter = 0
  f = tick(ns)
  check("none after: only the current step", not f.upcoming[1].shown and f.name.text == "Shoot" and nextText(f) == "", nextText(f))
  ClassCoachDB.stepsBefore, ClassCoachDB.stepsAfter = "lots", -3
  f = tick(ns)
  local sane = { ns.Panel.steps(ClassCoachDB) }
  check("a damaged setting falls back to a sane count", sane[1] == 2 and sane[2] == 0 and f.done[2].shown and not f.upcoming[1].shown, sane[1] .. "/" .. sane[2])
  ClassCoachDB.stepsBefore, ClassCoachDB.stepsAfter = 2, 2
  f = tick(ns)
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
  check("back on the first: its timers are remembered", f.name.text == "Shoot" and timers(f):find("Corruption") ~= nil, f.name.text .. " / " .. timers(f))

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
  check("hidden ids: timers on the current enemy work", timers(f):find("Bane of Agony %d+s") ~= nil, timers(f))
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
  -- A client that hands macro text back changed must not make us rewrite it forever.
  local realBody, edits = GetMacroBody, 0
  local realEdit = EditMacro
  GetMacroBody = function(i) return (realBody(i) or "") .. "\n" end
  EditMacro = function(...) edits = edits + 1; return realEdit(...) end
  for _ = 1, 3 do M.fire("SPELLS_CHANGED"); M.advance(1); tick(ns) end
  check("unchanged macros are not rewritten", edits == 0, edits)
  GetMacroBody, EditMacro = realBody, realEdit
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
  check("the icon nearest the ring shows the miss", f.done[1].timer.text == "miss", tostring(f.done[1].timer.text))
  check("a resisted cast does not count as on the enemy", ns.C.tracker:castsOnTarget("g:Creature-40", "Bane of Agony") == 0
    and not timers(f):find("Bane of Agony %d+s"), timers(f))
  cast(980); M.advance(1.5); f = tick(ns)
  check("it landed the second time", f.name.text == "Corruption" and timers(f):find("Bane of Agony %d+s") ~= nil, f.name.text .. " / " .. timers(f))
  cast(172); M.advance(1.2)
  M.fire("UNIT_COMBAT", "target", "RESIST", "", 0, 32); f = tick(ns)
  check("a resist long after your cast is someone else's", f.name.text ~= "Corruption" and timers(f):find("Corruption %d+s") ~= nil, f.name.text .. " / " .. timers(f))
  -- a resisted refresh keeps the old one running
  M.advance(1); local left = ns.C.tracker:debuffLeft("g:Creature-40", "Corruption", M.now)
  cast(172); M.fire("UNIT_COMBAT", "target", "RESIST", "", 0, 32)
  check("a resisted recast leaves the running one alone", math.abs(ns.C.tracker:debuffLeft("g:Creature-40", "Corruption", M.now) - left) < 0.01)
  -- immune
  cast(348); M.fire("UNIT_COMBAT", "target", "IMMUNE", "", 0, 4)
  M.advance(0.2); f = tick(ns)
  check("immune: not suggested again on this enemy", f.name.text ~= "Immolate" and not nextText(f):find("Immolate"), f.name.text .. " / " .. nextText(f))
  check("immune: explained", f.status.text:find("immune to Immolate") ~= nil, f.status.text)
  check("immune: marked on the icon nearest the ring", f.done[1].timer.text == "immune", tostring(f.done[1].timer.text))
  M.advance(12)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)
  check("the report counts resists", ns.C.lastReport.headline:find("3 resisted") ~= nil, ns.C.lastReport.headline)
  check("and puts them in perspective", table.concat(ns.C.lastReport.tips, " | "):find("3 of your 5 casts were resisted") ~= nil, table.concat(ns.C.lastReport.tips, " | "))
  target(nil); M.advance(1); tick(ns)

  -- The smart key: one key walks the plan, inside the game's secure code.
  check("no secure button until you ask for the smart key", ns.Smart.button == nil)
  SlashCmdList.CLASSCOACH("errors")
  SlashCmdList.CLASSCOACH("smart")
  local b = ns.Smart.button
  check("smart key: secure button made and loaded", b ~= nil and b:GetAttribute("cc-count") == 3, b and b:GetAttribute("cc-count"))
  check("smart key: resets when no living enemy is targeted", M.drivers.ccreset.conditions == "[@target,harm,nodead] keep; reset")
  local steps = table.concat(ns.Smart.describe(), ", ")
  check("smart key at half mana: the plan leaves out Immolate (spare mana only)", steps == "1 Bane of Agony, 2 Corruption, 3 Shoot (stays here)", steps)
  M.P.mana = 300; M.advance(2.5); tick(ns); M.advance(2.5); tick(ns)   -- a new plan is loaded once it holds for two checks
  steps = table.concat(ns.Smart.describe(), ", ")
  check("smart key: after drinking to full it is loaded again by itself, with Immolate", steps == "1 Bane of Agony, 2 Corruption, 3 Immolate, 4 Shoot (stays here)", steps)
  check("a plan that only flickers is never loaded", (function()
    local before = ns.C.planSeen
    ns.C.planNext = "flicker"; M.advance(2.1); tick(ns)
    return ns.C.planSeen == before
  end)())
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
  M.advance(2.1); f = tick(ns)   -- keys are read again every two seconds
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

  -- Forever's guides: from level 20 the Succubus or Incubus is the leveling demon
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.P.target = nil; M.fire("PLAYER_TARGET_CHANGED")
  M.P.pet = nil
  M.P.spells[712] = { name = "Summon Succubus", cost = 100 }; M.P.book[#M.P.book + 1] = 712
  M.P.knownIds = M.P.knownIds or {}; M.P.knownIds[712] = true
  M.P.level = 20; M.fire("PLAYER_LEVEL_UP", 20); M.fire("SPELLS_CHANGED"); M.advance(3)
  local f20 = tick(ns)
  local shown
  for _, slot in ipairs(f20.missing) do if rawget(slot, "spell") == "Summon Succubus" then shown = true end end
  check("level 20: no demon is fixed by the Succubus", missing(ns):find("No demon") ~= nil and shown == true, missing(ns))

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
    local shown = { f.name.text, f.why.text, f.status.text, nextText(f), f.dots.text, journeyNow(ns), missing(ns) }
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
      check(tag .. ": no demon talk without one", not (f.why.text:find("demon") or nextText(f):find("demon")), f.why.text)
    end
    if not opts.wand then
      check(tag .. ": no Shoot without a wand", f.name.text ~= "Shoot" and not nextText(f):find("Shoot"), f.name.text)
    end
    check(tag .. ": no error", ns.C.lastError == nil, ns.C.lastError)
    return f
  end

  -- The smart key at every level: its steps must be castable, in the coach's order, and
  -- end on something that is safe to keep pressing (wand, a filler spell or attacking).
  local smartSeen = {}
  local function smartKey(level, opts, spells)
    local s = ns.C.lastState
    local made = {}
    for _, m in ipairs(ns.Engine.macros(profile, s)) do made[m.name] = true end
    check(("%s L%d: the pull macro fits the game's 255 characters"):format(WANT, level), made["CC Pull"] == true)
    for _, variant in ipairs({ "with its macros", "without any macro" }) do
      local has = { macro = function(name) return variant == "with its macros" and made[name] == true end }
      local steps, gate = ns.Engine.smartSteps(profile, s, has)
      local tag = ("%s L%d smart key %s wand=%s pet=%s"):format(WANT, level, variant, tostring(opts.wand), tostring(opts.pet))
      local names = {}
      for i, st in ipairs(steps) do
        names[i] = st.kind .. ":" .. st.value
        if st.kind == "spell" then
          local known = false
          for _, sp in pairs(spells) do if sp.name == st.value then known = true end end
          check(tag .. ": step " .. i .. " is a spell you know", known, st.value)
        else
          check(tag .. ": step " .. i .. " is a macro that exists", made[st.value] == true, st.value)
        end
      end
      local line = table.concat(names, " > ")
      check(tag .. ": never more steps than a pull needs", #steps <= 8, line)
      local last = steps[#steps]
      if last then
        local meta = last.kind == "spell" and profile.spells[last.value]
        check(tag .. ": the step it stays on is safe to keep pressing", not (meta and meta.debuff), line)
        if opts.wand then
          -- a class that keeps casting at full mana (the Priest's Smite) ends on that spell: the coach moves you to the wand's own key when mana drops
          local nuke = last.kind == "spell" and last.value ~= "Shoot"
          check(tag .. ": with a wand it ends on the wand, or on the spell the coach casts at full mana",
            nuke or last.value == (variant == "with its macros" and "CC Wand" or "Shoot"), line)
        end
      end
      if next(spells) and (variant == "with its macros" or opts.wand) then check(tag .. ": it has steps", #steps >= 1, line) end
      if gate then check(tag .. ": the gate's macro exists", made[gate.macro] == true, tostring(gate.macro)) end
      check(tag .. ": the whole pull plan fits the key", #ns.Engine.plan(profile, s) == #ns.Engine.plan(profile, s, 20), #ns.Engine.plan(profile, s, 20))
      smartSeen[line] = smartSeen[line] or level
    end
  end

  -- The bars at every level: what you know sits side by side from button 1, and
  -- the fixed-buttons setting shows the same entries in the same order, each on its own button.
  local function barLayout(level, spells)
    local s = ns.C.lastState
    local has = { macro = function() return true end, book = function() return nil end, item = function() return nil end }
    local packed, fixed = ns.Engine.bars(profile, s, has), ns.Engine.bars(profile, s, has, true)
    for _, group in ipairs(ns.Engine.BAR_GROUPS) do
      local tag = ("%s L%d %s bar"):format(WANT, level, group)
      local gapless, same, rising, known = #packed[group] <= 12, #packed[group] == #fixed[group], true, true
      for i, e in ipairs(packed[group]) do
        if e.index ~= i then gapless = false end
        local other = fixed[group][i]
        if not other or other.label ~= e.label then same = false end
        if other and (other.index < i or other.index > 12 or (i > 1 and other.index <= fixed[group][i - 1].index)) then rising = false end
        if e.spell and not spells[e.spell] then known = false end
      end
      check(tag .. ": no gaps", gapless)
      check(tag .. ": fixed buttons hold the same entries in the same order", same and rising)
      check(tag .. ": only spells you know", known)
    end
  end

  for level = 1, 60 do
    for _, wand in ipairs(def.wand and { false, true } or { false }) do
      for _, pet in ipairs(def.pet and { false, true } or { false }) do
        for _, mana in ipairs({ 300, 120, 30 }) do
          local opts = { wand = wand and level >= 5, pet = pet, mana = mana, noImp = def.pet and not pet and level < 10 }
          local spells = setup(level, opts)
          local f = look(level, opts, spells, "idle")
          if mana == 300 then smartKey(level, opts, spells); barLayout(level, spells) end
          check(("%s L%d: a pull plan is shown"):format(WANT, level), ns.C.lastView.planning == true and f.name.text ~= "" and f.name.text ~= "Ready"
            and (f.chainLabel.text == "your pull plan" or not f.upcoming[1].shown), f.name.text)
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
    check("and it is not suggested", not nextText(f):find("Corruption"), nextText(f))
    setup(12, { mana = 60, pet = true })
    f = tick(ns)
    check("low mana out of combat: Life Tap icon and hint", missing(ns):find("Mana 20%%") ~= nil and f.missing[2].spell == "Life Tap" and f.missing[2].badgeText.text == "20" and f.missing[2].hint:find("Life Tap") ~= nil, missing(ns) .. " / " .. tostring(f.missing[2].spell))
  end
  check("no errors logged", errors() == 0, ClassCoachDB.log and table.concat(ClassCoachDB.log, " || "))
  if SWEEP_PRINT then
    local lines = {}
    for line, level in pairs(smartSeen) do lines[#lines + 1] = ("%s smart L%02d+  %s"):format(WANT, level, line) end
    table.sort(lines)
    for _, l in ipairs(lines) do print_real(l) end
    local last = {}
    for _, l in ipairs(samples) do
      local variant, body = l:sub(5, 26), l:sub(27)
      if last[variant] ~= body then print_real(WANT .. " " .. l) end
      last[variant] = body
    end
  end

---------------------------------------------------------------------------
-- Robustness: whatever the game does, the addon must never raise an error
-- into it, never loop, and never do protected things in combat.
elseif SCENARIO == "robust" then
  KEEP_LIMITS = true
  local before = {}
  for k in pairs(_G) do before[k] = true end
  M.player({
    class = "WARLOCK", className = "Warlock", level = 12, mana = 300, maxMana = 300,
    spells = {
      [686] = { name = "Shadow Bolt", cost = 25 }, [348] = { name = "Immolate", cost = 25 },
      [172] = { name = "Corruption", cost = 35 }, [980] = { name = "Bane of Agony", cost = 25 },
      [1454] = { name = "Life Tap", cost = 0 }, [687] = { name = "Demon Skin", cost = 50 },
      [688] = { name = "Summon Imp", cost = 60 }, [5019] = { name = "Shoot", cost = 0 },
    },
    book = { 686, 348, 172, 980, 1454, 687, 688, 5019 },
    equipped = { [18] = 11287 }, pet = { family = "Imp" }, talents = { 3, 0, 0 },
    actions = { [1] = 686 }, bindings = { ACTIONBUTTON1 = "1" },
  })
  -- a broken profile file must not stop anything
  local nsProbe = {}
  local ns = load("tests/broken_profile.lua")
  check("a broken profile is skipped and noted, not an error", #ns.Profiles.problems >= 3, #ns.Profiles.problems)
  check("the real profile still loads", ns.C.profile.spec == "Affliction", ns.C.profile.spec)
  local driver = ns.C.driver
  local escaped = 0
  local function guarded(what, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then escaped = escaped + 1; print_real("ESCAPED from " .. what .. ": " .. tostring(err)) end
  end
  local function refresh(dt) guarded("refresh", driver.scripts.OnUpdate, driver, dt or 1) end
  refresh(); M.advance(3); refresh()

  -- 1. An event storm: a sequence macro changing its button a hundred times a second
  local scans, realScan = 0, ns.API.scanKeys
  ns.API.scanKeys = function(...) scans = scans + 1; return realScan(...) end
  local spellScans, realBook = 0, ns.API.scanSpellbook
  ns.API.scanSpellbook = function(...) spellScans = spellScans + 1; return realBook(...) end
  for i = 1, 1000 do
    M.fire("ACTIONBAR_SLOT_CHANGED", (i % 12) + 1); M.fire("UPDATE_MACROS")
    if i % 100 == 0 then M.advance(1); refresh() end
  end
  check("1000 bar events in 10 seconds: keys read at most once every two seconds", scans >= 1 and scans <= 6, scans)
  check("and the spellbook not at all", spellScans == 0, spellScans)
  for i = 1, 300 do M.fire("SPELLS_CHANGED"); if i % 30 == 0 then M.advance(1); refresh() end end
  check("300 spell events in 10 seconds: at most one full rescan every two seconds", spellScans >= 1 and spellScans <= 6, spellScans)
  ns.API.scanKeys, ns.API.scanSpellbook = realScan, realBook

  -- 2. A client that keeps reporting macros as different: rewrites are rationed, then stop
  SlashCmdList.CLASSCOACH("macros")
  local edits, realEdit, realBody = 0, EditMacro, GetMacroBody
  EditMacro = function(...) edits = edits + 1; return realEdit(...) end
  for i = 1, 200 do
    ClassCoachCharDB.kill = { avg = 6 + (i % 2) * 20, n = 5 }   -- the plan flips every time
    M.fire("SPELLS_CHANGED"); M.advance(2.1); refresh()
  end
  check("automatic macro rewrites stop themselves", ns.C.macrosPaused == true and edits <= 14, edits)
  EditMacro = realEdit; ClassCoachCharDB.kill = nil

  -- 3. Nothing protected is touched in combat
  M.P.target = { name = "Wolf", level = 12, hostile = true, guid = "Creature-1" }; M.fire("PLAYER_TARGET_CHANGED")
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  local touched = 0
  for _, name in ipairs({ "EditMacro", "CreateMacro", "PlaceAction", "SetBinding", "SetBindingClick" }) do
    local real = _G[name]
    _G[name] = function(...) touched = touched + 1; return real(...) end
  end
  local realPage = C_ActionBar.SetActionBarPage
  C_ActionBar.SetActionBarPage = function(...) touched = touched + 1; return realPage(...) end
  for _, cmd in ipairs({ "macros", "bar", "bar replace", "smart", "smart next 1", "pages", "reset", "set scale 1.2", "check", "errors", "last" }) do
    guarded("/coach " .. cmd, SlashCmdList.CLASSCOACH, cmd)
  end
  for _, e in ipairs({ "SPELLS_CHANGED", "ACTIONBAR_SLOT_CHANGED", "BAG_UPDATE_DELAYED", "UPDATE_BINDINGS", "PLAYER_EQUIPMENT_CHANGED" }) do
    M.fire(e)
  end
  ClassCoachDB.autoBar = true
  for _ = 1, 20 do M.advance(0.5); refresh() end
  check("in combat: no macro, bar, binding or page call at all", touched == 0, touched)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(3); refresh()
  ClassCoachDB.autoBar = false

  -- 4. Commands with nonsense
  for _, cmd in ipairs({ "", " ", "set", "set nothing 1", "set scale banana", "set opacity -5", "spec", "spec Nope", "bar what",
    "smart next", "smart nope F1", "journey", "errors on", "errors off", "%s%d%%", string.rep("x", 5000) }) do
    guarded("/coach " .. cmd:sub(1, 20), SlashCmdList.CLASSCOACH, cmd)
  end
  guarded("/coach nil", SlashCmdList.CLASSCOACH, nil)
  guarded("/coach number", SlashCmdList.CLASSCOACH, 42)
  check("scale stayed a sane number", type(ClassCoachDB.scale) == "number" and ClassCoachDB.scale >= 0.6 and ClassCoachDB.scale <= 1.6, tostring(ClassCoachDB.scale))

  -- 5. A refresh that keeps failing: caught, slowed down, said, and it recovers
  local realNext = ns.Engine.next
  ns.Engine.next = function() error("boom") end
  local runs = 0
  local realBuild = ns.Engine.newState
  ns.Engine.newState = function(...) runs = runs + 1; return realBuild(...) end
  for _ = 1, 12 do refresh(1) end
  check("a failing refresh never reaches the game", escaped == 0, escaped)
  check("after ten failures it tells you on the panel", ns.C.trouble ~= nil and ns.Panel.frame.status.text:find("/coach errors") ~= nil, ns.Panel.frame.status.text)
  runs = 0
  for _ = 1, 20 do refresh(1) end
  check("and tries only once every five seconds", runs == 4, runs)
  ns.Engine.next = realNext
  for _ = 1, 6 do refresh(1) end
  check("it recovers by itself when the cause is gone", ns.C.trouble == nil and ns.Panel.frame.name.text ~= "", tostring(ns.C.trouble))
  ns.Engine.newState = realBuild
  check("the same error is logged once, then counted", #ClassCoachDB.log < 12, #ClassCoachDB.log)

  -- 6. Chaos: every game function returns nothing, something hidden, rubbish, or fails
  local SECRET = M.SECRET
  local names = {}
  for name, v in pairs(_G) do
    if type(v) == "function" and (name:match("^Unit") or name:match("^Get") or name:match("^Is") or name:match("^Can")
      or name:match("^Set") or name:match("^Pickup") or name:match("^Place") or name:match("^Edit") or name:match("^Create")
      or name:match("^Change") or name:match("^Save") or name:match("^Clear")) and name ~= "GetTime" and name ~= "CreateFrame" then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local tables = {}
  for _, tn in ipairs({ "C_Spell", "C_SpellBook", "C_Item", "C_Container", "C_UnitAuras", "C_Secrets", "C_NamePlate", "C_ActionBar",
    "C_ClassTalents", "C_Traits", "C_CVar" }) do
    if type(_G[tn]) == "table" then tables[#tables + 1] = tn end
  end
  local seed = 12345
  local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
  local junk = { function() return nil end, function() return SECRET end, function() return SECRET, SECRET, SECRET end,
    function() error("the game refused") end, function() return {} end, function() return "text" end, function() return -1 end,
    function() return 0 / 0 end, function() return true end, function() return math.huge end,
    function() return { itemID = SECRET, stackCount = SECRET, isActive = SECRET, name = SECRET } end }
  local originals = {}
  local function wreck(tbl, key)
    local real = tbl[key]
    originals[#originals + 1] = { tbl, key, real }
    tbl[key] = function(...)
      local r = rnd(100)
      if r < 55 then return real(...) end
      return junk[rnd(#junk) + 1](...)
    end
  end
  for _, name in ipairs(names) do wreck(_G, name) end
  for _, tn in ipairs(tables) do
    local keys = {}
    for k, v in pairs(_G[tn]) do if type(v) == "function" then keys[#keys + 1] = k end end
    table.sort(keys)
    for _, k in ipairs(keys) do wreck(_G[tn], k) end
  end
  local EVENTS = { "SPELLS_CHANGED", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "UPDATE_MACROS", "BAG_UPDATE_DELAYED", "MERCHANT_SHOW",
    "MERCHANT_CLOSED", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_SWING", "UNIT_AURA",
    "UNIT_COMBAT", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_TALENT_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_ENTERING_WORLD" }
  local ARGS = { nil, SECRET, "player", "target", "RESIST", "IMMUNE", 980, 172, 5019, -1, 0 / 0, {}, true, "ClassCoach", 13, 60, 999 }
  local COMMANDS = { "macros", "bar", "bar replace", "bar preview", "smart", "smart next 1", "pages", "reset", "check", "errors", "last",
    "set compact", "set scale 1.3", "spec auto", "hide", "show" }
  local began, steps = os.clock(), 0
  for i = 1, 6000 do
    local r = rnd(100)
    if r < 45 then
      guarded("event", M.fire, EVENTS[rnd(#EVENTS) + 1], ARGS[rnd(#ARGS) + 1], ARGS[rnd(#ARGS) + 1], ARGS[rnd(#ARGS) + 1])
    elseif r < 85 then
      M.now = M.now + 0.1 + rnd(20) / 10
      refresh(0.5)
    elseif r < 90 then
      guarded("command", SlashCmdList.CLASSCOACH, COMMANDS[rnd(#COMMANDS) + 1])
    elseif r < 95 then
      guarded("timers", M.advance, rnd(30) / 10)
    else
      M.P.combat = rnd(2) == 0
      M.P.target = rnd(3) > 0 and { name = "Thing", level = rnd(70) - 2, hostile = rnd(4) > 0, elite = rnd(5) == 0, guid = "Creature-" .. rnd(6) } or nil
      M.P.mana = rnd(400); M.P.level = rnd(62) + 1; M.P.pet = rnd(2) == 0 and { family = ({ "Imp", "Voidwalker", "Cat" })[rnd(3) + 1] } or nil
      -- the panels' own handlers
      local pf, jf = ns.Panel.frame, ns.Journey.frame
      pf.left, pf.bottom, pf.top = rnd(3000) - 500, rnd(2000) - 500, rnd(2000) - 500
      guarded("drag", pf.scripts.OnDragStart, pf); guarded("drag", pf.scripts.OnDragStop, pf)
      guarded("drag", jf.scripts.OnDragStop, jf)
      for _, s in ipairs(pf.missing) do guarded("hover", s.scripts.OnEnter, s); guarded("hover", s.scripts.OnLeave, s) end
      for _, rw in ipairs(jf.rows) do guarded("hover", rw.scripts.OnEnter, rw) end
      guarded("menu", ClassCoach_OnAddonCompartmentClick); guarded("menu", ClassCoach_OnAddonCompartmentEnter, nil, pf)
    end
    steps = steps + 1
  end
  local seconds = os.clock() - began
  for _, o in ipairs(originals) do o[1][o[2]] = o[3] end
  check("chaos: 6000 hostile steps, nothing escaped into the game", escaped == 0, escaped)
  check("chaos: it finished quickly (no runaway loop)", seconds < 20, seconds)
  check("chaos: the log stayed small", #ClassCoachDB.log <= 100, #ClassCoachDB.log)
  local dots, casts = 0, #ns.C.tracker.recentCasts
  for _ in pairs(ns.C.tracker.dots) do dots = dots + 1 end
  check("chaos: the trackers stayed small", dots <= 60 and casts <= 12, dots .. "/" .. casts)

  -- 7. Back to a sane game: it works again without a reload
  M.P.combat = false; M.P.level = 12; M.P.mana = 300; M.P.pet = { family = "Imp" }; M.P.target = nil
  M.fire("PLAYER_REGEN_ENABLED"); M.fire("PLAYER_LEVEL_UP", 12); M.fire("PLAYER_TARGET_CHANGED")
  for _ = 1, 30 do M.advance(1); refresh(1) end
  check("after the chaos it runs normally again", ns.C.trouble == nil and ns.C.lastState ~= nil and ns.C.lastState.level == 12,
    tostring(ns.C.trouble))

  -- 8. Damaged saved settings are repaired
  ClassCoachDB.scale, ClassCoachDB.opacity, ClassCoachDB.compact, ClassCoachDB.drinkAt = "big", 0 / 0, "yes", 9999
  ClassCoachCharDB.focusPos, ClassCoachCharDB.journeyPos = { "CENTER", 5, "x" }, "nowhere"
  ClassCoachDB.barGlow, ClassCoachDB.cueSound = 12, {}
  ClassCoachCharDB.kill, ClassCoachCharDB.specChoice, ClassCoachDB.log = { avg = -3, n = "many" }, 77, "oops"
  ns.Options.sanitize(ClassCoachDB, ClassCoachCharDB)
  check("damaged settings go back to defaults", ClassCoachDB.scale == 1 and ClassCoachDB.opacity == 60 and ClassCoachDB.compact == false
    and ClassCoachDB.barGlow == "glow" and ClassCoachDB.cueSound == "click"
    and ClassCoachDB.drinkAt == 60 and ClassCoachCharDB.pos == nil and ClassCoachCharDB.journeyPos == nil
    and ClassCoachCharDB.kill == nil and ClassCoachCharDB.specChoice == "auto" and ClassCoachDB.log == nil)
  for _ = 1, 5 do M.advance(1); refresh(1) end
  check("and nothing escaped at any point", escaped == 0, escaped)

  -- 9. Good neighbour: no stray global names that could collide with the game or another addon
  local stray = {}
  for k in pairs(_G) do
    if not before[k] and type(k) == "string" and not (k:match("^ClassCoach") or k:match("^SLASH_CLASSCOACH")
      or k:match("^BINDING_[A-Z]+_CLASSCOACH") or k:match("^BINDING_NAME_CLICK ClassCoach")) then
      stray[#stray + 1] = k
    end
  end
  table.sort(stray)
  check("no stray global names", #stray == 0, table.concat(stray, ", "))

---------------------------------------------------------------------------
-- WoW Forever only: the addon uses Forever's own functions and nothing from
-- another version of the game, and switches itself off anywhere else.
elseif SCENARIO == "forever" then
  local function player()
    M.player({
      class = "SHAMAN", className = "Shaman", level = 20, mana = 300, maxMana = 300,
      spells = { [403] = { name = "Lightning Bolt", cost = 15 }, [8017] = { name = "Rockbiter Weapon", cost = 10 },
        [324] = { name = "Lightning Shield", cost = 45 } },
      book = { 403, 8017, 324 }, talents = { 0, 11, 0 },
      actions = { [1] = 403 }, bindings = { ACTIONBUTTON1 = "1" },
    })
  end

  -- 1. The source calls nothing that Forever does not have. These names exist in
  --    Classic Era, Season of Discovery, the Classic expansions or older retail,
  --    but not in the Forever client (Warcraft Wiki's Forever API list).
  local GONE = { "GetSpellInfo", "GetSpellTabInfo", "GetNumSpellTabs", "GetSpellBookItemInfo", "GetSpellBookItemName", "GetSpellCooldown",
    "GetSpellPowerCost", "GetSpellDescription", "GetSpellTexture", "IsUsableSpell", "IsSpellKnown", "IsPlayerSpell", "IsAutoRepeatSpell",
    "IsCurrentSpell", "PickupSpell", "PickupItem", "GetItemInfo", "GetItemCount", "GetItemSpell", "GetContainerNumFreeSlots",
    "GetContainerNumSlots", "GetContainerItemInfo", "UnitBuff", "UnitDebuff", "UnitAura", "UnitCharacterPoints", "GetTalentTabInfo",
    "GetNumTalentTabs", "GetNumTalents", "GetTalentInfo", "GetWeaponEnchantInfo", "GetActionBarPage", "ChangeActionBarPage",
    "GetActionTexture", "GetActionText", "GetActionCooldown", "IsUsableAction", "SetCVar", "GetCVar", "CombatLogGetCurrentEventInfo",
    "GetAddOnMetadata", "IsAddOnLoaded" }
  local toc = io.open(ROOT .. "/ClassCoach/ClassCoach.toc"):read("*a")
  local bad = {}
  for line in toc:gmatch("[^\n]+") do
    if not line:match("^#") and line:match("%.lua%s*$") then
      local file = line:gsub("\\", "/"):gsub("%s+$", "")
      local src = " " .. io.open(ROOT .. "/ClassCoach/" .. file):read("*a")
      src = src:gsub("%-%-[^\n]*", "")                      -- comments may name them
      for _, name in ipairs(GONE) do
        -- the bare global: not C_Something.Name and not part of a longer word
        if src:find("[^%w_%.]" .. name .. "[^%w_]") then bad[#bad + 1] = file .. ": " .. name end
      end
    end
  end
  check("no call to a function Forever lacks", #bad == 0, table.concat(bad, "; "))
  check("the TOC names Forever's interface only", toc:match("## Interface:%s*([^\n]+)") == "16001", toc:match("## Interface:%s*([^\n]+)"))
  local extra = {}
  for _, f in ipairs({ "ClassCoach_Vanilla.toc", "ClassCoach_Classic.toc", "ClassCoach_Mainline.toc", "ClassCoach_TBC.toc", "ClassCoach_Wrath.toc",
    "ClassCoach_Cata.toc", "ClassCoach_Mists.toc" }) do
    local fh = io.open(ROOT .. "/ClassCoach/" .. f); if fh then fh:close(); extra[#extra + 1] = f end
  end
  check("no TOC for any other version", #extra == 0, table.concat(extra, ", "))

  -- 2. On another version of the game it does nothing at all
  local function offOn(what, setup)
    player(); setup()
    M.printed = {}
    local before = #M.frames
    ClassCoachDB, ClassCoachCharDB = nil, nil
    local ns = load()
    local said = table.concat(M.printed, " | ")
    local events = 0
    for i = before + 1, #M.frames do for _ in pairs(M.frames[i].events or {}) do events = events + 1 end end
    check(what .. ": stays off, says why once", ns.API.forever == false and ns.C.driver == nil and ns.Panel.frame == nil
      and ClassCoachDB == nil and select(2, said:gsub("Forever only", "")) == 1, said)
    check(what .. ": listens to no game events", events == 0, events)
    M.printed = {}
    local ok = pcall(SlashCmdList.CLASSCOACH, "bar replace")
    check(what .. ": /coach only explains", ok and #M.printed == 1 and M.printed[1]:find("Forever only") ~= nil and #M.macros == 0, M.printed[1])
  end
  local realBuild, realProject = GetBuildInfo, WOW_PROJECT_ID
  offOn("retail", function() WOW_PROJECT_ID = WOW_PROJECT_MAINLINE; GetBuildInfo = function() return "12.1.5", "1", "x", 120105 end end)
  offOn("Classic Era", function() WOW_PROJECT_ID = WOW_PROJECT_CLASSIC; GetBuildInfo = function() return "1.15.8", "1", "x", 11508 end end)
  -- an older client without the project list: the interface number decides
  local camelot = WOW_PROJECT_CAMELOT
  offOn("a Classic expansion", function() WOW_PROJECT_CAMELOT = nil; GetBuildInfo = function() return "5.5.3", "1", "x", 50503 end end)
  local hidden = issecretvalue
  offOn("a client without hidden values", function() WOW_PROJECT_CAMELOT = camelot; WOW_PROJECT_ID = camelot; GetBuildInfo = realBuild; issecretvalue = nil end)
  issecretvalue = hidden

  -- 3. On Forever it runs, by project id or (if the id list is missing) by interface number
  WOW_PROJECT_ID, WOW_PROJECT_CAMELOT, GetBuildInfo = nil, nil, realBuild
  player()
  local ns = load()
  check("Forever by interface number 16001", ns.API.forever == true and ns.C.driver ~= nil and ns.Panel.frame ~= nil)
  WOW_PROJECT_CAMELOT = camelot; WOW_PROJECT_ID = camelot
  GetBuildInfo = function() return "1.61.0", "1", "x", 16100 end
  player()
  ns = load()
  check("Forever by project id (and a later Forever patch)", ns.API.forever == true and ns.C.driver ~= nil)
  GetBuildInfo = realBuild
  local f = tick(ns)

  -- 4. What it reads comes from Forever's own functions
  check("talent trees read from the traits system", table.concat(ns.API.talentPoints() or {}, "/") == "0/11/0", table.concat(ns.API.talentPoints() or {}, "/"))
  check("so the spec is picked from your talents", ns.C.profile.spec == "Enhancement" and ns.C.profileWhy == "talents", tostring(ns.C.profileWhy))
  M.P.oneTree = true
  check("an unexpected tree layout is 'unknown', not a guess", ns.API.talentPoints() == nil)
  M.P.oneTree = nil
  M.P.talentPoints = 3
  check("unspent talent points", ns.API.unspentTalents() == 3, tostring(ns.API.unspentTalents()))
  M.P.talentPoints = 0
  check("none to spend", ns.API.unspentTalents() == 0, tostring(ns.API.unspentTalents()))
  check("weapon buff: none", ns.API.mainHandBuff() == false)
  M.P.mainHand = true
  check("weapon buff: Forever's imbue layer", ns.API.mainHandBuff() == true)
  M.P.combat = true
  check("weapon buff hidden in combat reads as unknown", ns.API.mainHandBuff() == nil)
  M.P.combat = false
  M.P.page = 3
  check("bar page from C_ActionBar", ns.API.barPage() == 3)
  M.P.keyActions = { ["SHIFT-2"] = "ACTIONPAGE2" }
  SlashCmdList.CLASSCOACH("pages")
  check("/coach pages goes back to page 1 through C_ActionBar", M.P.page == 1, M.P.page)
  M.printed = {}
  SlashCmdList.CLASSCOACH("errors on")
  check("/coach errors on sets the game setting through C_CVar", M.cvars.scriptErrors == "1" and table.concat(M.printed, " "):find("will now show errors") ~= nil,
    table.concat(M.printed, " "))
  local realSet = C_CVar.SetCVar
  C_CVar.SetCVar = function() end
  M.printed = {}
  SlashCmdList.CLASSCOACH("errors off")
  check("and says so when the game refuses", table.concat(M.printed, " "):find("/console scriptErrors 0", 1, true) ~= nil, table.concat(M.printed, " "))
  C_CVar.SetCVar = realSet
  M.printed = {}
  SlashCmdList.CLASSCOACH("check")
  local report = table.concat(M.printed, "\n")
  check("/coach check names the client", report:find("WoW Forever: yes", 1, true) ~= nil and report:find("missing on this client: none", 1, true) ~= nil,
    report:sub(1, 300))
  local realTex = C_ActionBar.GetActionTexture
  C_ActionBar.GetActionTexture = nil
  M.printed = {}
  SlashCmdList.CLASSCOACH("check")
  check("and lists a Forever function the client lacks", table.concat(M.printed, "\n"):find("missing on this client: C_ActionBar.GetActionTexture", 1, true) ~= nil,
    table.concat(M.printed, "\n"):sub(1, 400))
  C_ActionBar.GetActionTexture = realTex

  -- 5. The advice is Forever's
  local data = ns.JourneyData
  local function has(list, text) for _, e in ipairs(list) do if tostring(e[3] or e.text):find(text, 1, true) then return e end end end
  local thanes, krol, wet = has(data.dungeons.Alliance, "Hall of Thanes"), has(data.dungeons.Alliance, "Krol'dok Stronghold"), has(data.dungeons.Alliance, "Excavation Site")
  check("Forever's new dungeons at Blizzard's levels", thanes and thanes[1] == 13 and thanes[2] == 18 and krol and krol[1] == 40 and krol[2] == 45
    and wet and wet[1] == 24 and wet[2] == 29)
  check("Forever's new zones", has(data.zones.Alliance, "Riverglades") ~= nil and has(data.zones.Alliance, "Mount Hyjal") ~= nil)
  for _, list in ipairs({ data.zones.Alliance, data.dungeons.Alliance }) do
    for _, e in ipairs(list) do
      if not (type(e[1]) == "number" and type(e[2]) == "number" and e[1] >= 1 and e[1] <= e[2] and e[2] <= 60) then
        check("level range " .. tostring(e[3]), false, tostring(e[1]) .. "-" .. tostring(e[2]))
      end
    end
  end
  check("every level 1-60 has a zone", (function() for l = 1, 60 do local ok = false
    for _, e in ipairs(data.zones.Alliance) do if l >= e[1] and l <= e[2] then ok = true end end
    if not ok then return false end end return true end)())

---------------------------------------------------------------------------
-- Talent guidance: follow a guide's build from the talents you actually have,
-- and mark the next one in the game's own talent window.
elseif SCENARIO == "talents" then
  local links = {}
  assert(loadfile(ROOT .. "/ClassCoach/Data/TalentLinks.lua"))("ClassCoach", links)
  links = links.TalentLinks
  -- the Warlock's tree as Forever has it: one tree, every talent by name
  local MAX = { ["Improved Life Tap"] = 2, ["Siphon Life"] = 1, ["Wrack"] = 1, ["Amplify Curse"] = 1, ["Demonic Sacrifice"] = 1,
    ["Improved Bane of Agony"] = 2, ["Nightfall"] = 2, ["Demonic Energies"] = 2, ["Demonic Aegis"] = 2, ["Pandemic"] = 3,
    ["Improved Drains"] = 3, ["Soul Siphon"] = 3, ["Fel Concentration"] = 3, ["Fel Vitality"] = 3, ["Grim Reach"] = 2 }
  local tree, at, seen = {}, {}, {}
  local symbols = {}
  for sym in pairs(links.iv.WARLOCK) do symbols[#symbols + 1] = sym end
  table.sort(symbols)
  for _, sym in ipairs(symbols) do
    local name = links.iv.WARLOCK[sym]
    if not seen[name] then
      seen[name] = true
      tree[#tree + 1] = { name = name, max = MAX[name] or 5, rank = 0 }
      at[name] = #tree
    end
  end
  local function node(name) return 7000 + at[name] end
  local function spend(name, n) tree[at[name]].rank = n; M.fire("PLAYER_TALENT_UPDATE"); M.advance(3) end
  M.player({
    class = "WARLOCK", className = "Warlock", level = 11, mana = 300, maxMana = 300,
    spells = { [686] = { name = "Shadow Bolt", cost = 25 }, [172] = { name = "Corruption", cost = 35 }, [688] = { name = "Summon Imp", cost = 60 } },
    book = { 686, 172, 688 }, pet = { family = "Imp" },
    actions = { [1] = 686 }, bindings = { ACTIONBUTTON1 = "1" },
  })
  M.P.tree = tree
  ClassCoachDB = { showDone = false }   -- the old "show what you already cast" switch, turned off
  local ns = load()
  check("the old switch becomes 'no steps before'", ClassCoachDB.stepsBefore == 0 and ClassCoachDB.showDone == nil and ClassCoachDB.stepsAfter == 2,
    tostring(ClassCoachDB.stepsBefore))
  ClassCoachDB.stepsBefore = 2
  local function state() return ns.C.refreshTalents() end
  local function marks()
    local out = {}
    local holder = ns.Talents.holder
    if not holder or not ns.Talents.shown then return out end
    for _, m in ipairs(holder.marks) do
      if m.shown and rawget(m, "node") then out[#out + 1] = { node = rawget(m, "node"), role = rawget(m, "role"), text = rawget(m, "text") } end
    end
    return out
  end
  local function banner() return ns.Talents.shown and rawget(ns.Talents.holder.banner, "text") or "(hidden)" end

  -- 1. Reading the talents by name
  local have = ns.API.talents()
  check("every talent of the tree is read by name", have ~= nil and #have.list == #tree and have.byName[ns.API.talentKey("Improved Life Tap")].max == 2,
    have and #have.list)
  check("names compare whatever the punctuation", ns.API.talentKey("Improved  Life-Tap") == ns.API.talentKey("improved life tap"))

  -- 2. Nothing spent: the profile's own build, from its first point
  local s = state()
  check("nothing spent: the default build", s.build.name:find("Warcraft Tavern", 1, true) ~= nil and s.how == "auto", s.build.name)
  check("its first point", ns.Engine.nextTalent(s.plan) == "Improved Corruption (1 of 5)", ns.Engine.nextTalent(s.plan))
  check("every point of the default build is a talent of the tree", #s.plan.unknown == 0, table.concat(s.plan.unknown, ", "))

  -- 3. Two points already in Improved Life Tap, the way the Icy Veins build starts
  spend("Improved Life Tap", 2)
  s = state()
  check("points already spent: the build that fits them", s.build.name:find("Icy Veins", 1, true) ~= nil and s.how == "auto", s.build.name)
  check("continues where you are", ns.Engine.nextTalent(s.plan) == "Suppression (1 of 5)" and s.plan.taken == 2 and s.plan.extra == 0,
    tostring(ns.Engine.nextTalent(s.plan)))
  check("all 51 points of the link are talents of the tree", #s.plan.steps == 51 and #s.plan.unknown == 0, #s.plan.steps .. " / " .. table.concat(s.plan.unknown, ", "))
  tick(ns)
  check("the first-talent-point reminder is gone once a point is spent", not journey(ns):find("First talent point", 1, true), journey(ns))
  M.P.talentPoints = 1; ns.C.journey = nil; M.advance(3); tick(ns)
  check("a point to spend: the suggestion is your build's next talent", journey(ns):find("1 talent point to spend", 1, true) ~= nil
    and journey(ns):find("Suggested: Suppression (1 of 5)", 1, true) ~= nil, journey(ns))

  -- 4. The game's talent window
  check("window closed: nothing drawn", #marks() == 0 and banner() == "(hidden)")
  local win = M.talentWindow(true)
  M.advance(1); tick(ns)
  local m = marks()
  check("window open: NEXT on the next talent", m[1] and m[1].node == node("Suppression") and m[1].role == "next" and m[1].text == "Next",
    m[1] and (m[1].node .. " " .. tostring(m[1].text)))
  check("and 2 on the talent after it", m[2] and m[2].node == node("Improved Corruption") and m[2].text == "2" and m[2].role == "later",
    m[2] and (m[2].node .. " " .. tostring(m[2].text)))
  check("five marks at most, each on a different talent", #m == 5 and (function() local u = {} for _, x in ipairs(m) do if u[x.node] then return false end u[x.node] = true end return true end)(), #m)
  check("the line names the build and the next talent", banner() == "Next: Suppression (1 of 5)"
    and ns.Talents.holder.banner.title.text:find("Icy Veins: Wrack Build", 1, true) ~= nil, banner() .. " / " .. ns.Talents.holder.banner.title.text)
  check("the marks take no clicks and are not the game's children", (function()
    for _, mk in ipairs(ns.Talents.holder.marks) do if rawget(mk, "mouse") ~= false then return false end end
    return rawget(win.buttons[1], "children") == nil end)())
  -- a point clicked but not applied yet moves the mark on at once
  tree[at["Suppression"]].staged = 1
  M.advance(1); tick(ns)
  check("a clicked point counts before Apply", banner() == "Next: Suppression (2 of 5)", banner())
  tree[at["Suppression"]].staged = nil
  -- closing the window removes everything
  win.open = false; M.advance(1); tick(ns)
  check("closed again: marks gone", #marks() == 0 and banner() == "(hidden)")
  win.open = true; M.advance(1); tick(ns)
  ClassCoachDB.talentMarks = false; M.advance(1); tick(ns)
  check("the setting turns the marks off", #marks() == 0)
  ClassCoachDB.talentMarks = true; M.advance(1); tick(ns)

  -- 4b. The look: a glow on the next talent, a veil over talents outside the build, and the card
  local holder = ns.Talents.holder
  local nextButton = win.buttons[at["Suppression"]]
  check("the next talent wears the glow, in the default look", holder.glow.shown and holder.glow.target == nextButton and holder.glow.style == "glow",
    tostring(holder.glow.style))
  local outside, count = ns.Engine.outsideBuild(ns.C.talentState.plan, ns.C.talentState.have), 0
  for _ in pairs(outside) do count = count + 1 end
  check("talents the build never takes are veiled, and only those", count > 0 and ns.Talents.veiled == count and not outside[node("Suppression")]
    and not outside[node("Improved Life Tap")], ns.Talents.veiled .. "/" .. count)
  ClassCoachDB.talentGlow, ClassCoachDB.glowColor = "ants", "blue"; M.advance(1); tick(ns)
  check("the talent's look and colour are yours to pick", holder.glow.style == "ants" and holder.glow.dashes[1].shown and holder.glow.colorKey == "blue")
  ClassCoachDB.talentGlow, ClassCoachDB.glowColor = "glow", "gold"
  ClassCoachDB.talentDim = false; M.advance(1); tick(ns)
  check("dimming can be turned off", ns.Talents.veiled == 0)
  ClassCoachDB.talentDim = true; M.advance(1); tick(ns)
  local card = holder.card
  check("the card sits beside the window, on the side with room", card.shown and card.where == "right", tostring(card.where))
  local row1 = card.rows[1]
  check("the card: the next point first, with its rank and the level the build takes it", row1.shown and row1.name.text == "Suppression"
    and row1.detail.text == "Rank 1 of 5, at level 12" and row1.icon.texture ~= nil, row1.name.text .. " / " .. row1.detail.text)
  check("five points listed, then progress", card.rows[5].shown and card.progress.text == "2 of 51 points", card.progress.text)
  check("no Learn button unless you ask for it", not card.learn.shown)
  win.left, win.right = 400, 1300; M.advance(1); tick(ns)
  check("no room on the right: the card moves to the left", card.where == "left", tostring(card.where))
  win.left, win.right = 100, 1300; M.advance(1); tick(ns)
  check("no room on either side: inside the window's corner", card.where == "inside", tostring(card.where))
  win.left, win.right = nil, nil
  card.left, card.top = 40, 600
  card.scripts.OnDragStop(card)
  M.advance(1); tick(ns)
  check("dragged: the card stays where you put it", card.where == "yours" and ClassCoachDB.talentCardPos[1] == 40 and card.point[2] == UIParent, tostring(card.where))
  ClassCoachDB.talentCardPos = nil; M.advance(1); tick(ns)
  check("put back: beside the window again", card.where == "right", tostring(card.where))
  ClassCoachDB.talentList = false; M.advance(1); tick(ns)
  check("the card can be turned off; the marks stay", not card.shown and #marks() == 5)
  ClassCoachDB.talentList = true; M.advance(1); tick(ns)

  -- 4c. A level-up: the toast names the talent, and Learn now (opt-in) learns it
  M.P.level = 12; M.P.talentPoints = 1
  M.fire("PLAYER_LEVEL_UP", 12); M.advance(1); tick(ns)
  local toast = ns.Talents.toastFrame
  check("level up: a note names the talent your build takes", toast and toast.shown and toast.name.text == "Suppression" and toast.detail.text == "Rank 1/5 of your build"
    and not toast.learn.shown, toast and toast.name.text)
  check("the card now says it is due", card.rows[1].detail.text == "Rank 1 of 5: take it now", card.rows[1].detail.text)
  ClassCoachDB.learnNow = true; M.advance(1); tick(ns)
  check("Learn now turned on: the card offers the talent", card.learn.shown and card.learn.label.text == "Learn Suppression", card.learn.label.text)
  -- the talent window holds a change you have not applied: Learn now waits for you
  tree[at["Nightfall"]].staged = 1
  M.printed, M.learnLog = {}, {}
  card.learn.scripts.OnClick(card.learn)
  check("changes waiting in the talent window: nothing learned, and it says why", #M.learnLog == 0 and table.concat(M.printed, " "):find("Apply or undo them first", 1, true) ~= nil,
    table.concat(M.printed, " "))
  tree[at["Nightfall"]].staged = nil
  M.refuseCommit = true; M.learnLog = {}
  card.learn.scripts.OnClick(card.learn)
  check("the game refuses: the staged point is rolled back", tree[at["Suppression"]].rank == 0 and tree[at["Suppression"]].staged == nil
    and table.concat(M.learnLog, ", ") == "stage Suppression, saved config for spec 265, commit 5, rollback", table.concat(M.learnLog, ", "))
  M.refuseCommit = nil; M.learnLog, M.printed = {}, {}
  card.learn.scripts.OnClick(card.learn)
  check("Learn now: staged and applied the way the talent window does it", tree[at["Suppression"]].rank == 1 and M.P.talentPoints == 0
    and table.concat(M.printed, " "):find("Talent learned", 1, true) ~= nil, table.concat(M.learnLog, ", "))
  M.fire("TRAIT_CONFIG_UPDATED"); M.advance(1); tick(ns)
  check("and the marks move on", banner():find("Suppression (2 of 5)", 1, true) ~= nil and not card.learn.shown, banner())
  M.P.combat = true; M.P.talentPoints = 1; M.learnLog = {}
  check("never in a fight", ns.Talents.learn(node("Suppression")) == "combat" and #M.learnLog == 0)
  M.P.combat = false
  ClassCoachDB.learnNow = false
  tree[at["Suppression"]].rank = 0; M.P.level = 11; M.fire("PLAYER_TALENT_UPDATE"); M.advance(3); tick(ns)
  toast:Hide()

  -- 5. Choosing a build by hand
  M.printed = {}
  SlashCmdList.CLASSCOACH("build")
  local said = table.concat(M.printed, "\n")
  check("/coach build lists the builds and where you are", said:find("1. Warcraft Tavern", 1, true) ~= nil and said:find("2. Icy Veins: Wrack Build", 1, true) ~= nil
    and said:find("<- you follow this one", 1, true) ~= nil and said:find("2 of 51 points taken. Next: Suppression (1 of 5).", 1, true) ~= nil, said)
  SlashCmdList.CLASSCOACH("build 1")
  M.advance(1); tick(ns)
  check("/coach build 1: that build, with your stray points named", ns.C.talentState.how == "chosen" and banner():find("Next: Improved Corruption (1 of 5)", 1, true) ~= nil
    and banner():find("2 points taken earlier than this build does", 1, true) ~= nil, banner())
  local stray = ns.Engine.talentPlan({ { name = "Suppression" } }, ns.API.talents())
  check("points the build never asks for are counted as outside it", stray.extra == 2 and stray.offPlan[1].name == "Improved Life Tap")
  M.printed = {}
  SlashCmdList.CLASSCOACH("build 9")
  check("a number that is not on the list", table.concat(M.printed, " "):find("no build number 9", 1, true) ~= nil and ClassCoachCharDB.build == 1)

  -- 6. A link from a guide
  M.printed = {}
  SlashCmdList.CLASSCOACH("build https://www.icy-veins.com/wow-forever/warlock-talent-calculator#tc-0011122~70959-a8fe1dab")
  M.advance(1); tick(ns)
  check("an Icy Veins link is followed", ClassCoachCharDB.build == "custom" and table.concat(M.printed, " "):find("Following your Icy Veins link: 7 talent points", 1, true) ~= nil
    and ns.C.talentState.build.name == "Your Icy Veins link" and banner() == "Next: Suppression (1 of 5)", table.concat(M.printed, " ") .. " / " .. banner())
  check("the version at the end of the link is not a talent", #ns.C.talentState.plan.steps == 7)
  M.printed = {}
  SlashCmdList.CLASSCOACH("build https://www.warcrafttavern.com/forever/tools/talent-calculator/warlock#?t=A1111122222008")
  local order = ns.C.talentState.build.order
  check("a Warcraft Tavern link is followed", ns.C.talentState.build.name == "Your Warcraft Tavern link" and #order == 13 and order[1].name == "Suppression"
    and order[6].name == "Improved Corruption" and order[11].name == "Improved Life Tap", #order .. " " .. tostring(order[1].name))
  local kept = ClassCoachCharDB.buildLink
  for _, bad in ipairs({
    { "https://www.icy-veins.com/wow-forever/priest-talent-calculator#tc-22222", "priest build" },
    { "https://www.icy-veins.com/wow-forever/warlock-talent-calculator#tc-00!!", "do not know" },
    { "https://example.com/talents", "not one of those" },
    { "https://www.icy-veins.com/wow-forever/warlock-talent-calculator#tc-" .. string.rep("0", 60), "more than 51" },
  }) do
    M.printed = {}
    SlashCmdList.CLASSCOACH("build " .. bad[1])
    check("refused, with the reason: " .. bad[2], table.concat(M.printed, " "):find(bad[2], 1, true) ~= nil and ClassCoachCharDB.buildLink == kept,
      table.concat(M.printed, " "))
  end
  SlashCmdList.CLASSCOACH("build auto")
  check("/coach build auto goes back to the best fit", ClassCoachCharDB.build == "auto" and ns.C.talentState.build.name:find("Icy Veins: Wrack Build", 1, true) ~= nil)

  -- 7. A build that names a talent the game does not have is not guessed at
  local plan = ns.Engine.talentPlan({ { name = "Improved Life Tap" }, { name = "Improved Life Tap" }, { name = "No Such Talent", label = "No Such Talent" },
    { name = "Suppression" } }, ns.API.talents())
  check("an unknown talent stops the plan there", plan.next == 3 and plan.steps[3].known == false and plan.unknown[1] == "No Such Talent"
    and ns.Engine.nextTalent(plan) == "No Such Talent")
  plan = ns.Engine.talentPlan({ { name = "Improved Life Tap" }, { name = "Improved Life Tap" }, { name = "Improved Life Tap" } }, ns.API.talents())
  check("more ranks than the talent has is not followed", plan.next == 3 and plan.steps[3].known == false)

  -- 8. The game hides the talents: fall back to the level, mark nothing, raise nothing
  local realNodes = C_Traits.GetTreeNodes
  C_Traits.GetTreeNodes = function() error("no talents for you") end
  M.fire("PLAYER_TALENT_UPDATE"); M.advance(3); ns.C.journey = nil; tick(ns)
  check("talents unreadable: no marks, and the line says why", #marks() == 0 and banner():find("did not give your talents", 1, true) ~= nil, banner())
  check("and the suggestion goes by your level", journey(ns):find("Suggested:", 1, true) ~= nil and errors() == 0, journey(ns))
  C_Traits.GetTreeNodes = realNodes
  M.talentWindow(nil)
  M.fire("PLAYER_TALENT_UPDATE"); M.advance(3); tick(ns)
  check("no talent window at all: nothing drawn, no error", #marks() == 0 and errors() == 0 and ns.C.lastError == nil, tostring(ns.C.lastError))

  -- 9. Every build link shipped with a profile reads cleanly for its class
  for _, p in ipairs(ns.Profiles.list) do
    for _, b in ipairs(p.builds or {}) do
      local built, why = ns.Engine.decodeBuild(b.link, p.class, links)
      check(p.class .. " build link: " .. b.name, built ~= nil and #built == 51, tostring(why) .. " " .. (built and #built or 0))
    end
  end
  -- 10. Professions on the journey panel
  M.P.talentPoints = 0
  M.P.professions = { { name = "Tailoring", skill = 62, max = 75 }, { name = "Enchanting", skill = 40, max = 75 }, { name = "First Aid", skill = 75, max = 75 } }
  ns.C.journey = nil; M.advance(3); tick(ns)
  check("professions: what to craft next, from the Forever guide", journeyNow(ns):find("Tailoring 62: craft Bolt of Woolen Cloth", 1, true) ~= nil, journeyNow(ns))
  check("professions: at the cap, any profession", journeyNow(ns):find("First Aid 75 of 75: train the next rank", 1, true) ~= nil, journeyNow(ns))
  check("the second profession's next step is there too", journeyNow(ns):find("Enchanting 40: craft Enchant Chest - Inferior Stamina", 1, true) ~= nil, journeyNow(ns))
  check("both slots taken: no suggestion to learn another", not journey(ns):find("Learn T", 1, true), journey(ns))
  M.P.professions[1].skill = 73; ns.C.journey = nil; M.advance(3); tick(ns)
  check("Tailoring near its cap: train Journeyman", journeyNow(ns):find("Tailoring 73 of 75: train the next rank", 1, true) ~= nil, journeyNow(ns))
  ClassCoachDB.remindProfessions = false; ns.C.journey = nil; M.advance(3); tick(ns)
  check("the setting turns profession lines off", not journeyNow(ns):find("Tailoring", 1, true), journeyNow(ns))
  ClassCoachDB.remindProfessions = true
  M.P.professions = nil; ns.C.journey = nil; M.advance(3); tick(ns)
  check("no professions: no step lines, no error", not journeyNow(ns):find("craft", 1, true) and errors() == 0)
  -- Which two to learn, by class and goal
  local E, picks = ns.Engine, ns.ProfessionPicks
  local function pair(class, goal, a, b) return table.concat((E.professionPair(class, picks, goal, a, b)), "+") end
  check("cloth classes level with Tailoring and Enchanting", pair("WARLOCK", "gear") == "Tailoring+Enchanting" and pair("PRIEST", "gear") == "Tailoring+Enchanting", pair("WARLOCK", "gear"))
  check("a Shaman levels with Skinning and Leatherworking, a Warrior with Mining and Blacksmithing",
    pair("SHAMAN", "gear") == "Skinning+Leatherworking" and pair("WARRIOR", "gear") == "Mining+Blacksmithing", pair("SHAMAN", "gear"))
  check("gold: two gatherers", pair("WARLOCK", "gold") == "Mining+Skinning" and pair("DRUID", "gold") == "Herbalism+Skinning", pair("WARLOCK", "gold"))
  check("gear and some gold, for a cloth class: keep Tailoring, add a gatherer", pair("WARLOCK", "balanced") == "Tailoring+Herbalism", pair("WARLOCK", "balanced"))
  check("level 60 pairs differ by class", pair("SHAMAN", "endgame") == "Herbalism+Alchemy" and pair("ROGUE", "endgame") == "Mining+Engineering", pair("SHAMAN", "endgame"))
  check("your own pick comes first, the goal fills the other slot", pair("WARLOCK", "gear", "Alchemy", "auto") == "Alchemy+Tailoring", pair("WARLOCK", "gear", "Alchemy", "auto"))
  check("two picks of your own are followed as they are", pair("WARLOCK", "gear", "Mining", "Engineering") == "Mining+Engineering")
  check("a damaged pick or goal falls back to the class's leveling pair", pair("WARLOCK", "nonsense", "Juggling", 7) == "Tailoring+Enchanting", pair("WARLOCK", "nonsense", "Juggling", 7))
  check("a class with no entry still gets a pair", pair("DEATHKNIGHT", "gear") == "Mining+Skinning")
  for class, byGoal in pairs(picks.byClass) do
    for _, goal in ipairs(picks.goals) do
      local two = byGoal[goal[1]]
      check(class .. " " .. goal[1] .. ": two different professions that have a guide", two and #two == 2 and two[1] ~= two[2]
        and ns.ProfessionData[two[1]] ~= nil and ns.ProfessionData[two[2]] ~= nil and picks.why[goal[1]] ~= nil)
    end
  end
  for _, name in ipairs(picks.primary) do check(name .. " has a guide and is not secondary", ns.ProfessionData[name] ~= nil and not ns.ProfessionData[name].secondary) end
  for _, name in ipairs(picks.secondary) do check(name .. " is a secondary profession with a guide", ns.ProfessionData[name] ~= nil and ns.ProfessionData[name].secondary == true) end

  -- On the journey panel
  M.P.professions = {}; ClassCoachDB.remindProfessions = true; ns.C.journey = nil; M.advance(3); tick(ns)
  check("nothing learned: the class's pair is suggested, and the three free ones", journey(ns):find("Learn Tailoring and Enchanting", 1, true) ~= nil
    and journey(ns):find("Also learn First Aid, Cooking and Fishing", 1, true) ~= nil, journey(ns))
  ClassCoachDB.professionGoal = "gold"; ns.C.journey = nil; M.advance(3); tick(ns)
  check("the goal changes the suggestion", journey(ns):find("Learn Mining and Skinning", 1, true) ~= nil, journey(ns))
  ClassCoachCharDB.professionA = "Alchemy"; ns.C.journey = nil; M.advance(3); tick(ns)
  check("your own pick is suggested first", journey(ns):find("Learn Alchemy and Mining", 1, true) ~= nil, journey(ns))
  ClassCoachCharDB.professionA, ClassCoachDB.professionGoal = "auto", "gear"
  M.P.professions = { { name = "Herbalism", skill = 20, max = 75 } }; ns.C.journey = nil; M.advance(3); tick(ns)
  check("one slot taken by something else: one suggestion for the free slot, and no nagging about your choice",
    journey(ns):find("Learn Tailoring", 1, true) ~= nil and not journey(ns):find("Learn Tailoring and", 1, true), journey(ns))
  check("a gathering profession says what to pick and where", journey(ns):find("Herbalism 20: pick Peacebloom, Silverleaf and Earthroot in your starting zone", 1, true) ~= nil, journey(ns))
  M.P.professions = { { name = "Herbalism", skill = 20, max = 75 }, { name = "Mining", skill = 70, max = 75 }, { name = "Cooking", skill = 10, max = 75 },
    { name = "First Aid", skill = 30, max = 75 } }
  ns.C.journey = nil; M.advance(3); tick(ns)
  check("both slots taken: nothing more to learn there; the missing free one is still named", not journey(ns):find("Learn Tailoring", 1, true)
    and journey(ns):find("Also learn Fishing", 1, true) ~= nil, journey(ns))
  check("at most two what-next lines, your main professions first", journey(ns):find("Herbalism 20: pick", 1, true) ~= nil
    and journey(ns):find("Mining 70 of 75: train the next rank", 1, true) ~= nil and journey(ns):find("Cooking 10: cook Charred Wolf Meat", 1, true) ~= nil
    and not journey(ns):find("First Aid 30", 1, true), journey(ns))
  ClassCoachDB.remindSecondary = false; ns.C.journey = nil; M.advance(3); tick(ns)
  check("the free professions can be switched off", not journey(ns):find("Also learn", 1, true), journey(ns))
  ClassCoachDB.remindSecondary = true
  GetProfessionsReal, GetProfessions = GetProfessions, function() error("not now") end
  ns.C.journey = nil; M.advance(3); tick(ns)
  check("when the game will not say what you have, nothing is suggested", not journey(ns):find("Learn ", 1, true) and errors() == 0, journey(ns))
  GetProfessions = GetProfessionsReal
  SlashCmdList.CLASSCOACH("professions")
  local report = table.concat(E.professionReport(ns.API.professions(), "Affliction Warlock", ns.C.professionOptions()), "\n")
  check("/coach professions: the pair for your goal, what you have, the next steps and the free ones", report:find("Suggested: Tailoring and Enchanting", 1, true) ~= nil
    and report:find("Herbalism 20 of 75: pick Peacebloom", 1, true) ~= nil and report:find("from 70: pick Mageroyal", 1, true) ~= nil
    and report:find("Mining 70 of 75", 1, true) ~= nil and report:find("Free to learn, they use no profession slot: Fishing.", 1, true) ~= nil, report)
  M.P.professions = nil; ns.C.journey = nil; M.advance(3); tick(ns)

  for name, guide in pairs(ns.ProfessionData) do
    check(name .. " says what it is and which word goes before a step", type(guide.about) == "string" and type(guide.verb) == "string" and #guide.tiers == 3)
    local last = 1
    for _, st in ipairs(guide.steps) do
      if st[1] ~= last or st[2] <= st[1] then check(name .. " steps join up at " .. st[1], false, last) end
      last = st[2]
    end
    check(name .. " steps run from 1 to 300", last == 300, last)
  end
  check("level up: the tip is your build's next talent", ns.Engine.levelUp(ns.C.profile, 12, "Suppression (1 of 5)")[3] == "Talent point: Suppression (1 of 5).")
  check("no errors logged", errors() == 0, ClassCoachDB.log and table.concat(ClassCoachDB.log, " || "))

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
---------------------------------------------------------------------------
-- The game's action bars: reset to the coach's layout and undo, potions, and
-- the promise that the addon never changes a frame of the game
---------------------------------------------------------------------------
elseif SCENARIO == "bars" then
  local function warlock()
    M.player({ class = "WARLOCK", className = "Warlock", level = 13, mana = 300, maxMana = 300,
      spells = {
        [686] = { name = "Shadow Bolt", cost = 25 }, [348] = { name = "Immolate", cost = 25 },
        [172] = { name = "Corruption", cost = 35, text = "Corrupts the target, causing 40 Shadow damage over 12 sec." },
        [980] = { name = "Bane of Agony", cost = 25 }, [1454] = { name = "Life Tap", cost = 0 }, [5782] = { name = "Fear", cost = 30 },
        [687] = { name = "Demon Skin", cost = 50 }, [688] = { name = "Summon Imp", cost = 60 }, [5019] = { name = "Shoot", cost = 0 },
      },
      book = { 686, 348, 172, 980, 1454, 5782, 687, 688, 5019 }, equipped = { [18] = 11287 }, talents = { 3, 0, 0 },
      pet = { family = "Imp" },
      -- a player's own mix: a spell on the wrong button, a duplicate, a macro of their own, a mount, leftovers on bar 2 and 3
      actions = { [1] = 980, [3] = 172, [5] = 172, [9] = { macro = "MyOwn" }, [12] = { mount = 4 }, [61] = 687, [66] = 348, [50] = 5782, [25] = 686 },
      bindings = { ACTIONBUTTON1 = "1", ACTIONBUTTON7 = "7", ACTIONBUTTON8 = "8" },
    })
    M.P.buffs = { ["Demon Skin"] = true, ["Well Fed"] = true }
    M.P.professions = { { name = "Tailoring", skill = 50, max = 75 }, { name = "Enchanting", skill = 4, max = 75 }, { name = "First Aid", skill = 20, max = 75 } }
  end
  warlock()
  CreateMacro("MyOwn", "INV_MISC_QUESTIONMARK", "/dance")
  -- the fake client only knows spells, macros and items on a button: teach it "something else", like a mount
  local realInfo = GetActionInfo
  GetActionInfo = function(slot)
    local a = M.P.actions[slot]
    if type(a) == "table" and a.mount then return "summonmount", a.mount end
    return realInfo(slot)
  end
  local ns = load()
  local f = tick(ns)
  M.advance(3); tick(ns)
  local A = M.P.actions
  local function on(slot) local a = A[slot]; return type(a) == "table" and (a.macro or (a.item and ("item:" .. a.item)) or "other") or a end

  -- 1. The promise itself: the fake client's bars cannot be changed without the tests knowing
  local ok = pcall(function() ActionButton1:Hide() end)
  check("the test client refuses any change to a bar of the game and writes it down", not ok and #M.violations == 1 and M.violations[1]:find("ActionButton1:Hide") ~= nil,
    tostring(M.violations[1]))
  pcall(function() MainActionBar.alpha = 0 end); pcall(function() UIParent:SetScale(2) end); pcall(function() MultiBarBottomLeft:SetPoint("CENTER") end)
  pcall(function() RegisterStateDriver(MainActionBar, "visibility", "hide") end)
  check("also a written field, UIParent, and a state driver on a frame of the game", #M.violations == 5, #M.violations)
  M.violations = {}

  -- The same promise, read from the source: none of the calls that are known to upset the game's bars
  -- (hooking the game's functions, opening its settings or panels, reaching for its bar frames or its layout manager)
  local HAZARDS = { "hooksecurefunc", "OpenToCategory", "ShowUIPanel", "HideUIPanel", "EditModeManagerFrame", "ActionBarController", "SetOverrideBinding",
    "UIParent:Hide", "UIParent:SetScale", "UIParent:SetAlpha", "MainMenuBar[:%.]", "MainActionBar[:%.]", "MultiBar%w*[:%.]", "StatusTrackingBarManager", "PetActionBar",
    "SetFrameStrata%(\"TOOLTIP\"%)", "SetFrameStrata%(\"FULLSCREEN" }
  local toc, hazards = io.open(ROOT .. "/ClassCoach/ClassCoach.toc"):read("*a"), {}
  for line in toc:gmatch("[^\r\n]+") do
    if line:match("%.lua%s*$") then
      local file = line:gsub("\\", "/"):gsub("%s+$", "")
      local src = io.open(ROOT .. "/ClassCoach/" .. file):read("*a"):gsub("%-%-[^\n]*", "")   -- comments may name them
      for _, pattern in ipairs(HAZARDS) do
        if src:find(pattern) then hazards[#hazards + 1] = file .. ": " .. pattern end
      end
    end
  end
  check("the source holds none of the calls known to upset the game's bars", #hazards == 0, table.concat(hazards, "; "))

  -- 2. Reset: the three bars become exactly the coach's layout
  SlashCmdList.CLASSCOACH("bar preview")
  check("preview changes nothing", A[1] == 980 and A[5] == 172 and on(9) == "MyOwn")
  SlashCmdList.CLASSCOACH("bar reset")
  check("fight bar: the spells you have, side by side from button 1, with no gap for Drain Life or Drain Soul", barRow(1) == "CC Pull CC Wand 686 1454 980 172 348", barRow(1))
  check("fight bar: what the layout does not use is gone (the duplicate, the macro of your own, the mount)", A[8] == nil and A[9] == nil and A[12] == nil and A[10] == nil,
    tostring(A[9]) .. "/" .. tostring(A[12]))
  check("react bar: Fear on its button, the leftovers gone", A[61] == 5782 and A[66] == nil, tostring(A[61]) .. "/" .. tostring(A[66]))
  check("prepare bar: armor and demon on their buttons, the misplaced Fear gone", A[49] == 687 and A[50] ~= 5782, tostring(A[49]) .. "/" .. tostring(A[50]))
  check("a bar the layout does not use is not touched", A[25] == 686)
  local plan = ns.C.barPlan(ns.C.lastState)
  local exact = true
  for group, first in pairs({ fight = 1, react = 61, prep = 49 }) do
    local want = {}
    for _, e in ipairs(plan[group]) do want[e.index] = e end
    for i = 1, 12 do
      local e, a = want[i], A[first + i - 1]
      local same = (e == nil and a == nil) or (e ~= nil and (a == e.spell or (type(a) == "table" and (a.macro == e.macro and a.macro ~= nil or a.item == e.item and a.item ~= nil))))
      if not same then exact = false end
    end
  end
  check("button for button, the three bars are the plan and nothing else", exact)
  local backup = ClassCoachCharDB.barBackup
  check("what was there is remembered for undo", backup and backup.slots[1].spell == 980 and backup.slots[9].macro == "MyOwn" and backup.slots[12].other == "summonmount"
    and backup.slots[2] == false and backup.slots[25] == nil)
  SlashCmdList.CLASSCOACH("bar reset")
  check("a second reset changes nothing and keeps the layout", barRow(1) == "CC Pull CC Wand 686 1454 980 172 348" and A[61] == 5782, barRow(1))

  -- 3. Undo
  ClassCoachCharDB.barBackup = backup   -- the first reset's memory, as if you undo right away
  SlashCmdList.CLASSCOACH("bar undo")
  check("undo puts spells and macros back where they were and empties what was empty", A[1] == 980 and A[3] == 172 and A[5] == 172 and on(9) == "MyOwn"
    and A[2] == nil and A[4] == nil and A[61] == 687 and A[66] == 348 and A[50] == 5782, tostring(A[1]) .. "/" .. tostring(on(9)) .. "/" .. tostring(A[2]))
  check("the mount could not be put back, and the addon says so honestly", A[12] == nil and ClassCoachCharDB.barBackup == nil)
  SlashCmdList.CLASSCOACH("bar undo")
  check("nothing to undo twice", A[1] == 980)

  -- 4. Not in a fight, and never by accident
  M.P.combat = true; M.fire("PLAYER_REGEN_DISABLED")
  local before = on(1)
  SlashCmdList.CLASSCOACH("bar reset"); SlashCmdList.CLASSCOACH("bar undo")
  check("in a fight the bars are left alone", on(1) == before and ClassCoachCharDB.barBackup == nil and errors() == 0)
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(1); tick(ns)
  ClassCoachCharDB.barBackup = "junk"; SlashCmdList.CLASSCOACH("bar undo")
  ClassCoachCharDB.barBackup = { slots = { [999] = { spell = 1 }, junk = true, [3] = "x" } }; SlashCmdList.CLASSCOACH("bar undo")
  check("a damaged memory of the old bars does no harm", errors() == 0 and A[3] == 172)
  M.P.bars = { false, true }
  A[61] = 348
  SlashCmdList.CLASSCOACH("bar reset")
  check("a bar that is switched off is left alone, not emptied blindly", A[61] == 348 and on(1) == "CC Pull")
  M.P.bars = nil

  -- 5. Potions: found in your bags, on the react bar, and asked for when you have none
  M.P.bag = { { id = 2589, count = 12, class = 7, sub = 5, name = "Linen Cloth", min = 1 } }
  M.fire("BAG_UPDATE_DELAYED"); M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(3); tick(ns); M.advance(3); tick(ns)
  local potionHint = ""
  for _, r in ipairs(ns.Journey.frame.rows) do if rawget(r, "title") == "No healing potion" then potionHint = rawget(r, "hint") end end
  check("level 13 with no potion: the journey list says so, and how to get one", journey(ns):find("No healing potion", 1, true) ~= nil
    and potionHint:find("First Aid makes them in Forever from skill 55 (yours is 20)", 1, true) ~= nil and potionHint:find("works in a fight", 1, true) ~= nil, potionHint)
  check("no bandages with First Aid learned: said too", journey(ns):find("No bandages", 1, true) ~= nil)
  check("a Warlock has Life Tap: no mana potion line", not journey(ns):find("No mana potion", 1, true))
  M.P.bag = {
    { id = 118, count = 3, class = 0, sub = 1, name = "Minor Healing Potion", min = 1 },
    { id = 858, count = 2, class = 0, sub = 1, name = "Lesser Healing Potion", min = 3 },
    { id = 929, count = 1, class = 0, sub = 1, name = "Healing Potion", min = 12 },
    { id = 1710, count = 1, class = 0, sub = 1, name = "Greater Healing Potion", min = 21 },
    { id = 990001, count = 4, class = 0, sub = 1, name = "Minor Discolored Healing Potion", min = 1 },
    { id = 2455, count = 5, class = 0, sub = 1, name = "Minor Mana Potion", min = 5 },
    { id = 1251, count = 6, class = 0, sub = 7, name = "Linen Bandage", min = 1 },
  }
  M.fire("BAG_UPDATE_DELAYED"); M.advance(3); tick(ns); M.advance(3); tick(ns)
  local sup = ns.API.supplies(13)
  check("the strongest healing potion you can use at your level", sup.best.healingpotion.id == 929 and sup.best.manapotion.id == 2455 and sup.kindOf[118] == "healingpotion",
    tostring(sup.best.healingpotion and sup.best.healingpotion.name))
  check("Alchemy's Discolored potions heal at a price: not counted", sup.kindOf[990001] == nil)
  check("with a potion and bandages the lines are gone", not journey(ns):find("No healing potion", 1, true) and not journey(ns):find("No bandages", 1, true), journey(ns))
  SlashCmdList.CLASSCOACH("bar reset")
  check("the healing potion gets its own button on the react bar, right after Fear", barRow(61) == "5782 item:929", barRow(61))
  M.P.bag[3] = { id = 4306, count = 9, class = 7, sub = 5, name = "Silk Cloth", min = 1 }   -- drank it
  M.P.items = M.P.items or {}; M.P.items[929] = 0
  M.fire("BAG_UPDATE_DELAYED"); M.advance(3); tick(ns); M.advance(3); tick(ns)
  SlashCmdList.CLASSCOACH("bar")
  check("used up: the button moves to the next best one you carry", barRow(61) == "5782 item:858", barRow(61))

  -- 5b. Bars that follow what you know: no gaps, and nothing you press moves by itself
  SlashCmdList.CLASSCOACH("bar reset")
  local fightBefore = barRow(1)
  M.P.spells[689] = { name = "Drain Life", cost = 55 }; M.P.book[#M.P.book + 1] = 689; M.P.knownIds[689] = true
  M.fire("SPELLS_CHANGED"); M.advance(3); tick(ns); M.advance(3); tick(ns)
  check("learning a spell changes no bar by itself", barRow(1) == fightBefore and fightBefore == "CC Pull CC Wand 686 1454 980 172 348", barRow(1))
  M.printed = {}
  SlashCmdList.CLASSCOACH("bar")
  check("/coach bar: the new spell takes the first free button, and nothing you already press moves", barRow(1) == fightBefore .. " 689", barRow(1))
  check("...and you are told how to sort the bars", table.concat(M.printed, " | "):find("/coach bar reset sorts all three bars", 1, true) ~= nil, table.concat(M.printed, " | "))
  M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(3); tick(ns)
  SlashCmdList.CLASSCOACH("bar reset")
  check("/coach bar reset: Drain Life goes to its place in the order and the rest closes up", barRow(1) == "CC Pull CC Wand 686 1454 689 980 172 348", barRow(1))
  M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(3); tick(ns)
  -- a hole you made yourself is filled first
  A[4] = nil
  M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(3); tick(ns)
  SlashCmdList.CLASSCOACH("bar")
  check("a button you emptied is filled again before anything goes to the end", barRow(1) == "CC Pull CC Wand 686 1454 689 980 172 348", barRow(1))
  M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(3); tick(ns)
  -- the other way, for who wants a key to mean the same spell for good
  ClassCoachDB.barFixed = true
  SlashCmdList.CLASSCOACH("bar reset")
  check("fixed buttons: every spell on the button of its place in the list, with a gap for Drain Soul", barRow(1) == "CC Pull CC Wand 686 1454 689 - 980 172 348", barRow(1))
  check("fixed buttons: the react and prepare bars keep their gaps too", A[61] == 5782 and A[62] == nil and on(66) == "item:858" and A[49] == 687 and A[51] == nil and on(59) == "item:1251",
    barRow(61) .. " / " .. barRow(49))
  M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(3); tick(ns)
  M.P.spells[1120] = { name = "Drain Soul", cost = 55 }; M.P.book[#M.P.book + 1] = 1120; M.P.knownIds[1120] = true
  M.fire("SPELLS_CHANGED"); M.advance(3); tick(ns); M.advance(3); tick(ns)
  SlashCmdList.CLASSCOACH("bar")
  check("fixed buttons: a new spell fills its own gap", barRow(1) == "CC Pull CC Wand 686 1454 689 1120 980 172 348", barRow(1))
  M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(3); tick(ns)
  -- back to the default from a layout with gaps: replace leaves nothing on a bar twice
  ClassCoachDB.barFixed = false
  SlashCmdList.CLASSCOACH("bar replace")
  check("/coach bar replace from a layout with gaps: closed up, nothing twice", barRow(61) == "5782 item:858" and barRow(49):find("^687 688 ") ~= nil and not barRow(49):find("-", 1, true),
    barRow(61) .. " / " .. barRow(49))
  local plan2, tidy = ns.C.barPlan(ns.C.lastState), true
  for _, entries in pairs(plan2) do
    for i, e in ipairs(entries) do if e.index ~= i then tidy = false end end
  end
  check("the plan itself numbers the buttons 1, 2, 3... on every bar", tidy)
  M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(3); tick(ns)
  M.P.bagSizes = { 6, 0, 0, 6 }
  ns.C.journey = nil; M.advance(3); tick(ns)
  check("an empty bag slot is pointed out", journey(ns):find("2 bag slots are empty", 1, true) ~= nil, journey(ns))
  M.P.bagSizes = nil
  SlashCmdList.CLASSCOACH("tips")
  check("/coach tips: ten habits, each one line", #ns.JourneyData.tips == 10)

  -- 6. The watcher: when the game's bars leave the screen, the addon notices and says what it saw
  M.advance(2); tick(ns)
  check("bars on screen: nothing to report", (ns.C.barsLost or 0) == 0 and ns.C.barsSeen == true)
  target({ name = "Gnoll", level = 9, hostile = true, guid = "Creature-80" }); M.advance(1); tick(ns)
  cast(980); M.advance(0.4); M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  M.fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "MainActionBar:ClearAllPoints()")
  M.gameFrames.MainActionBar.points = 0; M.gameFrames.MainActionBar.shown = false
  local said = {}
  local realPrint = print
  print = function(text) said[#said + 1] = tostring(text) end
  M.advance(1.5); tick(ns); M.advance(1.5); tick(ns); M.advance(1.5); tick(ns)
  print = realPrint
  local all = table.concat(said, "\n")
  check("the main bar vanishing in a fight is noticed once", ns.C.barsLost == 1 and ns.C.barsGone ~= nil, tostring(ns.C.barsLost))
  check("it names the frame, what the game blamed, and how to get the bars back", all:find("MainActionBar is hidden", 1, true) ~= nil
    and all:find("SomeOtherAddon -> MainActionBar:ClearAllPoints()", 1, true) ~= nil and all:find("/reload", 1, true) ~= nil
    and select(2, all:gsub("left the screen", "")) == 1, all)
  check("noticing it changed nothing on the game's frames", #M.violations == 0, table.concat(M.violations, " | "))
  said = {}
  print = function(text) said[#said + 1] = tostring(text) end
  SlashCmdList.CLASSCOACH("bars")
  print = realPrint
  all = table.concat(said, "\n")
  check("/coach bars: each bar, the fight, and what the game blocked", all:find("main bar: NOT on screen: MainActionBar is hidden", 1, true) ~= nil
    and all:find("Action Bar 2: on screen", 1, true) ~= nil and all:find("in combat true", 1, true) ~= nil and all:find("SomeOtherAddon", 1, true) ~= nil, all)
  M.gameFrames.MainActionBar.shown = true; M.gameFrames.MainActionBar.points = 1
  M.advance(1.5); tick(ns)
  check("back on screen: the watcher is ready for a next time", ns.C.barsGone == nil and ns.C.barsLost == 1)
  M.gameFrames.MainActionBar.shown = true; M.gameFrames.MainActionBar.points = 0   -- shown, but its anchor was lost
  M.gameFrames.ActionButton1.shown = false
  M.advance(1.5); tick(ns)
  check("a button hidden on its own is told apart from a bar that lost its place", ns.C.barsLost == 2 and ns.C.barsGone.bars[1].why == "ActionButton1 is hidden", ns.C.barsGone and ns.C.barsGone.bars[1].why)
  M.gameFrames.ActionButton1.shown = true; M.gameFrames.MainActionBar.points = 1; M.advance(1.5); tick(ns)
  HasVehicleActionBar = function() return true end
  M.gameFrames.MainActionBar.shown = false; M.advance(1.5); tick(ns)
  check("a vehicle bar in their place is the game's doing: no alarm", ns.C.barsLost == 2)
  HasVehicleActionBar = nil
  M.gameFrames.MainActionBar.shown = true; M.advance(1.5); tick(ns)
  UIParent.shown = false; M.gameFrames.MainActionBar.shown = false; M.advance(1.5); tick(ns)
  check("hiding the whole interface yourself (Alt+Z): no alarm", ns.C.barsLost == 2)
  UIParent.shown = true; M.gameFrames.MainActionBar.shown = true
  ClassCoachDB.log = nil   -- the incidents above were written to the log on purpose
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(1); target(nil); M.advance(1); tick(ns)

  -- 7. A whole fight, a level up, the talent window, the demo and every command: still hands off
  for _, command in ipairs({ "check", "macros", "bar", "smart", "pages", "demo", "demo", "fonts", "fonts", "reset", "professions", "bars" }) do SlashCmdList.CLASSCOACH(command) end
  ClassCoachDB.barGlow = "sparkles"
  target({ name = "Gnoll", level = 9, hostile = true, guid = "Creature-81" }); M.advance(1); tick(ns)
  cast(980); M.advance(0.4); M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  for i = 1, 60 do
    M.advance(0.5); tick(ns)
    if i == 5 then cast(172) elseif i == 9 then cast(348) elseif i == 20 then M.P.page = 2 elseif i == 30 then M.P.page = 1 end
    if ns.BarGlow.holder and ns.BarGlow.holder.scripts.OnUpdate then ns.BarGlow.holder.scripts.OnUpdate(ns.BarGlow.holder, 0.1) end
  end
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(1); target(nil)
  M.P.level = 14; M.fire("PLAYER_LEVEL_UP", 14); M.advance(2); tick(ns)
  M.talentWindow(true); M.advance(1); tick(ns); M.talentWindow(false); M.advance(1); tick(ns)
  check("no errors logged", errors() == 0, ClassCoachDB.log and table.concat(ClassCoachDB.log, " || "))
  check("no tick error", ns.C.lastError == nil, ns.C.lastError)

---------------------------------------------------------------------------
-- The ring: fonts, the cue, the lit bar button, click to cast, the demo
---------------------------------------------------------------------------
elseif SCENARIO == "focus" then
  local function warlock()
    M.player({ class = "WARLOCK", className = "Warlock", level = 12, mana = 300, maxMana = 300,
      spells = {
        [686] = { name = "Shadow Bolt", cost = 25 }, [348] = { name = "Immolate", cost = 25 },
        [172] = { name = "Corruption", cost = 35, text = "Corrupts the target, causing 40 Shadow damage over 12 sec." },
        [980] = { name = "Bane of Agony", cost = 25 }, [1454] = { name = "Life Tap", cost = 0 },
        [687] = { name = "Demon Skin", cost = 50 }, [688] = { name = "Summon Imp", cost = 60 }, [5019] = { name = "Shoot", cost = 0 },
      },
      book = { 686, 348, 172, 980, 1454, 687, 688, 5019 }, equipped = { [18] = 11287 }, talents = { 3, 0, 0 },
      pet = { family = "Imp" },
      actions = { [7] = 980, [8] = 172, [62] = 5019 }, bindings = { ACTIONBUTTON7 = "7", ACTIONBUTTON8 = "8", MULTIACTIONBAR1BUTTON2 = "SHIFT-2" },
    })
    M.P.buffs = { ["Demon Skin"] = true, ["Well Fed"] = true }
  end
  warlock()
  local ns = load()
  local f = tick(ns)
  local C = ns.Style.COLORS

  -- Text: the game's own fonts unless you ask for ClassCoach's typefaces
  check("by default every text is one of the game's own fonts, picked by size, and no font file is set on it",
    f.name.template == "GameFontHighlightLarge" and f.why.template == "GameFontHighlight" and f.barText.template == "GameFontHighlightSmallOutline"
    and rawget(f.name, "font") == nil and rawget(f.why, "font") == nil and rawget(f.key, "font") == nil, tostring(f.name.template) .. " / " .. tostring(f.barText.template))
  check("a size the game has no font for takes the next one down, and never a font that does not exist",
    f.key.template == "GameFontHighlight" and f.dots.template == "GameFontHighlightSmall" and _G.GameFontHighlightMedium == nil, tostring(f.key.template))
  local S = ns.Style
  ClassCoachDB.ownFonts = true; tick(ns)
  check("ClassCoach's typefaces are never set while the addon loads", not S.ownFonts and rawget(f.name, "font") == nil)
  M.advance(4); f = tick(ns)
  check("a few seconds after login they go on: the name in Marcellus, the rest in Inter", S.ownFonts and f.name.font[1]:find("Marcellus%-Regular%.ttf$") ~= nil and f.name.font[2] == 19
    and f.why.font[1]:find("Inter%-Regular%.ttf$") ~= nil and f.key.font[1]:find("Inter%-Bold%.ttf$") ~= nil and f.barText.font[3] == "OUTLINE"
    and S.dressed > 40 and S.plain == 0, tostring(S.dressed) .. "/" .. tostring(S.plain))
  check("the level is not set in Marcellus, whose 1 reads as a capital I", ns.Journey.frame.title.font[1]:find("Inter%-Bold%.ttf$") ~= nil)
  ClassCoachDB.ownFonts = false; f = tick(ns)
  check("switched off, every text is back on its game font at once", not S.ownFonts and rawget(f.name, "font") == nil and rawget(f.name, "fontObject") == GameFontHighlightLarge
    and S.dressed == 0, tostring(S.dressed))
  -- a client that refuses the files
  M.refuseFonts = true
  ClassCoachDB.ownFonts = true; f = tick(ns)
  check("a typeface the game refuses: the text keeps its game font", rawget(f.name, "font") == nil and rawget(f.name, "fontObject") == GameFontHighlightLarge
    and S.fontMissing ~= nil and S.dressed == 0 and S.pending == true, tostring(S.fontMissing))
  local sets = 0
  local realSetFont = f.name.SetFont
  f.name.SetFont = function(...) sets = sets + 1; return realSetFont(...) end
  for _ = 1, 20 do M.advance(2.1); tick(ns) end
  check("it is tried a few more times, then left alone", sets == 4 and S.pending == false, sets)
  M.refuseFonts = false
  ClassCoachDB.ownFonts = false; tick(ns); ClassCoachDB.ownFonts = true; f = tick(ns)
  check("switching the setting off and on tries again", f.name.font ~= nil and S.plain == 0, tostring(S.plain))
  -- what the first test in the game showed: a typeface that is set and still draws nothing
  f.why.GetStringWidth = function(self) return rawget(self, "font") and 0 or 40 end
  M.advance(1); f = tick(ns)
  check("a text that comes out with no width is put back on the game's font, once", rawget(f.why, "fontObject") == GameFontHighlight and rawget(f.why, "font") == nil
    and f.why.text ~= "" and S.healed == 1, tostring(S.healed))
  for _ = 1, 5 do M.advance(2.1); tick(ns) end
  check("and is left alone after that", S.healed == 1 and rawget(f.why, "font") == nil)
  check("one text in words, for /coach check", S.describe(f.name):find("^Marcellus%-Regular%.ttf 19, %d+ letters, width %?, shown$") ~= nil, S.describe(f.name))
  f.why.GetStringWidth = nil
  ClassCoachDB.ownFonts = false; f = tick(ns)
  local card = S.probe()
  check("/coach fonts: a line of results per typeface and for the game's own font, every size plain and with a width", #card == 5 and card[1]:find("^Inter%-Regular  9:") ~= nil
    and card[4]:find("^game font") ~= nil and select(2, card[3]:gsub("%d+:%u%w%p/%u%w%p", "")) == 10 and S.probeFrame.shown, card[3])
  check("typing it again hides the card", #S.probe() == 0 and not S.probeFrame.shown)
  SlashCmdList.CLASSCOACH("fonts"); SlashCmdList.CLASSCOACH("fonts")
  check("icons are cut round with the game's mask", rawget(f.icon, "mask") ~= nil and rawget(f.done[1].icon, "mask") ~= nil)
  check("the ring is gold and the mana bar is the game's status bar, 100 by 5", f.ring.color[1] == C.accent[1] and rawget(f.bar, "width") == 100 and rawget(f.bar, "height") == 5)

  -- Before a fight: the drink reminder, spelled out
  M.P.mana = 90; M.advance(3); f = tick(ns)
  check("low mana before a pull: an amber mark and the reason in words", missing(ns):find("Mana 30%%") ~= nil and f.leftLabel.text == "before you pull"
    and f.status.text:find("Life Tap") ~= nil and f.status.shown, missing(ns) .. " / " .. f.status.text)
  check("the mana bar turns amber as the advice changes", f.bar.barColor[1] == C.warn[1] and f.barText.text == "30%", tostring(f.bar.barColor[1]) .. " " .. f.barText.text)
  M.P.mana = 300; M.advance(3); f = tick(ns)
  check("nothing missing: no mark, no caption, no line", missing(ns) == "" and f.status.text == "" and not f.leftLabel.shown)

  -- The step to press, lit on the action bar
  target({ name = "Boar", level = 11, hostile = true, guid = "Creature-70" })
  M.advance(1); f = tick(ns)
  local glow = ns.BarGlow
  check("with an enemy targeted the opener's bar button is lit", f.name.text == "Bane of Agony" and glow.slot == 7 and glow.holder.shown and glow.button == ActionButton7, tostring(glow.slot))
  check("the highlight lies over the button and takes no clicks", rawget(glow.holder, "mouse") == false and glow.holder.name == "ClassCoachBarGlow")
  check("the default look is the glow", glow.holder.style == "glow" and glow.holder.halo.shown and not glow.holder.sparks[1].shown and rawget(glow.holder.halo, "width") == 90)
  ClassCoachDB.barGlow = "sparkles"; tick(ns)
  glow.holder.width, glow.holder.height = 45, 45
  glow.holder.scripts.OnUpdate(glow.holder, 0.1)
  local sx, sy = glow.holder.sparks[1].point[4], glow.holder.sparks[1].point[5]
  check("sparkles: points run along the button's edge", glow.holder.style == "sparkles" and glow.holder.sparks[1].shown and not glow.holder.halo.shown
    and (sx == 0 or sx == 45 or sy == 0 or sy == -45), tostring(sx) .. "," .. tostring(sy))
  local x1, y1 = ns.BarGlow.around(0, 40, 20)
  local x2, y2 = ns.BarGlow.around(0.5, 40, 20)
  local x3, y3 = ns.BarGlow.around(7.25, 40, 20)
  check("a trip around the button: start at the top left, halfway at the bottom right, any number of laps", x1 == 0 and y1 == 0 and x2 == 40 and y2 == -20 and x3 == 30 and y3 == 0,
    x3 .. "," .. y3)
  ClassCoachDB.barGlow = "frame"; tick(ns)
  check("frame: steady, no animation running", glow.holder.style == "frame" and glow.holder.scripts.OnUpdate == nil and glow.holder.edges[1].shown)
  ClassCoachDB.barGlow = "off"; tick(ns)
  check("off: nothing lit", glow.slot == nil and not glow.holder.shown)
  ClassCoachDB.barGlow = "glow"; tick(ns)
  M.gameFrames.ActionButton7.shown = false; tick(ns)
  check("a button that is not on screen is not lit", glow.slot == nil and not glow.holder.shown)
  M.gameFrames.ActionButton7.shown = true; tick(ns)
  M.P.page = 2; M.advance(1); tick(ns)
  check("main bar on another page: its buttons show other spells, so none is lit", glow.slot == nil)
  M.P.page = 1; M.advance(1); tick(ns)
  check("back on page one it is lit again", glow.slot == 7)
  M.gameFrames.ActionButton7.action = 79; tick(ns)
  check("in a stance or form the main bar's buttons hold other spells: the wrong button is never lit", glow.slot == nil)
  M.gameFrames.ActionButton7.action = 7; tick(ns)
  check("a button that says it shows this slot is lit", glow.slot == 7)
  ClassCoachDB.showCoach = false; tick(ns)
  check("coach hidden: nothing lit, nothing clickable", glow.slot == nil and ns.Click.holder == nil or #ns.Click.describe() == 0)
  ClassCoachDB.showCoach = true; tick(ns)
  SlashCmdList.CLASSCOACH("set barGlow Sparkles")
  check("/coach set takes a choice by its name, whatever the capitals", ClassCoachDB.barGlow == "sparkles", tostring(ClassCoachDB.barGlow))
  SlashCmdList.CLASSCOACH("set barGlow rainbows")
  check("and refuses one that is not on the list", ClassCoachDB.barGlow == "sparkles")
  ClassCoachDB.barGlow = "glow"; tick(ns)

  -- Click to cast, before a fight
  local click = ns.Click
  check("the click buttons are the game's secure buttons, hidden by the game in a fight", click.holder ~= nil and click.holder.secure and click.buttons[1].secure
    and M.drivers.visibility.frame == click.holder and M.drivers.visibility.conditions == "[combat] hide; show")
  check("they are not anchored to the coach, so dragging it in a fight is never blocked", click.holder.point[2] == UIParent and click.buttons[7].point[2] == click.holder)
  local ring = click.buttons[7]
  check("the ring casts the opener", ring.on and ring:GetAttribute("type") == "spell" and ring:GetAttribute("spell") == "Bane of Agony" and rawget(ring, "width") == 84,
    tostring(ring:GetAttribute("spell")))
  check("the next steps cast themselves", click.buttons[8].on and click.buttons[8]:GetAttribute("spell") == "Corruption" and click.buttons[8].point[4] == 74,
    tostring(click.buttons[8]:GetAttribute("spell")))
  M.P.mana = 90; M.advance(3); tick(ns)
  check("an amber mark casts what fixes it", click.buttons[1].on and click.buttons[1]:GetAttribute("spell") == "Life Tap" and click.buttons[1].point[4] == -74,
    table.concat(click.describe(), ", "))
  click.buttons[1].scripts.OnEnter(click.buttons[1])
  M.P.mana = 300; M.advance(3); tick(ns)
  check("fixed: its button is gone again", not click.buttons[1].on and not click.buttons[1].shown)
  target(nil); M.advance(1); tick(ns)
  check("nothing targeted: the plan is a picture, not a button (no pulling by accident)", not ring.on and not click.buttons[8].on)
  target({ name = "Boar", level = 11, hostile = true, guid = "Creature-70" }); M.advance(1); tick(ns)
  ClassCoachDB.clickable = false; tick(ns)
  check("switched off in the settings: no buttons", #click.describe() == 0)
  ClassCoachDB.clickable = true; tick(ns)
  check("and back on", ring.on and #click.describe() >= 2, #click.describe())
  cast(980); M.advance(0.4); M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true
  local escaped = 0
  for _ = 1, 20 do
    local ok = pcall(tick, ns)
    if not ok then escaped = escaped + 1 end
    M.advance(0.5)
  end
  check("in a fight the addon never touches a click button (the fake client raises an error if it does)", escaped == 0 and errors() == 0 and ns.C.lastError == nil,
    tostring(ns.C.lastError) .. " " .. tostring(ClassCoachDB.log and ClassCoachDB.log[1]))
  check("and what a click casts did not change with the coach's advice", ring:GetAttribute("spell") == "Bane of Agony" and ns.Panel.frame.name.text ~= "Bane of Agony",
    ns.Panel.frame.name.text)
  check("the lit button follows the coach during the fight", glow.slot == (ns.C.slots[ns.Panel.frame.name.text]), tostring(glow.slot))

  -- The cue: quiet while the fight is steady, a pulse and a sound when a new key is needed
  f = tick(ns)
  cast(172); M.advance(1.5); f = tick(ns); cast(348); M.advance(1.5); f = tick(ns)
  check("the steady part of the fight: the wand, no pulse", f.name.text == "Shoot" and (ns.Panel.cues or 0) == 0 and #M.sounds == 0, f.name.text .. " " .. tostring(ns.Panel.cues))
  check("the wand's own button is lit to start it", glow.slot == 62 and glow.button == MultiBarBottomLeftButton2, tostring(glow.slot))
  M.P.repeating = 5019; M.advance(0.5); f = tick(ns)
  check("a wand that is firing is not lit: there is nothing to press", f.name.text == "Shoot" and glow.slot == nil, tostring(glow.slot))
  M.P.repeating = nil
  for _ = 1, 30 do M.advance(0.5); f = tick(ns); if f.name.text ~= "Shoot" then break end end
  check("a spell ran out: the ring pulses once and a soft click plays", f.name.text ~= "Shoot" and ns.Panel.cues == 1 and #M.sounds == 1 and M.sounds[1] == 856
    and f.scripts.OnUpdate ~= nil, f.name.text .. " cues " .. tostring(ns.Panel.cues) .. " sounds " .. #M.sounds)
  M.advance(0.3); f.scripts.OnUpdate(f, 0.3)
  check("the pulse grows out of the ring", rawget(f.pulseFrame, "width") > 84 * 0.95 and (rawget(f.pulse, "alpha") or 0) > 0)
  tick(ns); tick(ns)
  check("the same step does not pulse twice", ns.Panel.cues == 1)
  M.advance(2); f.scripts.OnUpdate(f, 0.1)
  check("the pulse ends and stops running", f.scripts.OnUpdate == nil and rawget(f.pulse, "alpha") == 0)
  ClassCoachDB.cueSound = "off"; ClassCoachDB.cue = false
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.6); target(nil); M.advance(1); tick(ns)

  -- A step with no key
  local function fightTo(guid)
    target({ name = "Wolf", level = 11, hostile = true, guid = guid }); M.advance(1); tick(ns)
    cast(980); M.advance(0.4); M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true; M.advance(1.2)
    return tick(ns)
  end
  local function leave()
    M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.6); target(nil); M.advance(1); tick(ns)
  end
  M.P.bindings.ACTIONBUTTON8 = nil; M.fire("UPDATE_BINDINGS"); M.fire("ACTIONBAR_SLOT_CHANGED", 8); M.advance(3)
  f = fightTo("Creature-73")
  check("on a bar but without a key: its button is lit and nobody is nagged", f.name.text == "Corruption" and glow.slot == 8 and not f.keyBadge.shown
    and not f.status.text:find("not on your action bars"), f.name.text .. " / " .. f.status.text .. " / " .. tostring(glow.slot))
  leave()
  M.P.actions[8] = nil; M.P.bindings.ACTIONBUTTON8 = "8"; M.fire("ACTIONBAR_SLOT_CHANGED", 8); M.advance(3)
  f = fightTo("Creature-71")
  check("a step that is on no bar: the coach says where to get it", f.name.text == "Corruption" and f.status.text:find("Corruption is not on your action bars") ~= nil
    and not f.keyBadge.shown and glow.slot == nil, f.name.text .. " / " .. f.status.text)
  leave()

  -- The demo
  SlashCmdList.CLASSCOACH("demo")
  local seen, cuesBefore = {}, ns.Panel.cues
  ClassCoachDB.cue = true
  for _ = 1, 80 do
    M.advance(0.5); f = tick(ns)
    seen[f.msg.text] = true
    check("demo: nothing real is lit or clickable", glow.slot == nil and #click.describe() == 0)
    if f.msg.text:find("Demo 7 of 7") then break end
  end
  local states = 0
  for text in pairs(seen) do if text:find("^Demo %d of 7") then states = states + 1 end end
  check("/coach demo plays seven states with your own spells", states == 7 and ns.C.demo ~= nil, states)
  check("while it plays, the coach says how to move it", f.hint.shown and f.hint.text == "Drag the ring to move the coach")
  check("the demo shows the pulse too", ns.Panel.cues > cuesBefore)
  target({ name = "Wolf", level = 11, hostile = true, guid = "Creature-72" }); M.advance(1)
  M.fire("PLAYER_REGEN_DISABLED"); M.P.combat = true; M.advance(0.5); f = tick(ns)
  check("a real fight ends the demo at once", ns.C.demo == nil and f.name.text ~= "")
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.6)
  SlashCmdList.CLASSCOACH("demo"); SlashCmdList.CLASSCOACH("demo")
  check("/coach demo again stops it, and the hint goes", ns.C.demo == nil and not f.hint.shown)
  SlashCmdList.CLASSCOACH("check")
  check("no errors logged", errors() == 0, ClassCoachDB.log and table.concat(ClassCoachDB.log, " || "))
  check("no tick error", ns.C.lastError == nil, ns.C.lastError)

---------------------------------------------------------------------------
-- The settings window, the spellbook, the quiet coach, sharing settings, and
-- a plan that follows your mana on a client that hides it.
elseif SCENARIO == "ui" then
  M.player({ class = "WARLOCK", className = "Warlock", level = 13, mana = 300, maxMana = 300,
    spells = {
      [686] = { name = "Shadow Bolt", cost = 25 }, [348] = { name = "Immolate", cost = 25 },
      [172] = { name = "Corruption", cost = 35 }, [980] = { name = "Bane of Agony", cost = 25 }, [1454] = { name = "Life Tap", cost = 0 },
      [687] = { name = "Demon Skin", cost = 50 }, [688] = { name = "Summon Imp", cost = 60 }, [5019] = { name = "Shoot", cost = 0 },
    },
    book = { 686, 348, 172, 980, 1454, 687, 688, 5019 }, equipped = { [18] = 11287 }, talents = { 3, 0, 0 },
    pet = { family = "Imp" },
    actions = { [8] = 172, [62] = 5019 }, bindings = { ACTIONBUTTON8 = "8", MULTIACTIONBAR1BUTTON2 = "SHIFT-2" },
  })
  M.P.buffs = { ["Demon Skin"] = true, ["Well Fed"] = true }
  local ns = load()
  local f = tick(ns)
  local G, W = ns.Glow, ns.Window

  -- 1. The shared glow
  local g = G.new()
  local spot = CreateFrame("Frame")
  spot:SetSize(40, 40)
  check("a glow lies over its target and takes no clicks", G.show(g, spot, "ants", "blue") and g.shown and g.target == spot and rawget(g, "mouse") == false)
  check("marching ants: dashes in the colour you picked, and they move", g.dashes[1].shown and not g.halo.shown and g.colorKey == "blue" and g.scripts.OnUpdate ~= nil)
  g.width, g.height = 40, 40
  g.scripts.OnUpdate(g, 0.1)
  local p1 = g.dashes[1].point[4]; M.advance(0.5); g.scripts.OnUpdate(g, 0.1)
  check("...along the edge", g.dashes[1].point[4] ~= p1)
  local _, _, flat = G.around(0.1, 40, 40)
  local _, _, upright = G.around(0.35, 40, 40)
  check("a dash lies flat on the top edge and upright on the sides", flat == true and upright == false)
  check("a style that does not exist becomes the glow", G.style("rainbow") == "glow" and G.style("off") == "off")
  G.show(g, spot, "off", "gold")
  check("off hides it", not g.shown and rawget(g, "target") == nil)

  -- 2. A step that is on no bar lights up in the spellbook
  target({ name = "Boar", level = 12, hostile = true, guid = "Creature-1" })
  M.advance(1); f = tick(ns)
  check("the opener is on no bar: the coach says the spellbook lights it", f.name.text == "Bane of Agony" and f.status.text:find("Open your spellbook (it lights up there)", 1, true) ~= nil,
    f.name.text .. " / " .. f.status.text)
  M.spellbook(true, { "Shadow Bolt", "Corruption" })
  M.advance(1); f = tick(ns)
  check("the book is open on another page: turn the pages", f.status.text:find("on another page of your spellbook", 1, true) ~= nil, f.status.text)
  M.spellbook(true, { "Shadow Bolt", "Bane of Agony", "Corruption" })
  M.advance(1); f = tick(ns)
  local book = ns.Spellbook
  check("on this page: it is lit, ready to drag", book.lit == "Bane of Agony" and book.holder.shown and book.holder.target == _G.MockSpellButton2
    and f.status.text:find("Drag the lit Bane of Agony", 1, true) ~= nil, f.status.text)
  ClassCoachDB.spellbookGlow = false; M.advance(1); f = tick(ns)
  check("the spellbook light can be turned off", book.lit == nil and not book.holder.shown)
  ClassCoachDB.spellbookGlow = true
  M.P.actions[7] = 980; M.fire("ACTIONBAR_SLOT_CHANGED"); M.advance(3); f = tick(ns)
  check("once it is on a bar the spellbook goes dark", book.lit == nil and not f.status.text:find("spellbook", 1, true), f.status.text)
  M.spellbook(false, {})

  -- 3. Quiet when ready, loud when there is something to do
  target(nil)
  for _ = 1, 12 do M.advance(0.3); f = tick(ns) end
  check("nothing targeted and nothing to prepare: the coach steps back", ns.Panel.quiet and math.abs(rawget(f, "alpha") - 0.5) < 0.01, tostring(rawget(f, "alpha")))
  M.P.buffs["Demon Skin"] = nil; M.fire("UNIT_AURA", "player")
  for _ = 1, 4 do M.advance(0.3); f = tick(ns) end
  check("something to do before the pull: full again at once", not ns.Panel.quiet and rawget(f, "alpha") == 1, tostring(rawget(f, "alpha")))
  M.P.buffs["Demon Skin"] = true; M.fire("UNIT_AURA", "player")
  for _ = 1, 12 do M.advance(0.3); f = tick(ns) end
  target({ name = "Boar", level = 12, hostile = true, guid = "Creature-2" })
  for _ = 1, 3 do M.advance(0.3); f = tick(ns) end
  check("an enemy targeted: full again", not ns.Panel.quiet and rawget(f, "alpha") == 1, tostring(rawget(f, "alpha")))
  ClassCoachDB.readyAlpha = 100; target(nil)
  for _ = 1, 12 do M.advance(0.3); f = tick(ns) end
  check("at 100% it never fades", rawget(f, "alpha") == 1, tostring(rawget(f, "alpha")))
  ClassCoachDB.readyAlpha = 50

  -- 4. The settings window
  check("the first time, the setup page opens by itself, once", W.isOpen() and W.current == "start" and ClassCoachDB.welcomed == true, tostring(W.current))
  local start = W.frame.pages.start
  check("setup: the smart key is not bound yet, and it says so", start.smartLine.text == "Not bound yet.")
  check("setup: the build you follow and its next talent", start.buildLine.text:find("You follow", 1, true) ~= nil, start.buildLine.text)
  W.frame.scripts.OnKeyDown(W.frame, "ESCAPE")
  check("Esc closes it", not W.isOpen())
  SlashCmdList.CLASSCOACH("")
  check("/coach opens it again where you were", W.isOpen() and W.current == "start")
  ClassCoach_OnAddonCompartmentClick()
  check("the minimap's addon menu closes it", not W.isOpen())
  check("the game's own Settings window is never opened by the addon", M.settings.opened == nil)
  local page = W.show("Action bars")
  check("a section page lists its options", page.byKey.barGlow ~= nil and page.byKey.glowColor ~= nil and page.byKey.spellbookGlow ~= nil and page.byKey.scale == nil)
  local tile = page.previews[1]
  check("the preview wears the glow you picked", tile.glow.shown and tile.glow.style == "glow" and tile.glow.target == tile.button)
  page.byKey.barGlow.step(1)
  check("a list steps through its choices and the preview follows", ClassCoachDB.barGlow == "sparkles" and tile.glow.style == "sparkles", tostring(ClassCoachDB.barGlow))
  page.byKey.glowColor.step(1)
  check("the colour too", ClassCoachDB.glowColor == "blue" and tile.glow.colorKey == "blue")
  local sw = page.byKey.spellbookGlow
  sw.scripts.OnClick(sw)
  check("a switch turns a setting off, and shows it", ClassCoachDB.spellbookGlow == false and sw.on == false)
  sw.scripts.OnClick(sw)
  page = W.show("Coach")
  local sl = page.byKey.readyAlpha
  sl.slider.scripts.OnValueChanged(sl.slider, 73)
  check("a slider snaps to its step", ClassCoachDB.readyAlpha == 75 and sl.text.text == "75%", tostring(ClassCoachDB.readyAlpha))
  check("only the page you look at has a lit preview", not tile.glow.shown)
  SlashCmdList.CLASSCOACH("set readyAlpha 40")
  check("/coach set: the open page catches up", sl.text.text == "40%", sl.text.text)
  page = W.show("Talents")
  check("the talent page", page.byKey.learnNow ~= nil and page.byKey.talentDim ~= nil and page.previews[1] ~= nil)
  for _ = 1, 30 do W.scrollBy(48) end
  check("the page scrolls, and stops at its end", (W.offset or 0) >= 0 and W.offset <= math.max(0, page:GetHeight()))
  M.P.combat = true; M.fire("PLAYER_REGEN_DISABLED")
  W.frame.scripts.OnKeyDown(W.frame, "ESCAPE")
  check("in a fight the window leaves the keyboard alone", W.isOpen())
  M.P.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(0.5)

  -- 5. Sharing settings as one line
  page = W.show("share")
  local line = page.out:GetText()
  check("your settings as one line: only what you changed", line:find("^ClassCoach1 ") ~= nil and line:find("barGlow=sparkles", 1, true) ~= nil
    and line:find("glowColor=blue", 1, true) ~= nil and line:find("readyAlpha=40", 1, true) ~= nil and not line:find("showCoach", 1, true), line)
  page.out.scripts.OnTextChanged(page.out, true)
  check("the line cannot be typed over by accident", page.out:GetText() == line)
  page.inBox:SetText("ClassCoach1 scale=1.3 cue=off bogus=1 glowColor=pink professionA=Mining readyAlpha=999")
  local use
  for _, child in ipairs(M.frames) do if rawget(child, "label") and child.label.text == "Use these settings" then use = child end end
  use.scripts.OnClick(use)
  check("a shared line: what fits is used, the rest is named", ClassCoachDB.scale == 1.3 and ClassCoachDB.cue == false and ClassCoachDB.glowColor == "blue"
    and ClassCoachDB.readyAlpha == 40 and page.result.text == "2 settings used. Not used: bogus, glowColor, professionA, readyAlpha.", page.result.text)
  page.inBox:SetText("hello there"); use.scripts.OnClick(use)
  check("anything else is refused", page.result.text == "That is not a ClassCoach settings line.")
  local now = ns.Options.export(ClassCoachDB)
  local copy = {}
  local taken = ns.Options.import(now, copy, {})
  check("a line read back gives the same settings", taken == select(2, now:gsub("=", "")) and copy.scale == 1.3 and copy.cue == false and ns.Options.export(copy) == now, now)
  ClassCoachDB.scale, ClassCoachDB.cue = 1, true
  W.close()

  -- 6. The plan follows your mana, also when the game hides it
  local Mana = ns.Mana
  local L = Mana.ledger()
  Mana.set(L, 0, 300, 300)
  Mana.spend(L, 0, 100, 0)
  Mana.tick(L, 4, { idle = 10 })
  check("ledger: nothing comes back inside the five-second rule", L.mana == 200, L.mana)
  Mana.tick(L, 9, { idle = 10 })
  check("ledger: then the regen the game gives", math.abs(L.mana - 240) < 0.01, L.mana)
  Mana.tick(L, 14, { idle = 10, drinking = true })
  check("ledger: drinking fills you up fast", L.mana == 300, L.mana)
  Mana.spend(L, 20, 0, 45)
  check("ledger: Life Tap gives, never above your maximum", L.mana == 300)
  Mana.spend(L, 21, 280, 0); Mana.fence(L, 25, nil)
  check("ledger: what you can still afford sets a floor", L.mana == 25, L.mana)
  Mana.fence(L, 0, 20)
  check("ledger: and what you cannot, a ceiling", L.mana == 19, L.mana)

  M.manaSecret = true
  target(nil)
  M.advance(3); f = tick(ns)
  check("mana hidden out of combat too: the coach keeps its own count", ns.C.lastState.manaExact == false and ns.C.lastState.manaPct ~= nil, tostring(ns.C.lastState.manaPct))
  local function planText()
    local names = {}
    for _, st in ipairs(ns.Engine.plan(ns.C.profile, ns.C.lastState)) do names[#names + 1] = st.label end
    return table.concat(names, " > ")
  end
  local full = planText()
  check("at full mana the plan has room for Immolate", full:find("Immolate", 1, true) ~= nil, full)
  for _ = 1, 4 do cast(688) end   -- summoning eats mana; the count follows your casts
  M.advance(1); f = tick(ns)
  local low = planText()
  check("after spending mana between fights the plan is shorter, from your own count", ns.C.lastState.manaPct < 30 and not low:find("Immolate", 1, true), low .. " @ " .. tostring(ns.C.lastState.manaPct))
  check("and the coach asks you to drink before the pull", missing(ns):find("Mana", 1, true) ~= nil, missing(ns))
  M.P.buffs["Drink"] = true; M.fire("UNIT_AURA", "player")
  M.P.mana = 300   -- the game's own count, which only the probes see
  for _ = 1, 10 do M.advance(3); f = tick(ns) end
  M.P.buffs["Drink"] = nil; M.fire("UNIT_AURA", "player"); M.advance(1); f = tick(ns)
  check("drinking: the count fills up and the full plan is back", ns.C.lastState.manaPct > 95 and planText() == full, tostring(ns.C.lastState.manaPct) .. " " .. planText())
  M.manaSecret = false
  check("no errors logged", errors() == 0, table.concat(ClassCoachDB.log or {}, " | "))
end

-- In every scenario: the addon never changed a frame of the game (see M.gameFrame in mock.lua).
check("the game's own bars and buttons were looked at, never changed", #M.violations == 0, table.concat(M.violations, " | "))

print_real(("%s: %d passed, %d failed"):format(SCENARIO, passed, failed))
return failed
