-- ServerStorage/Modules/PowerCalculator.lua
-- Resolves a player's authoritative save data (equipped gear + pets + skills)
-- into a CombatStats sheet, plus either a single Power scalar (ArenaSystem's
-- instant stat-check) or a real-time dps/maxHP combatant (StageSystem's
-- tick-based stage combat).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatStats = require(ReplicatedStorage.Modules.CombatStats)
local PetDefinitions = require(ReplicatedStorage.Modules.PetDefinitions)
local SkillDefinitions = require(ReplicatedStorage.Modules.SkillDefinitions)
local TechTreeSystem = require(script.Parent.TechTreeSystem)

local PowerCalculator = {}

local function findDef(list, id)
	for _, entry in list do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

function PowerCalculator.getStats(data)
	local stats = CombatStats.newStats()

	for _, itemId in data.equippedGear do
		if itemId then
			for _, gear in data.gear do
				if gear.id == itemId then
					CombatStats.addGear(stats, gear)
					break
				end
			end
		end
	end

	for _, petId in data.equippedPetIds do
		if petId then
			local def = findDef(PetDefinitions.Pets, petId)
			if def then
				CombatStats.addFlatBonuses(stats, def.bonuses)
			end
		end
	end

	for _, skillId in data.equippedSkillIds do
		if skillId then
			local def = findDef(SkillDefinitions.Skills, skillId)
			if def then
				CombatStats.addFlatBonuses(stats, def.bonuses)
			end
		end
	end

	return stats
end

function PowerCalculator.getPower(data): number
	return CombatStats.computePower(PowerCalculator.getStats(data))
end

-- Real-time stage combat numbers (dps/maxHP/regenPerSecond), folding in tech
-- tree damage/HP bonuses on top of the gear/pet/skill stat sheet.
function PowerCalculator.getCombatant(data)
	local stats = PowerCalculator.getStats(data)
	local techBonus = {
		damagePercent = TechTreeSystem.getBonus(data, "damagePercent"),
		maxHPPercent = TechTreeSystem.getBonus(data, "maxHPPercent"),
	}
	return CombatStats.computeCombatant(stats, techBonus)
end

return PowerCalculator
