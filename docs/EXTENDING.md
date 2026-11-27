# Adding a class or spec to ClassCoach

The engine has no class knowledge. Everything about a class lives in one file,
`ClassCoach/Profiles/<Class>.lua`, which calls `ns.RegisterProfile({ ... })`
once per spec. To add a class:

1. Copy `docs/ProfileTemplate.lua` to `ClassCoach/Profiles/<Class>.lua`.
2. Fill it in (fields below).
3. Add the file to `ClassCoach.toc` under the other profiles.
4. Run the tests (`tests/run.sh`, and `luacheck .`), then `/reload` in game and `/coach check`.

ClassCoach is for WoW Forever only. Use Forever's spell names, trainer levels and talents (a Forever
guide or the in-game trainer, not the original game's), and if you add a call to the game in
`Core/API.lua`, use a function the Forever client has and add its name to the `NEEDS` list there so
`/coach check` can report it. `tests/run.sh forever` fails on a call Forever lacks, and `luacheck .` flags a game function that is not in `NEEDS`.

Several specs of one class go in the same file, each with its own `RegisterProfile` call.
Shared spell lists can be a local table at the top of the file (see `Shaman.lua`).

## Profile fields

| Field | Required | Meaning |
|---|---|---|
| `class` | yes | Class token: `WARRIOR`, `PALADIN`, `HUNTER`, `ROGUE`, `PRIEST`, `SHAMAN`, `MAGE`, `WARLOCK`, `DRUID` |
| `spec` | yes | Name shown on the panel and used by `/coach spec <name>` |
| `tab` | no | Talent tree number (1–3). The tree with the most points picks the profile |
| `default` | no | `true` for the profile used before level 10 or with no matching tree |
| `freeDamage` | no | What does damage for free, used in tips: `"your melee swings"`, `"your wand"` |
| `restHint` | no | Hint shown when mana is low out of combat (default: "Drink before the next pull.") |
| `mana` | no | `{ low = 25, medium = 55 }`: mana % lines for the low / medium / high levels |
| `spells` | yes | Every spell the profile mentions (see below) |
| `priority` | no | In combat: what to press, in order |
| `opener` | no | Out of combat with an enemy targeted: how to pull |
| `filler` | no | What to do when nothing in `priority` fits (default: melee) |
| `checklist` | no | What must be on before a pull |
| `advice` | no | Live line in combat per mana level: `{ low = "...", medium = "..." }` (string or function) |
| `tips` | no | After-fight coaching rules |
| `trainer` | no | `[level] = "spells taught"` |
| `talents` | no | `{ fromLevel, toLevel, "talent name" }` ranges |

### spells

```lua
spells = {
  ["Flame Shock"] = { ids = { 8050, 8052, 8053 }, debuff = 12 },
  ["Searing Totem"] = { ids = { 3599 }, totem = "fire", lasts = 30 },
  ["Penance"] = {},                 -- no known id: found by English name
  ["Stormstrike"] = { ids = { 17364 }, core = true },
}
```

- **Key** = English spell name. All other fields refer to spells by this key.
- `ids`: every rank, lowest first. The addon uses the highest rank you know, and
  remembers rank 1 (`/coach check` shows both). Missing or changed ids fall back to the name.
- `debuff = seconds`: a damage-over-time spell. The addon times it per enemy from your casts,
  so `s:debuffUp("Flame Shock")` works in combat.
- `totem = "fire" | "earth" | "water" | "air"`, `lasts = seconds`: for `s:totemUp("fire")`.
- `core = true`: a main spell. The generic "most of your mana went on X" tip skips it.
- `learn = 8`: the level the trainer sells it. From that level the checklist says "Not trained: X" until it is learned.
- `cd = true`: it has a cooldown, so the chain preview won't show it twice in a row. Spells sharing one cooldown use the same name: `cd = "shock"`.
- `cdTime = 6`: that cooldown in seconds. In a fight Forever hides cooldown times and, during the global cooldown, reads every spell as busy; with `cdTime` the coach counts the cooldown from your own last cast instead of guessing "ready" (which made the ring jump back and forth). A clear answer from the game (a reset) still wins.
- Opener entries that are totems or buffs on yourself (`totem`, `self`) don't start the fight: the plan carries on down the opener list, so a pull plan can be "shield, totems, then the pull spell".
- `debuff = 18`: it leaves damage over time on the enemy for about that long. The real length is read from the spell's description when possible; this is the fallback. The coach then tracks it per enemy and stops suggesting it on enemies about to die (add `always = true` to a priority entry to opt out).
- `harm = true`: it damages or hinders the enemy, so it can be resisted. (Spells with `debuff` count already.) Add `travel = true` when it flies to the enemy, so its result arrives later.
- `auto = true`: it repeats by itself once started (a wand). It is never treated as "on cooldown".
- `summons = "Voidwalker"`: casting it brings out that pet (`s.demon`).
- `restores = 0.15`: it gives mana back (Life Tap): a rough share of maximum mana, for the mana level.

