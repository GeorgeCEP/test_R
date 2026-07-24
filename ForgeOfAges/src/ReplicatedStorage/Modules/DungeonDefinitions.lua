-- ReplicatedStorage/Modules/DungeonDefinitions.lua
-- Dungeons are a separate stage ladder from the main chapter crawl (see
-- StageDefinitions): three dungeon types, each with their own long stage
-- progression. A player can replay any stage they've already unlocked
-- (lower stage = safer, smaller reward) or push into the next unclaimed one
-- (harder monsters, better reward) - selection just moves a cursor, it
-- doesn't forfeit progress already made.
--
-- Reward composition follows the README's Egg/Ore/Enchantment split: each
-- run resolves to exactly one of the three kinds (weighted per dungeon, so
-- every dungeon "favors" one), not a blend of all three.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GearDefinitions = require(ReplicatedStorage.Modules.GearDefinitions)

local DungeonDefinitions = {}

DungeonDefinitions.MAX_STAGE = 40
DungeonDefinitions.STAGE_GROWTH = 1.18 -- per dungeon-stage difficulty growth
DungeonDefinitions.WAVES_PER_RUN = 3
DungeonDefinitions.WAVE_GROWTH = 1.15 -- difficulty ramp across the 3 waves within one run
DungeonDefinitions.COOLDOWN_SECONDS = 150

local HP_FACTOR = 6
local DPS_FACTOR = 0.4

DungeonDefinitions.Order = { "OreVault", "BeastDen", "RuneChamber" }

DungeonDefinitions.Dungeons = {
	OreVault = {
		id = "OreVault",
		name = "Ore Vault",
		flavor = "Rich veins guarded by stone golems - favors Ore.",
		zoneName = "Ore Vault",
		enemyName = "Vault Golem",
		baseDifficulty = 25,
		favorLabel = "Ore",
		eggWeight = 0.15,
		oreWeight = 0.70,
		enchantWeight = 0.15,
	},
	BeastDen = {
		id = "BeastDen",
		name = "Beast Den",
		flavor = "A snarling warren of feral beasts - favors Eggs.",
		zoneName = "Beast Den",
		enemyName = "Feral Stalker",
		baseDifficulty = 20,
		favorLabel = "Eggs",
		eggWeight = 0.65,
		oreWeight = 0.15,
		enchantWeight = 0.20,
	},
	RuneChamber = {
		id = "RuneChamber",
		name = "Rune Chamber",
		flavor = "Ancient wards hum with power - favors Enchantments.",
		zoneName = "Rune Chamber",
		enemyName = "Rune Sentinel",
		baseDifficulty = 22,
		favorLabel = "Enchantments",
		eggWeight = 0.10,
		oreWeight = 0.20,
		enchantWeight = 0.70,
	},
}

function DungeonDefinitions.get(dungeonId: string)
	return DungeonDefinitions.Dungeons[dungeonId]
end

local function enemyCount(stage: number): number
	return math.min(6, 2 + math.floor((stage - 1) / 6))
end

-- Total difficulty power for one wave, before the within-run per-wave ramp.
function DungeonDefinitions.getStageDifficulty(dungeonId: string, stage: number): number
	local def = DungeonDefinitions.Dungeons[dungeonId]
	stage = math.clamp(stage, 1, DungeonDefinitions.MAX_STAGE)
	return def.baseDifficulty * (DungeonDefinitions.STAGE_GROWTH ^ (stage - 1))
end

-- Everything needed to run/display one wave within a dungeon run. waveIndex
-- is 1..WAVES_PER_RUN - later waves in the same run are a bit tougher.
function DungeonDefinitions.getWaveInfo(dungeonId: string, stage: number, waveIndex: number)
	local def = DungeonDefinitions.Dungeons[dungeonId]
	stage = math.clamp(stage, 1, DungeonDefinitions.MAX_STAGE)

	local baseDifficulty = DungeonDefinitions.getStageDifficulty(dungeonId, stage)
	local difficulty = baseDifficulty * (DungeonDefinitions.WAVE_GROWTH ^ (waveIndex - 1))

	return {
		dungeonId = dungeonId,
		stage = stage,
		waveIndex = waveIndex,
		label = string.format("%s Stage %d (Wave %d/%d)", def.name, stage, waveIndex, DungeonDefinitions.WAVES_PER_RUN),
		zoneName = def.zoneName,
		enemyName = def.enemyName,
		enemyCount = enemyCount(stage),
		waveMaxHP = difficulty * HP_FACTOR,
		waveDPS = difficulty * DPS_FACTOR,
	}
end

-- Reward for clearing an entire run (all WAVES_PER_RUN waves) at a stage:
-- rolls exactly one of Egg | Ore | Enchantment against the dungeon's weight
-- table, then rolls a rarity/amount within that kind. `ageId` is the
-- player's current age (from EconomySystem.getAgeId) - only needed to size
-- an Enchantment's stat value against the same curve gear substats use.
function DungeonDefinitions.getRunReward(dungeonId: string, stage: number, ageId: number)
	local def = DungeonDefinitions.Dungeons[dungeonId]
	local difficulty = DungeonDefinitions.getStageDifficulty(dungeonId, stage)

	local roll = math.random()
	if roll <= def.eggWeight then
		-- Only Common/Legendary pets exist today (see PetDefinitions) - bias
		-- toward that split until Rare/Epic pets are authored; PetSystem
		-- also falls back gracefully if this ever doesn't match exactly.
		local eggRarity = if math.random() < 0.85 then "Common" else "Legendary"
		return { kind = "Egg", eggRarity = eggRarity }
	elseif roll <= def.eggWeight + def.oreWeight then
		return { kind = "Ore", oreAmount = difficulty * 0.5 }
	else
		local rarity = GearDefinitions.Rarities[math.random(1, #GearDefinitions.Rarities)]
		local statId = GearDefinitions.SubstatIds[math.random(1, #GearDefinitions.SubstatIds)]
		-- Smaller than a full gear-roll substat (0.4x) since this only adds
		-- one stat on top of an item's existing rolled substats.
		local maxValue = GearDefinitions.getMaxValue(statId, ageId) * rarity.valueMultiplier * 0.4
		local value = maxValue * (0.5 + math.random() * 0.5)
		return {
			kind = "Enchantment",
			enchantRarity = rarity.id,
			statId = statId,
			statValue = math.floor(value * 100) / 100,
		}
	end
end

return DungeonDefinitions
