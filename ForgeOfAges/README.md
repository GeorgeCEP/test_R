# Forge of Ages — Implementation Plan

This file is the build spec for everything decided during design (a long
back-and-forth that started as an HTML mockup and ended up redesigning half
the game). **Nothing in this document has been built yet** except where a
section explicitly says "already in the codebase." Treat this as the thing
to work from once Roblox Studio is installed - not as a changelog of what
exists.

The previous README (git history has it) documented an earlier, simpler
version of the redesign: auto-battle stage crawl, Ore-sink Forge, flat tech
tree, gacha for both pets and skills. Several later decisions changed or
replaced pieces of that - this document supersedes it. Where something below
matches what's already in a `.lua` file, it says so; where it doesn't, that
file needs to change.

Architecture still follows `../roblox-systems-scripter.md` (server-
authoritative, module-based, DataStore with retry) and
`../roblox-experience-designer.md` (engagement loop design) at the repo
root - read those first if anything below is ambiguous about *how* to wire
something in, this doc focuses on *what* to build.

---

## 1. The game, end to end

Your avatar auto-walks through a private lane and fights its way along a
150-stage crawl (chapters 1-1 through 10-15, nine ages Stone → Hell, chapter
10 an endgame reuse of Hell's theme). Combat is a real tick-based fight, not
an instant stat check: each enemy in a wave has its own HP, your avatar and
the enemies visibly trade hits, and a losing player gets "downed" and
recovers rather than hitting a hard RNG wall.

Four currencies:

| Currency | Earned from | Spent on |
|---|---|---|
| **Ore** | Hourly claim + Dungeon runs (**not** stage clears anymore) | Forge crafting |
| **Coins** | Selling gear | Forge Level upgrades |
| **Research Points** | Stage/wave clears | Tech Tree nodes |
| **Gacha Currency** | Arena wins, stage clears (small amount), chapter/prestige events | Skill rolls only (pets no longer roll) |

Five screens, tab-navigated at the bottom of the HUD: **Arena**, **Dungeon**,
**Home** (default), **Collection**, **Tech**. Age/background theming is
automatic (driven by chapter progress) - there is no player-facing "pick
your age" control; that was a mockup-only debug convenience and must not
ship in the real game.

---

## 2. System-by-system spec

### 2.1 Stage crawl (mostly already built)

Already in `StageSystem.lua` / `LaneSystem.lua` / `StageDefinitions.lua`:
private per-player lane, `Humanoid:MoveTo` walking, DPS-race combat,
downed/recover instead of RNG loss, Endless Cycle at the chapter cap,
Prestige gating. **Keep all of this.**

**Needs to change: enemies must each have their own HP, not a shared pool.**
Today `StageSystem` tracks one `waveRemainingHP` for the whole wave, and
`LaneSystem.setWaveHPFraction` just destroys dummies proportionally as that
one number drops - visually plausible but mechanically a shared pool.
Rework to:

- `StageDefinitions.getStageInfo` already returns `enemyCount` and
  `waveMaxHP`; split `waveMaxHP` across `enemyCount` enemies (evenly, or
  with a little per-enemy variance for texture) when a wave spawns.
- `StageSystem` keeps an array of `{ hp, maxHp }` per enemy instead of one
  scalar. Each tick, damage goes to whichever enemy is still alive first
  (front-most); when its `hp` hits 0 it's removed permanently (not
  respawned) until the whole wave is dead, then the wave resets.
- `LaneSystem` gets a `setEnemyHPFraction(player, index, fraction)`-style
  API (one dummy, one bar) instead of the current wave-wide
  `setWaveHPFraction`, plus a `killEnemy(player, index)` that plays the
  fall/fade and removes that one dummy.
- Whichever enemy is still alive after the player's hit should be the one
  that retaliates that tick (mirrors the mutual-attack behavior below).

**Needs to change: visible attack animation, not silent HP ticking.** Each
tick: avatar nudges toward the target (a small CFrame/lunge, not real
movement - `Humanoid:MoveTo` is already used for lane movement, don't
double up), the hit dummy gets a brief highlight, a floating damage number
pops at the enemy, then ~0.3-0.5s later the still-alive enemy does the same
lunge back at the avatar with its own floating number. `LaneSystem` already
has `popText` for combat toasts - extend that pattern (BillboardGui +
TextLabel, tween up and fade, `Destroy()` after) for per-hit damage numbers
instead of building a new system. No animation asset IDs needed - the lunge
is a positional tween of the model's `PrimaryPart` (or a `TweenService`
tween of an offset `Motor6D`/`CFrameValue` if you want it to survive
character respawn cleanly), not a Roblox `Animation`.

