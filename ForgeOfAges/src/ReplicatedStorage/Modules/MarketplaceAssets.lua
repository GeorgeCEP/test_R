-- ReplicatedStorage/Modules/MarketplaceAssets.lua
-- Curated catalog asset IDs per gear slot + rarity, consumed by GearVisuals.
-- Ships EMPTY on purpose - there is no script API to browse the Roblox
-- catalog, so this can only be filled in by hand: open the game in Studio,
-- use the Avatar Editor / catalog search to find a free accessory that fits
-- each slot+rarity (a rustic pauldron for Common Armor, something ornate
-- and glowing for Legendary), and paste its asset ID into the matching
-- array below. Prefer free items - equipping something a player doesn't
-- personally own is fine inside your own game (same as any NPC wearing
-- catalog cosmetics), but sticking to free items avoids any ambiguity and
-- costs nothing to test.
--
-- Weapon is a held-prop catalog accessory (a Front/Hat-type accessory that
-- happens to look weapon-shaped), not a real Roblox `Tool` - see README
-- §2.5 for why: classic swingable Gear is mostly ownership-gated now and
-- won't load for players who don't own it, and this game's combat is fully
-- automatic so a hotbar Tool was never doing real work anyway.
--
-- An empty pool for a slot+rarity is not an error - GearVisuals just skips
-- the visual for that item and the stat side keeps working normally, so
-- it's safe to ship, playtest, and fill in incrementally.

local MarketplaceAssets: { [string]: { [string]: { number } } } = {
	Weapon = {
		Common = {},
		Rare = {},
		Epic = {},
		Legendary = {},
	},
	Armor = {
		Common = {},
		Rare = {},
		Epic = {},
		Legendary = {},
	},
	Accessory = {
		Common = {},
		Rare = {},
		Epic = {},
		Legendary = {},
	},
}

return MarketplaceAssets
