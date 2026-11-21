-- Lights up the action-bar button of the step to press now, so the cue is also
-- where your eyes and fingers already are. ClassCoach lays its own frame over
-- the game's button: it is never a child of the button, never takes a click
-- and never touches the button itself. Three looks, yours to pick:
--   frame     a steady gold frame
--   glow      a soft gold glow that breathes
--   sparkles  bright points running around the button
local _, ns = ...

local Glow = {}
ns.BarGlow = Glow

Glow.STYLES = { { "off", "Off" }, { "glow", "Glow" }, { "frame", "Gold frame" }, { "sparkles", "Sparkles" } }
local KNOWN = { glow = true, frame = true, sparkles = true }
local SPARKS = 8
local HALO_INSET = 0.25   -- how far in the halo texture its frame sits (see tools/gen_textures.py)

local function create()
  local S = ns.Style
  local c = S.COLORS.accent
  local h = CreateFrame("Frame", "ClassCoachBarGlow", UIParent)
  h:SetFrameStrata("MEDIUM")
  h:SetFrameLevel(20)
  h:EnableMouse(false)
  h.edges = S.edges(h, "OVERLAY", 2, c)
  h.halo = h:CreateTexture(nil, "OVERLAY")
  h.halo:SetTexture(S.MEDIA .. "halo")
  h.halo:SetPoint("CENTER")
  S.tint(h.halo, c)
  pcall(h.halo.SetBlendMode, h.halo, "ADD")
  h.sparks = {}
  for i = 1, SPARKS do
    local dot = h:CreateTexture(nil, "OVERLAY")
    dot:SetTexture(S.MEDIA .. "disc")
    dot:SetSize(6, 6)
    dot:SetVertexColor(1, 0.93, 0.62, 1)
    pcall(dot.SetBlendMode, dot, "ADD")
    h.sparks[i] = dot
  end
  h:Hide()
  return h
end

-- Where a point is after travelling share p (0 to 1) of the way around a w by h rectangle, clockwise from the top left.
local function around(p, w, h)
  local d = (p % 1) * 2 * (w + h)
  if d < w then return d, 0 end
  d = d - w
  if d < h then return w, -d end
  d = d - h
  if d < w then return w - d, -h end
  return 0, -(h - (d - w))
end
Glow.around = around

local function animate(h)
  local t = GetTime()
  if h.style == "glow" then
    h.halo:SetAlpha(0.55 + 0.45 * math.sin(t * 4))
  elseif h.style == "sparkles" then
    local w, tall = h:GetWidth(), h:GetHeight()
    if type(w) ~= "number" or type(tall) ~= "number" or w <= 0 or tall <= 0 then return end
    for i, dot in ipairs(h.sparks) do
      local x, y = around(t * 0.45 + (i - 1) / SPARKS, w, tall)
      dot:ClearAllPoints()
      dot:SetPoint("CENTER", h, "TOPLEFT", x, y)
      dot:SetAlpha(0.55 + 0.45 * math.sin(t * 9 + i * 1.7))
    end
  end
end

local function dress(h, style)
  if h.style == style then return end
  h.style = style
  for _, line in ipairs(h.edges) do
    line:SetShown(style == "frame" or style == "sparkles")
    line:SetAlpha(style == "sparkles" and 0.45 or 1)
  end
  h.halo:SetShown(style == "glow")
  for _, dot in ipairs(h.sparks) do dot:SetShown(style == "sparkles") end
  h:SetScript("OnUpdate", style ~= "frame" and ns.Style.guard(animate) or nil)
end

function Glow.hide()
  local h = Glow.holder
  if h and Glow.slot then
    h:Hide()
    Glow.slot, Glow.button = nil, nil
  end
end

-- slot: the action slot holding the step to press now, or nil for none.
function Glow.update(slot, db)
  local style = db.barGlow
  if style == "off" or not slot then Glow.hide() return end
  if not KNOWN[style] then style = "glow" end
  local button = ns.API.barButton(slot)
  if not button then Glow.hide() return end
  local h = Glow.holder
  if not h then
    h = create()
    Glow.holder = h
  end
  dress(h, style)
  if Glow.button ~= button then
    Glow.button = button
    h:ClearAllPoints()
    h:SetAllPoints(button)
    -- just above the button, whatever layer its bar is drawn in
    local strata, level = button.GetFrameStrata and button:GetFrameStrata(), button.GetFrameLevel and button:GetFrameLevel()
    if type(strata) == "string" then h:SetFrameStrata(strata) end
    h:SetFrameLevel((type(level) == "number" and level or 10) + 10)
    local w = button.GetWidth and button:GetWidth()
    w = type(w) == "number" and w > 0 and w or 45
    local size = w / (1 - 2 * HALO_INSET)
    h.halo:SetSize(size, size)
  end
  if Glow.slot ~= slot then
    Glow.slot = slot
    h:Show()
  end
end
