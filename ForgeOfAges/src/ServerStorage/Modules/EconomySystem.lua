-- ServerStorage/Modules/EconomySystem.lua
-- Ore comes from three places now: the base per-age passive trickle (+ Tech
-- Tree levels), the hourly claim below, and Dungeon runs (DungeonSystem) -
-- stage clears no longer grant Ore at all (see StageDefinitions). Coins are
-- a separate currency from selling gear (GearSystem.sell), spent only on
-- Forge Level. This module still owns the shared pushState broadcast every
-- other system calls after it mutates player data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local AgeDefinitions = require(ReplicatedStorage.Modules.AgeDefinitions)
local StageDefinitions = require(ReplicatedStorage.Modules.StageDefinitions)
local DungeonDefinitions = require(ReplicatedStorage.Modules.DungeonDefinitions)
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local PowerCalculator = require(script.Parent.PowerCalculator)
local TechTreeSystem = require(script.Parent.TechTreeSystem)

local EconomySystem = {}

local IDLE_TICK_SECONDS = 1
local AUTOSAVE_SECONDS = 60
local PRESTIGE_MULTIPLIER_STEP = 0.02 -- +2% global Ore output per Prestige Point
local ARENA_DAILY_ATTEMPTS = 3
local BASE_PASSIVE_ORE = 0.2 -- flat, before age scale/tech bonuses/prestige multiplier
local ORE_CLAIM_INTERVAL_SECONDS = 3600
local BASE_ORE_CLAIM = 50 -- flat, before age scale/prestige multiplier - a meaningful chunk vs. the passive trickle

local stateUpdated = NetworkEvents.get("StateUpdated")

function EconomySystem.getAgeId(data): number
	return StageDefinitions.getAgeIdForChapter(data.stageProgress.chapter)
end

function EconomySystem.getGlobalOreMultiplier(data): number
	return 1 + (data.prestigePoints * PRESTIGE_MULTIPLIER_STEP)
end

function EconomySystem.getIdleOutputPerSecond(data): number
	local ageId = EconomySystem.getAgeId(data)
	local base = BASE_PASSIVE_ORE * AgeDefinitions.getScale(ageId)
	local techMultiplier = 1 + TechTreeSystem.getBonus(data, "passiveOrePercent") / 100
	return base * techMultiplier * EconomySystem.getGlobalOreMultiplier(data)
end

function EconomySystem.addOre(data, amount: number)
	data.ore += amount
	data.totalOreEarned += amount
end

function EconomySystem.getOreClaimAmount(data): number
	local ageId = EconomySystem.getAgeId(data)
	return BASE_ORE_CLAIM * AgeDefinitions.getScale(ageId) * EconomySystem.getGlobalOreMultiplier(data)
end

function EconomySystem.getSecondsUntilClaim(data): number
	return math.max(0, data.lastOreClaimAt + ORE_CLAIM_INTERVAL_SECONDS - os.time())
end

function EconomySystem.tryClaimHourlyOre(player: Player, data): boolean
	if EconomySystem.getSecondsUntilClaim(data) > 0 then
		return false
	end
	data.lastOreClaimAt = os.time()
	EconomySystem.addOre(data, EconomySystem.getOreClaimAmount(data))
	EconomySystem.pushState(player, data)
	return true
end

function EconomySystem.pushState(player: Player, data)
	local ageId = EconomySystem.getAgeId(data)
	local age = AgeDefinitions.get(ageId)
	local maxChapter = StageDefinitions.getMaxChapterUnlocked(data.prestigeCount)

	local today = math.floor(os.time() / 86400)
	local arenaAttemptsLeft = if data.arena.lastResetDay == today
		then math.max(0, ARENA_DAILY_ATTEMPTS - data.arena.rollsToday)
		else ARENA_DAILY_ATTEMPTS

	local combatant = PowerCalculator.getCombatant(data)

	local techTreeLevels = {}
	for nodeId, level in data.techTree do
		techTreeLevels[nodeId] = level
	end

	-- Lazy require: ForgeSystem requires EconomySystem (for getAgeId/pushState),
	-- so this can't be a top-level require without creating a cycle - same
	-- pattern TechTreeSystem.purchase already uses for the same reason.
	local ForgeSystem = require(script.Parent.ForgeSystem)

	local dungeonProgress = {}
	local dungeonCooldowns = {}
	local now = os.time()
	for _, dungeonId in DungeonDefinitions.Order do
		local entry = data.dungeonProgress and data.dungeonProgress[dungeonId]
		dungeonProgress[dungeonId] = {
			highestStage = if entry then entry.highestStage else 0,
			selectedStage = if entry then entry.selectedStage else 1,
		}
		local lastEntered = data.dungeonCooldowns and data.dungeonCooldowns[dungeonId]
		dungeonCooldowns[dungeonId] = if lastEntered
			then math.max(0, DungeonDefinitions.COOLDOWN_SECONDS - (now - lastEntered))
			else 0
	end

	stateUpdated:FireClient(player, {
		ore = data.ore,
		coins = data.coins,
		ageId = ageId,
		ageName = age.name,
		resourceLabel = age.resourceLabel,
		idlePerSecond = EconomySystem.getIdleOutputPerSecond(data),
		secondsUntilClaim = EconomySystem.getSecondsUntilClaim(data),
		oreClaimAmount = EconomySystem.getOreClaimAmount(data),

		stageChapter = data.stageProgress.chapter,
		stageStage = data.stageProgress.stage,
		stageCycle = data.stageProgress.cycle,
		stageLabel = StageDefinitions.getLabel(data.stageProgress.chapter, data.stageProgress.stage),
		atPrestigeCap = data.stageProgress.chapter >= maxChapter,

		prestigePoints = data.prestigePoints,
		prestigeCount = data.prestigeCount,

		gachaCurrency = data.gachaCurrency,
		power = PowerCalculator.getPower(data),
		combatDps = combatant.dps,
		combatMaxHP = combatant.maxHP,
		gear = data.gear,
		equippedGear = data.equippedGear,
		pets = data.pets,
		eggs = data.eggs,
		enchantments = data.enchantments,
		skills = data.skills,
		equippedSkillIds = data.equippedSkillIds,

		researchPoints = data.researchPoints,
		techTree = techTreeLevels,
		forgeSlotCount = TechTreeSystem.getForgeSlotCount(data),
		forgeLevel = data.forgeLevel,
		forgeCraftCost = ForgeSystem.getCraftCost(data),
		forgeUpgradeCost = ForgeSystem.getUpgradeCost(data),

		arenaAttemptsLeft = arenaAttemptsLeft,
		arenaRating = data.arena.rating or 1000,

		dungeonProgress = dungeonProgress,
		dungeonCooldownsRemaining = dungeonCooldowns,
	})
end

function EconomySystem.init()
	NetworkEvents.get("RequestClaimHourlyOre").OnServerEvent:Connect(function(player)
		local data = DataManager.getData(player)
		if data then
			EconomySystem.tryClaimHourlyOre(player, data)
		end
	end)

	-- Passive Ore tick
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
end

return EconomySystem
