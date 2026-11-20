-- A tiny fake WoW client so ClassCoach can be loaded and exercised outside the game.
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
function UnitCharacterPoints() return P.talentPoints or 0 end
function GetInventoryItemDurability(slot) if slot == 16 and P.durability then return P.durability, 100 end end
C_Container = { GetContainerNumFreeSlots = function(bag) if bag == 0 then return P.freeSlots or 10 end return 0 end }
function UnitCreatureFamily(u) if u == "pet" then return P.pet and P.pet.family end end
function UnitIsUnit() return SECRET end

-- Macros
M.macros = {}
function GetMacroIndexByName(name) for i, m in ipairs(M.macros) do if m.name == name then return i end end return 0 end
function GetMacroBody(i) return M.macros[i] and M.macros[i].body end
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
  GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #P.book } end,
  GetSpellBookItemInfo = function(i)
    local id = P.book[i]
    return id and { spellID = id, name = P.spells[id].name, isPassive = false } or nil
  end,
}
C_Spell = {
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
function GetWeaponEnchantInfo() return hidden(P.mainHand) end
function GetTotemInfo(slot) return hidden(P.totems[slot] == true) end
C_Item = { GetItemCount = function(id) return P.items[id] or 0 end }   -- by id or by name
function GetInventoryItemID(_, slot) return P.equipped[slot] end
function GetTalentTabInfo(tab) return tab, "Tree" .. tab, "", "icon", P.talents[tab] or 0 end
function GetActionInfo(slot) local id = P.actions[slot]; if id then return "spell", id end end
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
  }
  return setmetatable(w, { __index = function(_, k) return methods[k] or function() end end })
end
UIParent = widget()
function CreateFrame()
  local f = widget()
  M.frames[#M.frames + 1] = f
  return f
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

return M
