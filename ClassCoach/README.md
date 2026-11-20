# ClassCoach

A beginner's coach for WoW Forever that works for any class. One small panel shows:

- **What to press next**: the spell, its key, and why. Out of combat with an enemy targeted, it shows how to pull.
- **The carousel**: on the left what you already did to this enemy, in the middle (bigger) what to press now, on the right what comes next. With nothing targeted it shows your pull plan. Only spells your character has learned are shown.
- **Damage over time, per enemy**: each spell's seconds left on the enemy you are looking at, on the left icons and in the "On this enemy" line. Switch enemies and each keeps its own timers. When a spell is about to matter again the right side says so ("Corruption in 8s").
- **No wasted spells**: the addon learns how long your kills usually take. When an enemy should be nearly dead it stops suggesting new damage over time and tells you to finish it.
- **Your demon** (Warlock): the pull advice changes with who is out. Voidwalker goes in first; with the Imp you just start casting.
- **Macros**: `/coach macros` makes a few helper macros from the spells you know (see below).
- **Mana**: the bar is your real mana, drawn by the game itself. When mana gets low the advice changes, e.g. "melee only" or "wand until it dies".
- **Before you pull**: missing buffs, weapon buff, wand, reagents, food, and "drink first" when mana is low.
- **After each fight**: time, casts, mana spent, and up to two tips on what to do better.
- **Level-ups**: which new spells to train and which talent to take.

ClassCoach only shows advice. It never presses buttons for you, which keeps it within Blizzard's addon rules.

## Install

1. Close the game.
2. Copy the `ClassCoach` folder into `World of Warcraft\_forever_\Interface\AddOns\`.
   The `.toc` file must sit directly inside it: `AddOns\ClassCoach\ClassCoach.toc`.
3. Start the game and tick **ClassCoach** in the AddOns list on the character screen.

## Commands

| Command | What it does |
|---|---|
| `/coach` | Help |
| `/coach lock` / `unlock` | Stop or allow dragging the panel |
| `/coach scale 1.2` | Panel size (0.5–2) |
| `/coach spec Enhancement` | Pick a profile by hand; `/coach spec auto` goes back to automatic |
| `/coach last` | Repeat the last fight report in chat |
| `/coach chat off` | Stop fight tips in chat (they still show on the panel) |
| `/coach food off` | Stop the buff-food reminder |
| `/coach hide` / `show` / `reset` | Hide, show, or re-centre the panel |
| `/coach check` | Prints what the addon can read on your client. Useful when something looks wrong |

## Profiles included

| Class | Spec | Status |
|---|---|---|
| Shaman | Enhancement | Full: priority, checklist, tips, trainer, talents |
| Priest | Discipline | Full; Priest trainer levels are Classic's and may differ in Forever |
| Warlock | Affliction | Full: demon check, Life Tap advice, Soul Shard check, wand filler |
| Every other class | General | Mana coach, drink/food checks, fight report, level-up reminders |

The profile is picked from your talent points (the tree with the most points); before level 10 the class's default spec is used. Adding a class or spec is one file: see `docs/EXTENDING.md` in the project.

## Two panels

- **Coach** (top): only the fight. The carousel, your timers, mana, and before a pull the few things that matter for that fight (shield, weapon buff, demon, low health or mana).
- **Journey** (its own panel, hidden in combat): your XP and rested XP, and a short to-do list with an icon per item (hover one for the full advice). The list covers from the leveling guides: unspent talent points, spells you can train, a missing food buff (+5% XP from kills), no rested XP, your Cozy Sleeping Bag or Camp Tent if you own one, gear that needs repair, full bags, and the level your trainer next has something new. `!` marks something worth doing now; the grey line under the list explains the first one.

The two panels move independently: drag each where you like. `/coach journey off` hides the second one; `/coach reset` puts both back.

## Macros

`/coach macros` (out of combat) creates this class's macros on your character's macro tab, named `CC ...`. Open `/macro` and drag them to your bar. They rewrite themselves when you train new spells, and a macro on your bar lends its key to the spells inside it on the panel.

- One press still casts one spell: the game allows nothing else, and an addon may not press keys or change a macro during combat. `CC Pull` is written from the coach's own pull plan and steps through it, one spell per press. It rewrites itself between fights when the plan changes (new spells, or kills getting shorter).
- Without a wand, the filler spell (Shadow Bolt, Smite) is added to the end, so that one key carries the whole fight.
- Warlock `CC Pull` also sends your demon in. With the Voidwalker out, the first press only sends it; the spells start once it is fighting.
- Macros cannot think. Keep watching the panel: it knows when a spell is still running, the macro does not.

## How the timers work

In combat the game hides enemy debuffs from addons, so ClassCoach counts from your own casts: it knows what you cast, on whom, and how long the spell lasts (read from the spell's own description). Two limits follow from that: a resisted spell still counts as applied, and if the game also hides enemy ids on your client, coming back to an earlier enemy starts its timers fresh. `/coach check` says how enemies are told apart on your client.

## How mana works

Forever hides your mana number from addons during combat, but lets them hand it to the game to draw. So:

- **The bar and its percentage are real.** The game draws them; ClassCoach never sees the number in a fight.
- **The advice level (high / medium / low) is worked out**, because the addon has to decide something without the number. It uses your mana when the fight started, minus what your casts cost, corrected by which spells the game says you can still afford. It can be off by a little in long fights; the bar is the truth.

`/coach check` reports whether the game accepted the bar on your client.

## Known limits

- In combat Forever hides buffs, totems, enemy health and the combat log from addons. ClassCoach times your damage-over-time spells and totems itself from your own casts, so those timers are close but not exact.
- Spells are found by their Classic ids, then by English name. If Forever renamed a spell and you play in another language, that spell may be missing from the advice; `/coach check` lists what was found.
- Healing advice (watching party health) isn't possible in combat on Forever, so there is no healer profile yet.
