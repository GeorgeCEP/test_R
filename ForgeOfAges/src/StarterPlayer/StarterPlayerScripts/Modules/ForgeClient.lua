-- StarterPlayerScripts/Modules/ForgeClient.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)

local ForgeClient = {}

function ForgeClient.init(UIManager, BackgroundSystem)
	local stateUpdated = NetworkEvents.get("StateUpdated")
	stateUpdated.OnClientEvent:Connect(function(state)
		UIManager.render(state)
		BackgroundSystem.applyAge(state.ageId)
	end)

	NetworkEvents.get("GachaResult").OnClientEvent:Connect(function(result)
		UIManager.showGachaResult(result)
	end)

	NetworkEvents.get("ArenaResult").OnClientEvent:Connect(function(result)
		UIManager.showArenaResult(result)
	end)

	NetworkEvents.get("ArenaSceneEvent").OnClientEvent:Connect(function(event)
		UIManager.onArenaSceneEvent(event)
	end)

	NetworkEvents.get("ForgeResult").OnClientEvent:Connect(function(result)
		UIManager.showForgeResult(result)
	end)

	NetworkEvents.get("CombatTick").OnClientEvent:Connect(function(tick)
		UIManager.renderCombatTick(tick)
	end)

	NetworkEvents.get("StageEvent").OnClientEvent:Connect(function(event)
		UIManager.showStageEvent(event)
	end)

	NetworkEvents.get("DungeonSceneEvent").OnClientEvent:Connect(function(event)
		UIManager.onDungeonSceneEvent(event)
	end)

	NetworkEvents.get("DungeonRunResult").OnClientEvent:Connect(function(result)
		UIManager.onDungeonRunResult(result)
	end)

	NetworkEvents.get("HatchResult").OnClientEvent:Connect(function(result)
		UIManager.showHatchResult(result)
	end)
end

return ForgeClient
