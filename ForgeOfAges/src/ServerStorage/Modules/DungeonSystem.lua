-- ServerStorage/Modules/DungeonSystem.lua
-- A dungeon run is a short, separate combat scene from the main stage crawl
-- (StageSystem) - entering one pushes a "scene" event sequence to the client
-- (Start -> Tick* -> WaveCleared* -> Complete) that UIManager uses to switch
-- the whole screen into a full-screen dungeon view instead of resolving
-- inline. Deliberately UI-only (no LaneSystem/3D dummies): the player's
-- avatar and lane are already busy running the main stage crawl, and
-- spinning up real 3D geometry for a second simultaneous "place" needs
-- Studio-side world-building this project hasn't done yet. The combat model
-- (DPS race, downed/recover, per-tick HP) mirrors StageSystem exactly so it
-- reads the same to a player, just rendered as UI instead of a lane.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local DungeonDefinitions = require(ReplicatedStorage.Modules.DungeonDefinitions)
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)
local PowerCalculator = require(script.Parent.PowerCalculator)

local DungeonSystem = {}

local COMBAT_TICK = 1
local DOWN_RECOVERY_SECONDS = 3

type RunState = {
	dungeonId: string,
	stage: number,
	waveIndex: number,
	waveInfo: any,
	waveRemainingHP: number,
	playerHP: number,
	playerMaxHP: number,
	downedUntil: number?,
}

local runStates: { [number]: RunState } = {}

local dungeonSceneEvent = NetworkEvents.get("DungeonSceneEvent")
local dungeonRunResult = NetworkEvents.get("DungeonRunResult")

local function ensureProgress(data)
	data.dungeonProgress = data.dungeonProgress or {}
	data.dungeonCooldowns = data.dungeonCooldowns or {}
	for _, dungeonId in DungeonDefinitions.Order do
		if not data.dungeonProgress[dungeonId] then
			data.dungeonProgress[dungeonId] = { highestStage = 0, selectedStage = 1 }
		end
	end
	return data.dungeonProgress
end

function DungeonSystem.getSelectedStage(data, dungeonId: string): number
	local progress = ensureProgress(data)
	return progress[dungeonId].selectedStage
end

function DungeonSystem.trySelectStage(data, dungeonId: string, stage: number): boolean
	local progress = ensureProgress(data)
	local entry = progress[dungeonId]
	local maxSelectable = math.min(DungeonDefinitions.MAX_STAGE, entry.highestStage + 1)
	if stage < 1 or stage > maxSelectable then
		return false
	end
	entry.selectedStage = stage
	return true
end

local function startWave(player: Player, runState: RunState, combatant)
	local info = DungeonDefinitions.getWaveInfo(runState.dungeonId, runState.stage, runState.waveIndex)
	runState.waveInfo = info
	runState.waveRemainingHP = info.waveMaxHP

	dungeonSceneEvent:FireClient(player, {
		kind = if runState.waveIndex == 1 then "Start" else "WaveStart",
		dungeonId = runState.dungeonId,
		stage = runState.stage,
		waveIndex = runState.waveIndex,
		totalWaves = DungeonDefinitions.WAVES_PER_RUN,
		label = info.label,
		zoneName = info.zoneName,
		enemyName = info.enemyName,
		playerMaxHP = runState.playerMaxHP,
	})
end

local function completeRun(player: Player, data, runState: RunState)
	local progress = ensureProgress(data)
	local entry = progress[runState.dungeonId]
	local ageId = EconomySystem.getAgeId(data)
	local reward = DungeonDefinitions.getRunReward(runState.dungeonId, runState.stage, ageId)

	if reward.kind == "Ore" then
		EconomySystem.addOre(data, reward.oreAmount)
	elseif reward.kind == "Egg" then
		table.insert(data.eggs, { id = HttpService:GenerateGUID(false), rarity = reward.eggRarity })
	elseif reward.kind == "Enchantment" then
		table.insert(data.enchantments, {
			id = HttpService:GenerateGUID(false),
			rarity = reward.enchantRarity,
			statBonus = { stat = reward.statId, value = reward.statValue },
		})
	end

	local wasNewStage = runState.stage > entry.highestStage
	if wasNewStage then
		entry.highestStage = runState.stage
	end

	runStates[player.UserId] = nil
	EconomySystem.pushState(player, data)

	dungeonRunResult:FireClient(player, {
		dungeonId = runState.dungeonId,
		stage = runState.stage,
		reward = reward,
		newStageUnlocked = wasNewStage,
	})
