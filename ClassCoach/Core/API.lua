-- Everything that talks to the game client lives here.
--
-- WoW Forever hides many values from addons during combat ("secret values").
-- Comparing or doing maths on a secret raises an error, so every read goes
-- through pcall and is checked with issecretvalue before use. A failed read
-- means "unknown" (nil), never "false".
local _, ns = ...

local API = {}
ns.API = API

local issecret = issecretvalue or function() return false end

-- A value we may safely compare, or nil when it is secret.
local function plain(v)
  if issecret(v) then return nil end
  return v
end
API.plain = plain

-- Calls a game function; returns nothing if it is missing or errors.
local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g, h end
  return nil
end
API.try = try

-- Reads one field of a table the game returned.
local function field(t, k)
  if type(t) ~= "table" then return nil end
  local ok, v = pcall(function() return t[k] end)
  if ok then return plain(v) end
  return nil
end
API.field = field

local C_Spell = C_Spell or {}
local C_SpellBook = C_SpellBook or {}
local C_UnitAuras = C_UnitAuras or {}
local C_Item = C_Item or {}

API.log = function() end   -- replaced by ClassCoach.lua once saved variables exist

---------------------------------------------------------------------------
-- Player basics
---------------------------------------------------------------------------

function API.now() return GetTime() end

function API.classToken()
  local _, token = try(UnitClass, "player")
  return plain(token)
end

function API.level() return plain(try(UnitLevel, "player")) or 1 end

function API.usesMana()
  local kind = plain(try(UnitPowerType, "player"))
  if kind ~= nil and kind ~= 0 then
    -- Druids in forms report rage/energy; they still have mana underneath.
    local max = plain(try(UnitPowerMax, "player", 0))
    return max ~= nil and max > 0
  end
  return true
end

-- Exact mana when the game lets us read it (usually only out of combat).
function API.mana()
  local cur = plain(try(UnitPower, "player", 0))
  local max = plain(try(UnitPowerMax, "player", 0))
  if type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then return nil, max end
  return cur, max
end

-- Exact mana percent, when this client lets addons read it. In combat the
-- game usually hides it; then this returns nil.
function API.manaPct()
  local curve = CurveConstants and CurveConstants.ScaleTo100
  if not UnitPowerPercent or not curve then return nil end
  local v = plain(try(UnitPowerPercent, "player", 0, false, curve))
  if type(v) ~= "number" then return nil end
  return v
end

-- Draws your real mana on a status bar. The addon may not read the hidden
-- number in combat, but the game accepts it for drawing: the bar is always
-- true. Returns false if the game refuses.
function API.drawMana(bar, label)
  local drawn = pcall(function()
    bar:SetMinMaxValues(0, UnitPowerMax("player", 0))
    bar:SetValue(UnitPower("player", 0))
  end)
  if not drawn then return false end
  if label then
    local curve = CurveConstants and CurveConstants.ScaleTo100
    local written = false
    if UnitPowerPercent and curve then
      written = pcall(function()
        label:SetFormattedText("Mana %.0f%%", UnitPowerPercent("player", 0, false, curve))
      end)
    end
    if not written then label:SetText("Mana") end
  end
  return true
end

function API.inCombat()
  local c = plain(try(UnitAffectingCombat, "player"))
  if c == nil then c = plain(try(InCombatLockdown)) end
  return c == true
end

function API.inGroup() return plain(try(IsInGroup)) == true end

-- true / false / nil (unknown). Reliable out of combat.
function API.hasPet()
  local exists = plain(try(UnitExists, "pet"))
  if exists == nil then return nil end
  if exists and plain(try(UnitIsDead, "pet")) == true then return false end
  return exists == true
end

-- Health in percent when readable (usually only out of combat).
function API.healthPct()
  local cur, max = plain(try(UnitHealth, "player")), plain(try(UnitHealthMax, "player"))
  if type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
  return cur / max * 100
end

