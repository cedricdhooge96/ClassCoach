# ClassCoach

A beginner's coaching addon for **World of Warcraft: Forever** (patch 1.60.x, interface 16001). It shows what to press next in a ring under the character, a pre-pull checklist, per-enemy damage-over-time timers, a fight report, and a second "journey" list for everything outside combat. Owner: Cedric, a beginner player and a software developer. He plays a Dwarf Shaman, a Discipline Priest and an Affliction Warlock.

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
  Data/Professions.lua what to do next in each of the 12 professions, and which two suit a class
  Data/TalentLinks.lua generated: talent calculator link symbols to talent names (from Zbuilds, MIT)
  Profiles/*.lua       one file per class (Shaman, Priest, Warlock, Generic)
  UI/*.lua             the coach (Panel), journey list, smart key, click to cast, the shared glow (Glow) and its uses
                       (bar highlight, spellbook light, talent window), the settings window (Window) and the game's settings page (Options)
  Media/*.tga          ClassCoach's own shapes, made by tools/gen_textures.py
  Fonts/               Inter and Marcellus (SIL Open Font License), with their licences
  ClassCoach.lua       wiring: events, refresh loop, /coach commands
docs/EXTENDING.md      how to add a class or spec
tools/gen_textures.py  draws the textures (python3, Pillow)
tests/                 offline tests against a fake Forever client
```

## The game's frames are looked at, never changed

Cedric's action bars have vanished in fights more than once and no cause was found in this addon. Whatever the cause, ClassCoach must never be it:

- Never call a method that changes a frame the addon did not create (`Hide`, `Show`, `SetShown`, `SetAlpha`, `SetPoint`, `ClearAllPoints`, `SetParent`, `SetScale`, `SetSize`, `SetAttribute`), never write a field on one, never register a state driver on one. That covers the action bars and their buttons, `UIParent`, the talent window. Reading (`IsShown`, `GetWidth`, `button.action`) and anchoring the addon's own frame to one are fine.
- No `hooksecurefunc`, no opening the game's settings or panels, nothing from `EditModeManagerFrame` or `ActionBarController`. ClassCoach's settings are its own window (`UI/Window.lua`); it does not join `UISpecialFrames` (a table of the game's): Esc is handled by the window's own keyboard script, and only out of combat (`SetPropagateKeyboardInput` is never called in a fight).
- The spellbook (`PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame`) is read like the talent window: its frames and their `spellBookItemInfo`, never a page turned. In the mock it is `M.spellbook`, built from `M.gameFrame` with readable `fields`.
- `tests/mock.lua` builds the game's bars with `M.gameFrame`: any change raises an error and lands in `M.violations`, which every scenario checks at its end. The `bars` scenario also scans the source. A new game frame the addon reads goes into the mock as a `M.gameFrame`, not as a plain widget.
- Bar layout: `Engine.bars` numbers what you can use right now 1, 2, 3... per bar (no gaps); `barFixed` keeps each entry on the button of its place in the profile's list. `/coach bar` and the automatic fill only use free buttons and never move one; only `/coach bar reset` and `replace` re-order.
- `C.watchBars` notices when the bars leave the screen and reports the frame and what the game blocked (`/coach bars`). It only reads.

## Tests

```
pip install lupa
python3 tests/run.py            # everything
python3 tests/run.py forever    # one scenario
```

Scenarios: `shaman`, `priest`, `warlock`, `template`, `warrior`, `robust` (event storms, combat lockdown, chaos fuzzing), `forever` (no call to a function Forever lacks, off on other versions), `talents` (build following, talent window marks, link import, professions), `focus` (the ring: fonts, cue, bar highlight, click to cast, demo), `ui` (the glow, spellbook light, quiet coach, settings window, sharing, the mana ledger and mana-aware plans), `bars` (bar reset and undo, gapless and fixed layouts, potions, the bar watcher, hands off the game's frames), `wand` (the next step while the wand fires, the global cooldown, spells in macros on your bars), `trace` (the debug trace: consent, privacy, limits, export), `sweep` (every level 1 to 60 per class, including the smart key's steps and the bar layout).

`tests/mock.lua` offers only functions the Forever client has. Keep it that way: a test that needs a function from another version is testing the wrong thing. Run each scenario with a timeout; a hang is a finding, not a slow machine.

The tests run offline. Nothing is proven in the real game until Cedric has tried it, so say "passes the offline tests, not yet tried in game" until he confirms.

## Drawing in the game

The coach is drawn only with what Forever has: flat colour textures, texture files (32-bit TGA, sides a power of two, white on transparent and tinted in game), a mask for round icons, status bars, and fonts shipped in `Fonts/`. There are no vector shapes and no letter-spacing. A design is drawn on a 1365 x 768 grid so sizes copy straight into the code.

- **Mana is a status bar.** In combat the value is hidden; `StatusBar:SetValue` is the call that accepts it. Do not build a mana ring.
- **Secure frames** (the smart key, the click-to-cast buttons) are created, shown, hidden, moved and given attributes out of combat only, and are never anchored to an insecure frame that moves. `tests/mock.lua` raises an error when a test breaks that rule.
- **Frames over the game's own buttons** (talent marks, bar highlight) are children of `UIParent`, anchored to the button, with the mouse off.
- **Text starts on the game's own font objects** (`Style.text` picks one by size). ClassCoach's typefaces are opt-in (`ownFonts`) and are never set at creation: on 0.13.0, set while the addon loaded, they drew on some texts and nothing on others, while the `/coach fonts` card (same session, later) drew every typeface at every size with and without `SetWidth`. `Style.dress` applies them a few seconds after login, verifies each text with `GetFont` and its measured width, and restores the game font where that fails. Do not make them the default until Cedric has seen them survive a `/reload`.
- Marcellus draws the digit 1 like a capital I: never use it for text with numbers.

## Sigil

`github.com/thaoms/sigil` (by Narsil, all rights reserved) is a Forever addon proven in live fights and a good reference for what works in the client. Take ideas and techniques from it; never copy its code or artwork into this MIT repository.

## Talent window

Forever's talent window is `PlayerSpellsFrame.TalentsFrame`; talents live in the traits system as ONE tree per class holding all three specs. ClassCoach finds talents by name and lays its own frames over the game's buttons (never as their children, never taking clicks): the glow, numbered discs, veils over talents outside the build, and a draggable build card. It learns a talent only when the player clicks the opt-in "Learn now" (`API.learnTalent`: `C_Traits.PurchaseRank`, then `C_ClassTalents.CommitConfig` for the last selected loadout, as the talent window's Apply does; refused while the window holds unapplied changes, rolled back when the game says no; out of combat only). The game's UI source for this exact client is the `forever` branch of github.com/Gethe/wow-ui-source.

- The marks, the glow and the veils draw in the DIALOG strata (level 20, under the game's dialogs), not a few levels above the buttons: in game (0.15.4) frames placed 20 levels above the talent buttons in the same strata were "visible" yet never drawn. The glow only shows with an unspent point; the Next tag always.

## Debug trace

`UI/Trace.lua` works like QuestieTrace (idea only; its code is GPL and is not used): a consent pop-up of our own (not StaticPopup), sessions of every character recorded into `ClassCoachTrace.sessions` (the account's saved variables, written at /reload and logout), at most 10 sessions of 3000 lines, `/coach trace` status/export/clear/consent. Never record a player's name, a realm name or a player GUID (`Trace.clean`, `Trace.unit`). With Cedric's approval Claude reads `_forever_\WTF\Account\<account>\SavedVariables\ClassCoach.lua` to debug.

## Mana

Forever hides mana from addons in combat, and on Cedric's client out of combat too. `Core/Mana.lua` keeps a ledger: exact readings when there are any, else the cost of every own cast, Life Tap's gift, regen from `GetPowerRegen` (or a guess) outside the five-second rule, faster while drinking, fenced by which spells are affordable. `Engine.plan` and the chain spend each step's cost from it (`Sim:pressed`, `Sim:usable`), so the pull plan, the `CC Pull` macro and the smart key follow the mana you have; out of combat a changed plan reloads them (`C.planSeen`). The smart key cannot change in combat.

## Workflow for every change

1. Make the change, add or update a test, run the whole suite.
2. Bump `## Version:` in `ClassCoach/ClassCoach.toc`.
3. Commit and push to `main` (remote: `github.com/cedricdhooge96/ClassCoach`, MIT license).
4. Install to `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\ClassCoach`.
5. **Read the installed files back and compare them with the repo.** An install has reported success while writing an old copy of a file before.
6. Tell Cedric to `/reload` (a full restart only when a file was added).

No tool outside the game draws its fonts (Blizzard ships none; community emulators such as WoWBench, wowless and Mechanic's sandbox run the Lua but measure no text), so text layout is checked in the game itself: `Style.layoutCheck` (`/coach layout`, and after every settings page is shown) asks the client which ClassCoach texts are cut short (`IsTruncated`), measure nothing, or overlap another text of the same frame, and logs them (saved log and trace). Lay out from measured heights, measured in the font the text will be drawn in (a text created after the typefaces went on wears its own at once; a settings page laid out before a typeface change is rebuilt).

Diagnosing in game: `/coach check` prints what the addon can read and any Forever function the client lacks; `/coach errors` prints what the addon caught in itself; `/coach errors on` shows every addon's Lua errors on screen.

## Writing for the player

Panel text, tooltips, chat output and the README are read by a beginner. Use plain words, say what to do and why in one line, and avoid jargon and abbreviations. Answers to Cedric: short, the result first, and honest about what is verified and what is a guess.
