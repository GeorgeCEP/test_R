-- ServerStorage/Modules/EconomySystem.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local AgeDefinitions = require(ReplicatedStorage.Modules.AgeDefinitions)
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local PowerCalculator = require(script.Parent.PowerCalculator)

local EconomySystem = {}

local IDLE_TICK_SECONDS = 1
local AUTOSAVE_SECONDS = 60
local TECH_POINT_MULTIPLIER_STEP = 0.02 -- +2% global Ore output per Tech Point
local ARENA_DAILY_ATTEMPTS = 3

local stateUpdated = NetworkEvents.get("StateUpdated")

function EconomySystem.getGlobalMultiplier(data): number
	return 1 + (data.techPoints * TECH_POINT_MULTIPLIER_STEP)
end

function EconomySystem.getTapPower(data): number
	local age = AgeDefinitions.get(data.age)
	return age.tapBase * EconomySystem.getGlobalMultiplier(data)
end

function EconomySystem.getIdleOutputPerSecond(data): number
	local age = AgeDefinitions.get(data.age)
	local total = 0
	for _, building in age.buildings do
		local count = data.buildings[building.id] or 0
		total += count * building.baseOutput
	end
	return total * EconomySystem.getGlobalMultiplier(data)
end

function EconomySystem.getBuildingCost(building, ownedCount): number
	return building.baseCost * (building.costGrowth ^ ownedCount)
end

function EconomySystem.addOre(data, amount: number)
	data.ore += amount
	data.totalOreEarned += amount
end

function EconomySystem.pushState(player: Player, data)
	local age = AgeDefinitions.get(data.age)
	local maxAge = AgeDefinitions.getMaxAgeUnlocked(data.prestigeCount)

	local buildingInfo = {}
	for _, building in age.buildings do
		local owned = data.buildings[building.id] or 0
		table.insert(buildingInfo, {
			id = building.id,
			name = building.name,
			owned = owned,
			cost = EconomySystem.getBuildingCost(building, owned),
			output = building.baseOutput * EconomySystem.getGlobalMultiplier(data),
		})
	end

	local today = math.floor(os.time() / 86400)
	local arenaAttemptsLeft = if data.arena.lastResetDay == today
		then math.max(0, ARENA_DAILY_ATTEMPTS - data.arena.rollsToday)
		else ARENA_DAILY_ATTEMPTS

	stateUpdated:FireClient(player, {
		ore = data.ore,
		ageId = data.age,
		ageName = age.name,
		resourceLabel = age.resourceLabel,
		tapPower = EconomySystem.getTapPower(data),
		idlePerSecond = EconomySystem.getIdleOutputPerSecond(data),
		buildings = buildingInfo,
		techPoints = data.techPoints,
		prestigeCount = data.prestigeCount,
		ageUpCost = age.ageUpCost,
		atPrestigeCap = data.age >= maxAge,

		gachaCurrency = data.gachaCurrency,
		power = PowerCalculator.getPower(data),
		gear = data.gear,
		equippedGear = data.equippedGear,
		pets = data.pets,
		equippedPetIds = data.equippedPetIds,
		skills = data.skills,
		equippedSkillIds = data.equippedSkillIds,

		dungeonCooldownRemaining = math.max(0, data.dungeonCooldownEnd - os.time()),
		arenaAttemptsLeft = arenaAttemptsLeft,
	})
end

function EconomySystem.buyBuilding(player: Player, data, buildingId: string): boolean
	local age = AgeDefinitions.get(data.age)
	local building = AgeDefinitions.getBuilding(data.age, buildingId)
	if not building then
		return false
	end

	local owned = data.buildings[buildingId] or 0
	local cost = EconomySystem.getBuildingCost(building, owned)
	if data.ore < cost then
		return false
	end

	data.ore -= cost
	data.buildings[buildingId] = owned + 1
	EconomySystem.pushState(player, data)
	return true
end

function EconomySystem.init()
	-- Idle production tick
	task.spawn(function()
		while true do
			task.wait(IDLE_TICK_SECONDS)
			for _, player in Players:GetPlayers() do
				local data = DataManager.getData(player)
				if data then
					local perSecond = EconomySystem.getIdleOutputPerSecond(data)
					if perSecond > 0 then
						EconomySystem.addOre(data, perSecond * IDLE_TICK_SECONDS)
						EconomySystem.pushState(player, data)
					end
				end
			end
		end
	end)

	-- Autosave loop in addition to PlayerRemoving/BindToClose saves
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for _, player in Players:GetPlayers() do
				DataManager.savePlayerData(player)
			end
		end
	end)

	NetworkEvents.get("RequestBuyBuilding").OnServerEvent:Connect(function(player, buildingId)
		if type(buildingId) ~= "string" then
			return
		end
		local data = DataManager.getData(player)
		if not data then
			return
		end
		EconomySystem.buyBuilding(player, data, buildingId)
	end)
end

return EconomySystem
