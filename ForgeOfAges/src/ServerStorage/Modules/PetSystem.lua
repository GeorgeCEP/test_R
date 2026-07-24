-- ServerStorage/Modules/PetSystem.lua
-- Pets are hatched from eggs (a Dungeon "egg" reward - see DungeonSystem/
-- DungeonDefinitions), not gacha-rolled - GachaSystem only rolls Skills
-- now. Hatching a duplicate defId levels up the existing pet instead of
-- adding a second copy, since data.pets holds instance state ({defId,
-- level, equipped}) rather than a flat list of owned ids.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PetDefinitions = require(ReplicatedStorage.Modules.PetDefinitions)
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)

local PetSystem = {}

PetSystem.MAX_PET_LEVEL = 20

-- Same rarity+age filtering pattern GachaSystem uses: exact rarity match
-- first, falling back to anything unlocked at this age if none match.
local function pickPetForRarity(rarityId: string, maxAge: number)
	local candidates = {}
	for _, def in PetDefinitions.Pets do
		if def.ageId <= maxAge and def.rarity == rarityId then
			table.insert(candidates, def)
		end
	end
	if #candidates == 0 then
		for _, def in PetDefinitions.Pets do
			if def.ageId <= maxAge then
				table.insert(candidates, def)
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[math.random(1, #candidates)]
end

function PetSystem.hatch(player: Player, data, eggId: string)
	local eggIndex, egg = nil, nil
	for i, entry in data.eggs do
		if entry.id == eggId then
			eggIndex, egg = i, entry
			break
		end
	end
	if not egg then
		return nil
	end

	local def = pickPetForRarity(egg.rarity, EconomySystem.getAgeId(data))
	if not def then
		return nil
	end
	table.remove(data.eggs, eggIndex)

	local existing = nil
	for _, pet in data.pets do
		if pet.defId == def.id then
			existing = pet
			break
		end
	end

	local result
	if existing then
		existing.level = math.min(PetSystem.MAX_PET_LEVEL, existing.level + 1)
		result = { defId = def.id, name = def.name, rarity = def.rarity, duplicate = true, level = existing.level }
	else
		table.insert(data.pets, { defId = def.id, level = 1, equipped = false })
		result = { defId = def.id, name = def.name, rarity = def.rarity, duplicate = false, level = 1 }
	end

	EconomySystem.pushState(player, data)
	return result
end

function PetSystem.init()
	local hatchResult = NetworkEvents.get("HatchResult")

	NetworkEvents.get("RequestHatchEgg").OnServerEvent:Connect(function(player, eggId)
		if type(eggId) ~= "string" then
			return
		end
		local data = DataManager.getData(player)
		if not data then
			return
		end
		local result = PetSystem.hatch(player, data, eggId)
		if result then
			hatchResult:FireClient(player, result)
		end
	end)
end

return PetSystem
