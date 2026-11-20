# ClassCoach

A beginner's coach for WoW Forever that works for any class. One small panel shows:

- **What to press next**: the spell, its key, and why. Out of combat with an enemy targeted, it shows how to pull.
- **Mana**: exact out of combat, a careful estimate in combat (the game hides the real number from addons during fights). When mana gets low the advice changes, e.g. "melee only" or "wand until it dies".
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

## How the mana estimate works

Out of combat the addon reads your exact mana. In combat Forever hides it, so ClassCoach takes your mana at the start of the fight, subtracts the cost of every spell you cast, and then checks which of your spells the game still lets you afford. That bracket keeps the estimate honest. It shows "~45% (estimate)" while it's guessing.

## Known limits

- In combat Forever hides buffs, totems, enemy health and the combat log from addons. ClassCoach times your damage-over-time spells and totems itself from your own casts, so those timers are close but not exact.
- Spells are found by their Classic ids, then by English name. If Forever renamed a spell and you play in another language, that spell may be missing from the advice; `/coach check` lists what was found.
- Healing advice (watching party health) isn't possible in combat on Forever, so there is no healer profile yet.