end

local function tickRun(player: Player, data, runState: RunState)
	local now = os.time()
	if runState.downedUntil then
		if now < runState.downedUntil then
			dungeonSceneEvent:FireClient(player, {
				kind = "Tick",
				playerHP = 0,
				playerMaxHP = runState.playerMaxHP,
				enemyHP = runState.waveRemainingHP,
				enemyMaxHP = runState.waveInfo.waveMaxHP,
				downed = true,
			})
			return
		end
		runState.downedUntil = nil
		runState.playerHP = runState.playerMaxHP * 0.5
	end

	local combatant = PowerCalculator.getCombatant(data)
	runState.waveRemainingHP = math.max(0, runState.waveRemainingHP - combatant.dps * COMBAT_TICK)
	runState.playerHP = math.min(
		runState.playerMaxHP,
		runState.playerHP - runState.waveInfo.waveDPS * COMBAT_TICK + combatant.regenPerSecond * COMBAT_TICK
	)

	local downedNow = false
	if runState.playerHP <= 0 then
		runState.playerHP = 0
		runState.downedUntil = now + DOWN_RECOVERY_SECONDS
		downedNow = true
	end

	dungeonSceneEvent:FireClient(player, {
		kind = "Tick",
		playerHP = runState.playerHP,
		playerMaxHP = runState.playerMaxHP,
		enemyHP = runState.waveRemainingHP,
		enemyMaxHP = runState.waveInfo.waveMaxHP,
		downed = downedNow,
	})

	if runState.waveRemainingHP <= 0 then
		dungeonSceneEvent:FireClient(player, {
			kind = "WaveCleared",
			waveIndex = runState.waveIndex,
			totalWaves = DungeonDefinitions.WAVES_PER_RUN,
		})

		if runState.waveIndex >= DungeonDefinitions.WAVES_PER_RUN then
			completeRun(player, data, runState)
		else
			runState.waveIndex += 1
			startWave(player, runState, combatant)
		end
	end
end

function DungeonSystem.tryEnter(player: Player, data, dungeonId: string): boolean
	if runStates[player.UserId] then
		return false
	end
	if not DungeonDefinitions.get(dungeonId) then
		return false
	end

	ensureProgress(data)
	local now = os.time()
	local lastEntered = data.dungeonCooldowns[dungeonId]
	if lastEntered and (now - lastEntered) < DungeonDefinitions.COOLDOWN_SECONDS then
		return false
	end
	data.dungeonCooldowns[dungeonId] = now

	local combatant = PowerCalculator.getCombatant(data)
	local stage = DungeonSystem.getSelectedStage(data, dungeonId)

	local runState: RunState = {
		dungeonId = dungeonId,
		stage = stage,
		waveIndex = 1,
		waveInfo = nil,
		waveRemainingHP = 0,
		playerHP = combatant.maxHP,
		playerMaxHP = combatant.maxHP,
		downedUntil = nil,
	}
	runStates[player.UserId] = runState
	startWave(player, runState, combatant)
	return true
end

function DungeonSystem.init()
	NetworkEvents.get("RequestSelectDungeonStage").OnServerEvent:Connect(function(player, dungeonId, stage)
		local data = DataManager.getData(player)
		if not data or type(dungeonId) ~= "string" or type(stage) ~= "number" then
			return
		end
		if DungeonSystem.trySelectStage(data, dungeonId, stage) then
			EconomySystem.pushState(player, data)
		end
	end)

	NetworkEvents.get("RequestEnterDungeon").OnServerEvent:Connect(function(player, dungeonId)
		local data = DataManager.getData(player)
		if not data or type(dungeonId) ~= "string" then
			return
		end
		DungeonSystem.tryEnter(player, data, dungeonId)
	end)

	Players.PlayerRemoving:Connect(function(player)
		runStates[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(COMBAT_TICK)
			for _, player in Players:GetPlayers() do
				local runState = runStates[player.UserId]
				if runState then
					local data = DataManager.getData(player)
					if data then
						tickRun(player, data, runState)
					end
				end
			end
		end
	end)
end

return DungeonSystem
