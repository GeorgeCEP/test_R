-- ServerStorage/Modules/ArenaSystem.lua
-- PvP-flavored but resolved against a bot opponent scaled around the
-- player's own Power (no live matchmaking infrastructure) - 3 attempts per
-- day, resetting on UTC day boundary. Real player-vs-player matchmaking is a
-- natural future upgrade once there's a reason to build queueing/ELO.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)
local PowerCalculator = require(script.Parent.PowerCalculator)

local ArenaSystem = {}

local DAILY_ATTEMPTS = 3
local ARENA_REWARD = 60

local function currentDayNumber(): number
	return math.floor(os.time() / 86400)
end

local function ensureDailyReset(data)
	local today = currentDayNumber()
	if data.arena.lastResetDay ~= today then
		data.arena.lastResetDay = today
		data.arena.rollsToday = 0
	end
end

function ArenaSystem.tryBattle(player: Player, data)
	ensureDailyReset(data)
	if data.arena.rollsToday >= DAILY_ATTEMPTS then
		return nil
	end

	data.arena.rollsToday += 1

	local playerPower = PowerCalculator.getPower(data)
	local opponentPower = playerPower * (0.85 + math.random() * 0.3)
	local won = playerPower >= opponentPower

	local result = {
		playerPower = playerPower,
		opponentPower = opponentPower,
		won = won,
		attemptsLeft = DAILY_ATTEMPTS - data.arena.rollsToday,
	}

	if won then
		data.gachaCurrency += ARENA_REWARD
		result.gachaReward = ARENA_REWARD
	end

	EconomySystem.pushState(player, data)
	return result
end

function ArenaSystem.init()
	local arenaResult = NetworkEvents.get("ArenaResult")

	NetworkEvents.get("RequestArenaBattle").OnServerEvent:Connect(function(player)
		local data = DataManager.getData(player)
		if not data then
			return
		end

		local result = ArenaSystem.tryBattle(player, data)
		if result then
			arenaResult:FireClient(player, result)
		end
	end)
end

return ArenaSystem