function API.target()
  local t = { exists = plain(try(UnitExists, "target")) == true }
  if not t.exists then return t end
  t.hostile = plain(try(UnitCanAttack, "player", "target")) == true
  t.dead = plain(try(UnitIsDead, "target")) == true
  t.name = plain(try(UnitName, "target"))
  t.level = plain(try(UnitLevel, "target"))
  local class = plain(try(UnitClassification, "target"))
  t.elite = class == "elite" or class == "rareelite" or class == "worldboss"
  return t
end

-- A key that tells enemies apart, so damage-over-time timers stay with the
-- right one. Three ways, best first; `mode` says which one worked:
--   "guid"      the game gave us the enemy's id
--   "nameplate" we matched your target to one of the visible nameplates
--   "count"     neither is readable: every target change counts as a new enemy
local plateGen, targetSeq = {}, 0
function API.targetChanged() targetSeq = targetSeq + 1 end
function API.plateAdded(token)
  token = plain(token)
  if token then plateGen[token] = (plateGen[token] or 0) + 1 end
end
function API.targetKey()
  local guid = plain(try(UnitGUID, "target"))
  if type(guid) == "string" then return "g:" .. guid, "guid" end
  local plates = C_NamePlate and try(C_NamePlate.GetNamePlates)
  if type(plates) == "table" then
    for _, plate in ipairs(plates) do
      local token = field(plate, "namePlateUnitToken")
      if type(token) == "string" and plain(try(UnitIsUnit, "target", token)) == true then
        return "np:" .. token .. ":" .. (plateGen[token] or 0), "nameplate"
      end
    end
  end
  return "t:" .. targetSeq, "count"
end

-- Your class colour (r, g, b), gold when the game won't say.
function API.classColor()
  local token = API.classToken()
  local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
  if type(c) == "table" and c.r then return c.r, c.g, c.b end
  return 1, 0.82, 0.2
end

-- Your pet's kind ("Imp", "Voidwalker", ...) when the game tells us; English clients.
function API.petFamily()
  local family = plain(try(UnitCreatureFamily, "pet"))
  if type(family) ~= "string" or family == "" then return nil end
  return family
end

-- How long a spell's damage over time lasts, read from its own tooltip text
-- ("... over 18 sec"). nil when the text isn't available or isn't English.
function API.dotDuration(id)
  local text = plain(try(C_Spell and C_Spell.GetSpellDescription, id))
  if type(text) ~= "string" then text = plain(try(GetSpellDescription, id)) end
  if type(text) ~= "string" then return nil end
  local seconds = tonumber(text:match("over (%d+) sec"))
  if seconds and seconds >= 3 and seconds <= 120 then return seconds end
  return nil
end

---------------------------------------------------------------------------
-- Macros (the game only lets addons create or change them out of combat)
---------------------------------------------------------------------------

-- Returns "created", "updated", "same", "full", "combat" or nil on failure.
function API.saveMacro(name, body, onlyExisting)
  if API.inCombat() then return "combat" end
  local index = plain(try(GetMacroIndexByName, name)) or 0
  if index > 0 then
    if plain(try(GetMacroBody, index)) == body then return "same" end
    local done = try(EditMacro, index, name, nil, body)
    return done and "updated" or nil
  end
  if onlyExisting then return nil end
  local _, perChar = try(GetNumMacros)
  perChar = plain(perChar)
  if type(perChar) == "number" and perChar >= (MAX_CHARACTER_MACROS or 18) then return "full" end
  local done = try(CreateMacro, name, "INV_MISC_QUESTIONMARK", body, true)
  return done and "created" or nil
end

function API.macroExists(name)
  return (plain(try(GetMacroIndexByName, name)) or 0) > 0
end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------

local function isKnownId(id)
  local known = plain(try(C_SpellBook.IsSpellKnown, id))
  if known == nil then known = plain(try(IsSpellKnown, id)) end
  if known == nil then known = plain(try(IsPlayerSpell, id)) end
  return known == true
end

function API.spellName(id) return plain(try(C_Spell.GetSpellName, id)) or plain(try(GetSpellInfo, id)) end

function API.texture(id)
  if not id then return nil end
  return plain(try(C_Spell.GetSpellTexture, id)) or plain(select(3, try(GetSpellInfo, id)))
