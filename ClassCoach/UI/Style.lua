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
