-- ServerStorage/Modules/ForgeSystem.lua
-- The Forge is now an Ore *sink*, not a tap: spend Ore to start a timed
-- craft job that produces a rolled gear item (GearSystem.rollGear) when it
-- finishes. Clicking the physical Forge part in the world and the UI's
-- Forge button both call the same tryStartCraft - same "server is truth"
-- pattern the old tap-for-Ore version used. A tech tree node
-- ("forge_slot_2"/"forge_slot_3") raises how many jobs can run at once.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AgeDefinitions = require(ReplicatedStorage.Modules.AgeDefinitions)
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)
local GearSystem = require(script.Parent.GearSystem)
local TechTreeSystem = require(script.Parent.TechTreeSystem)

local ForgeSystem = {}

local CLICK_COOLDOWN = 0.3
local CRAFT_BASE_COST = 40
local CRAFT_BASE_TIME = 8 -- seconds
local CRAFT_MIN_TIME = 2
local JOB_RESOLVE_TICK = 1

local lastClick: { [number]: number } = {}
local forgeResult = NetworkEvents.get("ForgeResult")

local function createForgePart(): BasePart
	local existing = workspace:FindFirstChild("Forge")
	if existing then
		return existing :: BasePart
	end

	local part = Instance.new("Part")
	part.Name = "Forge"
	part.Anchored = true
	part.Size = Vector3.new(6, 4, 6)
	part.Position = Vector3.new(0, 2, 0)
	part.BrickColor = BrickColor.new("Dark stone grey")
	part.Material = Enum.Material.Slate
	part.Parent = workspace

	local detector = Instance.new("ClickDetector")
	detector.MaxActivationDistance = 15
	detector.Parent = part

	return part
end

function ForgeSystem.getCraftCost(ageId: number): number
	return CRAFT_BASE_COST * AgeDefinitions.getScale(ageId)
end

function ForgeSystem.getCraftTime(data): number
	local speedBonus = TechTreeSystem.getBonus(data, "forgeSpeedPercent")
	return math.max(CRAFT_MIN_TIME, CRAFT_BASE_TIME * (1 - speedBonus / 100))
end

function ForgeSystem.tryStartCraft(player: Player, data): boolean
	local slotCount = TechTreeSystem.getForgeSlotCount(data)
	if #data.forgeJobs >= slotCount then
		return false
	end

	local ageId = EconomySystem.getAgeId(data)
	local cost = ForgeSystem.getCraftCost(ageId)
	if data.ore < cost then
		return false
	end

	data.ore -= cost
	table.insert(data.forgeJobs, {
		finishAt = os.time() + ForgeSystem.getCraftTime(data),
		ageId = ageId,
	})

	EconomySystem.pushState(player, data)
	return true
end

local function resolveFinishedJobs(player: Player, data)
	local now = os.time()
	local index = 1
	local resolvedAny = false

	while index <= #data.forgeJobs do
		local job = data.forgeJobs[index]
		if now >= job.finishAt then
			table.remove(data.forgeJobs, index)
			local item = GearSystem.rollGear(job.ageId)
			table.insert(data.gear, item)
			forgeResult:FireClient(player, { item = item })
			resolvedAny = true
		else
			index += 1
		end
	end

	if resolvedAny then
		EconomySystem.pushState(player, data)
	end
end

local function handleClick(player: Player)
	local now = os.clock()
	if lastClick[player.UserId] and (now - lastClick[player.UserId]) < CLICK_COOLDOWN then
		return
	end
	lastClick[player.UserId] = now

	local data = DataManager.getData(player)
	if not data then
		return
	end
	ForgeSystem.tryStartCraft(player, data)
end

function ForgeSystem.init()
	local forge = createForgePart()
	local detector = forge:FindFirstChildOfClass("ClickDetector") :: ClickDetector
	detector.MouseClick:Connect(handleClick)

	NetworkEvents.get("RequestForgeCraft").OnServerEvent:Connect(function(player)
		local data = DataManager.getData(player)
		if not data then
			return
		end
		ForgeSystem.tryStartCraft(player, data)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastClick[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(JOB_RESOLVE_TICK)
			for _, player in Players:GetPlayers() do
				local data = DataManager.getData(player)
				if data then
					resolveFinishedJobs(player, data)
				end
			end
		end
	end)
end

return ForgeSystem
