-- What both panels share: the colours and typefaces of the design, round
-- icons, key badges, and the dark plate that keeps text readable on any ground.
-- Everything here is drawn with what the game has: flat colour textures,
-- texture files from the Media folder (the game cannot draw a circle itself), a mask
-- for round icons, and fonts from the Fonts folder.
local _, ns = ...

local Style = {}
ns.Style = Style

local MEDIA = "Interface\\AddOns\\ClassCoach\\Media\\"
local FONTS = "Interface\\AddOns\\ClassCoach\\Fonts\\"
Style.MEDIA = MEDIA
-- The game's own round mask (the one behind unit portraits).
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FACES = { body = "Inter-Regular.ttf", bold = "Inter-Bold.ttf", title = "Marcellus-Regular.ttf" }

Style.COLORS = {
  ink = { 0.937, 0.914, 0.863 }, muted = { 0.722, 0.698, 0.639 }, dark = { 0.039, 0.043, 0.051 },
  line = { 0.204, 0.220, 0.251 }, accent = { 0.941, 0.761, 0.294 }, mana = { 0.357, 0.608, 0.918 },
  warn = { 0.941, 0.643, 0.357 }, danger = { 1.00, 0.35, 0.30 }, ok = { 0.541, 0.827, 0.604 },
  xp = { 0.545, 0.420, 0.820 },
}

-- Text.
--
-- Every text starts as one of the game's own fonts, picked by size. That is the
-- look that is known to work in Forever, and what a text falls back to.
--
-- ClassCoach's own typefaces (Inter, Marcellus) are an option. What the game
-- showed so far: set while the addon loads at login, they drew on some texts
-- and nothing at all on others; set later (the /coach fonts test card), every
-- typeface drew at every size, with and without a set width. So they are never
-- set at creation. Style.dress puts them on a few seconds after login, checks
-- each text really took its typeface, and puts any that did not back on its
-- game font.
local GAME_FONTS = {   -- { from this design size up, the font, the same with an outline }
  { 17, "GameFontHighlightLarge", "GameFontHighlightLarge" },
  { 13.5, "GameFontHighlightMedium", "GameFontHighlightMedium" },
  { 11.5, "GameFontHighlight", "GameFontHighlightOutline" },
  { 0, "GameFontHighlightSmall", "GameFontHighlightSmallOutline" },
}
local SMALLEST = "GameFontHighlightSmall"
local MAX_TRIES = 5
local function gameFont(size, flags)
  for _, row in ipairs(GAME_FONTS) do
    if size >= row[1] then
      local name = flags == "OUTLINE" and row[3] or row[2]
      if type(_G[name]) == "table" then return name end
      if type(_G[row[2]]) == "table" then return row[2] end
    end
  end
  return SMALLEST
end

-- text -> { safe = its game font, face, size, flags, own = wearing its typeface, tries, healed }
local known = setmetatable({}, { __mode = "k" })

local function sameFile(a, b)
  return type(a) == "string" and type(b) == "string" and a:lower():gsub("/", "\\") == b:lower():gsub("/", "\\")
end

-- A text that holds words and measures nothing. A text the game keeps secret
-- (seen in game: comparing it raised an error) is unknown, never "nothing".
local function plainText(fs)
  local ok, text = pcall(fs.GetText, fs)
  if not ok or (issecretvalue and issecretvalue(text)) or type(text) ~= "string" then return nil end
  return text
end
local function drawsNothing(fs)
  local text = fs.GetText and plainText(fs)
  if not text or text == "" then return false end
  local w = fs.GetStringWidth and fs:GetStringWidth()
  if issecretvalue and issecretvalue(w) then return false end
  return type(w) == "number" and w <= 0
end

local function backToGameFont(fs, k)
  k.own = false
  if _G[k.safe] then pcall(fs.SetFontObject, fs, _G[k.safe]) end
end

-- Puts a text's own typeface on it and checks that it took. Returns true when it did.
function Style.font(fs)
  local k = known[fs]
  local file = k and FACES[k.face] and (FONTS .. FACES[k.face])
  if not file then return false end
  k.tries = (k.tries or 0) + 1
  local ok, set = pcall(fs.SetFont, fs, file, k.size, k.flags or "")
  local took = ok and set ~= false and sameFile(select(2, pcall(fs.GetFont, fs)), file) and not drawsNothing(fs)
  if took then
    k.own = true
    -- Seen in game (journey list): a text that already held its words when the
    -- typeface changed kept its old layout and drew nothing, and setting the same
    -- words again does not lay it out anew. Clearing and setting them does.
    local text = plainText(fs)
    if text and text ~= "" then fs:SetText(""); fs:SetText(text) end
  else
    Style.fontMissing = FACES[k.face]
    backToGameFont(fs, k)
  end
  return took
