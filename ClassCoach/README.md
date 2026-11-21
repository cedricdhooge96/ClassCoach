# ClassCoach

A beginner's coach for WoW Forever that works for any class. One ring under your character shows:

- **What to press next**: the spell in a gold ring, its key, its name and why. Out of combat with an enemy targeted, it shows how to pull.
- **Before and after**: left of the ring what you already cast on this enemy, right of it what comes next, each with its key. The steps sit on a rising arc and get smaller the further they are from now. With nothing targeted it shows your pull plan. Only spells your character has learned are shown.
- **Damage over time, per enemy**: each spell's seconds left, under its icon on the left. Switch enemies and each keeps its own timers. When a spell is about to matter again the right side says so ("in 8s").
- **A cue when it matters**: most of a fight is one steady key. When something else comes up, or a spell was resisted, the ring pulses and a soft click plays.
- **The button to press, lit on your action bars**: as a glow, sparkles, marching ants or a frame, in the colour you pick. When the step is on none of your bars, it lights up in your spellbook instead, ready to drag onto one.
- **Quiet when you are ready**: with nothing targeted and nothing to prepare, the coach steps back to half strength. Anything to do before a pull brings it back at once.
- **Click to cast, before a fight**: click an amber "before you pull" icon to cast what fixes it, or the ring to start the pull.
- **No wasted spells**: the addon learns how long your kills usually take. When an enemy should be nearly dead it stops suggesting new damage over time and tells you to finish it.
- **Your demon** (Warlock): the pull advice changes with who is out. The Voidwalker goes in together with your first spell (the pull key does both); with the Imp you just start casting.
- **Macros**: `/coach macros` makes a few helper macros from the spells you know (see below).
- **Mana**: the bar under the ring is your real mana, drawn by the game itself. It turns amber, then red, as the advice changes, e.g. "melee only" or "wand until it dies". The pull plan and the smart key are planned against the mana you have (see "How mana works").
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
| `/coach` | Opens ClassCoach's settings window (also from the minimap's addon menu). `/coach help` lists every command |
| `/coach setup` | The first-time setup page: bars, smart key, talent build, where the coach sits |
| `/coach share` | Your settings as one line of text, to keep or to give to a friend |
| `/coach set compact on` | Changes one setting from chat; `/coach set` lists them |
| `/coach demo` | Plays the coach's states with your own spells, out of combat, so you can see and place it without fighting |
| `/coach fonts` | A test card for ClassCoach's own typefaces: which sizes and uses this client draws |
| `/coach professions` | Which two professions suit your class and goal, and what to do next in each |
| `/coach tips` | Ten preparation habits from Forever guides (potions, First Aid, bags, hearthstone, gold) |
| `/coach bars` | What ClassCoach sees of the game's action bars, for when they vanish |
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

Everything else is in the settings window.

## Profiles included

| Class | Spec | Status |
|---|---|---|
| Shaman | Enhancement | Full: priority, checklist, tips, trainer, talents |
| Priest | Discipline | Full |
| Warlock | Affliction | Full: demon check, Life Tap advice, Soul Shard check, wand filler |
| Every other class | General | Mana coach, drink/food checks, fight report, level-up reminders |

The profile is picked from your talent points (the tree with the most points); before level 10 the class's default spec is used. Adding a class or spec is one file: see `docs/EXTENDING.md` in the project.

## Settings

