-- ServerStorage/Modules/StageSystem.lua
-- Replaces the old DungeonSystem (instant win/loss stat-check) and AgeSystem
-- (manual "Age Up" purchase). The player's avatar now auto-battles
-- continuously: walk to the wave marker, trade damage with the wave every
-- tick, walk on once it's dead, repeat for the next stage. There is no
-- RemoteEvent to "enter" a stage - it's an idler, this just runs.
--
-- Deliberately a deterministic DPS race, not an RNG stat-check: whoever's
-- winning the race wins faster, but a losing player is never permanently
-- stuck - they get "downed" (a short timeout) and recover instead of
-- failing outright. This sidesteps the exact bug the README flagged in the
-- old dungeon model (a zero-Power player stuck at a 5% floor indefinitely).
--
-- Each enemy in a wave has its own HP now (not a shared pool): the wave's
-- total HP is split across `enemyCount` enemies with a little variance, and
-- only the front-most one (index 1) is ever being damaged at a time - when
-- it dies it's removed permanently and the next one becomes the target.
-- Incoming damage to the player stays the wave's flat `waveDPS` scalar
-- (that's a "how hard is this wave overall" number, not per-enemy), it just
-- gets attributed to whichever enemy is still standing after the player's
-- hit for animation purposes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StageDefinitions = require(ReplicatedStorage.Modules.StageDefinitions)
local AgeDefinitions = require(ReplicatedStorage.Modules.AgeDefinitions)
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)
local PowerCalculator = require(script.Parent.PowerCalculator)
local TechTreeSystem = require(script.Parent.TechTreeSystem)
local LaneSystem = require(script.Parent.LaneSystem)

local StageSystem = {}

local COMBAT_TICK = 1 -- seconds
local DOWN_RECOVERY_SECONDS = 3
local ADVANCE_WALK_SECONDS = 1.2
local ENEMY_HP_VARIANCE = 0.15 -- +/- 15% per enemy, just for visual texture

type EnemyState = { hp: number, maxHp: number }

-- Runtime-only combat state, keyed by UserId - not persisted. Rebuilt fresh
-- (full HP, wave respawned) on join, same spirit as ForgeSystem's tap-cooldown table.
type RunState = {
	wave: any?, -- current StageDefinitions stage info, nil while "advancing"
	enemies: { EnemyState }, -- enemies[1] is always the current target
	stageHP: number,
	stageMaxHP: number,
	downedUntil: number?,
	advancing: boolean,
	lastAgeId: number?,
}

local runStates: { [number]: RunState } = {}

local combatTick = NetworkEvents.get("CombatTick")
local stageEvent = NetworkEvents.get("StageEvent")

local function applyLaneTheme(player: Player, data, runState: RunState)
	local ageId = EconomySystem.getAgeId(data)
	if runState.lastAgeId ~= ageId then
		runState.lastAgeId = ageId
		LaneSystem.setLaneTheme(player, AgeDefinitions.get(ageId).environment.ambient)
	end
end

local function buildEnemies(info): { EnemyState }
	local enemies = {}
	local baseShare = info.waveMaxHP / info.enemyCount
	for _ = 1, info.enemyCount do
		local variance = (1 - ENEMY_HP_VARIANCE) + math.random() * (ENEMY_HP_VARIANCE * 2)
		local maxHp = baseShare * variance
		table.insert(enemies, { hp = maxHp, maxHp = maxHp })
	end
	return enemies
end

local function startWave(player: Player, data, runState: RunState)
	local progress = data.stageProgress
	local info = StageDefinitions.getStageInfo(progress.chapter, progress.stage, progress.cycle)

	runState.wave = info
	runState.enemies = buildEnemies(info)
	runState.advancing = false

	applyLaneTheme(player, data, runState)
	LaneSystem.spawnWave(player, info)
	stageEvent:FireClient(player, { kind = "WaveStart", label = info.label, zoneName = info.zoneName })
end

local function advanceProgress(data)
	local progress = data.stageProgress
	local maxChapter = StageDefinitions.getMaxChapterUnlocked(data.prestigeCount)

	if progress.stage < StageDefinitions.STAGES_PER_CHAPTER then
		progress.stage += 1
		return "Stage"
	elseif progress.chapter < maxChapter then
		progress.chapter += 1
		progress.stage = 1
		return "Chapter"
	else
		progress.stage = 1
		progress.cycle += 1
		return "Cycle"
	end
end

-- Stage clears no longer grant Ore (see StageDefinitions/EconomySystem) -
-- only Research Points and a trickle of Gacha Currency.
local function grantClearRewards(data, info)
	local researchMultiplier = 1 + TechTreeSystem.getBonus(data, "researchPercent") / 100
	local researchGain = info.researchReward * researchMultiplier

	data.researchPoints += researchGain
	data.gachaCurrency += info.gachaReward

	return researchGain
