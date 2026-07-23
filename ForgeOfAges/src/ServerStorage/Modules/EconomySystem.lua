-- ServerStorage/Modules/EconomySystem.lua
-- Ore's only passive source now is the base per-age trickle plus tech tree
-- levels (buildings are gone) - everything else (stage clears, the Forge)
-- is a discrete grant/spend handled by the systems that own those actions.
-- This module still owns the shared pushState broadcast every other system
-- calls after it mutates player data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local AgeDefinitions = require(ReplicatedStorage.Modules.AgeDefinitions)
local StageDefinitions = require(ReplicatedStorage.Modules.StageDefinitions)
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

	local forgeJobs = {}
	for index, job in data.forgeJobs do
		table.insert(forgeJobs, {
			slot = index,
			secondsLeft = math.max(0, job.finishAt - os.time()),
		})
	end

	stateUpdated:FireClient(player, {
		ore = data.ore,
		ageId = ageId,
		ageName = age.name,
		resourceLabel = age.resourceLabel,
		idlePerSecond = EconomySystem.getIdleOutputPerSecond(data),

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
		equippedPetIds = data.equippedPetIds,
		skills = data.skills,
		equippedSkillIds = data.equippedSkillIds,

		researchPoints = data.researchPoints,
		techTree = techTreeLevels,
		forgeSlotCount = TechTreeSystem.getForgeSlotCount(data),
		forgeJobs = forgeJobs,

		arenaAttemptsLeft = arenaAttemptsLeft,
	})
end

function EconomySystem.init()
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