end

-- A text. `flags` is "OUTLINE" for text that sits straight on the game world, with no plate behind it.
function Style.text(parent, face, size, color, flags)
  local safe = gameFont(size, flags)
  local fs = parent:CreateFontString(nil, "OVERLAY", safe)
  known[fs] = { safe = safe, face = face, size = size, flags = flags }
  -- Once the typefaces went on after login (Style.dress), a new text wears its own
  -- at once: a layout measured in the game's font and then drawn in a wider one
  -- runs out of its place (seen in game in the settings window).
  if Style.ownFonts and Style.dressedOnce then Style.font(fs)
  elseif Style.ownFonts then Style.pending = true end
  local c = color or Style.COLORS.ink
  fs:SetTextColor(c[1], c[2], c[3])
  fs:SetJustifyH("LEFT")
  return fs
end

-- Puts ClassCoach's typefaces on every text (on = true) or takes them off again.
-- Safe to call again: it only touches texts that still need it, and gives a
-- text up after a few tries. Returns how many wear their typeface and how many do not.
function Style.dress(on)
  Style.ownFonts = on == true
  Style.dressedOnce = Style.ownFonts or nil
  Style.fontEpoch = (Style.fontEpoch or 0) + 1
  Style.pending = false
  local dressed, plain = 0, 0
  for fs, k in pairs(known) do
    if not on then
      if k.own then backToGameFont(fs, k) end
      k.tries, k.healed = 0, nil
    elseif not k.own and not k.healed and (k.tries or 0) < MAX_TRIES then
      -- one text that fails must not leave the rest half dressed
      local ok, took = pcall(Style.font, fs)
      if not ok then k.tries = MAX_TRIES; backToGameFont(fs, k)
      elseif not took and k.tries < MAX_TRIES then Style.pending = true end
    end
    if k.own then dressed = dressed + 1 else plain = plain + 1 end
  end
  Style.dressed, Style.plain = dressed, plain
  return dressed, plain
end

-- Sets a text. A text that wears its own typeface and comes out with no width
-- was not drawn: it goes back to its game font for good.
function Style.set(fs, value)
  fs:SetText(value)
  local k = known[fs]
  if k and k.own and drawsNothing(fs) then
    k.healed = true
    Style.healed = (Style.healed or 0) + 1
    backToGameFont(fs, k)
    fs:SetText(value)
  end
end

