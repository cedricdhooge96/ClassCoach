# ClassCoach

A beginner's coach for WoW Forever that works for any class. One ring under your character shows:

- **What to press next**: the spell in a gold ring, its key, its name and why. Out of combat with an enemy targeted, it shows how to pull.
- **Before and after**: left of the ring what you already cast on this enemy, right of it what comes next, each with its key. The steps sit on a rising arc and get smaller the further they are from now. With nothing targeted it shows your pull plan. Only spells your character has learned are shown.
- **Damage over time, per enemy**: each spell's seconds left, under its icon on the left. Switch enemies and each keeps its own timers. When a spell is about to matter again the right side says so ("in 8s").
- **A cue when it matters**: most of a fight is one steady key. When something else comes up, or a spell was resisted, the ring pulses and a soft click plays.
- **The button to press, lit on your action bars**: as a glow, a gold frame or sparkles, whichever you pick.
- **Click to cast, before a fight**: click an amber "before you pull" icon to cast what fixes it, or the ring to start the pull.
- **No wasted spells**: the addon learns how long your kills usually take. When an enemy should be nearly dead it stops suggesting new damage over time and tells you to finish it.
- **Your demon** (Warlock): the pull advice changes with who is out. Voidwalker goes in first; with the Imp you just start casting.
- **Macros**: `/coach macros` makes a few helper macros from the spells you know (see below).
- **Mana**: the bar under the ring is your real mana, drawn by the game itself. It turns amber, then red, as the advice changes, e.g. "melee only" or "wand until it dies".
- **Before you pull**: missing buffs, weapon buff, demon, wand and reagents as amber icons left of the ring, and in words under it: "Drink before the next pull" when mana is low.
- **After each fight**: time, casts, mana spent, and up to two tips on what to do better.
- **Level-ups**: which new spells to train and which talent to take.

ClassCoach only shows advice. It never presses buttons for you, which keeps it within Blizzard's addon rules.

## For WoW Forever only

ClassCoach is made for **World of Warcraft: Forever** (patch 1.60.x) and no other version of the game.

- **It switches itself off anywhere else.** On Classic Era, Season of Discovery, a Classic expansion or retail it prints one line and does nothing.
- **It only calls functions the Forever client has.** There are no fallbacks for other versions. `/coach check` lists any Forever function the client is missing, so a change in a Forever patch shows up by name.
- **The advice is Forever's.** Spell and trainer levels, talent builds, zone and dungeon levels, the food buff, the Camp Tent and the Cozy Sleeping Bag all come from Forever's guides and Blizzard's posts for Forever, not from the original game.

## Install

