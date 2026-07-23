-- ServerStorage/Modules/DataManager.lua
local DataStoreService = game:GetService("DataStoreService")

local DataManager = {}

local playerDataStore = DataStoreService:GetDataStore("ForgeOfAges_PlayerData_v1")
local loadedData: { [number]: any } = {}

local DEFAULT_DATA = {
	_version = 2,

	-- Economy
	ore = 0,
	prestigePoints = 0, -- permanent +2%/point global Ore & stage-damage multiplier, earned from Prestige
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

	-- Tech tree (replaces the old buildings-for-passive-income loop)
	researchPoints = 0,
	techTree = {},

	-- Stage crawl progress. Age/theme is derived from chapter, not stored
	-- separately, so there's one source of truth for "how far has this
	-- player gotten". cycle counts Endless Cycle loops once capped out.
	stageProgress = { chapter = 1, stage = 1, cycle = 0 },

	-- Forge crafting queue - persisted so an in-flight craft survives relog.
	-- Each entry: { finishAt: number (os.time), ageId: number }. Position in
	-- the array is the display slot number.
	forgeJobs = {},

	-- Arena
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
