-- StarterPlayerScripts/Modules/ForgeClient.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)

local ForgeClient = {}

function ForgeClient.init(UIManager)
	local stateUpdated = NetworkEvents.get("StateUpdated")
	stateUpdated.OnClientEvent:Connect(function(state)
		UIManager.render(state)
	end)

	NetworkEvents.get("GachaResult").OnClientEvent:Connect(function(result)
		UIManager.showGachaResult(result)
	end)

	NetworkEvents.get("DungeonResult").OnClientEvent:Connect(function(result)
		UIManager.showDungeonResult(result)
	end)

	NetworkEvents.get("ArenaResult").OnClientEvent:Connect(function(result)
		UIManager.showArenaResult(result)
	end)
end

return ForgeClient