end

function API.cost(id)
  local costs = try(C_Spell.GetSpellPowerCost, id) or try(GetSpellPowerCost, id)
  if type(costs) ~= "table" then return nil end
  local found
  pcall(function()
    for _, c in ipairs(costs) do
      local kind, cost = field(c, "type"), field(c, "cost")
      if kind == 0 and cost and cost > 0 then found = cost break end
    end
  end)
  return found
end

-- Every spell in the spellbook by (localized) name: { id, ids = {all ranks} }.
function API.scanSpellbook()
  local byName = {}
  local function add(id, name)
    id, name = plain(id), plain(name)
    if not id or not name then return end
    local entry = byName[name]
    if not entry then entry = { ids = {} }; byName[name] = entry end
    entry.ids[#entry.ids + 1] = id
    entry.id = id
  end
  local ok = pcall(function()
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
      local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
      local first = field(info, "itemIndexOffset") or 0
      local count = field(info, "numSpellBookItems") or 0
      for i = first + 1, first + count do
        local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
        local id = field(item, "spellID")
        if id and not field(item, "isPassive") and isKnownId(id) then
          add(id, field(item, "name") or API.spellName(id))
        end
      end
    end
  end)
  if not ok or not next(byName) then
    -- Older client API as a fallback.
    pcall(function()
      for tab = 1, (GetNumSpellTabs() or 0) do
        local _, _, offset, num = GetSpellTabInfo(tab)
        for i = offset + 1, offset + num do
          local kind, id = GetSpellBookItemInfo(i, "spell")
          if kind == "SPELL" and id then add(id, API.spellName(id)) end
        end
      end
    end)
  end
  return byName
end

-- Resolves one profile spell to what this character actually knows.
-- spec = { ids = {rank ids, lowest first}, name = "English name" }
function API.resolveSpell(spec, book)
  local known = {}
  for _, id in ipairs(spec.ids or {}) do
    if isKnownId(id) then known[#known + 1] = id end
  end
  local display = (spec.ids and spec.ids[1] and API.spellName(spec.ids[1])) or spec.name
  if #known == 0 then
    -- Not found by id (new Forever spell, or ids changed): look it up by name.
    local entry = book[display] or book[spec.name]
    if entry then
      for _, id in ipairs(entry.ids) do known[#known + 1] = id end
      display = display or spec.name
    end
  end
  if #known == 0 then return nil end
  local id = known[#known]
  return {
    id = id,                     -- highest known rank
    lowest = known[1],           -- rank 1, cheap for interrupts
    name = API.spellName(id) or display or spec.name,
    cost = API.cost(id),
    lowestCost = API.cost(known[1]),
    icon = API.texture(id),
  }
end

-- usable: true/false/nil, short: true when "not enough mana"
function API.usable(id)
  local usable, short = try(C_Spell.IsSpellUsable, id)
  if usable == nil and short == nil then usable, short = try(IsUsableSpell, id) end
  return plain(usable), plain(short)
end

-- true when off cooldown (the global cooldown doesn't count), nil when unknown
function API.ready(id)
  local info = try(C_Spell.GetSpellCooldown, id)
  if type(info) == "table" then
    local active = field(info, "isActive")
    if active ~= nil then
      if not active then return true end
      return field(info, "isOnGCD") == true
    end
    local start, duration = field(info, "startTime"), field(info, "duration")
    if start and duration then return start == 0 or duration <= 1.5 end
    return nil
  end
  local start, duration = try(GetSpellCooldown, id)
  start, duration = plain(start), plain(duration)
  if start == nil then return nil end
  return start == 0 or (duration or 0) <= 1.5
end

---------------------------------------------------------------------------
-- Buffs, weapon buffs, totems, items (reliable out of combat only)
---------------------------------------------------------------------------

function API.aurasReadable(inCombat)
  if inCombat then return false end
  local secret = try(C_Secrets and C_Secrets.ShouldAurasBeSecret)
  return plain(secret) ~= true
end

-- Set of buff names on the player, or nil when the game hides them.
function API.playerBuffs()
  local names, any = {}, false
  local ok = pcall(function()
    for i = 1, 40 do
      local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      if not aura then break end
      local name = field(aura, "name")
      if name then names[name] = true; any = true end
    end
  end)
  if not ok or not any then
    pcall(function()
      for i = 1, 40 do
        local name = UnitBuff("player", i)
        name = plain(name)
        if not name then break end
        names[name] = true; any = true
      end
    end)
  end
  return names
end

-- true / false / nil (unknown)
function API.mainHandBuff()
  local has = plain(try(GetWeaponEnchantInfo))
  if has == nil then return nil end
  return has == true
end

-- slot 1 fire, 2 earth, 3 water, 4 air
API.TOTEM_SLOT = { fire = 1, earth = 2, water = 3, air = 4 }
function API.totemUp(element)
  local slot = API.TOTEM_SLOT[element]
  if not slot then return nil end
  local have = plain(try(GetTotemInfo, slot))
  if have == nil then return nil end
  return have == true
end

function API.itemCount(itemID)
  return plain(try(C_Item.GetItemCount, itemID)) or plain(try(GetItemCount, itemID))
end

---------------------------------------------------------------------------
-- Out-of-combat status for the journey panel
---------------------------------------------------------------------------

-- cur, max, rested (0 when none), resting. Any may be nil.
function API.xp()
  local cur, max = plain(try(UnitXP, "player")), plain(try(UnitXPMax, "player"))
  local rested = plain(try(GetXPExhaustion))
  if type(cur) ~= "number" or type(max) ~= "number" then return nil end
  return { cur = cur, max = max, rested = type(rested) == "number" and rested or 0, resting = plain(try(IsResting)) == true }
end

function API.unspentTalents()
  local points = plain(try(UnitCharacterPoints, "player"))
  if type(points) ~= "number" then return nil end
  return points
end

-- Lowest durability of anything you wear, in percent.
function API.durability()
  local lowest
  for slot = 1, 18 do
    local cur, max = try(GetInventoryItemDurability, slot)
    cur, max = plain(cur), plain(max)
    if type(cur) == "number" and type(max) == "number" and max > 0 then
      local pct = cur / max * 100
      if not lowest or pct < lowest then lowest = pct end
    end
  end
  return lowest
end

function API.freeBagSlots()
  local free, any = 0, false
  for bag = 0, 4 do
    local slots = plain(try(C_Container and C_Container.GetContainerNumFreeSlots, bag))
    if type(slots) ~= "number" then slots = plain(try(GetContainerNumFreeSlots, bag)) end
    if type(slots) == "number" then free = free + slots; any = true end
  end
  if not any then return nil end
  return free
end

-- "Alliance" / "Horde"
function API.faction()
  local f = plain(try(UnitFactionGroup, "player"))
  return type(f) == "string" and f or nil
end

-- Food and drink in your bags: { food = n, drink = n }. The game marks both
-- as "Food & Drink"; the item's use ("Food" / "Drink") tells them apart on
-- English clients, otherwise an item counts as both.
function API.supplies()
  if not C_Container or not C_Container.GetContainerNumSlots then return nil end
  local food, drink, any = 0, 0, false
  for bag = 0, 4 do
    local slots = plain(try(C_Container.GetContainerNumSlots, bag))
    for slot = 1, type(slots) == "number" and slots or 0 do
      local info = try(C_Container.GetContainerItemInfo, bag, slot)
      local id, count = plain(field(info, "itemID")), plain(field(info, "stackCount")) or 1
      if id then
        any = true
        local _, _, _, _, _, classID, subID = try(C_Item.GetItemInfoInstant, id)
        if plain(classID) == 0 and plain(subID) == 5 then
          local use = plain(try(C_Item.GetItemSpell, id)) or plain(try(GetItemSpell, id))
          if use == "Food" then food = food + count
          elseif use == "Drink" then drink = drink + count
          else food = food + count; drink = drink + count end
        end
      end
    end
  end
  if not any then return nil end
  return { food = food, drink = drink }
end

function API.canRepair()
  return plain(try(CanMerchantRepair)) == true
end

---------------------------------------------------------------------------
-- Action bar (out of combat only)
---------------------------------------------------------------------------

function API.slotEmpty(slot)
  return plain((try(GetActionInfo, slot))) == nil
end

-- Puts a spell (by id) or a macro (by name) on an action button.
-- Whatever was there is removed. Returns true when the button now holds something.
function API.placeAction(slot, what)
  if API.inCombat() then return false end
  try(ClearCursor)
  if what.macro then
    try(PickupMacro, what.macro)
  elseif C_Spell and C_Spell.PickupSpell then
    try(C_Spell.PickupSpell, what.spell)
  else
    try(PickupSpell, what.spell)
  end
  try(PlaceAction, slot)
  try(ClearCursor)
  return not API.slotEmpty(slot)
end

-- Do you carry an item with this name? (true / false)
function API.hasItem(name)
  local count = API.itemCount(name)
  return type(count) == "number" and count > 0
end

-- Something equipped in a slot (18 = ranged/wand).
function API.equipped(slot)
  local id = plain(try(GetInventoryItemID, "player", slot))
  return id ~= nil
end

---------------------------------------------------------------------------
-- Talents: which tree has the most points (for picking a spec profile)
---------------------------------------------------------------------------

function API.talentPoints()
  local points, any = {}, false
  for tab = 1, 3 do
    local r = { try(GetTalentTabInfo, tab) }
    -- Classic returns name, icon, pointsSpent; newer clients id, name, description, icon, pointsSpent.
    local spent
    if type(plain(r[3])) == "number" and type(plain(r[1])) == "string" then spent = plain(r[3]) end
    if spent == nil and type(plain(r[5])) == "number" then spent = plain(r[5]) end
    points[tab] = spent or 0
    if spent then any = true end
  end
  return any and points or nil
end

---------------------------------------------------------------------------
-- Keybinds: which key each spell sits on
---------------------------------------------------------------------------

local function bindingForSlot(slot)
  local i = (slot - 1) % 12 + 1
  if slot <= 12 then return "ACTIONBUTTON" .. i end
  if slot >= 25 and slot <= 36 then return "MULTIACTIONBAR3BUTTON" .. i end
  if slot >= 37 and slot <= 48 then return "MULTIACTIONBAR4BUTTON" .. i end
  if slot >= 49 and slot <= 60 then return "MULTIACTIONBAR2BUTTON" .. i end
  if slot >= 61 and slot <= 72 then return "MULTIACTIONBAR1BUTTON" .. i end
  if slot >= 145 and slot <= 156 then return "MULTIACTIONBAR5BUTTON" .. i end
  if slot >= 157 and slot <= 168 then return "MULTIACTIONBAR6BUTTON" .. i end
  if slot >= 169 and slot <= 180 then return "MULTIACTIONBAR7BUTTON" .. i end
end

local function shortKey(key)
  if not key then return nil end
  key = key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A")
  key = key:gsub("NUMPAD", "N"):gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD"):gsub("BUTTON", "M")
  return key
end

-- name -> key text, for every spell placed on a bound action button
function API.scanKeys()
  local keys = {}
  for slot = 1, 180 do
    local binding = bindingForSlot(slot)
    if binding then
      local kind, id = try(GetActionInfo, slot)
      kind, id = plain(kind), plain(id)
      if kind == "spell" and id then
        local name = API.spellName(id)
        if name and keys[name] == nil then
          keys[name] = shortKey(plain(try(GetBindingKey, binding))) or false
        end
      elseif kind == "macro" then
        -- remembered as "macro:<name>" so the key can stand in for the spells inside it
        local name = plain(try(GetActionText, slot))
        if not name and id then name = plain(try(GetMacroInfo, id)) end
        if name and keys["macro:" .. name] == nil then
          keys["macro:" .. name] = shortKey(plain(try(GetBindingKey, binding))) or false
        end
      end
    end
  end
  return keys
end