1. Close the game.
2. Copy the `ClassCoach` folder into `World of Warcraft\_forever_\Interface\AddOns\`.
   The `.toc` file must sit directly inside it: `AddOns\ClassCoach\ClassCoach.toc`.
3. Start the game and tick **ClassCoach** in the AddOns list on the character screen.

## Commands

| Command | What it does |
|---|---|
| `/coach set compact on` | Changes one setting from chat; `/coach set` lists them |
| `/coach demo` | Plays the coach's states with your own spells, out of combat, so you can see and place it without fighting |
| `/coach fonts` | A test card for ClassCoach's own typefaces: which sizes and uses this client draws |
| `/coach professions` | Which two professions suit your class and goal, and what to do next in each |
| `/coach pages` | Stops Shift+number from switching your main bar to an empty page |
| `/coach macros` | Creates or refreshes this class's helper macros (out of combat) |
| `/coach build` | The talent build you follow. `/coach build 2` picks one from the list, `/coach build auto` lets the addon choose, and `/coach build` followed by an Icy Veins or Warcraft Tavern talent calculator link follows that build |
| `/coach smart` | Shows the smart key's steps and keys; `/coach smart next 1` binds a key |
| `/coach bar` | Lays out the fight, react and prepare bars on empty buttons; `preview` only lists, `replace` overwrites |
| `/coach last` | Repeats the last fight report in chat |
| `/coach hide` / `show` | Hides or shows the coach |
| `/coach reset` | Puts the coach and the journey list back where they started |
| `/coach spec Enhancement` | Picks a profile by hand; `/coach spec auto` goes back to automatic |
| `/coach check` | Prints what the addon can read on your client. Useful when something looks wrong |
| `/coach errors` | Lists problems ClassCoach caught in itself. `/coach errors on` makes the game show every addon's error on screen; `off` hides them again |

Everything else is on the settings screen.

## Profiles included

| Class | Spec | Status |
|---|---|---|
| Shaman | Enhancement | Full: priority, checklist, tips, trainer, talents |
| Priest | Discipline | Full |
| Warlock | Affliction | Full: demon check, Life Tap advice, Soul Shard check, wand filler |
| Every other class | General | Mana coach, drink/food checks, fight report, level-up reminders |

The profile is picked from your talent points (the tree with the most points); before level 10 the class's default spec is used. Adding a class or spec is one file: see `docs/EXTENDING.md` in the project.

## Settings

Press Esc, then Options > AddOns > ClassCoach. Everything is on one page and applies at once. (`/coach set` changes a single setting from chat, for example `/coach set compact on`. The addon never opens the game's settings panel itself: an addon doing that is a known way to upset action bars in combat.)

- **Coach**: show or hide, size, compact (no explanation), how many steps show before and after the current one (0 to 4 each), the mana bar, the pulse and its sound, the look of the lit bar button (glow, gold frame, sparkles or off), and click to cast.
- **Journey list**: show or hide, size, and which reminders you want (food, rested XP, trainer and talents, repairs and bags).
- **Professions**: what you want from them (your own gear, gear and some gold, gold, or level 60), your own two if you prefer, and the three free ones.
- **Look**: how dark the plate behind the text is, ClassCoach's own typefaces instead of the game's font (being tested), lock in place.
- **Coaching**: profile for this character, skipping damage over time on dying enemies, when to suggest drinking, tips in chat, keeping macros up to date.
- **Actions**: create or refresh macros, reset panel positions.

## The coach and the journey list

- **Coach**: only the fight. A ring with the spell to press, the steps before and after it, your mana, and under it the spell's name, why, and any advice. It has no window around it: only the ring can be dragged, and everything else lets clicks through to the game. Before a pull, anything missing shows left of the ring as the icon of the spell that fixes it, in an amber ring, with its key; hover it for the details or click it to cast.
- **Journey** (its own list; in a fight it stays as it was before the pull, or hides if you turn off "Keep it visible in combat"): your level, XP and rested XP, then **Do now** and **Coming up**, each a short list with an icon per item (hover one for the full advice). It covers, from the leveling guides: unspent talent points, spells you can train, a missing food buff (+5% XP from kills), no rested XP, your Cozy Sleeping Bag or Camp Tent if you own one, gear that needs repair, full bags, professions, and the level your trainer next has something new. The grey line under the list explains the first thing to do.

What the journey list adds on top of that:

- **Milestones**: class quests and other things worth doing at your level, and the next one coming ("At level 20: Water totem quest and Ghost Wolf").
- **Where to be**: zones and dungeons that fit your level (Alliance for now).
- **Supplies**: at a vendor it tells you what you are low on (water, food, class reagents) and whether to repair. On the road it only speaks up when you have run out.

Before a pull the coach also shows a red or amber icon when the enemy is one you shouldn't fight alone: far above your level, elite, or grey (no XP).

The two move independently: drag the coach by its ring and the journey list anywhere on it. `/coach reset` puts both back. `/coach demo` plays every state of the coach so you can place it without fighting.

### What the game allows

- **Mana is a straight bar, not a ring.** In a fight the game hides your mana from addons and only lets them hand it to a status bar to draw. A ring would need the number.
- **Icons are clickable before a fight only.** Only the game's own secure buttons may cast, and in a fight an addon may not change what they cast, move them or hide them. So the game itself hides ClassCoach's click buttons when a fight starts. In a fight, press your keys or the lit button on your action bar.
- **The lit bar button works on the game's own action bars.** ClassCoach lays its own frame over the button; it never touches the button itself. Another bar addon's buttons are not found.
- **The big icon can look soft.** The game's icon art is 64 pixels; the ring shows it larger. If that bothers you, lower "Size" a little.

## Talents

Open the game's talent window (N). The talent to take next has a **gold frame and NEXT** above it, and the four after it carry a small 2, 3, 4, 5. A line at the bottom left names the build and the next talent. ClassCoach only marks; you click.

- **It follows what you already have.** The next talent is worked out from the points you have spent, not from your level, so it stays right if you took a point early or late. A point you have clicked but not applied yet already counts.
- **Which build.** Each class comes with a leveling build and an Icy Veins build. With nothing spent you get the first; once you have spent points, the build that fits them best is followed. `/coach build` shows the list and where you are; `/coach build 2` pins one.
- **Your own guide.** On the Icy Veins or Warcraft Tavern talent calculator, set up the build (or open the one a guide links to), copy the address from your browser and type `/coach build ` followed by the link. The link holds the talents in the order they were clicked, and that is the order ClassCoach follows.
- **Nothing is guessed.** A link that names a talent your game does not have is refused with the reason. Points outside the build, or taken earlier than the build has them, are counted and shown.

To switch the marks off: Options > AddOns > ClassCoach > "Mark my next talent in the talent window".

## Professions

`/coach professions` shows the plan; the journey list carries the next thing to do.

- **Which two.** While you have a profession slot free, the coach suggests the pair for your class and your goal. The goal is a setting: make your own gear while leveling (cloth classes: Tailoring and Enchanting; Shaman, Hunter, Rogue, Druid: Skinning and Leatherworking; Warrior, Paladin: Mining and Blacksmithing), gear and some gold, gold (two gathering professions), or ready for level 60. You can also set your own two; a profession you already learned is never argued with.
- **The three free ones.** In Forever, First Aid, Cooking and Fishing use no profession slot. The coach names the ones you have not learned. First Aid also makes the healing potions in Forever.
- **What to do next.** For every profession: what to craft, or what to mine, pick or skin and where, for your skill. And a reminder when you are at a skill cap and need the next rank, with what that rank asks for.

The steps follow the Forever guides on wow-professions.com, which are based on the beta; materials, amounts and alternatives are in the guides. The pairs are the ones Forever guides agree on (Gfinity Esports and RankedBoost, November 2026). They are recommendations, not rules. Switch all of it off with "Remind me: professions".

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

- The coach and the journey list are drawn below the action bars, so they cannot cover your buttons, and the coach takes no clicks outside its ring.
- Shift+number switches the main bar to another, usually empty, page. The coach flags it ("Main bar is on page 2") and `/coach pages` stops Shift+number from doing that.
- If the game blocks an action and blames this addon, it is recorded: `/coach check` lists it.

## Macros

`/coach macros` (out of combat) creates this class's macros on your character's macro tab, named `CC ...`. Open `/macro` and drag them to your bar. They rewrite themselves when you train new spells, and a macro on your bar lends its key and its lit button to the spells inside it.

- One press still casts one spell: the game allows nothing else, and an addon may not press keys or change a macro during combat. `CC Pull` is written from the coach's own pull plan and steps through it, one spell per press. It rewrites itself between fights when the plan changes (new spells, or kills getting shorter).
- Without a wand, the filler spell (Shadow Bolt, Smite) is added to the end, so that one key carries the whole fight.
- Warlock `CC Pull` also sends your demon in. With the Voidwalker out, the first press only sends it; the spells start once it is fighting.
- Macros cannot think. Keep watching the coach: it knows when a spell is still running, the macro does not.

## When a spell is resisted

The game tells addons only that "something was resisted on your target", not what. ClassCoach matches that to the harmful spell you cast a moment before and undoes it: the timer is removed, the icon left of the ring is marked "miss", and the coach asks for the same spell again. If the enemy is immune, the spell is skipped on that enemy for the rest of the fight. The fight report counts resists and tells you when the enemy's level was the reason.

A macro cannot do this. A `/castsequence` moves on after a resisted cast, because the cast itself went off. That is what the smart key's Again key is for.

## The smart key

One key that walks the coach's plan: opening spells in order, then it stays on your wand, filler spell or attack. No looping back, no cutting off a channel, and it returns to the first step by itself when your enemy dies.

- Bind three keys under Esc > Options > Keybindings > AddOns > ClassCoach (or type `/coach smart next 1`, `/coach smart again 2`, `/coach smart restart 3`):
  **Next** casts the next step. **Again** casts the previous step once more, for a resist. **Restart** goes back to the start, for a new enemy.
- The coach shows which of those keys to press: it switches to the Again key when a spell was resisted.
- `/coach smart` lists its steps and keys.

Its limits, which come from how the game's secure buttons work:

- **One press per spell.** The key moves on with every press, also when the spell could not be cast (still casting the last one, not ready, out of range). Pressing it faster than your spells go off skips steps. When that happens the coach shows the skipped spell's own key and lights its button; Restart puts the key back at the start.
- **A new enemy needs Restart** when you switch straight from one living enemy to another. It goes back to the start by itself only when your target dies or you have no target.
- **It walks the opening you would do at full mana.** When the coach changes its advice in a fight (low mana, an enemy about to die), follow the coach's key, not the smart key.
- The `CC Pull` macro is the other way to put the opening on one key: it only moves on when a spell really went off, but it cannot repeat a resisted spell and it starts over after its last step.

What it is not: the addon does not decide during a fight what the key casts. The game forbids that, and nothing here works around it. The plan is loaded into the game's own secure button between fights; in a fight one press is still one cast, the same rule macros follow.

## How the timers work

In combat the game hides enemy debuffs from addons, so ClassCoach counts from your own casts: it knows what you cast, on whom, and how long the spell lasts (read from the spell's own description). Two limits follow from that: a resisted spell still counts as applied, and if the game also hides enemy ids on your client, coming back to an earlier enemy starts its timers fresh. `/coach check` says how enemies are told apart on your client.

## How mana works

Forever hides your mana number from addons during combat, but lets them hand it to the game to draw. So:

- **The bar and its percentage are real.** The game draws them; ClassCoach never sees the number in a fight.
- **The advice level (high / medium / low) is worked out**, because the addon has to decide something without the number. It uses your mana when the fight started, minus what your casts cost, corrected by which spells the game says you can still afford. It can be off by a little in long fights; the bar is the truth.

`/coach check` reports whether the game accepted the bar on your client.

## Safety

ClassCoach is built so that a mistake in it costs you a line of advice, never your game.

- **Nothing it does can raise an error into the game.** Every refresh, game event, chat command, drag and mouse-over runs inside a guard. A problem is written to a small log (100 entries at most, repeats counted instead of repeated) that `/coach errors` prints.
- **It slows itself down when something is wrong.** After ten failed refreshes in a row it retries only once every five seconds and says so under the ring, then goes back to normal by itself when the cause is gone. A refresh that keeps taking too long is run less often.
- **It cannot loop.** Every list the game hands over (spellbook, bags, bars) is read up to a fixed size, whatever length the game reports. Rescans run at most once every two seconds, however many events ask for one.
- **It rations its own writes.** At most 12 automatic macro updates and 3 automatic bar fills per minute; past that it stops and tells you, and the commands still work by hand.
- **It leaves combat alone.** Macros, bar buttons, key bindings and the smart key are only changed out of combat, as the game requires.
- **It repairs damaged settings.** A saved value of the wrong kind or out of range goes back to its default when you log in.

If the game says "Your AddOns are experiencing a large number of errors", type `/coach errors on`, then `/reload`. The first error window names the addon and the line. `/coach errors` shows what ClassCoach caught in itself; an empty list means the errors come from another addon.

## Tested, and not yet

The offline tests play every level from 1 to 60 for the three class profiles against a fake Forever client, including the smart key's steps, event storms and combat lockdown. They cannot show how the coach looks.

Seen in the real game (0.13.0, a level 11 Warlock): the gold ring, the round icons, the key badge, the mana bar, the steps and their caption, and the journey list's headers and icons all draw as designed, and `/coach check` reads spells, keys, professions and the smart key.

What that test also showed: with ClassCoach's own typefaces (Inter and Marcellus), short labels drew correctly, but every text with a set width (the spell's name, the explanation, the journey list's lines) and the smallest key badges drew nothing. Since 0.13.1 all text uses the game's own fonts, which have always worked here. The typefaces are a setting, off by default, until `/coach fonts` has shown which uses this client accepts.

Not yet seen in the real game: the lit bar button, click to cast, the pulse and its sound, the talent window marks, and the profession lines.

## Credits

- The ring, the true mana bar, the cue, the demo and the drink reminder take their ideas from **Sigil** by Narsil (github.com/thaoms/sigil), a Retribution Paladin helper for Forever. No code or artwork was taken: Sigil is all rights reserved.
- Fonts (optional, see above): **Inter** by The Inter Project Authors and **Marcellus** by Astigmatic, both under the SIL Open Font License; the licences are in the `Fonts` folder.
- Talent calculator link tables: **Zbuilds** by Zael98 (MIT).
- Profession steps: the Forever guides on **wow-professions.com**.

## Known limits

- In combat Forever hides buffs, totems, enemy health and the combat log from addons. ClassCoach times your damage-over-time spells and totems itself from your own casts, so those timers are close but not exact.
- Spells are found by their spell ids, then by English name. If Forever re-numbered a spell and you play in another language, that spell may be missing from the advice; `/coach check` lists what was found.
- Healing advice (watching party health) isn't possible in combat on Forever, so there is no healer profile yet.
- Where to quest and which dungeon fits is written for the Alliance only.
