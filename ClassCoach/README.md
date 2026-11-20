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
| `/coach set compact on` | Changes one setting from chat; `/coach set` lists them |
| `/coach pages` | Stops Shift+number from switching your main bar to an empty page |
| `/coach macros` | Creates or refreshes this class's helper macros (out of combat) |
| `/coach smart` | Shows the smart key's steps and keys; `/coach smart next 1` binds a key |
| `/coach bar` | Lays out the fight, react and prepare bars on empty buttons; `preview` only lists, `replace` overwrites |
| `/coach last` | Repeats the last fight report in chat |
| `/coach hide` / `show` | Hides or shows the coach panel |
| `/coach reset` | Puts both panels back where they started |
| `/coach spec Enhancement` | Picks a profile by hand; `/coach spec auto` goes back to automatic |
| `/coach check` | Prints what the addon can read on your client. Useful when something looks wrong |

Everything else is on the settings screen.

## Profiles included

| Class | Spec | Status |
|---|---|---|
| Shaman | Enhancement | Full: priority, checklist, tips, trainer, talents |
| Priest | Discipline | Full; Priest trainer levels are Classic's and may differ in Forever |
| Warlock | Affliction | Full: demon check, Life Tap advice, Soul Shard check, wand filler |
| Every other class | General | Mana coach, drink/food checks, fight report, level-up reminders |

The profile is picked from your talent points (the tree with the most points); before level 10 the class's default spec is used. Adding a class or spec is one file: see `docs/EXTENDING.md` in the project.

## Settings

Press Esc, then Options > AddOns > ClassCoach. Everything is on one page and applies at once. (`/coach set` changes a single setting from chat, for example `/coach set compact on`. The addon never opens the game's settings panel itself: an addon doing that is a known way to upset action bars in combat.)

- **Coach panel**: show or hide, size, compact (icons only), the left "already cast" icons, the timers line, the mana bar.
- **Journey panel**: show or hide, size, and which reminders you want (food, rested XP, trainer and talents, repairs and bags).
- **Look**: background darkness, thin border, class-colour line, lock in place.
- **Coaching**: profile for this character, skipping damage over time on dying enemies, when to suggest drinking, tips in chat, keeping macros up to date.
- **Actions**: create or refresh macros, reset panel positions.

## Two panels

- **Coach** (top): only the fight. The carousel, your timers, mana, and before a pull the few things that matter for that fight (shield, weapon buff, demon, low health or mana). Anything missing shows as the icon of the spell that fixes it, with its key; hover it for the details.
- **Journey** (its own panel, hidden in combat): your XP and rested XP, and a short to-do list with an icon per item (hover one for the full advice). The list covers from the leveling guides: unspent talent points, spells you can train, a missing food buff (+5% XP from kills), no rested XP, your Cozy Sleeping Bag or Camp Tent if you own one, gear that needs repair, full bags, and the level your trainer next has something new. `!` marks something worth doing now; the grey line under the list explains the first one.

What the journey panel adds on top of that:

- **Milestones**: class quests and other things worth doing at your level, and the next one coming ("At level 20: Water totem quest and Ghost Wolf").
- **Where to be**: zones and dungeons that fit your level (Alliance for now).
- **Supplies**: at a vendor it tells you what you are low on (water, food, class reagents) and whether to repair. On the road it only speaks up when you have run out.

And on the coach panel, before a pull, a red or amber icon when the enemy is one you shouldn't fight alone: far above your level, elite, or grey (no XP).

The two panels move independently: drag each where you like. `/coach reset` puts both back.

## Action bars

`/coach bar` lays out three bars, each with one job, so a key always means the same kind of thing:

| Bar | Job | Examples |
|---|---|---|
| Main bar | **Fight**: what you press during a fight, in the order you use it | Pull macro, wand, damage spells |
| Action Bar 2 | **React**: emergencies and answers | Fear, heals, shield, interrupts, cleanses |
| Action Bar 3 | **Prepare**: between fights | Armor and weapon buffs, summons, conjuring, travel |

- Every spell has a fixed button, so nothing moves as you level; gaps fill in when you learn the spell.
- `/coach bar` only fills empty buttons. If a spell's own button is taken, it goes to the next free one on the same bar. Nothing already on your bars is doubled.
- `/coach bar preview` only lists the plan. `/coach bar replace` puts everything on its own button, overwriting what is there.
- A bar that is switched off is skipped, and the addon tells you to turn it on (Esc > Options > Action Bars).
- Optional setting: put newly learned spells on their button automatically. It never overwrites.
- The prepare bar also gets **CC Rest** (one press drinks and eats the best you carry; it rewrites itself when your bags change), your best **bandage** and your **Hearthstone**. Warlocks get their **Healthstone** on the react bar. A used-up or weaker item on one of these buttons is swapped for the better one.

### If your bars seem to vanish

- The panels are drawn below the action bars and grow away from the nearest screen edge, so they cannot cover your buttons.
- Shift+number switches the main bar to another, usually empty, page. The coach flags it ("Main bar is on page 2") and `/coach pages` stops Shift+number from doing that.
- If the game blocks an action and blames this addon, it is recorded: `/coach check` lists it.

## Macros

`/coach macros` (out of combat) creates this class's macros on your character's macro tab, named `CC ...`. Open `/macro` and drag them to your bar. They rewrite themselves when you train new spells, and a macro on your bar lends its key to the spells inside it on the panel.

- One press still casts one spell: the game allows nothing else, and an addon may not press keys or change a macro during combat. `CC Pull` is written from the coach's own pull plan and steps through it, one spell per press. It rewrites itself between fights when the plan changes (new spells, or kills getting shorter).
- Without a wand, the filler spell (Shadow Bolt, Smite) is added to the end, so that one key carries the whole fight.
- Warlock `CC Pull` also sends your demon in. With the Voidwalker out, the first press only sends it; the spells start once it is fighting.
- Macros cannot think. Keep watching the panel: it knows when a spell is still running, the macro does not.

## When a spell is resisted

The game tells addons only that "something was resisted on your target", not what. ClassCoach matches that to the harmful spell you cast a moment before and undoes it: the timer is removed, the carousel marks the cast "miss", and the coach asks for the same spell again. If the enemy is immune, the spell is skipped on that enemy for the rest of the fight. The fight report counts resists and tells you when the enemy's level was the reason.

A macro cannot do this. A `/castsequence` moves on after a resisted cast, because the cast itself went off. That is what the smart key's Again key is for.

## The smart key

One key that walks the coach's plan: opening spells in order, then it stays on your wand, filler spell or attack. No looping back, no cutting off a channel, and it returns to the first step by itself when your enemy dies.

- Bind three keys under Esc > Options > Keybindings > AddOns > ClassCoach (or type `/coach smart next 1`, `/coach smart again 2`, `/coach smart restart 3`):
  **Next** casts the next step. **Again** casts the previous step once more, for a resist. **Restart** goes back to the start, for a new enemy.
- The panel shows which of those keys to press: it switches to the Again key when a spell was resisted.
- `/coach smart` lists its steps and keys.

What it is not: the addon does not decide during a fight what the key casts. The game forbids that, and nothing here works around it. The plan is loaded into the game's own secure button between fights; in a fight one press is still one cast, the same rule macros follow.

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