-- In the real game: which of ClassCoach's texts do not fit. No tool outside the
-- game can draw its fonts, so the game itself is asked: a text it cut short
-- (IsTruncated), one that holds words and measures nothing (not drawn), and two
-- texts of the same frame drawn over each other. Returns lines in words.
function Style.layoutCheck()
  local function call(fs, m)
    local f = fs[m]
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, fs)
    if ok and not (issecretvalue and issecretvalue(v)) then return v end
  end
  local issues, byParent, seen = {}, {}, 0
  for fs in pairs(known) do
    seen = seen + 1
    if seen > 2000 then break end
    local text = call(fs, "GetText")
    if type(text) == "string" and text ~= "" and call(fs, "IsVisible") == true then
      local label = '"' .. text:gsub("%s+", " "):sub(1, 34) .. '"'
      if call(fs, "IsTruncated") == true then issues[#issues + 1] = label .. " is cut short" end
      if drawsNothing(fs) then issues[#issues + 1] = label .. " measures nothing: it is not drawn" end
      local l, r, t, b = call(fs, "GetLeft"), call(fs, "GetRight"), call(fs, "GetTop"), call(fs, "GetBottom")
      if type(l) == "number" and type(r) == "number" and type(t) == "number" and type(b) == "number" then
        local p = call(fs, "GetParent") or "none"
        byParent[p] = byParent[p] or {}
        local list = byParent[p]
        list[#list + 1] = { label = label, l = l, r = r, t = t, b = b }
      end
    end
  end
  for _, list in pairs(byParent) do
    for i = 1, math.min(#list, 200) do
      for j = i + 1, math.min(#list, 200) do
        local a, c = list[i], list[j]
        local wide = math.min(a.r, c.r) - math.max(a.l, c.l)
        local high = math.min(a.t, c.t) - math.max(a.b, c.b)
        if wide > 2 and high > 2 then issues[#issues + 1] = a.label .. " and " .. c.label .. " are drawn over each other" end
      end
    end
  end
  table.sort(issues)
  return issues
end

-- One text in words, for /coach check: which font it reports, how wide it measures, whether it is shown.
function Style.describe(fs)
  local ok, path, size = pcall(fs.GetFont, fs)
  local file = ok and type(path) == "string" and path:match("[^\\/]+$") or "no font"
  local text = fs.GetText and fs:GetText()
  local w = fs.GetStringWidth and fs:GetStringWidth()
  return ("%s %s, %d letters, width %s, %s"):format(file, type(size) == "number" and ("%.0f"):format(size) or "?",
    type(text) == "string" and #text or 0, type(w) == "number" and ("%.0f"):format(w) or "?", fs:IsShown() and "shown" or "hidden")
end

-- /coach fonts: a test card. Each of ClassCoach's typefaces and the game's own
-- font file, at every size the design uses and a few around them, once as a
-- plain label and once with a set width. What shows on the card, and the
-- letters in chat, say what this client accepts.
local PROBE_SIZES = { 9, 10, 11, 12, 13, 14, 16, 18, 19, 20 }
function Style.probe()
  if Style.probeFrame then
    Style.probeFrame:SetShown(not Style.probeFrame:IsShown())
    return {}
  end
  local c = Style.COLORS
  local f = CreateFrame("Frame", "ClassCoachFontProbe", UIParent)
  Style.probeFrame = f
  f:SetFrameStrata("DIALOG")
  f:SetSize(700, 40 + #PROBE_SIZES * 24)
  f:SetPoint("TOP", UIParent, "TOP", 0, -60)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(c.dark[1], c.dark[2], c.dark[3], 0.95)
  local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  head:SetPoint("TOPLEFT", 10, -8)
  head:SetText("ClassCoach font test. Left of each pair: a plain label. Right: the same with a set width. /coach fonts hides this.")
  local gameFile = STANDARD_TEXT_FONT
  if type(GameFontNormal) == "table" and GameFontNormal.GetFont then
    local ok, path = pcall(GameFontNormal.GetFont, GameFontNormal)
    if ok and type(path) == "string" then gameFile = path end
  end
  local columns = { { "Inter-Regular", FONTS .. FACES.body }, { "Inter-Bold", FONTS .. FACES.bold },
    { "Marcellus", FONTS .. FACES.title }, { "game font", gameFile or "Fonts\\FRIZQT__.TTF" } }
  local function cell(col, row, file, size, wide)
    local fs = f:CreateFontString(nil, "OVERLAY", SMALLEST)
    local ok, set = pcall(fs.SetFont, fs, file, size, "")
    fs:SetTextColor(c.ink[1], c.ink[2], c.ink[3])
    fs:SetJustifyH("LEFT")
    fs:SetPoint("TOPLEFT", 10 + (col - 1) * 172 + (wide and 84 or 0), -30 - (row - 1) * 24)
    if wide then
      fs:SetWidth(80)
      fs:SetWordWrap(false)
    end
    fs:SetText("Ag8 " .. size)
    local w = fs.GetStringWidth and fs:GetStringWidth()
    local took = fs.GetFont and select(2, pcall(fs.GetFont, fs))
    -- T/F/n/E: what SetFont answered (true, false, nothing, an error); w/0: whether the text has a width; =/x: whether the text reports this file
    return (not ok and "E" or set == true and "T" or set == false and "F" or "n")
      .. ((type(w) == "number" and w > 0) and "w" or "0")
      .. (sameFile(took, file) and "=" or "x")
  end
  local lines = {}
  for col, column in ipairs(columns) do
    local parts = {}
    for row, size in ipairs(PROBE_SIZES) do
      parts[#parts + 1] = ("%d:%s/%s"):format(size, cell(col, row, column[2], size, false), cell(col, row, column[2], size, true))
    end
    lines[#lines + 1] = column[1] .. "  " .. table.concat(parts, " ")
  end
  lines[#lines + 1] = "Each entry is size:plain/with a width. T F n E = SetFont said true, false, nothing, or raised an error; w or 0 = the text has a width or not; = or x = the text reports this font file or another."
  return lines
end

function Style.tint(tex, c, a)
  tex:SetVertexColor(c[1], c[2], c[3], a or 1)
end

-- One of ClassCoach's own shapes (ring, ring_bold, disc, pulse), filling `parent`.
function Style.shape(parent, name, layer, sub)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
  t:SetTexture(MEDIA .. name)
  t:SetAllPoints(parent)
  return t
end

-- Cuts a square spell icon into a circle. If the game refuses the mask, the
-- icon stays square with its border cropped: plainer, never broken.
function Style.round(owner, icon)
  local ok = pcall(function()
    local mask = owner:CreateMaskTexture()
    mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
  end)
  if not ok then pcall(icon.SetTexCoord, icon, 0.07, 0.93, 0.07, 0.93) end
  return ok
end

-- Four straight lines around a frame: the game has no border of its own to give.
local EDGES = {
  { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
  { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
}
function Style.edges(f, layer, thickness, color)
  local lines = {}
  for i, e in ipairs(EDGES) do
    local line = f:CreateTexture(nil, layer)
    line:SetPoint(e[1])
    line:SetPoint(e[2])
    if e[3] then line:SetHeight(thickness) else line:SetWidth(thickness) end
    line:SetColorTexture(color[1], color[2], color[3], 1)
    lines[i] = line
  end
  return lines
end

-- The tooltip every icon shares. An icon sets what it has: title, spell (what
-- to cast), bind (its key), does (what a click does, on a clickable icon), hint.
function Style.tooltip(self)
  if type(self.title) ~= "string" or not GameTooltip then return end
  local key = type(self.bind) == "string" and self.bind or nil
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(self.title, 1, 0.82, 0.2)
  if self.clickable then
    GameTooltip:AddLine("Click to " .. (type(self.does) == "string" and self.does or "cast it") .. (key and (" (or press " .. key .. ")") or "") .. ".", 1, 1, 1)
  elseif type(self.spell) == "string" then
    GameTooltip:AddLine("Cast " .. self.spell .. (key and (" (" .. key .. ")") or ""), 1, 1, 1)
  elseif key then
    GameTooltip:AddLine("Key " .. key, 1, 1, 1)
  end
  if type(self.hint) == "string" then GameTooltip:AddLine(self.hint, 0.9, 0.9, 0.9, true) end
  GameTooltip:Show()
end
function Style.hideTooltip()
  if GameTooltip then GameTooltip:Hide() end
end

-- The small dark square that shows a key: a flat fill, four hairlines, a text.
function Style.badge(parent, size)
  local b = CreateFrame("Frame", nil, parent)
  b:SetSize(size, size)
  b.size = size
  local c = Style.COLORS
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(c.dark[1], c.dark[2], c.dark[3], 1)
  Style.edges(b, "BORDER", 1, c.line)
  b.text = Style.text(b, "bold", math.floor(size * 0.62 + 0.5), c.ink)
  b.text:SetPoint("CENTER")
  b.text:SetJustifyH("CENTER")
  return b
end

-- Shows a key on a badge, or hides the badge when there is none. A long key
-- ("SF1") widens the badge instead of spilling out of it.
function Style.setBadge(b, key)
  if not key or key == "" then
    b.text:SetText("")
    b:Hide()
    return
  end
  Style.set(b.text, key)
  local w = b.text.GetStringWidth and b.text:GetStringWidth()
  b:SetWidth(math.max(b.size, (type(w) == "number" and w or 0) + 8))
  b:Show()
end

-- Wraps a script handler (mouse-over, drag) so it can never raise an error
-- into the game; a problem is noted in the addon's own log instead.
-- A plain flat button in the coach's look: a tinted plate with a hairline edge.
function Style.button(parent, label, width)
  local S, C = Style, Style.COLORS
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width or 120, 24)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.16)
  b.edges = S.edges(b, "BORDER", 1, C.accent)
  b.label = S.text(b, "bold", 12, C.accent)
  b.label:SetPoint("CENTER")
  b.label:SetJustifyH("CENTER")
  S.set(b.label, label)
  local function shade(self, a)
    local c = self.off and C.line or C.accent
    self.bg:SetColorTexture(c[1], c[2], c[3], a)
  end
  b:SetScript("OnEnter", function(self) if not self.off then shade(self, 0.32) end end)
  b:SetScript("OnLeave", function(self) shade(self, 0.16) end)
  b.shade = shade
  return b
end

-- Greys a Style.button out (on = false) or brings it back; a greyed button ignores clicks.
function Style.enable(b, on)
  b.off = not on
  b:EnableMouse(on and true or false)
  local c = on and Style.COLORS.accent or Style.COLORS.muted
  b.label:SetTextColor(c[1], c[2], c[3])
  for _, e in ipairs(b.edges) do e:SetColorTexture(c[1], c[2], c[3], on and 1 or 0.5) end
  b.shade(b, 0.16)
end

function Style.guard(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok and ns.API and ns.API.log then ns.API.log("panel: %s", tostring(err)) end
  end
end

-- The dark plate behind a panel's text.
function Style.skin(f)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  f.skinBg = bg
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
  local alpha = (db.opacity or 60) / 100
  if f.skinAlpha ~= alpha then
    f.skinAlpha = alpha
    local c = Style.COLORS.dark
    f.skinBg:SetColorTexture(c[1], c[2], c[3], alpha)
  end
  scale = scale or 1
  if f.skinScale ~= scale then
    f.skinScale = scale
    f:SetScale(scale)
  end
end
