-- Lights up the action-bar button of the step to press now, so the cue is also
-- where your eyes and fingers already are. The look is the shared glow
-- (UI/Glow.lua): yours to pick in the settings, with a colour.
local _, ns = ...

local Bar = {}
ns.BarGlow = Bar

Bar.STYLES = ns.Glow.STYLES
Bar.around = ns.Glow.around

function Bar.hide()
  if Bar.holder and Bar.slot then ns.Glow.hide(Bar.holder) end
  Bar.slot, Bar.button = nil, nil
end

-- slot: the action slot holding the step to press now, or nil for none.
function Bar.update(slot, db)
  local button = slot and db.barGlow ~= "off" and ns.API.barButton(slot) or nil
  if not button then Bar.hide() return end
  Bar.holder = Bar.holder or ns.Glow.new("ClassCoachBarGlow")
  if ns.Glow.show(Bar.holder, button, db.barGlow, db.glowColor) then
    Bar.slot, Bar.button = slot, button
  else
    Bar.hide()
  end
end
