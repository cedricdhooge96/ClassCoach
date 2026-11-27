# ClassCoach

A beginner coach addon for **World of Warcraft Forever** (client 1.60.1). One ring under your character shows:

- the next ability to press, in a gold ring, with its key, its name and why,
- what you already cast on this enemy to its left and what comes next to its right, using only spells you have learned,
- timers for your damage-over-time spells on each enemy,
- a pulse and a soft click when a new key is needed, and the button to press lit up on your action bars (or in your spellbook when it is on no bar),
- a pull plan and smart key planned against the mana you have, kept by ClassCoach itself when the game hides it,
- your talent build inside the game's talent window: the next talent lit, the rest of the tree dimmed, a build card with the levels to come, and an optional Learn now button,
- its own settings window (`/coach`) with live previews, a first-time setup and settings you can share as one line,
- resist handling: a resisted spell is noticed and asked for again,
- your real mana (drawn by the game, since Forever hides the number from addons in combat),
- a pre-fight checklist (buffs, demon, low health or mana), each item clickable to fix it,
- a smart key that walks the plan with one key, plus helper macros (`/coach smart`, `/coach macros`),
- a second "journey" list for everything outside the fight: XP, rested XP, food buff, trainer, talents, repairs, bags, professions,
- which two professions suit your class and what to do next in each (`/coach professions`),
- a short report after each fight with what to improve,
- what to train and which talent to take when you level up.

Advisory only: it never presses anything for you.

**Forever only.** The addon calls only functions the Forever client has, carries Forever's own data (spells, talents, zones, dungeons, XP buffs), and switches itself off on any other version of the game.

## Classes

| Class | Spec | Status |
|---|---|---|
| Shaman | Enhancement | Full (Icy Veins' leveling plan and talents) |
| Shaman | Restoration | Talents, totems and cooldowns; alone it levels like Icy Veins says. Whom to heal stays your call: the game hides party health from addons in a fight |
| Priest | Discipline | Full |
| Warlock | Affliction | Full |
| Anything else | General | Mana estimate, checklist and fight report |

Adding a class is one file: see [docs/EXTENDING.md](docs/EXTENDING.md).

## Install

Copy the `ClassCoach` folder into
`World of Warcraft\_forever_\Interface\AddOns\`, then restart the game or type `/reload`.
Type `/coach` in game for the settings screen.

## Layout

```
ClassCoach/   the addon (copy this folder into AddOns)
docs/         how to add classes, a profile template
tests/        offline tests against a fake game client
tools/        draws the addon's textures
```

## Credits

The tables that turn an Icy Veins or Warcraft Tavern talent calculator link into talent names (`ClassCoach/Data/TalentLinks.lua`) come from [Zbuilds](https://github.com/Zael98/Zbuilds) by Zael98, MIT License.

## Tests

```
tests/run.sh                    # everything (needs Lua 5.1: apt install lua5.1)
tests/run.sh robust             # one scenario
luacheck .                      # the lint
```

The `robust` scenario is the safety net: event storms, combat lockdown, a refresh that keeps failing, damaged saved settings, broken profiles, and 6000 steps in which every game function randomly returns nothing, a hidden value, rubbish or an error. It fails if anything escapes into the game, if a loop runs away, or if the addon leaves a stray global name behind.
