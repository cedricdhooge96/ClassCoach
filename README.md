# ClassCoach

A beginner coach addon for **World of Warcraft Forever** (client 1.60.1). One compact panel that shows:

- the next ability to press, with its keybind,
- a carousel of what you did, what to press now and what comes next, using only spells you have learned,
- timers for your damage-over-time spells on each enemy,
- resist handling: a resisted spell is noticed and asked for again,
- a smart key that walks the plan with one key, plus helper macros (`/coach smart`, `/coach macros`),
- your real mana (drawn by the game, since Forever hides the number from addons in combat),
- a pre-fight checklist (buffs, demon, low health or mana),
- a second "journey" panel for everything outside the fight: XP, rested XP, food buff, trainer, talents, repairs, bags,
- a short report after each fight with what to improve,
- what to train and which talent to take when you level up.

Advisory only: it never presses anything for you.

**Forever only.** The addon calls only functions the Forever client has, carries Forever's own data (spells, talents, zones, dungeons, XP buffs), and switches itself off on any other version of the game.

## Classes

| Class | Spec | Status |
|---|---|---|
| Shaman | Enhancement | Full |
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
```

## Credits

The tables that turn an Icy Veins or Warcraft Tavern talent calculator link into talent names (`ClassCoach/Data/TalentLinks.lua`) come from [Zbuilds](https://github.com/Zael98/Zbuilds) by Zael98, MIT License.

## Tests

```
pip install lupa
python3 tests/run.py            # everything
python3 tests/run.py robust     # one scenario
```

The `robust` scenario is the safety net: event storms, combat lockdown, a refresh that keeps failing, damaged saved settings, broken profiles, and 6000 steps in which every game function randomly returns nothing, a hidden value, rubbish or an error. It fails if anything escapes into the game, if a loop runs away, or if the addon leaves a stray global name behind.
