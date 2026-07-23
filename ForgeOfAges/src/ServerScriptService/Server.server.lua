-- ServerScriptService/Server.server.lua
-- Bootstrap only. All logic lives in ServerStorage/Modules ModuleScripts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

require(ReplicatedStorage.Modules.NetworkEvents).get("StateUpdated") -- ensure Remotes exist before anything else

local DataManager = require(ServerStorage.Modules.DataManager)
local EconomySystem = require(ServerStorage.Modules.EconomySystem)
local ForgeSystem = require(ServerStorage.Modules.ForgeSystem)
local AgeSystem = require(ServerStorage.Modules.AgeSystem)
local PrestigeSystem = require(ServerStorage.Modules.PrestigeSystem)
local GearSystem = require(ServerStorage.Modules.GearSystem)
local GachaSystem = require(ServerStorage.Modules.GachaSystem)
local LoadoutSystem = require(ServerStorage.Modules.LoadoutSystem)
local DungeonSystem = require(ServerStorage.Modules.DungeonSystem)
local ArenaSystem = require(ServerStorage.Modules.ArenaSystem)

EconomySystem.init()
ForgeSystem.init()
AgeSystem.init()
PrestigeSystem.init()
GearSystem.init()
GachaSystem.init()
LoadoutSystem.init()
DungeonSystem.init()
ArenaSystem.init()

Players.PlayerAdded:Connect(function(player)
	local data = DataManager.loadPlayerData(player)
	EconomySystem.pushState(player, data)
end)

Players.PlayerRemoving:Connect(function(player)
	DataManager.savePlayerData(player)
	DataManager.releasePlayerData(player)
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		DataManager.savePlayerData(player)
	end
end)