### priority, opener, filler

```lua
priority = {
  { spell = "Stormstrike", why = "Your main attack." },
  { spell = "Flame Shock", mana = "medium",
    when = function(s) return not s:debuffUp("Flame Shock") end,
    why = "Put Flame Shock on the enemy once." },
},
filler = {
  { spell = "Shoot", when = function(s) return s.hasWand end, why = "Wand: free damage." },
  { label = "Melee", why = "Your swings cost nothing." },
},
```

The first entry that passes all of these is shown:
the spell is known → off cooldown → affordable → `mana` level allows it
(`"any"`, `"medium"` = medium or high, `"high"`) → `minLevel` → `when(s)` returns true.
Unknown values (the game hiding something) count as "fine", so advice never freezes.

### The `s` object your functions receive

| Field / method | Meaning |
|---|---|
| `s.level`, `s.inCombat`, `s.inGroup`, `s.fightTime` | Basics |
| `s.manaPct`, `s.manaLevel` (`"high"`/`"medium"`/`"low"`), `s.manaExact`, `s.usesMana` | Mana |
| `s.target.exists`, `.hostile`, `.dead`, `.elite`, `.level` | Target (name may be hidden in combat) |
| `s.hasWand` | Something in the ranged slot |
| `s.demon` | Which pet is out, when known (`"Imp"`, `"Voidwalker"`, ...) |
| `s:debuffLeft(key)`, `s:timeOnTarget()`, `s.killTime` | Seconds left on your spell on this enemy; seconds on this enemy; your usual kill time |
| `s.hasPet` | Pet out (`nil` = unknown). In combat: what it was at the pull |
| `s.healthPct` | Your health %, out of combat only |
| `s:known(key)`, `s:ready(key)`, `s:usable(key)` | Spell checks (`nil` = unknown) |
| `s:debuffUp(key)`, `s:totemUp(element)` | Own timers from your casts |
| `s:sinceCast(key)`, `s:castsOnTarget(key)` | Seconds since last cast; casts on this enemy this fight |
| `s:buff(keyOrName)` | Out of combat only; `nil` when hidden |

Never read game functions inside a profile: use `s`. That keeps profiles safe
from Forever's hidden values and lets the tests run them.

`why`, `label` and `hint` may be a string or a `function(s)` returning one. Use a
function whenever the text names a spell, a pet or a wand the character may not
have yet: `s:have({ "A", "B" })` returns the names of the ones that are known
("A and B", or `nil`). The level sweep in `tests/run.lua` fails if any text
names a spell before it is learned.

Entries also take `minLevel` / `maxLevel`. A `filler` entry with a `spell` follows
the same rules as a priority entry (known, ready, affordable, `mana`, `when`).

The panel's chain strip is built from `priority`, `opener` and `filler`
automatically (`Engine.chain`): it presses each step in a simulation and asks
what comes next.

### macros

```lua
macros = {
  { name = "CC Pull", about = "Shown after /coach macros.",
    body = function(s)                       -- return nil when the spells aren't known yet
      if not s:known("Frostbolt") then return nil end
      return "#showtooltip\n/cast " .. s.spells["Frostbolt"].name
    end },
}
```

`body` and `about` also receive the coach's pull plan as a second argument:
`function(s, plan)`. `ns.Engine.sequence(plan, skip, tail)` turns it into the
spell names for a `/castsequence`. Bodies are limited to 255 characters and use the spell names from `s.spells[key].name`.
After-fight tips also get `f.demon`, `f.precast` (you cast before combat started),
`f.targets` and `f.elite`.

### smart

