# ClassCoach

A beginner's coaching addon for **World of Warcraft: Forever** (patch 1.60.x, interface 16001). It shows what to press next, a pre-pull checklist, per-enemy damage-over-time timers, a fight report, and a second "journey" panel for everything outside combat. Owner: Cedric, a beginner player and a software developer. He plays a Dwarf Shaman, a Discipline Priest and an Affliction Warlock.

## Rules that do not bend

1. **Forever only.** No support for Classic Era, Season of Discovery, the Classic expansions or retail. Call only functions the Forever client has, and add each new one to the `NEEDS` list in `Core/API.lua`. Never add a fallback for another version. The addon switches itself off elsewhere (`API.forever`).
2. **Advisory only.** The addon never decides in combat what a key casts. Macros, bar buttons, bindings and the secure smart key are set up out of combat, as the game requires. Do not build anything that automates combat decisions.
3. **Never raise an error into the game.** Every refresh, event, slash command and UI handler runs inside a guard (`safely`, `Style.guard`, `pcall`). A failure costs one line of advice.
4. **Secret values.** In combat Forever hides mana, auras, enemy health and the combat log. Every read goes through `try` and `plain` in `Core/API.lua`; an unreadable value means "unknown" (nil), never false.
5. **No unbounded loops.** A count that comes from the game goes through `API.upTo(n, most)` before a loop uses it.
6. **Forever's own data.** Spell and trainer levels, talents, zone and dungeon levels and XP buffs come from Forever sources (Blizzard's posts for Forever, Forever guides, the Warcraft Wiki's Forever pages), not from the original game. Say so when something could not be confirmed.

## Layout

```
ClassCoach/            the addon (this folder is what gets installed)
  ClassCoach.toc       load order and version
  Core/API.lua         the only file that talks to the game
  Core/Engine.lua      advice logic; no game calls, no class knowledge
  Core/Tracker.lua     casts, resists and timers counted from your own casts
  Core/Profiles.lua    profile registration and choice
  Data/Journey.lua     milestones, zones, dungeons, vendor food and drink
  Data/TalentLinks.lua generated: talent calculator link symbols to talent names (from Zbuilds, MIT)
  Profiles/*.lua       one file per class (Shaman, Priest, Warlock, Generic)
  UI/*.lua             coach panel, journey panel, smart key, talent window marks, settings
  ClassCoach.lua       wiring: events, refresh loop, /coach commands
docs/EXTENDING.md      how to add a class or spec
tests/                 offline tests against a fake Forever client
```

## Tests

```
pip install lupa
python3 tests/run.py            # everything
python3 tests/run.py forever    # one scenario
```

Scenarios: `shaman`, `priest`, `warlock`, `template`, `warrior`, `robust` (event storms, combat lockdown, chaos fuzzing), `forever` (no call to a function Forever lacks, off on other versions), `talents` (build following, talent window marks, link import), `sweep` (every level 1 to 60 per class).

`tests/mock.lua` offers only functions the Forever client has. Keep it that way: a test that needs a function from another version is testing the wrong thing. Run each scenario with a timeout; a hang is a finding, not a slow machine.

The tests run offline. Nothing is proven in the real game until Cedric has tried it, so say "passes the offline tests, not yet tried in game" until he confirms.

## Talent window

Forever's talent window is `PlayerSpellsFrame.TalentsFrame`; talents live in the traits system as ONE tree per class holding all three specs. ClassCoach finds talents by name, lays its own frames over the game's buttons (never as their children, never taking clicks) and never learns a talent for the player.

## Workflow for every change

1. Make the change, add or update a test, run the whole suite.
2. Bump `## Version:` in `ClassCoach/ClassCoach.toc`.
3. Commit and push to `main` (remote: `github.com/cedricdhooge96/ClassCoach`, MIT license).
4. Install to `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\ClassCoach`.
5. **Read the installed files back and compare them with the repo.** An install has reported success while writing an old copy of a file before.
6. Tell Cedric to `/reload` (a full restart only when a file was added).

Diagnosing in game: `/coach check` prints what the addon can read and any Forever function the client lacks; `/coach errors` prints what the addon caught in itself; `/coach errors on` shows every addon's Lua errors on screen.

## Writing for the player

Panel text, tooltips, chat output and the README are read by a beginner. Use plain words, say what to do and why in one line, and avoid jargon and abbreviations. Answers to Cedric: short, the result first, and honest about what is verified and what is a guess.
