-- ServerStorage/Modules/ForgeSystem.lua
-- The tap-to-forge interaction. Uses ClickDetector (server-side event, no
-- client-trusted RemoteEvent needed for the tap itself) with a cooldown as a
-- basic spam/exploit mitigation, per the "server is truth" rule.

local Players = game:GetService("Players")

local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)

local ForgeSystem = {}

local TAP_COOLDOWN = 0.15 -- seconds
local lastTap: { [number]: number } = {}

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

local function handleTap(player: Player)
	local now = os.clock()
	if lastTap[player.UserId] and (now - lastTap[player.UserId]) < TAP_COOLDOWN then
		return
	end
	lastTap[player.UserId] = now

	local data = DataManager.getData(player)
	if not data then
		return
	end

	local reward = EconomySystem.getTapPower(data)
	EconomySystem.addOre(data, reward)
	EconomySystem.pushState(player, data)
end

function ForgeSystem.init()
	local forge = createForgePart()
	local detector = forge:FindFirstChildOfClass("ClickDetector") :: ClickDetector
	detector.MouseClick:Connect(handleTap)

	Players.PlayerRemoving:Connect(function(player)
		lastTap[player.UserId] = nil
	end)
end

return ForgeSystem
