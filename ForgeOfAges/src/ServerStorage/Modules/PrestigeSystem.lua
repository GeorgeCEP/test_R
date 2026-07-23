-- ServerStorage/Modules/PrestigeSystem.lua
-- Eligibility is now "stuck at your max-unlocked chapter" (StageSystem loops
-- you through Endless Cycle there instead of hard-blocking) rather than
-- "at the age cap after buying every building". Resets Ore and stage/chapter
-- progress only - gear, pets, skills, the tech tree, and Research Points are
-- permanent and survive every Prestige, same spirit as the old
-- gear/pets/skills persistence, just extended to the tech tree.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StageDefinitions = require(ReplicatedStorage.Modules.StageDefinitions)
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)

local PrestigeSystem = {}

local PRESTIGE_GACHA_BONUS = 200

function PrestigeSystem.isEligible(data): boolean
	local maxChapter = StageDefinitions.getMaxChapterUnlocked(data.prestigeCount)
	return data.stageProgress.chapter >= maxChapter
end

function PrestigeSystem.previewPrestigePoints(data): number
	return math.floor(math.sqrt(data.totalOreEarned / 1e6))
end

function PrestigeSystem.tryPrestige(player: Player, data): boolean
	if not PrestigeSystem.isEligible(data) then
		return false
	end

	local awarded = PrestigeSystem.previewPrestigePoints(data)
	if awarded <= 0 then
		return false
	end

	data.prestigePoints += awarded
	data.gachaCurrency += PRESTIGE_GACHA_BONUS
	data.prestigeCount += 1

	data.ore = 0
	data.totalOreEarned = 0
	data.stageProgress = { chapter = 1, stage = 1, cycle = 0 }

	EconomySystem.pushState(player, data)
	return true
end

function PrestigeSystem.init()
	NetworkEvents.get("RequestPrestige").OnServerEvent:Connect(function(player)
		local data = DataManager.getData(player)
		if not data then
			return
		end
		PrestigeSystem.tryPrestige(player, data)
	end)
end

return PrestigeSystem