end

local function onWaveCleared(player: Player, data, runState: RunState)
	local info = runState.wave
	local researchGain = grantClearRewards(data, info)

	runState.advancing = true
	runState.wave = nil
	LaneSystem.popText(player, "Wave cleared!", Color3.fromRGB(255, 220, 120), true)
	LaneSystem.clearWave(player)

	local marker = LaneSystem.getMarkerPosition(player)
	if marker then
		LaneSystem.walkTo(player, marker + Vector3.new(6, 0, 0))
	end

	local advanceKind = advanceProgress(data)
	EconomySystem.pushState(player, data)

	stageEvent:FireClient(player, {
		kind = "WaveCleared",
		label = info.label,
		researchGain = researchGain,
		gachaGain = info.gachaReward,
		advanceKind = advanceKind,
		atPrestigeCap = advanceKind == "Cycle",
	})

	task.delay(ADVANCE_WALK_SECONDS, function()
		if not Players:GetPlayerByUserId(player.UserId) then
			return
		end
		startWave(player, data, runState)
	end)
end

local function tickPlayer(player: Player, data, runState: RunState)
	if runState.advancing then
		return
	end
	if not runState.wave then
		startWave(player, data, runState)
		return
	end

	local now = os.time()
	if runState.downedUntil then
		if now < runState.downedUntil then
			LaneSystem.setPlayerHPBar(player, 0, true)
			return
		end
		runState.downedUntil = nil
		runState.stageHP = runState.stageMaxHP * 0.5
	end

	local combatant = PowerCalculator.getCombatant(data)
	runState.stageMaxHP = combatant.maxHP

	-- Player hits the front-most alive enemy.
	local front = runState.enemies[1]
	if front then
		local damage = combatant.dps * COMBAT_TICK
		front.hp = math.max(0, front.hp - damage)

		LaneSystem.playerLunge(player)
		LaneSystem.popEnemyDamage(player, 1, damage)
		LaneSystem.setEnemyHPFraction(player, 1, front.hp / front.maxHp)

		if front.hp <= 0 then
			LaneSystem.killEnemy(player, 1)
			table.remove(runState.enemies, 1)
		else
			LaneSystem.enemyLunge(player, 1)
		end
	end

	-- Incoming damage: the wave's flat DPS, same as the old shared-pool
	-- version - attributed to "whichever enemy is still standing" above,
	-- not modeled per-enemy, since it represents the wave's overall threat.
	runState.stageHP =
		math.min(runState.stageMaxHP, runState.stageHP - runState.wave.waveDPS * COMBAT_TICK + combatant.regenPerSecond * COMBAT_TICK)

	if #runState.enemies > 0 then
		LaneSystem.popPlayerDamage(player, runState.wave.waveDPS * COMBAT_TICK)
	end

	if runState.stageHP <= 0 then
		runState.stageHP = 0
		runState.downedUntil = now + DOWN_RECOVERY_SECONDS
		LaneSystem.popText(player, "Downed!", Color3.fromRGB(220, 80, 80), false)
	end

	LaneSystem.setPlayerHPBar(player, runState.stageHP / runState.stageMaxHP, runState.downedUntil ~= nil)

	local frontAfter = runState.enemies[1]
	combatTick:FireClient(player, {
		label = runState.wave.label,
		zoneName = runState.wave.zoneName,
		enemyHP = if frontAfter then frontAfter.hp else 0,
		enemyMaxHP = if frontAfter then frontAfter.maxHp else 1,
		enemiesLeft = #runState.enemies,
		totalEnemies = runState.wave.enemyCount,
		playerHP = runState.stageHP,
		playerMaxHP = runState.stageMaxHP,
		downed = runState.downedUntil ~= nil,
	})

	if #runState.enemies == 0 then
		onWaveCleared(player, data, runState)
	end
end

local function initRunState(player: Player, data): RunState
	local combatant = PowerCalculator.getCombatant(data)
	local runState: RunState = {
		wave = nil,
		enemies = {},
		stageHP = combatant.maxHP,
		stageMaxHP = combatant.maxHP,
		downedUntil = nil,
		advancing = false,
		lastAgeId = nil,
	}
	runStates[player.UserId] = runState
	return runState
end

function StageSystem.init()
	-- Run state inits lazily on the first tick after DataManager has the
	-- player's data loaded (join order between systems isn't guaranteed, so
	-- this is deliberately not driven off PlayerAdded).
	Players.PlayerRemoving:Connect(function(player)
		runStates[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(COMBAT_TICK)
			for _, player in Players:GetPlayers() do
				local data = DataManager.getData(player)
				if data then
					local runState = runStates[player.UserId] or initRunState(player, data)
					tickPlayer(player, data, runState)
				end
			end
		end
	end)
end

return StageSystem
