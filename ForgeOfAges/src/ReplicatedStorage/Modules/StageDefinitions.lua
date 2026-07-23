-- ReplicatedStorage/Modules/StageDefinitions.lua
-- The stage-crawl ladder: 10 chapters x 15 stages ("1-1" .. "10-15"), each
-- chapter themed to one of AgeDefinitions' 9 ages (chapter 10 reuses Hell's
-- theme as the "true endgame" chapter - no 10th age asset needed). Numbers
-- below are illustrative placeholders, same as every other balance table in
-- this project - they need tuning once real gear/stat totals are observed.
--
-- Combat is a deterministic DPS race, not a win/loss RNG check: the player
-- always eventually clears a wave given enough time, they just get "downed"
-- and recover if outmatched rather than hitting a permanent wall. See
-- StageSystem.lua.

local StageDefinitions = {}

StageDefinitions.TOTAL_CHAPTERS = 10
StageDefinitions.STAGES_PER_CHAPTER = 15
StageDefinitions.STAGE_GROWTH = 1.15 -- per stage within a chapter
StageDefinitions.CYCLE_GROWTH = 1.08 -- per Endless Cycle once capped out

-- Mirrors the old per-age Prestige cap exactly, just renumbered into
-- chapter-space: chapters 1-6 (through Digital Age) are open from the
-- start, and chapters 7-10 (Alien/Heaven/Hell/the true endgame) unlock one
-- Prestige at a time.
local PRESTIGE_BASE_CAP = 6

function StageDefinitions.getMaxChapterUnlocked(prestigeCount: number): number
	return math.min(StageDefinitions.TOTAL_CHAPTERS, PRESTIGE_BASE_CAP + prestigeCount)
end

-- One entry per chapter - base "difficulty power" for stage 1 of that chapter.
-- Chapters 1-9 mirror the old per-age dungeon numbers (~15x jump per chapter);
-- chapter 10 continues the same curve as the post-Hell "true endgame".
StageDefinitions.CHAPTER_BASE_DIFFICULTY = {
	40,
	600,
	9000,
	140000,
	2200000,
	34000000,
	520000000,
	8000000000,
	120000000000,
	1800000000000,
}

StageDefinitions.CHAPTER_FLAVOR = {
	{ zone = "Sabertooth Den", enemy = "Sabertooth" },
	{ zone = "Bandit Stronghold", enemy = "Bandit Raider" },
	{ zone = "Smog-Choked Mines", enemy = "Mine Wretch" },
	{ zone = "Rogue Fortress", enemy = "Rogue Trooper" },
	{ zone = "Derelict Station", enemy = "Salvage Drone" },
	{ zone = "Corrupted Mainframe", enemy = "Rogue Process" },
	{ zone = "Xeno Hive", enemy = "Hive Drone" },
	{ zone = "Gates of Judgement", enemy = "Judged Soul" },
	{ zone = "The Abyssal Throne", enemy = "Abyssal Fiend" },
	{ zone = "The Eternal Warzone", enemy = "Deathless Legionnaire" },
}

local HP_FACTOR = 6 -- total wave HP as a multiple of "difficulty power"
local DPS_FACTOR = 0.4 -- total incoming wave DPS as a multiple of "difficulty power"
local ORE_REWARD_FACTOR = 0.02

-- Enemy count per wave ramps slowly, capped so the numeric-tick sim (and the
-- handful of dummy models LaneSystem spawns) stay cheap.
local function enemyCount(stage: number): number
	return math.min(6, 3 + math.floor((stage - 1) / 5))
end

function StageDefinitions.getLabel(chapter: number, stage: number): string
	return string.format("%d-%d", chapter, stage)
end

-- Chapters 1-9 map 1:1 to ages; chapter 10 reuses age 9 (Hell)'s theme.
function StageDefinitions.getAgeIdForChapter(chapter: number): number
	return math.min(chapter, 9)
end

function StageDefinitions.getFlavor(chapter: number)
	return StageDefinitions.CHAPTER_FLAVOR[math.clamp(chapter, 1, StageDefinitions.TOTAL_CHAPTERS)]
end

function StageDefinitions.getDifficultyPower(chapter: number, stage: number, cycle: number): number
	local base = StageDefinitions.CHAPTER_BASE_DIFFICULTY[math.clamp(chapter, 1, StageDefinitions.TOTAL_CHAPTERS)]
	local stageMultiplier = StageDefinitions.STAGE_GROWTH ^ (stage - 1)
	local cycleMultiplier = StageDefinitions.CYCLE_GROWTH ^ (cycle or 0)
	return base * stageMultiplier * cycleMultiplier
end

-- Everything needed to run/display one wave: total wave HP/DPS, enemy count,
-- and the ore/research/gacha rewards for clearing it.
function StageDefinitions.getStageInfo(chapter: number, stage: number, cycle: number)
	local difficultyPower = StageDefinitions.getDifficultyPower(chapter, stage, cycle)
	local flavor = StageDefinitions.getFlavor(chapter)
	local count = enemyCount(stage)

	return {
		chapter = chapter,
		stage = stage,
		cycle = cycle or 0,
		label = StageDefinitions.getLabel(chapter, stage),
		ageId = StageDefinitions.getAgeIdForChapter(chapter),
		zoneName = flavor.zone,
		enemyName = flavor.enemy,
		enemyCount = count,
		waveMaxHP = difficultyPower * HP_FACTOR,
		waveDPS = difficultyPower * DPS_FACTOR,
		oreReward = difficultyPower * ORE_REWARD_FACTOR,
		researchReward = chapter + math.floor((stage - 1) / 5),
		gachaReward = 5 + chapter * 2,
	}
end

return StageDefinitions