Type `/coach`, or click ClassCoach in the minimap's addon menu. ClassCoach's own window opens: sections on the left, each setting on one row with what it does, and it applies at once. Drag the window by its title; Esc or the cross closes it. (The same settings are also under Esc > Options > AddOns > ClassCoach. The addon never opens the game's settings window itself: an addon doing that is a known way to upset action bars in combat.)

- **Start here**: the first-time setup in four steps, also opened by itself the first time you log in: lay out your bars, bind the smart key, follow a talent build, place the coach.
- **Coach**: show or hide, size, compact, how many steps show before and after the current one, the mana bar, how far the coach steps back when you are ready, the pulse and its sound, click to cast, warnings, the profile, drinking, tips in chat, the smart key. A button plays the demo.
- **Action bars**: the look and colour of the lit button, with a live preview; the spellbook light; filling new spells in; fixed buttons; the macros. Buttons to fill, reset or undo your bars.
- **Talents**: guiding you in the talent window, the look of the next talent (with a preview), dimming talents outside your build, the build card, the level-up note, and Learn now.
- **Journey**, **Professions**, **Look**: as before.
- **Share**: your settings as one line of text. Paste a line from a friend to use theirs; anything that does not fit is named and left alone. Settings for one character (the profile, your professions) are not in it.

## The coach and the journey list

- **Coach**: only the fight. A ring with the spell to press, the steps before and after it, your mana, and under it the spell's name, why, and any advice. It has no window around it: only the ring can be dragged, and everything else lets clicks through to the game. Before a pull, anything missing shows left of the ring as the icon of the spell that fixes it, in an amber ring, with its key; hover it for the details or click it to cast.
- **Journey** (its own list; in a fight it stays as it was before the pull, or hides if you turn off "Keep it visible in combat"): your level, XP and rested XP, then **Do now** and **Coming up**, each a short list with an icon per item (hover one for the full advice). It covers, from the leveling guides: unspent talent points, spells you can train, a missing food buff (+5% XP from kills), no rested XP, your Cozy Sleeping Bag or Camp Tent if you own one, gear that needs repair, full bags, professions, and the level your trainer next has something new. The grey line under the list explains the first thing to do.

What the journey list adds on top of that:

- **Milestones**: class quests and other things worth doing at your level, and the next one coming ("At level 20: Water totem quest and Ghost Wolf").
- **Where to be**: zones and dungeons that fit your level (Alliance for now).
- **Supplies**: at a vendor it tells you what you are low on (water, food, class reagents) and whether to repair. On the road it only speaks up when you have run out.

It also names what you are missing for the road, from level 10: a healing potion, bandages if you know First Aid, a mana potion for classes that need one, and an empty bag slot.

Before a pull the coach also shows a red or amber icon when the enemy is one you shouldn't fight alone: far above your level, elite, or grey (no XP).

The two move independently: drag the coach by its ring and the journey list anywhere on it. `/coach reset` puts both back. `/coach demo` plays every state of the coach so you can place it without fighting.

### What the game allows

- **Mana is a straight bar, not a ring.** In a fight the game hides your mana from addons and only lets them hand it to a status bar to draw. A ring would need the number.
- **Icons are clickable before a fight only.** Only the game's own secure buttons may cast, and in a fight an addon may not change what they cast, move them or hide them. So the game itself hides ClassCoach's click buttons when a fight starts. In a fight, press your keys or the lit button on your action bar.
- **The lit bar button works on the game's own action bars.** ClassCoach lays its own frame over the button; it never touches the button itself. Another bar addon's buttons are not found.
- **The big icon can look soft.** The game's icon art is 64 pixels; the ring shows it larger. If that bothers you, lower "Size" a little.

## Talents

Open the game's talent window. The talent to take next **lights up** (in the look and colour you pick) with "Next" above it, and the four after it carry a small round 2, 3, 4, 5. Talents your build never takes are **dimmed**.

Beside the window sits a **build card**: the build you follow, how far along you are, and the next talents, ranks of one talent on one line ("Ranks 1 to 5: now to level 18", or the levels they come at). "Now" only ever means a point you have to spend. It goes on the side with room, or inside the window's corner when neither side has any; drag it anywhere and it stays there ("Put the build card back" in the settings undoes that).

When you level up and have a point to spend, a short note at the top of the screen names the talent your build takes.

**Learn now** (off by default, Settings > Talents): a button on the card and on the note learns that talent when you click it, the way the talent window does (it stages the point and applies it). Out of combat only. If the talent window holds changes you have not applied, it waits for you; if the game refuses, the point is rolled back and it says so.

- **It follows what you already have.** The next talent is worked out from the points you have spent, not from your level, so it stays right if you took a point early or late. A point you have clicked but not applied yet already counts.
- **Which build.** Each class comes with a leveling build and an Icy Veins build; for the Warlock the default is Icy Veins' Forever leveling build (Suppression at 10 to 13, Improved Corruption at 14 to 18, ..., Wrack at 51), checked level by level against the guide's own level slider. With nothing spent you get the first; once you have spent points, the build that fits them best is followed. `/coach build` shows the list and where you are; `/coach build 2` pins one.
- **Your own guide.** On the Icy Veins or Warcraft Tavern talent calculator, set up the build (or open the one a guide links to), copy the address from your browser and type `/coach build ` followed by the link. The link holds the talents in the order they were clicked, and that is the order ClassCoach follows.
- **Nothing is guessed.** A link that names a talent your game does not have is refused with the reason. Points outside the build, or taken earlier than the build has them, are counted and shown.

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

- **No gaps.** A bar shows what you can use right now, side by side from button 1, in the order you use it. A spell you have not learned takes no button.
- `/coach bar` only fills empty buttons: something new goes to the first free button of its bar, so nothing you already press moves and nothing is doubled.
- After you learn a spell, `/coach bar reset` sorts it into its place in the order; the buttons after it move one up.
- Rather have a key mean the same spell for good? Turn on **Fixed buttons** in the settings: every spell keeps its own button and gaps fill in as you level.
- `/coach bar preview` only lists the plan. `/coach bar replace` puts everything on its button, overwriting what is there.
- `/coach bar reset` makes the three bars **exactly** the coach's layout: every button gets its entry or is emptied, so gaps, leftovers and doubles are gone. Other bars are not touched. `/coach bar undo` puts back what was there (a mount or equipment set cannot be put back; the addon tells you if one was on a button). Nothing is lost either way: a spell stays in your spellbook, a macro in `/macro`, an item in your bags.
- A bar that is switched off is skipped, and the addon tells you to turn it on (Esc > Options > Action Bars).
- Optional setting: put newly learned spells on a free button automatically. It never overwrites or moves anything.
- The prepare bar also gets **CC Rest** (one press drinks and eats the best you carry; it rewrites itself when your bags change), your best **bandage** and your **Hearthstone**. Warlocks get their **Healthstone** on the react bar. A used-up or weaker item on one of these buttons is swapped for the better one.
- A **healing potion** you carry gets its own button on the react bar (the strongest one you can use), and so does a **mana potion** for classes that have no other way to get mana back. A potion is instant and works in a fight: it is your emergency button. With none in your bags, the journey list says so from level 10 and how to get one: in Forever, First Aid makes healing potions (Minor from skill 55, Lesser from 85, Healing from 135).

### If your bars vanish

ClassCoach never hides, moves, resizes or re-parents the game's action bars, and it sets nothing on their buttons. The tests enforce that: the test client raises an error the moment the addon tries to change one of the game's frames, in every scenario, and the source is scanned for the calls known to cause this.

Bars can still vanish, usually in a fight, when another addon has interfered with the game's interface and the game then refuses to lay out its own bars. ClassCoach watches for it (it only looks):

- When the bars leave the screen it says so once in chat: which frame went, and what the game last blocked and blamed.
- `/coach bars` prints what it sees of each bar at any time, also in a fight. Send those lines.
- `/reload` brings the bars back.
- To find the culprit, switch off one addon at a time on the character screen, ClassCoach included, and play a fight.

Other reasons a bar can look empty:

- Shift+number switches the main bar to another, usually empty, page. The coach flags it ("Main bar is on page 2") and `/coach pages` stops Shift+number from doing that.
- The coach and the journey list are drawn below the action bars and the coach takes no clicks outside its ring, so they cannot cover your buttons.

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
- **It starts over by itself** when your target dies, when you drop your target, when a fight ends, and when you pick a new target between fights.
- **In a fight, a new enemy needs Restart** when you switch straight from one living enemy to another (the game gives the key no way to notice that). The ring then shows your Restart key, with why.
- **It is planned at the mana you have before the pull.** Each planned spell spends its cost, so on low mana the steps reach your wand (or Life Tap) sooner, and when your mana changes between fights (you drank, you cast a buff) the key is loaded again by itself. In a fight the game does not let an addon change it: when the coach changes its advice there (mana lower than planned, an enemy about to die), follow the coach's key and the lit button.
- The `CC Pull` macro is the other way to put the opening on one key: it only moves on when a spell really went off, but it cannot repeat a resisted spell and it starts over after its last step.

What it is not: the addon does not decide during a fight what the key casts. The game forbids that, and nothing here works around it. The plan is loaded into the game's own secure button between fights; in a fight one press is still one cast, the same rule macros follow.

A wand reports every shot to addons as a new cast. Shots in a row count as one, and while the wand is still firing it stays in the ring: it only moves to the left ("already cast") once you cast something else. Wand shots also do not start the clock on an enemy: the "nearly dead, skip damage over time" guess counts from your first real spell on it.

## How the timers work

In combat the game hides enemy debuffs from addons, so ClassCoach counts from your own casts: it knows what you cast, on whom, and how long the spell lasts (read from the spell's own description). Two limits follow from that: a resisted spell still counts as applied, and if the game also hides enemy ids on your client, coming back to an earlier enemy starts its timers fresh. `/coach check` says how enemies are told apart on your client.

## How mana works

Forever hides your mana number from addons in combat, and on some clients out of combat too. The game still draws it for an addon. So:

- **The bar and its percentage are real.** The game draws them; ClassCoach never needs the number for that.
- **For planning, ClassCoach keeps its own count** when the game will not say: your mana minus what each of your casts cost (exact: the game says what a spell costs), plus what Life Tap gives back, plus regen once five seconds have passed since you last spent mana (the "five-second rule"), faster while you drink. Which spells the game says you can still afford keeps the count honest. It can be off by a little; the bar is the truth.
- **The plan follows it.** The pull plan, the `CC Pull` macro and the smart key spend that count step by step, so a plan at 40% mana is shorter than one at full. Out of combat, below your "drink" setting, the coach asks you to drink first.

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

What that test also showed: with ClassCoach's own typefaces (Inter and Marcellus) set while the addon loaded, short labels drew correctly, but the spell's name, the explanation, the journey list's lines and the smallest key badges drew nothing. The `/coach fonts` test card, run later in the same session, drew every typeface at every size, with and without a set width. So the files and sizes are fine; what went wrong is tied to setting them at login.

Since 0.13.1 all text starts on the game's own fonts, which have always worked here. Since 0.13.2 the typefaces are a setting (`/coach set ownFonts on`, off by default) that goes on a few seconds after login, checks every text really took its typeface, and leaves any that did not on the game's font. `/coach check` lists what five key texts report.

Not yet seen in the real game: the lit bar button, click to cast, the pulse and its sound, the talent window marks, the profession lines, and everything new in 0.14.0 (the settings window, the talent glow, dimming, card, note and Learn now, the spellbook light, the quiet coach, and planning against ClassCoach's own mana count).

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
