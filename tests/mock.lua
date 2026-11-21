-- A tiny fake WoW Forever client so ClassCoach can be loaded and exercised outside the game.
-- It offers only functions the Forever client has (no globals from other versions of
-- the game), so a call to anything else simply finds nothing here, as it would there.
-- In combat, mana, buffs, weapon buffs and enemy names come back as SECRET,
-- like on WoW Forever: comparing or adding a SECRET raises an error.
local M = {}

local SECRET = setmetatable({}, {
  __tostring = function() return "SECRET" end,
  __lt = function() error("compared a secret value") end,
  __le = function() error("compared a secret value") end,
  __add = function() error("arithmetic on a secret value") end,
  __sub = function() error("arithmetic on a secret value") end,
  __mul = function() error("arithmetic on a secret value") end,
  __div = function() error("arithmetic on a secret value") end,
  __index = function() error("indexed a secret value") end,
})
M.SECRET = SECRET
function issecretvalue(v) return rawequal(v, SECRET) end

M.now = 1000
function GetTime() return M.now end
date = os.date
M.printed = {}
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  M.printed[#M.printed + 1] = table.concat(parts, " ")
end

-- The player -------------------------------------------------------------
local P = {}
M.P = P
function M.player(t)
  for k in pairs(P) do P[k] = nil end
  P.class = t.class; P.className = t.className; P.level = t.level or 10
  P.powerType = t.powerType or 0
  P.mana, P.maxMana = t.mana or 300, t.maxMana or 300
  P.combat = false
  P.buffs, P.mainHand, P.totems, P.items, P.equipped = {}, false, {}, {}, t.equipped or {}
  P.target = nil
  P.spells = t.spells or {}        -- id -> { name, cost }
  P.book = t.book or {}            -- list of ids in the spellbook (all ranks)
  P.cooldowns = {}
  P.actions, P.bindings = t.actions or {}, t.bindings or {}
  P.talents = t.talents or { 0, 0, 0 }
  P.pet = t.pet                    -- nil = no pet, else { dead = bool }
  P.health, P.maxHealth = t.health or 200, t.maxHealth or 200
  P.knownIds = {}
  for _, id in ipairs(P.book) do P.knownIds[id] = true end
end

local function hidden(v) if P.combat then return SECRET end return v end

function UnitClass(u) if u == "player" then return P.className, P.class end end
function UnitLevel(u) if u == "player" then return P.level end return P.target and P.target.level end
function UnitPowerType() return P.powerType end
function UnitPower(_, kind) if kind == 0 or kind == nil then return hidden(P.powerType == 0 and P.mana or 0) end end
-- The percent is hidden in combat too, unless a test says this client shows it.
CurveConstants = { ScaleTo100 = "ScaleTo100" }
function UnitPowerPercent()
  local pct = P.maxMana > 0 and P.mana / P.maxMana * 100 or 0
  if M.percentReadable then return pct end
  return hidden(pct)
end
function UnitPowerMax(_, kind) if kind == 0 or kind == nil then return hidden(P.powerType == 0 and P.maxMana or 0) end end
function UnitAffectingCombat(u) if u == "player" then return P.combat end end
function InCombatLockdown() return P.combat end
function IsInGroup() return false end
function UnitExists(u)
  if u == "target" then return P.target ~= nil end
  if u == "pet" then return P.pet ~= nil end
  return true
end
function UnitHealth(u) if u == "player" then return hidden(P.health) end end
function UnitHealthMax(u) if u == "player" then return hidden(P.maxHealth) end end
function UnitCanAttack() return P.target and P.target.hostile or false end
function UnitIsDead(u)
  if u == "pet" then return P.pet and P.pet.dead or false end
  return P.target and P.target.dead or false
end
function UnitName(u) if u == "target" then return P.target and hidden(P.target.name) end return "Marida" end
function UnitClassification() return P.target and P.target.classification or "normal" end
-- Some clients hide enemy ids: tests switch that on with M.secretGuid.
function UnitGUID(u)
  if u ~= "target" or not P.target then return nil end
  if M.secretGuid then return SECRET end
  return P.target.guid
end
-- Journey: XP, rested XP, talents, gear, bags
function UnitXP() return P.xp or 0 end
function UnitXPMax() return P.xpMax or 1000 end
function GetXPExhaustion() return P.rested end
function IsResting() return P.resting or false end
-- Talents live in Forever's traits system: one config, three trees, nodes with ranks.
C_ClassTalents = {
  GetActiveConfigID = function() return 1 end,
  HasUnspentTalentPoints = function() return (P.talentPoints or 0) > 0 end,
}
-- With P.tree set ({ { name, max, rank, staged } ... }) the character has ONE tree holding every talent of the
-- class, as the Forever client does. Without it: three anonymous trees filled from P.talents.
C_Traits = {
  GetConfigInfo = function()
    if P.tree then return { treeIDs = { 77 } } end
    return { treeIDs = P.oneTree and { 11 } or { 11, 12, 13 } }
  end,
  GetTreeNodes = function(tree)
    local nodes = {}
    if tree == 77 then
      for k = 1, #P.tree do nodes[k] = 7000 + k end
      return nodes
    end
    for k = 1, 12 do nodes[k] = tree * 100 + k end   -- twelve talents a tree, five ranks each, filled from the top
    return nodes
  end,
  GetNodeInfo = function(_, node)
    if node >= 7000 then
      local t = P.tree[node - 7000]
      if not t then return nil end
      return { ID = node, ranksPurchased = t.rank or 0, currentRank = t.staged or t.rank or 0, maxRanks = t.max or 5,
        entryIDs = { node + 1000 }, isVisible = t.hidden ~= true }
    end
    local tree, k = math.floor(node / 100) - 10, node % 100
    local left = (P.talents[tree] or 0) - 5 * (k - 1)
    return { ranksPurchased = math.max(0, math.min(5, left)) }
  end,
  GetEntryInfo = function(_, entry) return { definitionID = entry + 1000 } end,
  GetDefinitionInfo = function(definition)
    local t = P.tree and P.tree[definition - 9000]
    if not t then return nil end
    M.names[definition + 10000] = t.name
    return { spellID = definition + 10000 }
  end,
  GetTreeCurrencyInfo = function(_, tree)
    if P.noTalentCount then return {} end
    return { { quantity = (tree == 11 or tree == 77) and (P.talentPoints or 0) or 0, spent = 0 } }
  end,
}
C_CVar = {
  SetCVar = function(name, value) M.cvars[name] = value end,
  GetCVar = function(name) return M.cvars[name] end,
}
M.cvars = {}
-- This is the Forever client: its project id, and no functions from other versions.
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC, WOW_PROJECT_CAMELOT = 1, 2, 23
WOW_PROJECT_ID = WOW_PROJECT_CAMELOT
function GetInventoryItemDurability(slot) if slot == 16 and P.durability then return P.durability, 100 end end
-- P.bag = { { id, count, class, sub, use } }: bag 0 holds everything
C_Container = {
  GetContainerNumFreeSlots = function(bag) if bag == 0 then return P.freeSlots or 10 end return 0 end,
  GetContainerNumSlots = function(bag) if bag == 0 then return #(P.bag or {}) end return 0 end,
  GetContainerItemInfo = function(bag, slot)
    local it = bag == 0 and P.bag and P.bag[slot]
    if it then return { itemID = it.id, stackCount = it.count } end
  end,
}
function UnitCreatureFamily(u) if u == "pet" then return P.pet and P.pet.family end end
function UnitIsUnit() return SECRET end

-- Macros
M.macros = {}
function GetMacroIndexByName(name) for i, m in ipairs(M.macros) do if m.name == name then return i end end return 0 end
function GetMacroBody(i) return M.macros[i] and M.macros[i].body end
function GetMacroInfo(i) return M.macros[i] and M.macros[i].name end
function GetNumMacros() return 0, #M.macros end
function CreateMacro(name, icon, body, perChar)
  assert(not P.combat, "macros cannot be made in combat")
  M.macros[#M.macros + 1] = { name = name, icon = icon, body = body, perChar = perChar }
  return #M.macros
end
function EditMacro(i, name, icon, body)
  assert(not P.combat, "macros cannot be changed in combat")
  M.macros[i].name, M.macros[i].body = name, body
  return i
end

C_SpellBook = {
  IsSpellKnown = function(id) return P.spells[id] ~= nil and P.knownIds and P.knownIds[id] or false end,
  GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookItemTexture = function(i) local id = P.book[i]; return id and P.bookIcons and P.bookIcons[id] end,
  GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #P.book } end,
  GetSpellBookItemInfo = function(i)
    local id = P.book[i]
    return id and { spellID = id, name = P.spells[id].name, isPassive = false, iconID = P.bookIcons and P.bookIcons[id] } or nil
  end,
}
C_Spell = {
  IsAutoRepeatSpell = function(id) return P.repeating == id end,
  PickupSpell = function(id) M.cursor = { spell = id } end,
  GetSpellDescription = function(id) return P.spells[id] and P.spells[id].text end,
  GetSpellName = function(id) return P.spells[id] and P.spells[id].name or M.names[id] end,
  GetSpellTexture = function(id) return "Interface\\Icons\\spell_" .. id end,
  GetSpellPowerCost = function(id) local s = P.spells[id]; return s and { { type = 0, cost = s.cost or 0 } } or {} end,
  IsSpellUsable = function(id)
    local s = P.spells[id]
    if not s or not (P.knownIds and P.knownIds[id]) then return false, false end
    local short = (s.cost or 0) > P.mana
    return not short, short
  end,
  GetSpellCooldown = function(id)
    local untilTime = P.cooldowns[id]
    return { isActive = untilTime ~= nil and M.now < untilTime, isOnGCD = false }
  end,
}
M.names = {}
C_NamePlate = { GetNamePlates = function() return {} end }
C_Secrets = { ShouldAurasBeSecret = function() return P.combat end }
C_UnitAuras = {
  GetAuraDataByIndex = function(_, i)
    local list = {}
    for name in pairs(P.buffs) do list[#list + 1] = name end
    table.sort(list)
    if not list[i] then return nil end
    return { name = hidden(list[i]) }
  end,
}
function GetTotemInfo(slot) return hidden(P.totems[slot] == true) end
C_Item = {
  GetItemCount = function(id) return P.items[id] or 0 end,   -- by id or by name
  GetItemInfo = function(id)
    for _, it in ipairs(P.bag or {}) do if it.id == id then return it.name or ("item " .. id), "", 1, it.min or 1, it.min or 1 end end
  end,
  PickupItem = function(id) M.cursor = { item = id } end,
  GetItemSpell = function(id) for _, it in ipairs(P.bag or {}) do if it.id == id then return it.use end end end,
  -- one entry per enchant layer: the permanent enchant (type 1) and the imbue (type 3)
  GetWeaponEnchantInfo = function(slot)
    if slot ~= 0 then return {} end
    if P.combat then return SECRET end
    return {
      { hasEnchant = P.permanentEnchant == true, timeLeft = 0, charges = 0, enchantType = 1, enchantID = 1 },
      { hasEnchant = P.mainHand == true, timeLeft = 1800000, charges = 0, enchantType = 3, enchantID = 2 },
    }
  end,
  GetItemInfoInstant = function(id)
    for _, it in ipairs(P.bag or {}) do if it.id == id then return id, "", "", "", 0, it.class, it.sub end end
  end,
}
function GetInventoryItemID(_, slot) return P.equipped[slot] end
-- An action button holds a spell id, or { macro = name }.
function GetActionInfo(slot)
  local a = P.actions[slot]
  if type(a) == "table" and a.item then return "item", a.item end
  if type(a) == "table" then return "macro", GetMacroIndexByName(a.macro) end
  if a then return "spell", a end
end
C_ActionBar = {
  GetActionTexture = function(slot)
    local a = P.actions[slot]
    if type(a) == "number" then return P.barIcons and P.barIcons[a] end
  end,
  GetActionText = function(slot) local a = P.actions[slot]; if type(a) == "table" then return a.macro end end,
  GetActionBarPage = function() return P.page or 1 end,
  SetActionBarPage = function(n) P.page = n end,
}
function ClearCursor() M.cursor = nil end
function GetBindingAction(key) return P.keyActions and P.keyActions[key] or "" end
function SetBinding(key, action) P.keyActions = P.keyActions or {}; P.keyActions[key] = action end
function PickupMacro(name) M.cursor = { macro = name } end
function PlaceAction(slot)
  assert(not P.combat, "the action bar cannot change in combat")
  local held = M.cursor
  M.cursor = P.actions[slot]          -- what was there ends up on the cursor
  if held then P.actions[slot] = held.spell or held end   -- a spell id, { macro = name } or { item = id }
end
function UnitClassification(u) if u == "target" and P.target then return P.target.elite and "elite" or "normal" end end
-- The game's talent window: PlayerSpellsFrame.TalentsFrame, one button per talent of P.tree.
function M.talentWindow(open)
  if open == nil then PlayerSpellsFrame = nil return end
  local buttons = {}
  for k = 1, #(P.tree or {}) do
    local node = 7000 + k
    buttons[k] = { GetNodeID = function() return node end, IsVisible = function() return P.tree[k].hidden ~= true end, node = node }
  end
  local talents = {
    open = open,
    IsVisible = function(self) return self.open == true end,
    EnumerateAllTalentButtons = function()
      local i = 0
      return function() i = i + 1; return buttons[i] end
    end,
    GetFrameStrata = function() return "HIGH" end,
    GetFrameLevel = function() return 10 end,
    buttons = buttons,
  }
  PlayerSpellsFrame = { TalentsFrame = talents }
  return talents
end
-- Secure environment
M.drivers = {}
function RegisterStateDriver(frame, state, conditions) M.drivers[state] = { frame = frame, conditions = conditions } end
function SetBindingClick(key, button, click) P.bindings["CLICK " .. button .. ":" .. (click or "LeftButton")] = key end
function SaveBindings() end
function GetCurrentBindingSet() return 1 end
-- The game's own condition parser, for the conditions the smart key uses.
function M.secureParse(text)
  if text:find("%[channeling%]") then return M.channeling and "hold" or "go" end
  if text:find("pet:Voidwalker,nocombat", 1, true) then
    return (P.pet and P.pet.family == "Voidwalker" and not P.combat) and "hold" or "go"
  end
  return "go"
end
-- One key press on a secure button: the wrapped snippet runs (down, then up), then the button acts.
function M.press(b, click)
  local fn = assert(loadstring("return function(self, button, down, SecureCmdOptionParse) " .. b.wrapped.OnClick .. "\nend"))()
  M.inSecure = true
  fn(b, click or "LeftButton", true, M.secureParse)
  fn(b, click or "LeftButton", false, M.secureParse)
  M.inSecure = false
  local kind = b:GetAttribute("type")
  if kind == "spell" then return "spell", b:GetAttribute("spell") end
  if kind == "macro" then return "macro", b:GetAttribute("macro") end
  return nil
end
-- The state driver noticing there is no living enemy targeted.
function M.secureReset(b)
  local fn = assert(loadstring("return function(self, newstate) " .. b:GetAttribute("_onstate-ccreset") .. "\nend"))()
  M.inSecure = true; fn(b, "reset"); M.inSecure = false
end
-- Action Bars 2 and 3 are on unless a test switches one off: P.bars = { false, true }
function GetActionBarToggles()
  local b = P.bars or {}
  return b[1] ~= false, b[2] ~= false, true, true
end
-- P.professions = { { name, skill, max } }: the first two are the primary ones, as GetProfessions returns them.
function GetProfessions()
  local list = P.professions or {}
  return list[1] and 1 or nil, list[2] and 2 or nil, nil, list[3] and 3 or nil, list[4] and 4 or nil
end
function GetProfessionInfo(i)
  local p = (P.professions or {})[i]
  if p then return p.name, "Interface\\Icons\\Trade_" .. p.name, p.skill, p.max, 0, 0, 100 + i end
end
function UnitFactionGroup() return P.faction or "Alliance" end
function CanMerchantRepair() return P.vendorRepairs == true end
function GetBindingKey(b) return P.bindings[b] end
function GetBuildInfo() return "1.60.1", "99999", "Nov 2026", 16001 end
Enum = { SpellBookSpellBank = { Player = 0 } }

-- Frames ------------------------------------------------------------------
M.frames = {}
local function widget()
  local w = { scripts = {}, events = {}, shown = true, text = "" }
  local methods = {
    SetScript = function(self, name, fn) self.scripts[name] = fn end,
    GetScript = function(self, name) return self.scripts[name] end,
    RegisterEvent = function(self, e) self.events[e] = true end,
    RegisterUnitEvent = function(self, e) self.events[e] = true end,
    UnregisterEvent = function(self, e) self.events[e] = nil end,
    CreateTexture = function() return widget() end,
    CreateFontString = function() return widget() end,
    CreateMaskTexture = function() return widget() end,
    AddMaskTexture = function(self, mask) rawset(self, "mask", mask) end,
    SetShown = function(self, on) self.shown = on and true or false end,
    SetSize = function(self, w, h) rawset(self, "width", w); rawset(self, "height", h) end,
    SetWidth = function(self, w) rawset(self, "width", w) end,
    SetHeight = function(self, h) rawset(self, "height", h) end,
    GetWidth = function(self) return rawget(self, "width") end,
    GetCenter = function(self) return rawget(self, "cx") or 683, rawget(self, "cy") or 240 end,
    IsVisible = function(self) return self.shown end,
    SetAlpha = function(self, a) rawset(self, "alpha", a) end,
    SetStatusBarColor = function(self, r, g, b) rawset(self, "barColor", { r, g, b }) end,
    SetVertexColor = function(self, r, g, b, a) rawset(self, "color", { r, g, b, a }) end,
    SetFont = function(self, path, size, flags)
      if M.refuseFonts and path:find("AddOns") then return false end
      rawset(self, "font", { path, size, flags })
      return true
    end,
    SetText = function(self, t) self.text = t end,
    SetFormattedText = function(self, fmt, v)
      if v == SECRET then self.text, self.secretText = fmt, true else self.text, self.secretText = fmt:format(v), false end
    end,
    SetMinMaxValues = function(self, lo, hi) self.min, self.max = lo, hi end,
    GetText = function(self) return self.text end,
    GetStringHeight = function() return 12 end,
    IsShown = function(self) return self.shown end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
    SetValue = function(self, v) self.value = v end,
    SetTexture = function(self, t) self.texture = t end,
    -- geometry, for panel placement: a test sets .left / .bottom / .top
    GetLeft = function(self) return rawget(self, "left") end,
    GetBottom = function(self) return rawget(self, "bottom") end,
    GetTop = function(self) return rawget(self, "top") end,
    GetHeight = function(self) return rawget(self, "height") end,
    GetScale = function(self) return rawget(self, "scale") or 1 end,
    SetScale = function(self, v) rawset(self, "scale", v) end,
    SetFrameStrata = function(self, v) rawset(self, "strata", v) end,
    EnableMouse = function(self, v) rawset(self, "mouse", v) end,
    SetPoint = function(self, ...) rawset(self, "point", { ... }) end,
    -- secure buttons: attributes may not change in combat, like the real thing
    SetAttribute = function(self, k, v)
      assert(not (P.combat and not M.inSecure), "attributes cannot change in combat")
      if not rawget(self, "attrs") then rawset(self, "attrs", {}) end
      self.attrs[k] = v
    end,
    GetAttribute = function(self, k) local a = rawget(self, "attrs"); return a and a[k] end,
    WrapScript = function(self, _, script, body)
      if not rawget(self, "wrapped") then rawset(self, "wrapped", {}) end
      self.wrapped[script] = body
    end,
  }
  return setmetatable(w, { __index = function(_, k) return methods[k] or function() end end })
end
UIParent = widget()
UIParent.height = 768
-- Secure frames (a template starting with "Secure") follow the game's rule: they
-- cannot be made, shown, hidden, moved or resized while a fight is on.
local PROTECTED = { "Show", "Hide", "SetPoint", "ClearAllPoints", "SetSize", "SetScale", "SetShown" }
function CreateFrame(kind, name, parent, template)
  local f = widget()
  f.kind, f.name, f.template = kind, name, template
  if type(template) == "string" and template:find("Secure") then
    assert(not P.combat, "a secure frame cannot be created in combat")
    f.secure = true
    for _, method in ipairs(PROTECTED) do
      local plain = f[method]
      rawset(f, method, function(...)
        assert(not (P.combat and not M.inSecure), method .. " on a secure frame in combat")
        return plain(...)
      end)
    end
  end
  if name then _G[name] = f end
  M.frames[#M.frames + 1] = f
  return f
end

M.sounds = {}
function PlaySound(id, channel) M.sounds[#M.sounds + 1] = id; return true end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, READY_CHECK = 8960 }
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

-- The game's own action buttons, so the bar highlight has something to sit on.
for _, bar in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton" }) do
  for i = 1, 12 do
    local b = widget()
    b.width = 45
    _G[bar .. i] = b
  end
end
function M.fire(event, ...)
  for _, f in ipairs(M.frames) do
    if (f.events[event] or event == "ADDON_LOADED") and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

M.timers = {}
C_Timer = { After = function(sec, fn) M.timers[#M.timers + 1] = { at = M.now + sec, fn = fn } end }
function M.advance(sec)
  M.now = M.now + sec
  local due, keep = {}, {}
  for _, t in ipairs(M.timers) do if t.at <= M.now then due[#due + 1] = t else keep[#keep + 1] = t end end
  M.timers = keep
  for _, t in ipairs(due) do t.fn() end
end

SlashCmdList = {}
RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 }, WARLOCK = { r = 0.53, g = 0.53, b = 0.93 } }
GameTooltip = widget()

-- The game's Settings system, 11.0.2+ signatures. Wrong argument shapes error, as in the game.
M.settings = { list = {}, headers = {}, buttons = {}, opened = nil }
Settings = {
  RegisterVerticalLayoutCategory = function(name)
    local category = { name = name, GetID = function() return 77 end }
    local page = { AddInitializer = function(_, init) (init.button and M.settings.buttons or M.settings.headers)[#(init.button and M.settings.buttons or M.settings.headers) + 1] = init end }
    return category, page
  end,
  RegisterAddOnSetting = function(category, variable, key, tbl, kind, name, default)
    assert(type(category) == "table" and type(variable) == "string" and type(key) == "string", "bad setting ids")
    assert(type(tbl) == "table", "variableTbl must be the saved table")
    assert(kind == type(default) and type(name) == "string", "bad type or name")
    local s = { variable = variable, key = key, tbl = tbl, name = name, default = default }
    M.settings.list[key] = s
    return s
  end,
  CreateCheckbox = function(_, setting, tip) assert(type(setting.default) == "boolean"); setting.control = "check"; setting.tip = tip end,
  CreateSliderOptions = function(lo, hi, step) return { min = lo, max = hi, step = step, SetLabelFormatter = function(self, _, fn) self.format = fn end } end,
  CreateSlider = function(_, setting, opts, tip) assert(type(setting.default) == "number" and opts.min < opts.max); setting.control = "slider"; setting.opts = opts end,
  CreateControlTextContainer = function()
    local c = { data = {} }
    function c:Add(value, label) self.data[#self.data + 1] = { value = value, label = label } end
    function c:GetData() return self.data end
    return c
  end,
  CreateDropdown = function(_, setting, getOptions) setting.control = "choice"; setting.getOptions = getOptions end,
  RegisterAddOnCategory = function(category) M.settings.category = category end,
  OpenToCategory = function(id) M.settings.opened = id end,
}
MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
function CreateSettingsListSectionHeaderInitializer(name) return { header = name } end
function CreateSettingsButtonInitializer(name, text, onClick, tip) return { button = name, text = text, click = onClick } end

return M