**Needs to change: stage clears no longer grant Ore.** They grant Research
Points (small amount, scales with chapter) and a small amount of Gacha
Currency. Ore's only sources are the Hourly Claim and Dungeon runs (2.2).
Passive Ore/sec (Tech Tree "Automated Mining") still trickles continuously
on top of that - it isn't removed, just no longer the only Ore-from-Ore
source alongside a bonus claim.

### 2.2 Ore: hourly claim + Dungeon (new)

Nothing like this exists yet. Add:

- **Hourly claim**: server tracks `data.lastOreClaimAt` (a Unix timestamp).
  A remote lets the client ask to claim; server checks
  `os.time() - data.lastOreClaimAt >= 3600`, and if so grants a flat amount
  scaled by the player's current age (reuse `AgeDefinitions.getScale`, same
  pattern `EconomySystem.getIdleOutputPerSecond` already uses), and updates
  the timestamp. Client shows "Ready to claim" vs. a countdown from
  `pushState`'s `secondsUntilClaim = data.lastOreClaimAt + 3600 - os.time()`.
- **Dungeon**: a genuinely separate activity from the stage crawl, not
  folded into `StageSystem`. Three dungeon types, each weighted toward a
  different reward:

  | Dungeon | Egg | Ore | Enchantment |
  |---|---|---|---|
  | Ore Vault | 15% | 70% | 15% |
  | Beast Den | 65% | 15% | 20% |
  | Rune Chamber | 10% | 20% | 70% |

  Entering is **server-resolved** (never trust a client-rolled reward) and
  rate-limited per player - the old pre-redesign `DungeonSystem` had a
  20-second cooldown for a similar reason; a dungeon run granting real
  currency needs something in that range (2-5 minutes feels right for how
  meaningful the reward is, but this needs tuning once real numbers exist -
  don't ship it cooldown-free, it'll get macro'd).
  Reward resolution: pick a dungeon's weight table, roll `egg | ore |
  enchant`, then roll a rarity/amount within that kind. Push the result to
  the client for the reveal screen (see §4), and only apply it to `data`
  once the client acks/claims (or apply immediately and just use the
  "Claim" button as a client-side "okay, close this screen" - either is
  fine since it's server-rolled either way; the mockup's two-step
  roll-then-claim was purely presentational).

### 2.3 The Forge: instant, multi-slot, Level ≠ Slots (two different upgrades now)

**Needs a real change**, not just an add. The current `ForgeSystem.lua`
runs a timed queue (`CRAFT_BASE_TIME = 8s`, jobs resolve on a tick loop).
The final design has **no wait time** - crafting is instant. What survives
from the timed-queue version is the *idea* of forge slots, just
reinterpreted: **a forge slot is now "one more item per craft," not "one
more parallel timer."** Concretely:

```
-- ForgeSystem.craft(player, data)
local slotCount = TechTreeSystem.getForgeSlotCount(data)   -- existing helper
local cost = ForgeSystem.getCraftCost(ageId) * slotCount    -- pay for every slot
if data.ore < cost then return false end
data.ore -= cost

local results = {}
for i = 1, slotCount do
    local rarity = ForgeSystem.rollRarity(forgeLevel)  -- see below
    local item = GearSystem.rollGear(ageId, rarity)     -- rarity now forced, not re-rolled
    table.insert(data.gear, item)
    table.insert(results, item)
end
forgeResult:FireClient(player, { items = results })
```

This means `forgeJobs`/`finishAt` and the whole tick-based job resolver in
`ForgeSystem.lua` go away entirely - delete `resolveFinishedJobs` and the
`JOB_RESOLVE_TICK` loop, and drop `forgeJobs` from `DataManager`'s schema.

**Forge Level is new and separate from forge slots.** It's bought with
Coins (not Research Points - it doesn't live in the Tech Tree), and it
shifts the rarity-roll weights toward higher tiers:

```
-- illustrative starting point, needs balancing
function ForgeSystem.rollRarity(forgeLevel)
    local bonus = math.max(0, forgeLevel - 1)
    local weights = {
        Common = math.max(5, 55 - bonus * 4),
        Rare = 30,
        Epic = 12 + bonus * 2,
        Legendary = 3 + bonus * 2,
    }
    -- weighted pick, same pattern GearSystem already uses for rarity
end
```

`GearDefinitions.Rarities` already has weights - either add a
`forgeLevel` parameter to the existing pick-weighted helper, or keep a
separate table just for Forge rolls (gear *drops* elsewhere, if any ever
exist again, might want the un-adjusted odds).

`data.forgeLevel` and `data.coins` are new `DataManager` fields (§5).
Upgrade cost scales (`250 * 1.4^level` was the mockup's placeholder curve -
needs the same "not simulated yet" caveat as everything else numeric here).

### 2.4 Selling gear pays Coins, not Ore

`GearSystem` needs a `sell(player, data, itemId)` that removes the item from
`data.gear` (unequipping first if equipped) and grants `data.coins +=
item.sellValue`. `sellValue` should be a function of rarity (and maybe age),
computed once when the item is rolled and stored on the item so it doesn't
need recomputing - same pattern gear already uses for storing its rolled
substats.

### 2.5 Marketplace items: gear is now *visible* on the avatar

This is the big new piece and the one most worth de-risking before writing
a lot of code around it, since it depends on Roblox APIs this project
hasn't used yet.

**The mechanism**: `InsertService:LoadAsset(assetId)` loads any public
Roblox asset by ID at runtime and returns a `Model` wrapper. For a catalog
avatar accessory, that wrapper contains an `Accessory` instance you can hand
straight to `Humanoid:AddAccessory()`:

```lua
local InsertService = game:GetService("InsertService")

local function equipVisual(humanoid: Humanoid, assetId: number, tag: string)
    local ok, model = pcall(function()
        return InsertService:LoadAsset(assetId)
    end)
    if not ok or not model then
        warn("[Visuals] Failed to load asset", assetId)
        return
    end
    local accessory = model:FindFirstChildOfClass("Accessory")
    if accessory then
        accessory.Name = tag -- so it can be found and removed again on unequip
        humanoid:AddAccessory(accessory)
    end
    model:Destroy()
end

local function unequipVisual(humanoid: Humanoid, tag: string)
    local existing = humanoid.Parent and humanoid.Parent:FindFirstChild(tag)
    if existing then existing:Destroy() end
end
```

Run this **server-side**, inside `GearSystem.equip`/`unequip` (or a new
`GearVisuals.lua` those call into) - the accessory needs to exist on the
server's copy of the character to replicate to every other player in the
server, not just show up locally.

**What can and can't be a marketplace item, realistically:**

- **Armor and Accessory slots map cleanly to catalog accessories** by
  `AccessoryType` - Shoulder/Back/Waist for armor-flavored pieces, Neck/
  Front/Hat for accessory-flavored ones. This is well-supported and low
  risk.
- **Weapons are the risky one.** Classic Roblox "Gear" (the category that
  used to mean an equippable `Tool`) is largely unusable this way now -
  most Gear items are ownership-gated and won't load for a player who
  doesn't own them, and Roblox has been steadily restricting that category.
  **Recommendation: represent "Weapon" as a held-prop catalog accessory
  too** (there are plenty of `Front`/`Hat`-type catalog accessories that are
  visually weapon-shaped props), not a functional `Tool`. You lose "it's in
  a hotbar slot and can be un-equipped by pressing a number key," but you
  keep the reliability, and this game's weapon "usage" is already fully
  automatic (the avatar auto-attacks) so a swingable `Tool` was never doing
  real work anyway.
- **Pets should not be avatar accessories at all** - they read much better
  as a small separate `Model` that follows the player (offset behind/beside
  the `HumanoidRootPart`, simple `Humanoid:MoveTo` or CFrame-lerp following,
  same idea `LaneSystem` already uses for walking). That model can *itself*
  be sourced from `InsertService:LoadAsset` if you find a suitable public
  toolbox model, or be a simple hand-built primitive rig in the same
  "flat/cartoon" style as the enemy dummies - either is fine, this doesn't
  need to be a real catalog item the way gear does.
- **There is no reliable "search the catalog by category" API for a
  running game.** Don't try to build dynamic catalog browsing into the
  game. Instead: **curate a fixed table by hand in Studio.** Open the
  in-game Avatar Editor / catalog, find accessories that fit each
  slot+rarity (a rustic pauldron for Common Armor, something ornate and
  glowing for Legendary), copy their asset IDs, and hardcode them into a
  new `MarketplaceAssets.lua`:

  ```lua
  -- ReplicatedStorage/Modules/MarketplaceAssets.lua
  return {
      Weapon = {
          Common = { 123456789, 123456790 },
          Rare = { 123456791 },
          Epic = { 123456792 },
          Legendary = { 123456793 },
      },
      Armor = { --[[ same shape ]] },
      Accessory = { --[[ same shape ]] },
  }
  ```

  When `GearSystem.rollGear` rolls an item, also roll a `visualAssetId`
  from `MarketplaceAssets[slot][rarity]` and store it on the item. Prefer
  **free** catalog accessories where practical - equipping something a
  player doesn't personally own is fine inside your own game (you're not
  granting them the item, just displaying it, same as any NPC wearing
  catalog cosmetics), but sticking to free items avoids any ambiguity and
  costs nothing to test.
- **Failure handling is not optional.** Assets get deleted or moderated
  after you've hardcoded their IDs. `equipVisual` above already wraps
  `LoadAsset` in `pcall` and warns instead of erroring - keep that, and
  make sure a failed visual load never blocks the *stat* side of equipping
  (a reskinned-as-invisible legendary sword is a minor bug; an unequippable
  one is a real one).

### 2.6 Tech Tree: a real prerequisite tree, not a flat list

`TechTreeDefinitions.lua` already has a `prerequisite` field in its type
(only `forge_slot_3` actually uses it today). Extend the dependency graph to
match the shape settled on:

```
damage (root, no prerequisite)
├─ vitality
│   └─ research_gain      -- "Field Research" in the mockup's naming
└─ passive_ore            -- "Automated Mining"
    ├─ stage_ore          -- "Plundering"
    └─ forge_speed        -- "Efficient Tongs"
        └─ forge_slot_2
            └─ forge_slot_3
                └─ (new) forge_overclock  -- capstone, one-time
```

Everything else about `TechTreeSystem.lua` (per-node level, cost curve,
`getBonus(data, effectKey)` aggregation) stays as-is - only the dependency
edges and one new leaf node need adding. `isUnlocked(node)` is already
effectively `not node.prerequisite or level(prerequisite) >= 1` for the one
node that uses it today; that logic just needs to run for every node now,
which `TechTreeSystem` already supports without changes (`getBonus` doesn't
care about the tree shape, only `purchase`'s eligibility check does, and
that check is already prerequisite-aware).

**Rendering this as a tree in Roblox UI is genuinely different from the
HTML mockup**, worth flagging before someone tries to port the mockup's CSS
trick directly: that trick (`::before`/`::after` pseudo-elements on `<li>`)
has no Roblox equivalent. Two realistic options:

1. **Indentation, no connector lines** (recommended to ship first): render
   nodes in a flat scrolling list but indent each one under its parent
   (`UIListLayout` + a `Frame` spacer sized to depth × some padding). Gets
   the *gating* right immediately with almost no new UI code.
   Locked/unlocked/maxed states are just `Frame.BackgroundColor3` /
   `TextButton.Active` changes, same pattern already used for gear rows.
2. **Real connector lines** (polish pass, later): compute each node
   `Frame`'s `AbsolutePosition`/`AbsoluteSize` after layout and draw thin
   `Frame`s between a parent's bottom-center and each child's top-center.
   This has to happen in a `RenderStepped`/`Changed` listener since Roblox
   doesn't lay out UI synchronously the way CSS does - don't attempt this
   before (1) is working and looks fine on its own.

### 2.7 Enchantments (new, currently undefined beyond "a reward exists")

The mockup only got as far as "Rune Chamber gives you an Enchantment" - it
never designed what applying one does. Minimum viable version:

- `data.enchantments = { { id, statBonus = { stat = "Damage", value = N },
  rarity } }` - an unattached inventory, separate from gear.
- A new remote, `RequestApplyEnchantment(itemId, enchantmentId)`: finds the
  gear item and the enchantment, appends `statBonus` as an extra entry in
  the item's `substats` list (reuse the existing substat rendering/stat-sum
  code as-is, it doesn't care where a substat came from), removes the
  enchantment from `data.enchantments`.
- v1 can allow unlimited enchantments per item (simplest); "one per item,
  re-applying overwrites the old one" is an easy tightening pass later if
  stacking turns out to be too strong once real numbers exist.

### 2.8 Pets: hatched from eggs, not gacha-rolled, duplicates level up

**Structural change to `data.pets`.** Today it's a flat list of owned pet
*definition IDs* (`PetDefinitions.Pets` entries are static, no per-owner
state). That no longer works, because pets now need instance state (level).
Change `data.pets` to a list of `{ defId, level, equipped }` records.
Unlike Gear's Weapon/Armor/Accessory, pets don't have distinct slot roles,
so the "up to 3 equipped" cap doesn't need slot indices anymore - just
refuse to set `equipped = true` on a 4th pet while 3 already have it set.
`LoadoutSystem`'s equip/unequip logic mostly survives, just swap its
slot-index bookkeeping for a count check when the kind is `"Pet"`, and have
`isOwned` check `defId` instead of a raw string.

New pieces:

- `data.eggs = { { id, rarity } }` - egg inventory, populated by Dungeon
  "egg" rewards (§2.2).
- `RequestHatchEgg(eggId)` remote → `PetSystem.hatch(player, data, eggId)`:
  removes the egg, rolls a pet from `PetDefinitions` filtered to that
  rarity (reuse `GachaSystem`'s existing `pickPool`-style filtering, same
  idea as its rarity+age filter, just rarity-only here since an egg's
  rarity is already fixed). If the player already owns that `defId`,
  increment its `level` instead of adding a duplicate record and fire a
  "duplicate, leveled up" result; otherwise push a new `{ defId, level = 1,
  equipped = false }` record. Fire a result to the client either way so the
  UI can show the right toast.
- Pet stat bonuses (`PowerCalculator`/`CombatStats.addFlatBonuses`) need to
  scale with `level` now instead of being flat - something like `bonus *
  (1 + 0.1 * (level - 1))`, capped at a sane max level (20, matching the
  mockup).
- `GachaSystem.lua` loses its `"Pet"` branch entirely - only `"Skill"` rolls
  remain. Remove the `poolType == "Pet"` handling and the client's Roll Pet
  button/remote call.

### 2.9 Skills: unchanged

Still gacha-rolled via Gacha Currency, still up to 3 equipped via
`LoadoutSystem`. No design changes here - just note that with Pets gone
from `GachaSystem`, it's now single-purpose (`"Skill"` is the only valid
`poolType`); simplify the remote signature if it's easy, but that's cleanup
not a requirement.

### 2.10 Arena, Prestige, Background theming: unchanged

Everything in `ArenaSystem.lua`, `PrestigeSystem.lua`, and
`BackgroundSystem.lua` stays exactly as designed in the previous pass - no
part of the mockup work touched these. (Age is still fully automatic,
driven by chapter progress; there is no "age switcher" in the real game -
that control only ever existed in the HTML preview to demo the theming
system, and showing it to players would let them see content out of order
for no gameplay reason.)

---

## 3. Client UI: tabs, not a single drawer

The previous pass built one toggleable "Menu" drawer holding everything.
That's now five bottom tabs - **Arena / Dungeon / Home / Collection /
Tech**, Home the default-open one - each showing different `Frame`s inside
the same panel area. Collection additionally splits into two **sub-tabs**
(Pets / Skills) via a small pill switcher at the top of that tab's content -
same show-one-hide-others pattern as the main tabs, just nested one level.

Always-visible (not behind any tab): the Ore/Power/Gacha-Currency readout,
the current stage label + enemy/player HP bars (now per-enemy, §2.1), and
the world view itself with the avatar and enemies.

**Home tab contents**: Progress (age, idle Ore rate, Hourly Claim
button/countdown, Prestige Points + Prestige button when eligible),
Equipment (3 gear-slot tiles, tap one to open the detail popup), Forge
(Craft button - now costs `baseCost × slotCount` and is instant, Forge
Level + Coins + Upgrade Forge button).

**Dungeon tab**: three entries (Ore Vault / Beast Den / Rune Chamber), each
with a name, one-line flavor, and which reward it favors, each with its own
Enter button. Entering opens a full-screen reveal flow (brief "searching"
state, then the rolled reward with a Claim button) rather than resolving
inline in the tab.

**Collection tab → Pets sub-tab**: Eggs list (tap to hatch), equipped pet
slot(s), owned pets list (each shows level, Equip/Unequip). **Skills
sub-tab**: Roll Skill button + result feedback, equipped skill slots, owned
skills list.

**Tech tab**: the node tree (§2.6) - ship the indented-list version first,
connector lines later if it's worth the polish.

**Gear detail popup** (opens from an Equipment tile, a Gear Inventory row if
you keep one, or right after a Forge craft): item name, rarity, full
substat list (including any applied enchantment - §2.7), and two buttons,
**Equip/Unequip** and **Sell**. This already conceptually exists in the
mockup and just needs to be the one place both crafting-reveal and
inventory-browsing route through, instead of separate UI for each.

---

## 4. `DataManager` schema changes

Additions to `DEFAULT_DATA` (everything else - `ore`, `prestigePoints`,
`prestigeCount`, `totalOreEarned`, `gachaCurrency`, `gear`, `equippedGear`,
`skills`, `equippedSkillIds`, `researchPoints`, `techTree`, `stageProgress`,
`arena` - stays as-is):

| Field | Type | Notes |
|---|---|---|
| `coins` | `number` | new currency, from selling gear |
| `forgeLevel` | `number` | starts at 1; Coins-funded, shifts craft rarity odds |
| `lastOreClaimAt` | `number` (`os.time()`) | hourly-claim gate |
| `pets` | `{ { defId, level, equipped } }` | **changed shape** - was a flat list of ids |
| `equippedPetIds` | *(remove)* | folded into `pets[i].equipped` now that pets carry state |
| `eggs` | `{ { id, rarity } }` | new - dungeon "egg" reward inventory |
| `enchantments` | `{ { id, statBonus, rarity } }` | new - dungeon "enchant" reward inventory |
| `dungeonCooldowns` | `{ [dungeonId]: number }` | new - per-dungeon-type last-entered timestamp |
| `forgeJobs` | *(remove)* | the timed-queue system it supported is gone (§2.3) |

Bump `DEFAULT_DATA._version` and let the existing generic `migrate()`
backfill new fields as always - no special-case migration needed for
additions. The **shape change** to `pets` (and removal of
`equippedPetIds`) is the one field `migrate()` can't safely handle
generically (it only fills in *missing* keys, it doesn't reshape existing
ones) - since this project has never been opened in Studio and has no real
player saves yet, that's a non-issue right now; if it ever does have real
saves before this change ships, write a one-time explicit migration step
for `pets` instead of relying on the generic backfill.

---

## 5. Module change map

**New files:**
- `ReplicatedStorage/Modules/MarketplaceAssets.lua` - curated asset-ID
  table per slot+rarity (§2.5)
- `ReplicatedStorage/Modules/DungeonDefinitions.lua` - the 3 dungeon
  entries + reward weight tables (§2.2) - note this is a *different*
  concept from the pre-redesign `DungeonDefinitions.lua` that got deleted
  earlier; don't resurrect that one from git history, it was the old
  auto-battle-resolver design
- `ServerStorage/Modules/DungeonSystem.lua` - server-authoritative reward
  roll + cooldown enforcement
- `ServerStorage/Modules/GearVisuals.lua` - `InsertService`/`AddAccessory`
  wrapper (§2.5), called from `GearSystem.equip`/`unequip`
- `ServerStorage/Modules/PetSystem.lua` - egg hatching (§2.8)

**Modified files:**
- `ForgeSystem.lua` - remove the timed job queue, add instant batch
  crafting + Forge Level rarity weighting (§2.3)
- `GearSystem.lua` - add `sell()` (§2.4), call into `GearVisuals` on
  equip/unequip (§2.5)
- `TechTreeDefinitions.lua` - add prerequisite edges + the one new leaf
  node (§2.6)
- `StageSystem.lua` / `LaneSystem.lua` - per-enemy HP instead of a shared
  pool, attack-animation hooks, stage clears grant Research Points instead
  of Ore (§2.1)
- `GachaSystem.lua` - drop the `"Pet"` pool type (§2.8)
- `LoadoutSystem.lua` - pet ownership check reads `pets[i].defId` instead
  of a raw id (§2.8)
- `EconomySystem.lua` - add the hourly-claim remote handler and
  `secondsUntilClaim` in `pushState` (§2.2)
- `DataManager.lua` - schema changes (§4)
- `NetworkEvents.lua` - add `RequestClaimHourlyOre`, `RequestEnterDungeon`,
  `DungeonResult`, `RequestHatchEgg`, `HatchResult`,
  `RequestApplyEnchantment`, `RequestSellGear`; remove anything tied to the
  deleted forge-job system if it had its own remote (it didn't - forge
  results already push through the existing `ForgeResult`)
- `UIManager.lua` - the tab rebuild (§3); this is the single biggest
  client-side rewrite in this pass, comparable in size to the previous
  redesign's UIManager rewrite
- `Server.server.lua` - require/init the new `DungeonSystem` and
  `PetSystem`

**Unchanged:** `AgeDefinitions.lua`, `StageDefinitions.lua` (aside from the
per-enemy-HP split, which is additive to its return shape, not a rewrite),
`GearDefinitions.lua`, `SkillDefinitions.lua`, `CombatStats.lua`,
`PowerCalculator.lua` (aside from pet-level scaling, §2.8),
`ArenaSystem.lua`, `PrestigeSystem.lua`, `BackgroundSystem.lua`,
`ForgeClient.lua` (just gains a couple more remote listeners, same
pattern).

---

## 6. Suggested build order

Roughly in dependency order - each milestone should be playable end-to-end
before starting the next, even if ugly:

1. **Data schema first** - land the `DataManager` changes (§4) and get the
   game loading/saving with the new shape before touching gameplay, so
   every later step has somewhere to put state.
2. **Per-enemy HP + attack animation** (§2.1) - this touches the core loop
   that's already running, do it before layering new systems on top of a
   combat model that's about to change shape.
3. **Forge rework** (§2.3) - instant batch crafting, Forge Level. Verify
   Coins flow correctly once §2.4 (sell) exists alongside it.
4. **Tech Tree prerequisites** (§2.6) - small, mostly data-only change;
   ship the indented-list UI, not connector lines, first.
5. **Dungeon** (§2.2, §2.7 for the enchant reward, new `DungeonSystem.lua`)
   - the reward pool references eggs and enchantments, so land the *data
   shapes* for those even before Pets (§2.8) fully consumes eggs.
6. **Pets rework** (§2.8) - egg hatching, the `pets` schema change,
   `GachaSystem` losing its Pet branch.
7. **Marketplace visuals** (§2.5) - do this last among the systems work; it
   depends on gear already existing and equip/unequip already working, and
   it's the one piece that needs real testing in Studio against real
   catalog IDs before you'll know if the approach holds up.
8. **UIManager tab rebuild** (§3) - can start in parallel with steps 3-7
   once their remotes/state shapes are settled, since the UI is mostly
   consuming `pushState` fields; finish it once all the systems above are
   in so there's real data to render.

---

## 7. Open questions / risks to resolve once you're actually in Studio

- **Marketplace asset reliability is completely unverified.** Everything in
  §2.5 is the *correct API shape* (`InsertService:LoadAsset` +
  `Humanoid:AddAccessory` is genuinely how this works), but which specific
  catalog IDs are actually free, currently loadable, and look right on an
  R15 rig can only be checked by hand in Studio's Avatar Editor. Budget real
  time for this - it's asset curation work, not scripting work.
- **All numeric balance is still an illustrative placeholder** - Forge
  Level's rarity-weight curve, dungeon cooldown length, hourly-claim amount,
  pet level-scaling formula, enchantment stacking. None of this got the
  Python shadow-model treatment the very first version of this project got.
  Don't trust any specific number here; trust the *shapes* of the formulas
  and re-tune once you can actually play it.
- **Dungeon cooldown/cost is a genuine open design decision**, not just an
  unbalanced number - free-and-uncooled would get macro'd, but the right
  cost (time-gated only? consumes a "key" resource? both?) wasn't settled
  during design. Pick something simple to ship (a flat per-dungeon-type
  cooldown) and revisit once the rest of the economy is tuned.
- **Enchantment application is the least-designed system in this doc** -
  the mockup only ever got as far as "you receive one." Whether it should
  cap at one-per-item, whether different enchantment types should exist
  beyond "+stat," and how it's surfaced in the gear popup all need a real
  decision before or during implementation, not just during design.
