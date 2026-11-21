-- Everything that talks to the game client lives here.
--
-- ClassCoach is written for World of Warcraft: Forever and nothing else
-- (patch 1.60.x, interface 160xx; the game calls this version "Camelot").
-- Every call below is one the Forever client has. There are no fallbacks for
-- Classic Era, Season of Discovery, the Classic expansions or retail, and on
-- any of those the addon switches itself off (see API.forever).
--
-- WoW Forever hides many values from addons during combat ("secret values").
-- Comparing or doing maths on a secret raises an error, so every read goes
-- through pcall and is checked with issecretvalue before use. A failed read
-- means "unknown" (nil), never "false".
local _, ns = ...

local API = {}
ns.API = API

-- Is this the Forever client? The game's own project id decides when it has
-- one; otherwise the interface number does (16001 = 1.60.1; Classic Era is
-- 115xx, the Classic expansions 2xxxx and up, retail 12xxxx).
local function isForever()
  if type(issecretvalue) ~= "function" then return false end
  if WOW_PROJECT_ID ~= nil and WOW_PROJECT_CAMELOT ~= nil then return WOW_PROJECT_ID == WOW_PROJECT_CAMELOT end
  local ok, _, _, _, interface = pcall(GetBuildInfo)
  return ok and type(interface) == "number" and interface >= 16000 and interface < 20000
end
API.forever = isForever()
API.NOT_FOREVER = "ClassCoach is made for World of Warcraft: Forever only. It does nothing on this version of the game."

-- Forever's function groups. A group the client lacks reads as empty, so a
-- call into it means "unknown" instead of an error.
local function group(name)
  local t = _G[name]
  return type(t) == "table" and t or {}
end
local C_Spell, C_SpellBook, C_Item, C_Container = group("C_Spell"), group("C_SpellBook"), group("C_Item"), group("C_Container")
local C_ActionBar, C_UnitAuras, C_Secrets, C_NamePlate = group("C_ActionBar"), group("C_UnitAuras"), group("C_Secrets"), group("C_NamePlate")
local C_ClassTalents, C_Traits, C_CVar = group("C_ClassTalents"), group("C_Traits"), group("C_CVar")

local issecret = issecretvalue or function() return true end   -- never on Forever; elsewhere the addon is off

-- A value we may safely compare, or nil when it is secret.
local function plain(v)
  if issecret(v) then return nil end
  return v
end
API.plain = plain

-- A count the game gave us, made safe to loop over: a whole number between
-- 0 and `most`. A hidden value, text, a negative, "not a number" or an absurdly
-- large value all become something a loop finishes at once.
local function upTo(n, most)
  n = plain(n)
  if type(n) ~= "number" or n ~= n or n < 0 then return 0 end
  if n > most then return most end
  return math.floor(n)
end
API.upTo = upTo

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
        label:SetFormattedText("%.0f%%", UnitPowerPercent("player", 0, false, curve))
      end)
    end
    if not written then label:SetText("") end
  end
  return true
end

-- In combat, or the game has locked protected things (bars, macros, secure
-- buttons). Either one counts: the two can differ for a moment at the start
-- and end of a fight, and with a pet fighting, and touching protected things
-- in that moment is what makes the game block an addon.
function API.inCombat()
  if plain(try(InCombatLockdown)) == true then return true end
  return plain(try(UnitAffectingCombat, "player")) == true
end

