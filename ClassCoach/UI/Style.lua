-- One look for both panels: a flat dark plate, a hairline border and a thin
-- accent line in your class colour. Opacity, border and size come from the
-- settings and are re-applied whenever they change.
local _, ns = ...

local Style = {}
ns.Style = Style

local EDGES = {
  { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
  { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
}

-- Wraps a script handler (mouse-over, drag) so it can never raise an error
-- into the game; a problem is noted in the addon's own log instead.
function Style.guard(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok and ns.API and ns.API.log then ns.API.log("panel: %s", tostring(err)) end
  end
end

function Style.skin(f)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  f.skinBg = bg
  f.skinEdges = {}
  for i, e in ipairs(EDGES) do
    local line = f:CreateTexture(nil, "BORDER")
    line:SetPoint(e[1])
    line:SetPoint(e[2])
    if e[3] then line:SetHeight(1) else line:SetWidth(1) end
    line:SetColorTexture(1, 1, 1, 0.12)
    f.skinEdges[i] = line
  end
  local accent = f:CreateTexture(nil, "ARTWORK")
  accent:SetPoint("TOPLEFT", 1, -1)
  accent:SetPoint("TOPRIGHT", -1, -1)
  accent:SetHeight(2)
  f.skinAccent = accent
end

-- Pins a panel by the edge that faces the middle of the screen. A panel in
-- the lower half is held by its bottom edge and grows upward; one in the upper
-- half is held by its top and grows downward. Either way it grows away from
-- the screen edge, where your action bars are, instead of over them.
-- Returns the position to save, or nil when the frame has no place yet.
function Style.pin(f)
  local left, bottom, top = f:GetLeft(), f:GetBottom(), f:GetTop()
  local screen, scale = UIParent:GetHeight(), f:GetScale()
  if type(left) ~= "number" or type(bottom) ~= "number" or type(top) ~= "number" or type(screen) ~= "number" then return nil end
  if type(scale) ~= "number" or scale <= 0 then scale = 1 end
  local lower = (bottom + top) / 2 * scale < screen / 2
  local pos = lower and { "BOTTOMLEFT", "BOTTOMLEFT", left, bottom } or { "TOPLEFT", "BOTTOMLEFT", left, top }
  f:ClearAllPoints()
  f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  return pos
end

-- A saved position from before panels were pinned (it let them grow both ways).
function Style.unpinned(pos)
  return pos ~= nil and not (pos[2] == "BOTTOMLEFT" and (pos[1] == "BOTTOMLEFT" or pos[1] == "TOPLEFT"))
end

-- Cheap to call every render: only touches the frame when a value changed.
function Style.apply(f, db, scale)
  local alpha = (db.opacity or 75) / 100
  if f.skinAlpha ~= alpha then
    f.skinAlpha = alpha
    f.skinBg:SetColorTexture(0.04, 0.04, 0.06, alpha)
  end
  local border = db.border ~= false
  if f.skinBorder ~= border then
    f.skinBorder = border
    for _, line in ipairs(f.skinEdges) do if border then line:Show() else line:Hide() end end
  end
  local accent = db.accent ~= false
  if f.skinAccentOn ~= accent then
    f.skinAccentOn = accent
    if accent then
      local r, g, b = ns.API.classColor()
      f.skinAccent:SetColorTexture(r, g, b, 0.9)
      f.skinAccent:Show()
    else
      f.skinAccent:Hide()
    end
  end
  scale = scale or 1
  if f.skinScale ~= scale then
    f.skinScale = scale
    f:SetScale(scale)
  end
end