```lua
smart = {
  pet = true,                      -- every press also sends the pet in
  attack = true,                   -- every press also starts your auto attack
  finish = "Stormstrike",          -- the spell the sequence ends on, a few times
  gate = { when = "[pet:Voidwalker,nocombat]", macro = "CC Send" },  -- hold step one while this is true
  skip = { ["Power Word: Shield"] = true },                           -- steps with their own key
},
-- A spec whose fight has more choices than one fixed list (mana, number of enemies):
smart = { attack = true, pull = true, combat = "Stormstrike" },
--   out of a fight the key walks the pull plan (a shield, totems, the pull spell);
--   in a fight it only casts `combat`, so it can never stall on a spell that cannot
--   be cast or drop a totem on an add. The coach shows the other spells, each on its own key.
```

The smart key's steps come from the same pull plan as the macros
(`Engine.smartSteps`). Macros it needs are ordinary `macros` entries marked
`smart = true`.

### bar, supplies, milestones

```lua
bars = {                                  -- three bars by purpose, up to 12 buttons each
  fight = {                               -- main bar: entries in bar order, best candidate first;
                                          -- one you cannot use yet takes no button, so the bar has no gaps
    { "macro:CC Pull", "Frostbolt" },     -- a CC macro, else a spell key
  },
  react = { { "book:Blink" }, { "book:Counterspell" } },   -- Action Bar 2; "book:" = not in `spells`
  prep  = { { "book:Arcane Intellect" }, { "book:Conjure Water" } },   -- Action Bar 3
},
supplies = { { item = 17020, name = "Arcane Powder", needs = "Arcane Brilliance", low = 5 } },
milestones = {
  { level = 20, text = "Blink", hint = "Your escape: put it on an easy key." },
  { level = 5, text = "Get a wand", done = function(s) return s.hasWand end },
},
```

A milestone with `done` stays on the journey panel until it is done; without it,
it shows for that level and the next. Milestones for every class, and the zones
and dungeons per level, are in `Data/Journey.lua`.

### checklist

```lua
checklist = {
  { buff = { "Lightning Shield", "Water Shield" }, label = "No shield", hint = "Cast it before the pull." },
  { weapon = { "Windfury Weapon", "Rockbiter Weapon" }, label = "No weapon buff", hint = "..." },
  { item = 17030, needs = "Reincarnation", label = "No Ankh", hint = "..." },
  { slot = 18, needs = "Shoot", label = "No wand", hint = "..." },
  { pet = true, needs = { "Summon Imp", "Summon Voidwalker" }, label = "No demon", hint = "..." },
  { check = function(s) return s.level >= 20 and not s:buff("Some Buff") end, label = "...", hint = "..." },
}
```

Buff and weapon checks only nag when you know at least one of the spells.
`needs` = a spell key (or list) the character must know; `minLevel` also works.
Give a `tip` entry an `icon = "Interface\\Icons\\..."` for its row on the journey panel.
A missing entry is shown as the icon of the spell that fixes it: by default the
first spell of its `buff` / `weapon` / `needs` list that you know. Set
`fix = "Spell"` or `fix = function(s) return "Spell" end` to choose another, or
`icon = "Interface\\Icons\\..."` for something that is not a spell. A profile's
`restFix = "Life Tap"` is the icon for low mana.
Add `tip = true` to an entry that is advice rather than something to fix before
every pull (a missing wand, a class quest, a reagent): it then shows on the
journey panel instead. Health and mana checks, and the journey panel's XP,
rested XP, food, talent, trainer, repair and bag lines, are added for every class
automatically (`Engine.journey`).
After a fight, tips get `f.hadPet` (was a pet out at the pull).

### tips

```lua
tips = {
  function(f, s)
    if (f.castCount["Earth Shock"] or 0) >= 2 and (f.endPct or 100) < 45 then
      return "Keep Earth Shock for interrupts; melee is free."
    end
  end,
},
```

`f` is the fight summary: `duration`, `castCount[key]`, `spentBy[key]`, `spent`,
`startPct`, `endPct`, `spentPct`, `swings`, `casts` (list sorted by mana).
Return a sentence or `nil`. At most two tips show, profile tips first.

## What happens when a profile is wrong

A profile that is not a table, has no class, or lists a spell it never defined is skipped with a note
instead of stopping the addon: `/coach errors` shows which one and why. Your `when`, `why`, `advice`
and `tips` functions are called inside a guard too, so an error in one costs that line, not the panel.
Counts you read from the game should go through `ns.API.upTo(n, most)` before you loop over them.

## Testing a new profile

Add a scenario to `tests/run.lua` (copy the Shaman one): give the fake player the spells,
cast them, and check what the panel shows. The fake client returns hidden values
in combat exactly where Forever does, so a profile that passes there won't break in game.
