# Forge of Ages

An incremental Roblox experience: tap the Forge and build idle production
through nine ages (Stone → Medieval → Industrial → Modern → Space → Digital
→ Alien → Heaven → Hell), collecting gear, pets, and skills through dungeons,
a daily arena, and gacha rolls along the way.

Architecture follows the patterns in `../roblox-systems-scripter.md` (server-
authoritative, module-based, DataStore with retry) and
`../roblox-experience-designer.md` (engagement loop / retention design) -
those two files live at the repo root, one level up from this folder, and
were the design brief this whole project was built from.

## Status (read this first if picking the project back up)

- **Never opened in Roblox Studio.** The dev machine this was built on has
  no Studio installed and no desktop GUI automation was available, so
  nothing here has been visually confirmed to run in the real 3D client.
  Everything below was verified a different way - treat "should work" as
  the honest status, not "confirmed working."
- **What was actually verified:**
  1. Static cross-reference check (grep-based) - every `require()` target
     exists, every `NetworkEvents.get("...")` name matches the declared
     `REMOTE_NAMES` list, every `state.xxx` field the client reads is one
     the server actually sends. No wiring bugs found.
  2. A standalone Python "shadow model" reimplementing the core formulas
     (age scaling, building costs, gear substat rolls, the Power formula,
     gacha odds) to sanity-check balance without a Luau interpreter -
     see the finding below.
  3. A browser HTML/JS mockup replicating the HUD and running the same
     formulas client-side, to preview layout and interaction flow. Not
     committed to this repo (it was a throwaway scratchpad artifact) -
     rebuild it from this README's system description if needed again.
- **Known unfixed bug found by the Python simulation:** Dungeon 1 is far
  too grindy on a fresh account. Power starts at 0 (no starting gear), so
  win chance floors at the 5% minimum in `DungeonSystem.tryEnter`'s clamp,
  and gear only drops on a win (50% chance) - so gear, and therefore any
  chance of climbing out of the 5% floor, arrives extremely slowly.
  Monte-carlo of 500 simulated players: median ~5 minutes of repeated
  20s-cooldown attempts for a **single** win, and the large majority still
  hadn't reached a reliable (90%+) win rate after 300 attempts (~100
  minutes of active grinding), with average Power (13.5) still well below
  Dungeon 1's difficulty (40). **Not yet fixed.** Cheapest fix discussed:
  lower Dungeon 1's `difficultyPower` from 40 to ~12-15 in
  `ReplicatedStorage/Modules/DungeonDefinitions.lua`, which the same
  simulation showed would put a zero-gear player near 50/50 immediately.
  Alternatives considered: raise the win-chance floor for early dungeons,
  or grant new players one starter gear piece.
- **Next concrete step:** either apply the Dungeon 1 balance fix above, or
  get this connected to real Roblox Studio via Rojo (see Setup) and
  playtest the actual tap → age-up → dungeon → gacha loop end to end.

## Setup

1. Install [Rojo](https://rojo.space/) (via [Aftman](https://github.com/LPGhatguy/aftman): `aftman add rojo-rbx/rojo`, or the VSCode extension + Studio plugin).
2. From this folder: `rojo serve`
3. In Roblox Studio, open the Rojo plugin and click **Connect**.
4. Press **Play** (F5) to test. DataStores don't work by default in Studio -
   enable **Game Settings → Security → Enable Studio Access to API Services**
   if you want to test persistence locally.

## What's implemented

- **Core loop**: click the `Forge` part in Workspace for a burst of Ore;
  owned buildings (`Worker`, `Facility`) produce Ore/sec passively.
- **Age progression**: 9 ages, each with its own resource label, tap power,
  and building costs (`ReplicatedStorage/Modules/AgeDefinitions.lua`).
- **Prestige**: at the current age cap, Prestige resets Ore/age/buildings in
  exchange for permanent Tech Points (+2% Ore output each) and raises the age
  cap by one tier - so Digital/Alien/Heaven/Hell unlock one rebirth at a time.
- **Gear**: 3 slots (Weapon/Armor/Accessory), rolled with 1 substat (ages 1-4)
  or 2 substats (age 5+) from a fixed pool (HP, Damage, Crit Rate, Crit
  Damage, Health Regen, Ranged/Melee Damage, Attack Speed). Legendary gear has
  a small chance to roll a rare unique effect (Burn/Poison/Stun).
- **Pets & Skills**: gacha-rolled collectibles, 2 per age (one Common, one
  Legendary), themed to that age. Passive stat bonuses only - up to 3
  equipped at once each.
- **Dungeons**: one per age, auto-battle stat-check (your `Power` vs the
  dungeon's `difficultyPower`), 20s cooldown, rewards gacha currency and a
  chance at a gear drop.
- **Arena**: 3 free attempts/day against a bot opponent scaled to your own
  Power (±15%) - no live matchmaking infrastructure.
- **Gacha currency sources**: dungeon clears (primary), arena wins, age-up
  milestones, and prestige.
- **DataStore persistence**: retry with backoff, saves on `PlayerRemoving`
  and `BindToClose`, autosave every 60s, schema migration for new fields.

## Known placeholders / next steps

- **Balance**: dungeon difficulty, gear substat ranges, and building costs
  are illustrative. They need tuning once real Power totals are observed
  from actual gear/pet/skill combinations.
- **UI is functional, not polished** - plain text/colored rarity labels, no
  icons or animations. The `Adventure` panel toggle button (bottom-right)
  opens dungeon/arena/gacha/inventory; lists rebuild fully on every state
  update rather than being incrementally pooled (fine at this scale).
- **No monetization yet.** `roblox-experience-designer.md` has a working
  `PassManager` pattern (Game Passes for things like a permanent tap-power
  boost or auto-clicker) that would slot in next to `ForgeSystem`.
- **No real PvP matchmaking** - Arena is bot-only. Real player-vs-player
  would need a matchmaking/queue service and stored opponent snapshots.
- **No onboarding flow** - a new player is dropped straight at the Forge.
  See the Onboarding Flow doc in `roblox-experience-designer.md` for the
  first-60-seconds / first-5-minutes structure to build toward.
- **No offline-earnings catch-up** - idle production only ticks while the
  server has the player loaded; consider crediting elapsed time on join.
