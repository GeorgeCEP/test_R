-- ReplicatedStorage/Modules/NetworkEvents.lua
-- Single source of truth for RemoteEvent references. The server creates them
-- on first access; clients wait for them. Never hardcode a remote lookup
-- outside this module.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAMES = {
	"StateUpdated",
	"RequestBuyBuilding",
	"RequestAgeUp",
	"RequestPrestige",
	"RequestEquipGear",
	"RequestUnequipGear",
	"RequestEquipCollectible",
	"RequestGachaRoll",
	"GachaResult",
	"RequestEnterDungeon",
	"DungeonResult",
	"RequestArenaBattle",
	"ArenaResult",
}

local NetworkEvents = {}

local remotesFolder: Folder? = nil

local function ensureFolder(): Folder
	if remotesFolder then
		return remotesFolder
	end

	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		local folder: Folder
		if existing then
			folder = existing :: Folder
		else
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end

		for _, name in REMOTE_NAMES do
			if not folder:FindFirstChild(name) then
				local remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = folder
			end
		end

		remotesFolder = folder
	else
		local folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
		for _, name in REMOTE_NAMES do
			folder:WaitForChild(name)
		end
		remotesFolder = folder
	end

	return remotesFolder :: Folder
end

function NetworkEvents.get(name: string): RemoteEvent
	local folder = ensureFolder()
	return folder:WaitForChild(name) :: RemoteEvent
end

return NetworkEvents
