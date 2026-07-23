-- ServerStorage/Modules/DataManager.lua
local DataStoreService = game:GetService("DataStoreService")

local DataManager = {}

local playerDataStore = DataStoreService:GetDataStore("ForgeOfAges_PlayerData_v1")
local loadedData: { [number]: any } = {}

local DEFAULT_DATA = {
	_version = 1,

	-- Economy / age progression
	ore = 0,
	age = 1,
	buildings = {},
	techPoints = 0,
	prestigeCount = 0,
	totalOreEarned = 0,

	-- Gear / pets / skills / gacha
	gachaCurrency = 0,
	gear = {},
	equippedGear = {},
	pets = {},
	equippedPetIds = {},
	skills = {},
	equippedSkillIds = {},

	-- Dungeon / arena
	dungeonCooldownEnd = 0,
	arena = { rollsToday = 0, lastResetDay = 0 },
}

local function deepCopy(t)
	local copy = {}
	for k, v in t do
		copy[k] = if type(v) == "table" then deepCopy(v) else v
	end
	return copy
end

local function retryAsync(fn, maxAttempts)
	local attempts = 0
	local success, result
	repeat
		attempts += 1
		success, result = pcall(fn)
		if not success then
			task.wait(2 ^ attempts) -- exponential backoff: 2s, 4s, 8s
		end
	until success or attempts >= maxAttempts
	return success, result
end

-- Backfills any field missing from an older save (schema growth) without
-- ever overwriting data the player already has.
local function migrate(data)
	data._version = data._version or 1
	for key, value in DEFAULT_DATA do
		if data[key] == nil then
			data[key] = if type(value) == "table" then deepCopy(value) else value
		end
	end
	return data
end

function DataManager.loadPlayerData(player: Player)
	local key = "player_" .. player.UserId
	local success, data = retryAsync(function()
		return playerDataStore:GetAsync(key)
	end, 3)

	if success and data then
		loadedData[player.UserId] = migrate(data)
	elseif success then
		loadedData[player.UserId] = deepCopy(DEFAULT_DATA)
	else
		warn("[DataManager] Failed to load data for", player.Name, "- using defaults")
		loadedData[player.UserId] = deepCopy(DEFAULT_DATA)
	end

	return loadedData[player.UserId]
end

function DataManager.savePlayerData(player: Player)
	local key = "player_" .. player.UserId
	local data = loadedData[player.UserId]
	if not data then
		return
	end

	local success, err = retryAsync(function()
		playerDataStore:SetAsync(key, data)
	end, 3)

	if not success then
		warn("[DataManager] Failed to save data for", player.Name, ":", err)
	end
end

function DataManager.releasePlayerData(player: Player)
	loadedData[player.UserId] = nil
end

function DataManager.getData(player: Player)
	return loadedData[player.UserId]
end

return DataManager
