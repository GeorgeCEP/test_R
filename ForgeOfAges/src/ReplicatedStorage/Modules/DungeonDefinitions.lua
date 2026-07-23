-- ReplicatedStorage/Modules/DungeonDefinitions.lua
-- One dungeon per age. difficultyPower is compared against the player's
-- CombatStats.computePower() result - these numbers are placeholders and
-- need tuning once real gear/pet/skill power totals are observed in
-- playtesting.

local DungeonDefinitions = {}

DungeonDefinitions.Dungeons = {
	{ ageId = 1, name = "Sabertooth Den", difficultyPower = 40, gachaReward = 15, gearDropChance = 0.5 },
	{ ageId = 2, name = "Bandit Stronghold", difficultyPower = 600, gachaReward = 25, gearDropChance = 0.5 },
	{ ageId = 3, name = "Smog-Choked Mines", difficultyPower = 9000, gachaReward = 40, gearDropChance = 0.45 },
	{ ageId = 4, name = "Rogue Fortress", difficultyPower = 140000, gachaReward = 60, gearDropChance = 0.45 },
	{ ageId = 5, name = "Derelict Station", difficultyPower = 2200000, gachaReward = 90, gearDropChance = 0.4 },
	{ ageId = 6, name = "Corrupted Mainframe", difficultyPower = 34000000, gachaReward = 130, gearDropChance = 0.4 },
	{ ageId = 7, name = "Xeno Hive", difficultyPower = 520000000, gachaReward = 190, gearDropChance = 0.35 },
	{ ageId = 8, name = "Gates of Judgement", difficultyPower = 8000000000, gachaReward = 260, gearDropChance = 0.35 },
	{ ageId = 9, name = "The Abyssal Throne", difficultyPower = 120000000000, gachaReward = 350, gearDropChance = 0.3 },
}

function DungeonDefinitions.get(ageId: number)
	for _, dungeon in DungeonDefinitions.Dungeons do
		if dungeon.ageId == ageId then
			return dungeon
		end
	end
	return nil
end

return DungeonDefinitions
