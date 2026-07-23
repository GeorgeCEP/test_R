-- ServerStorage/Modules/DungeonSystem.lua
-- Auto-battle stat-check simulation: no manual combat, the server compares
-- the player's Power against the current age's dungeon difficulty and
-- resolves win/loss instantly. Wins grant gachaCurrency and a chance at gear.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DungeonDefinitions = require(ReplicatedStorage.Modules.DungeonDefinitions)
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)
local PowerCalculator = require(script.Parent.PowerCalculator)
local GearSystem = require(script.Parent.GearSystem)

local DungeonSystem = {}

local DUNGEON_COOLDOWN = 20 -- seconds

function DungeonSystem.tryEnter(player: Player, data)
	local now = os.time()
	if data.dungeonCooldownEnd and now < data.dungeonCooldownEnd then
		return nil
	end

	local dungeon = DungeonDefinitions.get(data.age)
	if not dungeon then
		return nil
	end

	data.dungeonCooldownEnd = now + DUNGEON_COOLDOWN

	local power = PowerCalculator.getPower(data)
	local winChance = math.clamp(0.5 + (power - dungeon.difficultyPower) / dungeon.difficultyPower * 0.5, 0.05, 0.95)
	local won = math.random() < winChance

	local result = { dungeonName = dungeon.name, won = won, power = power, difficultyPower = dungeon.difficultyPower }

	if won then
		data.gachaCurrency += dungeon.gachaReward
		result.gachaReward = dungeon.gachaReward

		if math.random() < dungeon.gearDropChance then
			local item = GearSystem.rollGear(data.age)
			table.insert(data.gear, item)
			result.gearDropped = item
		end
	end

	EconomySystem.pushState(player, data)
	return result
end

function DungeonSystem.init()
	local dungeonResult = NetworkEvents.get("DungeonResult")

	NetworkEvents.get("RequestEnterDungeon").OnServerEvent:Connect(function(player)
		local data = DataManager.getData(player)
		if not data then
			return
		end

		local result = DungeonSystem.tryEnter(player, data)
		if result then
			dungeonResult:FireClient(player, result)
		end
	end)
end

return DungeonSystem
