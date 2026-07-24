-- ServerStorage/Modules/GachaSystem.lua
-- Skill rolls only now - Pets are hatched from Dungeon egg rewards instead
-- (see PetSystem), not gacha-rolled. The pool is filtered to entries whose
-- ageId is <= the player's current age, so new skills unlock progressively
-- as the player advances through the ages.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkillDefinitions = require(ReplicatedStorage.Modules.SkillDefinitions)
local GearDefinitions = require(ReplicatedStorage.Modules.GearDefinitions)
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)

local GachaSystem = {}

local ROLL_COST = 100
local DUPLICATE_REFUND = 25

local function rollRarity(): string
	local total = 0
	for _, rarity in GearDefinitions.Rarities do
		total += rarity.weight
	end
	local roll = math.random() * total
	local cursor = 0
	for _, rarity in GearDefinitions.Rarities do
		cursor += rarity.weight
		if roll <= cursor then
			return rarity.id
		end
	end
	return "Common"
end

local function pickPool(pool, maxAge: number, rarityId: string)
	local candidates = {}
	for _, entry in pool do
		if entry.ageId <= maxAge and entry.rarity == rarityId then
			table.insert(candidates, entry)
		end
	end
	if #candidates == 0 then
		-- Fall back to any rarity unlocked at this age if none match the roll exactly.
		for _, entry in pool do
			if entry.ageId <= maxAge then
				table.insert(candidates, entry)
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[math.random(1, #candidates)]
end

function GachaSystem.roll(player: Player, data)
	if data.gachaCurrency < ROLL_COST then
		return nil
	end

	local rarityId = rollRarity()
	local entry = pickPool(SkillDefinitions.Skills, EconomySystem.getAgeId(data), rarityId)
	if not entry then
		return nil
	end

	data.gachaCurrency -= ROLL_COST

	local alreadyOwned = false
	for _, ownedId in data.skills do
		if ownedId == entry.id then
			alreadyOwned = true
			break
		end
	end

	if alreadyOwned then
		data.gachaCurrency += DUPLICATE_REFUND
	else
		table.insert(data.skills, entry.id)
	end

	EconomySystem.pushState(player, data)
	return { poolType = "Skill", resultId = entry.id, name = entry.name, rarity = entry.rarity, duplicate = alreadyOwned }
end

function GachaSystem.init()
	local gachaResult = NetworkEvents.get("GachaResult")

	NetworkEvents.get("RequestGachaRoll").OnServerEvent:Connect(function(player)
		local data = DataManager.getData(player)
		if not data then
			return
		end

		local result = GachaSystem.roll(player, data)
		if result then
			gachaResult:FireClient(player, result)
		end
	end)
end

return GachaSystem
