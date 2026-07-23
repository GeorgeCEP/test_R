-- ServerStorage/Modules/PrestigeSystem.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AgeDefinitions = require(ReplicatedStorage.Modules.AgeDefinitions)
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)

local PrestigeSystem = {}

local PRESTIGE_GACHA_BONUS = 200

function PrestigeSystem.isEligible(data): boolean
	local maxAge = AgeDefinitions.getMaxAgeUnlocked(data.prestigeCount)
	return data.age >= maxAge
end

function PrestigeSystem.previewTechPoints(data): number
	return math.floor(math.sqrt(data.totalOreEarned / 1e6))
end

function PrestigeSystem.tryPrestige(player: Player, data): boolean
	if not PrestigeSystem.isEligible(data) then
		return false
	end

	local awarded = PrestigeSystem.previewTechPoints(data)
	if awarded <= 0 then
		return false
	end

	data.techPoints += awarded
	data.gachaCurrency += PRESTIGE_GACHA_BONUS
	data.prestigeCount += 1

	-- Reset the economy loop; gear/pets/skills/gachaCurrency/techPoints persist.
	data.ore = 0
	data.age = 1
	data.buildings = {}
	data.totalOreEarned = 0

	EconomySystem.pushState(player, data)
	return true
end

function PrestigeSystem.init()
	NetworkEvents.get("RequestPrestige").OnServerEvent:Connect(function(player)
		local data = DataManager.getData(player)
		if not data then
			return
		end
		PrestigeSystem.tryPrestige(player, data)
	end)
end

return PrestigeSystem