-- Every Forever function ClassCoach calls. /coach check lists the ones this
-- client does not have, so a change in a Forever patch shows up by name.
local NEEDS = {
  "issecretvalue", "GetTime", "GetBuildInfo", "PlaySound", "GetProfessions", "GetProfessionInfo", "InCombatLockdown", "IsInGroup", "IsResting", "GetXPExhaustion", "GetTotemInfo",
  "GetInventoryItemID", "GetInventoryItemDurability", "CanMerchantRepair", "GetActionInfo", "GetActionBarToggles", "PlaceAction", "PickupAction",
  "PickupMacro", "ClearCursor", "CreateMacro", "EditMacro", "GetMacroBody", "GetMacroIndexByName", "GetMacroInfo", "GetNumMacros",
  "GetBindingKey", "GetBindingAction", "SetBinding", "SetBindingClick", "SaveBindings", "GetCurrentBindingSet", "RegisterStateDriver",
  "UnitAffectingCombat", "UnitCanAttack", "UnitClass", "UnitClassification", "UnitCreatureFamily", "UnitExists", "UnitFactionGroup",
  "UnitGUID", "UnitHealth", "UnitHealthMax", "UnitIsDead", "UnitIsUnit", "UnitLevel", "UnitName", "UnitPower", "UnitPowerMax",
  "UnitPowerPercent", "UnitPowerType", "UnitXP", "UnitXPMax",
  "C_ActionBar.GetActionBarPage", "C_ActionBar.SetActionBarPage", "C_ActionBar.GetActionText", "C_ActionBar.GetActionTexture",
  "C_CVar.GetCVar", "C_CVar.SetCVar", "C_ClassTalents.GetActiveConfigID", "C_ClassTalents.HasUnspentTalentPoints",
  "C_Container.GetContainerItemInfo", "C_Container.GetContainerNumFreeSlots", "C_Container.GetContainerNumSlots",
  "C_Item.GetItemCount", "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant", "C_Item.GetItemSpell", "C_Item.GetWeaponEnchantInfo",
  "C_Item.PickupItem", "C_NamePlate.GetNamePlates", "C_Secrets.ShouldAurasBeSecret",
  "C_Spell.GetSpellCooldown", "C_Spell.GetSpellDescription", "C_Spell.GetSpellName", "C_Spell.GetSpellPowerCost",
  "C_Spell.GetSpellTexture", "C_Spell.IsAutoRepeatSpell", "C_Spell.IsSpellUsable", "C_Spell.PickupSpell",
  "C_SpellBook.GetNumSpellBookSkillLines", "C_SpellBook.GetSpellBookItemInfo", "C_SpellBook.GetSpellBookItemTexture",
  "C_SpellBook.GetSpellBookSkillLineInfo", "C_SpellBook.IsSpellKnown", "C_Timer.After",
  "C_Traits.GetConfigInfo", "C_Traits.GetDefinitionInfo", "C_Traits.GetEntryInfo", "C_Traits.GetNodeInfo",
  "C_Traits.GetTreeCurrencyInfo", "C_Traits.GetTreeNodes",
  "C_UnitAuras.GetAuraDataByIndex",
}
function API.missing()
  local out = {}
  for _, name in ipairs(NEEDS) do
    local space, fn = name:match("^(.-)%.(.+)$")
    local found
    if space then found = type(_G[space]) == "table" and _G[space][fn] else found = _G[name] end
    if type(found) ~= "function" then out[#out + 1] = name end
  end
  return out
end

-- Turns the game's own error windows on or off. Returns what the setting is
-- afterwards (true / false), or nil when the game would not say.
function API.showErrors(on)
  try(C_CVar.SetCVar, "scriptErrors", on and "1" or "0")
  local now = plain(try(C_CVar.GetCVar, "scriptErrors"))
  if now == nil then return nil end
  return tostring(now) == "1"
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
  local plates = try(C_NamePlate.GetNamePlates)
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
  local text = plain(try(C_Spell.GetSpellDescription, id))
  if type(text) ~= "string" then return nil end
  local seconds = tonumber(text:match("over (%d+) sec"))
  if seconds and seconds >= 3 and seconds <= 120 then return seconds end
  return nil
end

---------------------------------------------------------------------------
-- Macros (the game only lets addons create or change them out of combat)
---------------------------------------------------------------------------

-- Returns "created", "updated", "same", "full", "combat" or nil on failure.
local written = {}   -- what we last stored in each macro
function API.saveMacro(name, body, onlyExisting)
  if API.inCombat() then return "combat" end
  local index = plain(try(GetMacroIndexByName, name)) or 0
  if index > 0 then
    -- The game may hand a macro back slightly differently from how it was
    -- stored. Going by our own record as well keeps us from rewriting the same
    -- macro over and over, which makes the buttons holding it flicker.
    if written[name] == body or plain(try(GetMacroBody, index)) == body then
      written[name] = body
      return "same"
    end
    local done = try(EditMacro, index, name, nil, body)
    if done then written[name] = body end
    return done and "updated" or nil
  end
  if onlyExisting then return nil end
  local _, perChar = try(GetNumMacros)
  perChar = plain(perChar)
  if type(perChar) == "number" and perChar >= (MAX_CHARACTER_MACROS or 18) then return "full" end
  local done = try(CreateMacro, name, "INV_MISC_QUESTIONMARK", body, true)
  if done then written[name] = body end
  return done and "created" or nil
end

function API.macroExists(name)
  return (plain(try(GetMacroIndexByName, name)) or 0) > 0
end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------

local function isKnownId(id)
  return plain(try(C_SpellBook.IsSpellKnown, id)) == true
end

function API.spellName(id) return plain(try(C_Spell.GetSpellName, id)) end

function API.texture(id)
  if not id then return nil end
  return plain(try(C_Spell.GetSpellTexture, id))
end

-- The icon the game itself shows for a spell. Its own id can carry different
-- art from what you see in game, so the picture on your action bar button comes
-- first, then the one in your spellbook, and only then the id's own.
API.barIcons, API.bookIcons = {}, {}
local function picture(v)
  v = plain(v)
  if (type(v) == "number" and v == v and v > 0) or (type(v) == "string" and v ~= "") then return v end
end
function API.iconFor(name, id)
  return (name and (API.barIcons[name] or API.bookIcons[name])) or API.texture(id)
end

function API.cost(id)
  local costs = try(C_Spell.GetSpellPowerCost, id)
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
  local byName, icons = {}, {}
  API.bookIcons = icons
  local function add(id, name, icon)
    id, name = plain(id), plain(name)
    if not id or not name then return end
    icons[name] = picture(icon) or icons[name]
    local entry = byName[name]
    if not entry then entry = { ids = {} }; byName[name] = entry end
    entry.ids[#entry.ids + 1] = id
    entry.id = id
  end
  pcall(function()
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for line = 1, upTo(C_SpellBook.GetNumSpellBookSkillLines(), 40) do
      local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
      local first = upTo(field(info, "itemIndexOffset"), 5000)
      local count = upTo(field(info, "numSpellBookItems"), 1000)
      for i = first + 1, first + count do
        local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
        local id = field(item, "spellID")
        if id and not field(item, "isPassive") and isKnownId(id) then
          add(id, field(item, "name") or API.spellName(id),
            field(item, "iconID") or try(C_SpellBook.GetSpellBookItemTexture, i, bank))
        end
      end
    end
  end)
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

-- Is this auto-repeating spell (wand, auto shot) firing right now? true / false / nil
function API.repeating(id)
  local on = plain(try(C_Spell.IsAutoRepeatSpell, id))
  if type(on) ~= "boolean" then return nil end
  return on
end

-- usable: true/false/nil, short: true when "not enough mana"
function API.usable(id)
  local usable, short = try(C_Spell.IsSpellUsable, id)
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
  end
  return nil
end

---------------------------------------------------------------------------
-- Buffs, weapon buffs, totems, items (reliable out of combat only)
---------------------------------------------------------------------------

function API.aurasReadable(inCombat)
  if inCombat then return false end
  local secret = try(C_Secrets.ShouldAurasBeSecret)
  return plain(secret) ~= true
end

-- Set of buff names on the player, or nil when the game hides them.
function API.playerBuffs()
  local names = {}
  pcall(function()
    for i = 1, 40 do
      local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      if not aura then break end
      local name = field(aura, "name")
      if name then names[name] = true end
    end
  end)
  return names
end

-- Is a temporary buff on your main-hand weapon (a Shaman imbue, a stone, an oil)?
-- true / false / nil (unknown). Forever answers with a list, one entry per enchant
-- layer: { hasEnchant, enchantType (1 = the permanent enchant, which does not count) }.
function API.mainHandBuff()
  local list = plain(try(C_Item.GetWeaponEnchantInfo, 0))   -- 0 = main hand
  if type(list) ~= "table" then return nil end
  local found, readable = false, true
  pcall(function()
    for i = 1, upTo(#list, 8) do
      local has, kind = field(list[i], "hasEnchant"), field(list[i], "enchantType")
      if has == nil then readable = false
      elseif has == true and kind ~= 1 then found = true end
    end
  end)
  if found then return true end
  if not readable then return nil end
  return false
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
  return plain(try(C_Item.GetItemCount, itemID))
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

-- Calls fn(config, treeID) for each of your talent trees. Forever keeps
-- talents in the game's "traits" system.
local function eachTalentTree(fn)
  pcall(function()
    local config = plain(C_ClassTalents.GetActiveConfigID())
    if type(config) ~= "number" then return end
    local trees = field(C_Traits.GetConfigInfo(config), "treeIDs")
    if type(trees) ~= "table" then return end
    for i = 1, upTo(#trees, 6) do
      local tree = plain(trees[i])
      if type(tree) == "number" then fn(config, tree, i) end
    end
  end)
end

-- Talent points waiting to be spent: a number, true (some, count unknown),
-- 0, or nil when the game won't say.
function API.unspentTalents()
  local has = plain(try(C_ClassTalents.HasUnspentTalentPoints))
  if has == false then return 0 end
  if has ~= true then return nil end
  local count = 0
  eachTalentTree(function(config, tree)
    local list = C_Traits.GetTreeCurrencyInfo(config, tree, false)
    if type(list) ~= "table" then return end
    for i = 1, upTo(#list, 8) do
      local n = field(list[i], "quantity")
      if type(n) == "number" and n > 0 and n <= 60 then count = count + n end
    end
  end)
  return count > 0 and count or true
end

-- Your professions: { { name, icon, skill, max } }, or nil when the game won't say.
function API.professions()
  local out = {}
  -- "readable" is whether the game answered at all: only then does an empty list mean "none learned".
  local answer = { pcall(GetProfessions) }
  API.professionsReadable = answer[1] == true
  if not answer[1] then return out end
  for i = 1, 8 do
    local index = plain(answer[i + 1])
    if type(index) == "number" then
      local name, icon, skill, max = try(GetProfessionInfo, index)
      name, skill, max = plain(name), plain(skill), plain(max)
      if type(name) == "string" and type(skill) == "number" and skill >= 0 and skill <= 450 then
        -- the game lists your two main professions first, then the secondary ones
        out[#out + 1] = { name = name, icon = picture(icon), skill = skill, max = (type(max) == "number" and max >= skill) and max or nil,
          primary = i <= 2 }
      else
        API.professionsReadable = false   -- a slot is filled but would not say with what
      end
    end
  end
  return out
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
    local slots = plain(try(C_Container.GetContainerNumFreeSlots, bag))
    if type(slots) == "number" then free = free + slots; any = true end
  end
  if not any then return nil end
  return free
end

-- How many of your four bag slots have no bag in them. nil when the game won't say.
function API.emptyBagSlots()
  local empty, any = 0, false
  for bag = 1, 4 do
    local slots = plain(try(C_Container.GetContainerNumSlots, bag))
    if type(slots) == "number" then
      any = true
      if slots == 0 then empty = empty + 1 end
    end
  end
  if not any then return nil end
  return empty
end

-- "Alliance" / "Horde"
function API.faction()
  local f = plain(try(UnitFactionGroup, "player"))
  return type(f) == "string" and f or nil
end

-- What you carry for the road. Returns
--   { food = n, drink = n, best = { food = item, drink = item, bandage = item, healthstone = item, hearth = item,
--     healingpotion = item, manapotion = item }, kindOf = { [itemID] = kind } }       item = { id, name, level }
-- "best" is the strongest one you can use at your level. The game marks food
-- and water alike as "Food & Drink"; the item's use ("Food" / "Drink") tells
-- them apart on English clients, otherwise an item counts as both. Potions
-- are told apart by name ("Healing Potion", "Mana Potion"), so on other
-- languages they are not found. Alchemy's "Discolored" healing potions are
-- left out: they heal at a price.
local HEARTHSTONE = 6948
function API.supplies(playerLevel)
  if not C_Container or not C_Container.GetContainerNumSlots then return nil end
  local out = { food = 0, drink = 0, best = {}, kindOf = {} }
  local any = false
  local function consider(kind, id, name, level)
    out.kindOf[id] = out.kindOf[id] or kind
    local best = out.best[kind]
    if not best or level > best.level then out.best[kind] = { id = id, name = name, level = level } end
  end
  for bag = 0, 4 do
    for slot = 1, upTo(try(C_Container.GetContainerNumSlots, bag), 200) do
      local info = try(C_Container.GetContainerItemInfo, bag, slot)
      local id, count = plain(field(info, "itemID")), plain(field(info, "stackCount")) or 1
      if id then
        any = true
        local _, _, _, _, _, classID, subID = try(C_Item.GetItemInfoInstant, id)
        classID, subID = plain(classID), plain(subID)
        local name, _, _, _, minLevel = try(C_Item.GetItemInfo, id)
        name, minLevel = plain(name), plain(minLevel) or 0
        local usable = not playerLevel or minLevel <= playerLevel
        if id == HEARTHSTONE then
          consider("hearth", id, name or "Hearthstone", 0)
        elseif classID == 0 and subID == 5 then
          local use = plain(try(C_Item.GetItemSpell, id))
          local isFood, isDrink = use ~= "Drink", use ~= "Food"
          if isFood then out.food = out.food + count; if usable then consider("food", id, name, minLevel) end end
          if isDrink then out.drink = out.drink + count; if usable then consider("drink", id, name, minLevel) end end
        elseif classID == 0 and subID == 7 then
          if usable then consider("bandage", id, name, minLevel) end
        elseif classID == 0 and subID == 1 and type(name) == "string" then
          if usable and name:find("Healing Potion", 1, true) and not name:find("Discolored", 1, true) then
            consider("healingpotion", id, name, minLevel)
          elseif usable and name:find("Mana Potion", 1, true) then
            consider("manapotion", id, name, minLevel)
          end
        elseif type(name) == "string" and name:find("Healthstone$") then
          consider("healthstone", id, name, minLevel)
        end
      end
    end
  end
  if not any then return nil end
  return out
end

function API.canRepair()
  return plain(try(CanMerchantRepair)) == true
end

---------------------------------------------------------------------------
-- Action bar (out of combat only)
---------------------------------------------------------------------------

-- Action slots of each bar, and the frame that shows it.
local BARS = {
  [1] = { first = 1, name = "your main bar" },
  [2] = { first = 61, name = "Action Bar 2", frame = "MultiBarBottomLeft" },
  [3] = { first = 49, name = "Action Bar 3", frame = "MultiBarBottomRight" },
}
function API.barInfo(bar) return BARS[bar] end

-- Is that bar switched on? true / false, nil when the game won't say.
function API.barShown(bar)
  if bar == 1 then return true end
  local info = BARS[bar]
  if not info then return false end
  local toggles = { try(GetActionBarToggles) }
  local v = plain(toggles[bar - 1])
  if type(v) == "boolean" then return v end
  local frame = _G[info.frame]
  if frame and frame.IsShown then
    local shown = plain(try(frame.IsShown, frame))
    if type(shown) == "boolean" then return shown end
  end
  return nil
end

-- Which page your main bar shows (1 is the normal one). Shift+number and the
-- small arrows next to the bar switch pages; pages 2-6 are usually empty.
function API.barPage()
  local page = plain(try(C_ActionBar.GetActionBarPage))
  return type(page) == "number" and page or nil
end

-- Stops Shift+1..6 from switching bar pages (only those still on the game's
-- default). Returns the keys it freed. Out of combat only.
function API.freePageKeys()
  local freed = {}
  if API.inCombat() then return freed end
  for i = 1, 6 do
    local key = "SHIFT-" .. i
    if plain(try(GetBindingAction, key)) == "ACTIONPAGE" .. i then
      try(SetBinding, key)
      freed[#freed + 1] = key
    end
  end
  if #freed > 0 then try(SaveBindings, plain(try(GetCurrentBindingSet)) or 1) end
  try(C_ActionBar.SetActionBarPage, 1)
  return freed
end

-- The item on an action button, if it holds one.
function API.slotItem(slot)
  local kind, id = try(GetActionInfo, slot)
  if plain(kind) == "item" then return plain(id) end
end

function API.slotEmpty(slot)
  return plain((try(GetActionInfo, slot))) == nil
end

-- Puts a spell (by id) or a macro (by name) on an action button.
-- Whatever was there is removed. Returns true when the button now holds something.
function API.placeAction(slot, what)
  if API.inCombat() then return false end
  try(ClearCursor)
  if what.item then
    try(C_Item.PickupItem, what.item)
  elseif what.macro then
    try(PickupMacro, what.macro)
  else
    try(C_Spell.PickupSpell, what.spell)
  end
  try(PlaceAction, slot)
  try(ClearCursor)
  return not API.slotEmpty(slot)
end

-- Empties an action button. Returns true when it is empty afterwards.
function API.clearAction(slot)
  if API.inCombat() then return false end
  try(ClearCursor)
  try(PickupAction, slot)
  try(ClearCursor)   -- dropping what was picked up removes it from the bar; the spell, macro or item itself stays yours
  return API.slotEmpty(slot)
end

-- What an action button holds, in the form API.placeAction takes: { spell = id },
-- { macro = name } or { item = id }. Anything else (a mount, an equipment set)
-- comes back as { other = kind }: it can be seen and cleared, not put back.
-- nil for an empty button.
function API.slotContent(slot)
  local kind, id = try(GetActionInfo, slot)
  kind, id = plain(kind), plain(id)
  if kind == nil then return nil end
  if kind == "spell" and id then return { spell = id } end
  if kind == "item" and id then return { item = id } end
  if kind == "macro" then
    local name = plain(try(C_ActionBar.GetActionText, slot))
    if not name and id then name = plain(try(GetMacroInfo, id)) end
    if type(name) == "string" and name ~= "" then return { macro = name } end
  end
  return { other = tostring(kind) }
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

-- Points spent in each of your three talent trees, in the game's order, or nil
-- when the game does not list three trees.
function API.talentPoints()
  local points = {}
  eachTalentTree(function(config, tree, index)
    local spent = 0
    local nodes = C_Traits.GetTreeNodes(tree)
    if type(nodes) == "table" then
      for n = 1, upTo(#nodes, 400) do
        local ranks = field(C_Traits.GetNodeInfo(config, nodes[n]), "ranksPurchased")
        if type(ranks) == "number" and ranks > 0 and ranks <= 10 then spent = spent + ranks end
      end
    end
    points[index] = spent
  end)
  if #points ~= 3 then return nil end
  return points
end

-- A talent name reduced to letters and digits, so "Improved Life Tap" from a
-- guide and from the game compare equal whatever the spacing or punctuation.
function API.talentKey(name)
  return (tostring(name):lower():gsub("[^%a%d]", ""))
end

-- Every talent in your talent window, by name:
--   { list = { { node, name, rank, bought, max } }, byName = { [key] = entry }, spent = points }
-- `rank` includes points you have clicked but not applied yet; `bought` does not.
-- nil when the game won't say.
local talentNames = {}   -- node id -> name (a talent keeps its name for the whole session)
function API.talents()
  local out = { list = {}, byName = {}, spent = 0 }
  eachTalentTree(function(config, tree)
    local nodes = C_Traits.GetTreeNodes(tree)
    if type(nodes) ~= "table" then return end
    for n = 1, upTo(#nodes, 400) do
      pcall(function()
        local node = plain(nodes[n])
        if type(node) ~= "number" then return end
        local info = C_Traits.GetNodeInfo(config, node)
        if type(info) ~= "table" or field(info, "isVisible") == false then return end
        local name = talentNames[node]
        if not name then
          local entries = field(info, "entryIDs")
          local entry = type(entries) == "table" and plain(entries[1])
          if type(entry) ~= "number" then return end
          local definition = field(C_Traits.GetEntryInfo(config, entry), "definitionID")
          if type(definition) ~= "number" then return end
          local def = C_Traits.GetDefinitionInfo(definition)
          name = field(def, "overrideName")
          if type(name) ~= "string" or name == "" then
            local spell = field(def, "spellID") or field(def, "overriddenSpellID")
            name = type(spell) == "number" and API.spellName(spell) or nil
          end
          if type(name) ~= "string" or name == "" then return end
          talentNames[node] = name
        end
        local bought, current, max = field(info, "ranksPurchased"), field(info, "currentRank"), field(info, "maxRanks")
        bought = (type(bought) == "number" and bought > 0 and bought <= 10) and bought or 0
        local rank = (type(current) == "number" and current > bought and current <= 10) and current or bought
        local e = { node = node, name = name, rank = rank, bought = bought, max = (type(max) == "number" and max >= 1 and max <= 10) and max or 1 }
        out.list[#out.list + 1] = e
        out.byName[API.talentKey(name)] = e
        out.spent = out.spent + bought
      end)
    end
  end)
  if #out.list == 0 then return nil end
  return out
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
  local keys, icons, slots = {}, {}, {}
  API.barIcons, API.barSlots = icons, slots
  for slot = 1, 180 do
    local binding = bindingForSlot(slot)
    if binding then
      local kind, id = try(GetActionInfo, slot)
      kind, id = plain(kind), plain(id)
      if kind == "spell" and id then
        local name = API.spellName(id)
        if name and keys[name] == nil then
          keys[name] = shortKey(plain(try(GetBindingKey, binding))) or false
          icons[name] = picture(try(C_ActionBar.GetActionTexture, slot))
          slots[name] = slot
        end
      elseif kind == "item" and id then
        if keys["item:" .. id] == nil then keys["item:" .. id] = shortKey(plain(try(GetBindingKey, binding))) or false end
      elseif kind == "macro" then
        -- remembered as "macro:<name>" so the key can stand in for the spells inside it
        local name = plain(try(C_ActionBar.GetActionText, slot))
        if not name and id then name = plain(try(GetMacroInfo, id)) end
        if name and keys["macro:" .. name] == nil then
          keys["macro:" .. name] = shortKey(plain(try(GetBindingKey, binding))) or false
          slots["macro:" .. name] = slot
        end
      end
    end
  end
  return keys
end

-- The game's own button for an action slot, when it is on screen right now.
-- Only the game's standard bars are known; another bar addon's buttons are not.
local BAR_BUTTONS = {
  { 1, 12, "ActionButton" }, { 61, 72, "MultiBarBottomLeftButton" }, { 49, 60, "MultiBarBottomRightButton" },
  { 25, 36, "MultiBarRightButton" }, { 37, 48, "MultiBarLeftButton" },
  { 145, 156, "MultiBar5Button" }, { 157, 168, "MultiBar6Button" }, { 169, 180, "MultiBar7Button" },
}
function API.barButton(slot)
  if type(slot) ~= "number" then return nil end
  for _, bar in ipairs(BAR_BUTTONS) do
    if slot >= bar[1] and slot <= bar[2] then
      local button = _G[bar[3] .. (slot - bar[1] + 1)]
      if type(button) ~= "table" then return nil end
      -- the main bar shows another page's buttons while it is switched away from page 1
      if bar[1] == 1 and (API.barPage() or 1) ~= 1 then return nil end
      if plain(try(button.IsVisible, button)) ~= true then return nil end
      -- In a stance or form the main bar's buttons hold other slots: only light a button that really shows this one.
      local showing = plain(button.action)
      if type(showing) == "number" and showing ~= slot then return nil end
      return button
    end
  end
end

-- A short sound for the coach's cue. Returns false when the game would not play it.
local SOUNDS = { click = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856 }, ready = { "READY_CHECK", 8960 } }
function API.sound(kind)
  local sound = SOUNDS[kind]
  if not sound then return false end
  local id = (type(SOUNDKIT) == "table" and SOUNDKIT[sound[1]]) or sound[2]
  local ok, played = pcall(PlaySound, id, "Master")
  return ok and played ~= false
end

---------------------------------------------------------------------------
-- Are the game's action bars on screen? (read only)
---------------------------------------------------------------------------
-- ClassCoach never hides, moves, resizes or re-parents the game's bars. This
-- only LOOKS at them, so that when they vanish the addon can say which frame
-- went and what the game was doing. Walks from a bar's first button up to
-- the screen and names the first frame that is hidden, transparent or has
-- lost its place.
local WATCHED = { { "ActionButton1", "main bar" }, { "MultiBarBottomLeftButton1", "Action Bar 2" }, { "MultiBarBottomRightButton1", "Action Bar 3" } }

local function frameName(f)
  local name = f.GetName and plain(try(f.GetName, f))
  return type(name) == "string" and name or "a frame without a name"
end

-- One bar: { name, there = the bar exists, visible, why = "MainActionBar is hidden" }.
local function lookAt(buttonName, barName)
  local out = { name = barName, there = false, visible = false }
  local f = _G[buttonName]
  if type(f) ~= "table" then return out end
  out.there = true
  out.visible = plain(try(f.IsVisible, f)) == true
  if out.visible then return out end
  for _ = 1, 8 do   -- a button is never more than a few frames below the screen
    if type(f) ~= "table" or f == UIParent then break end
    local shown = f.IsShown and plain(try(f.IsShown, f))
    local alpha = f.GetAlpha and plain(try(f.GetAlpha, f))
    local points = f.GetNumPoints and plain(try(f.GetNumPoints, f))
    if shown == false then out.why = frameName(f) .. " is hidden" break end
    if type(alpha) == "number" and alpha < 0.05 then out.why = frameName(f) .. " is transparent" break end
    if points == 0 then out.why = frameName(f) .. " has lost its place on screen (no anchor)" break end
    f = f.GetParent and try(f.GetParent, f)
  end
  out.why = out.why or "the game does not say why"
  return out
end

-- Every watched bar, plus what the game says about special bars. Safe in combat.
function API.barState()
  local bars = {}
  for i, w in ipairs(WATCHED) do bars[i] = lookAt(w[1], w[2]) end
  local flags = {}
  for _, name in ipairs({ "HasOverrideActionBar", "HasVehicleActionBar", "HasTempShapeshiftActionBar", "HasBonusActionBar" }) do
    local fn = _G[name]
    if type(fn) == "function" and plain(try(fn)) == true then flags[#flags + 1] = name end
  end
  return { bars = bars, flags = flags, page = API.barPage(), combat = API.inCombat() }
end
