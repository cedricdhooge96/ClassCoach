-- One look for every "press this" cue: the action-bar button to press, the
-- next talent, a spell to drag out of the spellbook, and the preview in the
-- settings. A glow is ClassCoach's own frame laid over the target: it is never
-- a child of the target, never takes a click and never changes the target.
--   glow      a soft halo that breathes
--   frame     a steady frame
--   sparkles  bright points running around the edge
--   ants      short dashes marching around the edge
local _, ns = ...

local Glow = {}
ns.Glow = Glow

Glow.STYLES = { { "glow", "Glow" }, { "sparkles", "Sparkles" }, { "ants", "Marching ants" }, { "frame", "Frame" }, { "off", "Off" } }
Glow.COLORS = { { "gold", "Gold" }, { "blue", "Blue" }, { "green", "Green" }, { "white", "White" }, { "purple", "Purple" } }
local KNOWN = { glow = true, frame = true, sparkles = true, ants = true }
local PALETTE = { gold = "accent", blue = "mana", green = "ok", white = "ink", purple = "xp" }
local SPARKS, DASHES = 8, 12
local HALO_INSET = 0.25   -- how far in the halo texture its frame sits (see tools/gen_textures.py)

-- A style or colour from saved settings, made safe.
function Glow.style(v, fallback) return KNOWN[v] and v or (v == "off" and "off") or fallback or "glow" end
function Glow.color(v)
  local key = PALETTE[v] or PALETTE.gold
  return ns.Style.COLORS[key]
end

-- Where a point is after travelling share p (0 to 1) of the way around a w by h rectangle, clockwise from the top left.
-- The second pair says along which edge it travels: true for a top or bottom edge.
local function around(p, w, h)
  local d = (p % 1) * 2 * (w + h)
  if d < w then return d, 0, true end
  d = d - w
  if d < h then return w, -d, false end
  d = d - h
  if d < w then return w - d, -h, true end
  return 0, -(h - (d - w)), false
end
Glow.around = around

local function animate(h)
  local t = GetTime()
  if h.style == "glow" then
    h.halo:SetAlpha(0.55 + 0.45 * math.sin(t * 4))
    return
  end
  local w, tall = h:GetWidth(), h:GetHeight()
  if type(w) ~= "number" or type(tall) ~= "number" or w <= 0 or tall <= 0 then return end
  if h.style == "sparkles" then
    for i, dot in ipairs(h.sparks) do
      local x, y = around(t * 0.45 + (i - 1) / SPARKS, w, tall)
      dot:ClearAllPoints()
      dot:SetPoint("CENTER", h, "TOPLEFT", x, y)
      dot:SetAlpha(0.55 + 0.45 * math.sin(t * 9 + i * 1.7))
    end
  elseif h.style == "ants" then
    for i, dash in ipairs(h.dashes) do
      local x, y, flat = around(t * 0.2 + (i - 1) / DASHES, w, tall)
      dash:ClearAllPoints()
      dash:SetPoint("CENTER", h, "TOPLEFT", x, y)
      if flat then dash:SetSize(7, 2) else dash:SetSize(2, 7) end
    end
  end
end

-- name: a global name for /fstack and bug reports, or nil.
function Glow.new(name)
  local S = ns.Style
  local h = CreateFrame("Frame", name, UIParent)
  h:SetFrameStrata("MEDIUM")
  h:SetFrameLevel(20)
  h:EnableMouse(false)
  h.edges = S.edges(h, "OVERLAY", 2, S.COLORS.accent)
  h.halo = h:CreateTexture(nil, "OVERLAY")
  h.halo:SetTexture(S.MEDIA .. "halo")
  h.halo:SetPoint("CENTER")
  pcall(h.halo.SetBlendMode, h.halo, "ADD")
  h.sparks, h.dashes = {}, {}
  for i = 1, SPARKS do
    local dot = h:CreateTexture(nil, "OVERLAY")
    dot:SetTexture(S.MEDIA .. "disc")
    dot:SetSize(6, 6)
    pcall(dot.SetBlendMode, dot, "ADD")
    h.sparks[i] = dot
  end
  for i = 1, DASHES do
    local dash = h:CreateTexture(nil, "OVERLAY")
    dash:SetColorTexture(1, 1, 1, 1)
    dash:SetSize(7, 2)
    h.dashes[i] = dash
  end
  h:Hide()
  return h
end

-- Puts a style and colour on a glow. Returns false for "off".
function Glow.dress(h, style, colorKey)
  style = Glow.style(style)
  colorKey = PALETTE[colorKey] and colorKey or "gold"
  if h.style == style and h.colorKey == colorKey then return style ~= "off" end
  h.style, h.colorKey = style, colorKey
  local c = Glow.color(colorKey)
  for _, line in ipairs(h.edges) do
    line:SetColorTexture(c[1], c[2], c[3], 1)
    line:SetShown(style == "frame" or style == "sparkles")
    line:SetAlpha(style == "sparkles" and 0.45 or 1)
  end
  ns.Style.tint(h.halo, c)
  h.halo:SetShown(style == "glow")
  for _, dot in ipairs(h.sparks) do
    dot:SetVertexColor(0.5 + c[1] / 2, 0.5 + c[2] / 2, 0.5 + c[3] / 2, 1)   -- a lighter shade: a spark is a point of light
    dot:SetShown(style == "sparkles")
  end
  for _, dash in ipairs(h.dashes) do
    dash:SetColorTexture(c[1], c[2], c[3], 1)
    dash:SetShown(style == "ants")
  end
  h:SetScript("OnUpdate", (style == "glow" or style == "sparkles" or style == "ants") and ns.Style.guard(animate) or nil)
  return style ~= "off"
end

-- Lays the glow over a target frame, just above it. Reads the target, never changes it.
function Glow.attach(h, target)
  if h.target == target then return end
  h.target = target
  h:ClearAllPoints()
  h:SetAllPoints(target)
  local strata = target.GetFrameStrata and target:GetFrameStrata()
  local level = target.GetFrameLevel and target:GetFrameLevel()
  if type(strata) == "string" then h:SetFrameStrata(strata) end
  h:SetFrameLevel(math.min((type(level) == "number" and level or 10) + 10, 9000))
  local w = target.GetWidth and target:GetWidth()
  w = type(w) == "number" and w > 0 and w or 45
  local size = w / (1 - 2 * HALO_INSET)
  h.halo:SetSize(size, size)
end

-- Shows the glow on target with a style and colour; nil target or "off" hides it.
function Glow.show(h, target, style, colorKey)
  if not target or not Glow.dress(h, style, colorKey) then
    Glow.hide(h)
    return false
  end
  Glow.attach(h, target)
  if not h:IsShown() then h:Show() end
  return true
end

function Glow.hide(h)
  if h.target then h.target = nil end
  if h:IsShown() then h:Hide() end
end
