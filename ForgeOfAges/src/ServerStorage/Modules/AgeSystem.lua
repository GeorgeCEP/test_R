-- ServerStorage/Modules/AgeSystem.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AgeDefinitions = require(ReplicatedStorage.Modules.AgeDefinitions)
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)

local AgeSystem = {}

local AGE_UP_GACHA_BONUS = 20

function AgeSystem.tryAgeUp(player: Player, data): boolean
	local age = AgeDefinitions.get(data.age)
	if not age.ageUpCost then
		return false -- final age in this prestige cycle (or true final age, Hell)
	end

	local maxAge = AgeDefinitions.getMaxAgeUnlocked(data.prestigeCount)
	if data.age >= maxAge then
		return false
	end

	if data.ore < age.ageUpCost then
		return false
	end

	data.ore -= age.ageUpCost
	data.age += 1
	data.gachaCurrency += AGE_UP_GACHA_BONUS

	EconomySystem.pushState(player, data)
	return true
end

function AgeSystem.init()
	NetworkEvents.get("RequestAgeUp").OnServerEvent:Connect(function(player)
		local data = DataManager.getData(player)
		if not data then
			return
		end
		AgeSystem.tryAgeUp(player, data)
	end)
end

return AgeSystem
