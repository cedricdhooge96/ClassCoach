-- When the coach's step is a spell that is on none of your action bars, the
-- spell lights up in your spellbook, so you can drag it onto a bar.
--
-- Forever's spellbook is PlayerSpellsFrame.SpellBookFrame; the spells on the
-- open page are frames of its PagedSpellsFrame, each knowing which spell it
-- shows (spellBookItemInfo). ClassCoach reads that and lays the shared glow
-- (UI/Glow.lua) over the spell's button. It never turns pages, never opens
-- the book and never changes its frames.
local _, ns = ...

local Book = {}
ns.Spellbook = Book

local MOST = 200   -- frames on a page, at most

local function visible(frame)
  local ok, shown = pcall(frame.IsVisible, frame)
  return ok and shown == true
end

local function book()
  local spells = _G.PlayerSpellsFrame
  local b = type(spells) == "table" and spells.SpellBookFrame
  local paged = type(b) == "table" and b.PagedSpellsFrame
  if type(paged) ~= "table" or type(paged.EnumerateFrames) ~= "function" then return nil end
  return b, paged
end

-- Is the spellbook open right now?
function Book.open()
  local b = book()
  return b ~= nil and visible(b)
end

-- The button showing the spell called `name` on the open page, or nil.
function Book.find(name)
  local b, paged = book()
  if not b or not visible(b) or type(name) ~= "string" then return nil end
  local found
  pcall(function()
    local n = 0
    for _, frame in paged:EnumerateFrames() do
      n = n + 1
      if n > MOST then break end
      local info = type(frame) == "table" and frame.spellBookItemInfo
      local shown = type(info) == "table" and info.name
      if type(shown) == "string" and shown == name and visible(frame) then
        found = type(frame.Button) == "table" and frame.Button or frame
        break
      end
    end
  end)
  return found
end

function Book.hide()
  if Book.holder then ns.Glow.hide(Book.holder) end
  Book.lit = nil
end

-- name: the spell to drag onto a bar, or nil. Out of combat only.
-- Returns "lit" (found and lit on the open page), "elsewhere" (the book is
-- open on another page), "closed", or nil when there is nothing to do.
function Book.update(name, db, inCombat)
  if not name or inCombat or db.spellbookGlow == false then Book.hide() return nil end
  if not Book.open() then Book.hide() return "closed" end
  local button = Book.find(name)
  if not button then Book.hide() return "elsewhere" end
  Book.holder = Book.holder or ns.Glow.new("ClassCoachSpellbookGlow")
  local style = db.barGlow ~= "off" and db.barGlow or "glow"
  ns.Glow.show(Book.holder, button, style, db.glowColor)
  Book.lit = name
  return "lit"
end
