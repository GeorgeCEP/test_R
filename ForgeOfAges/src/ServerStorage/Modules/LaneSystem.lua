-- ServerStorage/Modules/LaneSystem.lua
-- Pure presentation for the stage crawl: gives each player a private lane in
-- Workspace (so many players can auto-battle side by side without walking
-- through each other), walks their real avatar between an origin and an
-- encounter marker via Humanoid:MoveTo, and spawns simple non-physical dummy
-- models with billboard HP bars for the current wave. StageSystem owns all
-- the actual numbers (HP/DPS/timing) and just tells LaneSystem what to show.
--
-- Enemy "models" are plain anchored parts, not rigged Humanoid NPCs - there's
-- no hit detection here, combat is resolved numerically by StageSystem, so a
-- full rig would only add asset-ID risk (this project has never been opened
-- in Studio - see README) for zero gameplay benefit.

local Players = game:GetService("Players")

local LaneSystem = {}

local LANE_SPACING = 40
local WALK_FORWARD_DISTANCE = 20 -- origin -> encounter marker
local LANE_FLOOR_LENGTH = 30

local lanesFolder: Folder? = nil
local laneIndexByUserId: { [number]: number } = {}
local freeLaneIndices: { number } = {}
local nextLaneIndex = 1

local waveHandles: { [number]: any } = {} -- userId -> { dummies: {Model}, totalEnemies: number }
local playerBillboards: { [number]: BillboardGui } = {}

local function ensureLanesFolder(): Folder
	if lanesFolder then
		return lanesFolder
	end
	local existing = workspace:FindFirstChild("Lanes")
	if existing then
		lanesFolder = existing :: Folder
	else
		local folder = Instance.new("Folder")
		folder.Name = "Lanes"
		folder.Parent = workspace
		lanesFolder = folder
	end
	return lanesFolder :: Folder
end

local function laneOrigin(laneIndex: number): Vector3
	return Vector3.new(0, 3, laneIndex * LANE_SPACING)
end

local function markerPosition(laneIndex: number): Vector3
	return laneOrigin(laneIndex) + Vector3.new(WALK_FORWARD_DISTANCE, 0, 0)
end

local function buildLaneFloor(laneIndex: number)
	local folder = ensureLanesFolder()
	local name = "Lane" .. laneIndex
	if folder:FindFirstChild(name) then
		return
	end

	local floor = Instance.new("Part")
	floor.Name = name
	floor.Anchored = true
	floor.CanCollide = true
	floor.Size = Vector3.new(WALK_FORWARD_DISTANCE + LANE_FLOOR_LENGTH, 1, LANE_SPACING - 4)
	floor.Position = laneOrigin(laneIndex) + Vector3.new(WALK_FORWARD_DISTANCE / 2, -3.5, 0)
	floor.Material = Enum.Material.Rock
	floor.Color = Color3.fromRGB(120, 105, 85)
	floor.Parent = folder
end

local function getLaneIndex(player: Player): number?
	return laneIndexByUserId[player.UserId]
end

function LaneSystem.getOriginPosition(player: Player): Vector3?
	local index = getLaneIndex(player)
	return if index then laneOrigin(index) else nil
end

function LaneSystem.getMarkerPosition(player: Player): Vector3?
	local index = getLaneIndex(player)
	return if index then markerPosition(index) else nil
end

function LaneSystem.walkTo(player: Player, position: Vector3)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:MoveTo(position)
	end
end

-- Cosmetic-only: tints the lane floor toward the current age's ambient color.
function LaneSystem.setLaneTheme(player: Player, ambientColor: Color3)
	local index = getLaneIndex(player)
	if not index then
		return
	end
	local floor = ensureLanesFolder():FindFirstChild("Lane" .. index) :: BasePart?
	if floor then
		floor.Color = ambientColor
	end
end

local function newBillboardBar(parent: Instance, size: UDim2, offset: Vector3, name: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = name
	billboard.Size = size
	billboard.StudsOffset = offset
	billboard.AlwaysOnTop = true
	billboard.Parent = parent

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.new(1, 0, 1, 0)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	fill.BorderSizePixel = 0
	fill.Parent = back

	return billboard
end

function LaneSystem.spawnWave(player: Player, stageInfo)
	LaneSystem.clearWave(player)

	local index = getLaneIndex(player)
	if not index then
		return
	end

	local folder = ensureLanesFolder()
	local marker = markerPosition(index)
	local dummies = {}

	for i = 1, stageInfo.enemyCount do
		local model = Instance.new("Model")
		model.Name = stageInfo.enemyName

		local torso = Instance.new("Part")
		torso.Name = "Torso"
		torso.Anchored = true
		torso.CanCollide = false
		torso.Size = Vector3.new(2, 3, 1)
		torso.Color = Color3.fromRGB(150, 40, 40)
		torso.Material = Enum.Material.SmoothPlastic
		local spread = (i - 1) - (stageInfo.enemyCount - 1) / 2
		torso.Position = marker + Vector3.new(3, 1.5, spread * 2.5)
		torso.Parent = model

		model.PrimaryPart = torso
		newBillboardBar(torso, UDim2.new(3, 0, 0.4, 0), Vector3.new(0, 2.2, 0), "HpBar")
		model.Parent = folder
		table.insert(dummies, model)
	end

	waveHandles[player.UserId] = { dummies = dummies, totalEnemies = stageInfo.enemyCount }
	LaneSystem.walkTo(player, marker)
end

-- fraction is remaining wave HP / max wave HP; destroys dummies one at a time
-- as the fraction crosses each enemy's share, so the wave visibly thins out.
function LaneSystem.setWaveHPFraction(player: Player, fraction: number)
	local handle = waveHandles[player.UserId]
	if not handle then
		return
	end

	local aliveTarget = math.max(0, math.ceil(fraction * handle.totalEnemies))
	while #handle.dummies > aliveTarget do
		local dead = table.remove(handle.dummies)
		if dead then
			dead:Destroy()
		end
	end

	if #handle.dummies > 0 then
		local front = handle.dummies[1]
		local torso = front and front.PrimaryPart
		local bar = torso and torso:FindFirstChild("HpBar")
		local fill = bar and bar.Back and bar.Back:FindFirstChild("Fill")
		if fill then
			-- Front dummy's own bar reflects the wave's overall remaining fraction,
			-- which is a fine approximation for a simple numeric-only sim.
			fill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
		end
	end
end

function LaneSystem.clearWave(player: Player)
	local handle = waveHandles[player.UserId]
	if not handle then
		return
	end
	for _, model in handle.dummies do
		model:Destroy()
	end
	waveHandles[player.UserId] = nil
end

local function ensurePlayerBillboard(player: Player): BillboardGui?
	local character = player.Character
	if not character then
		return nil
	end
	local head = character:FindFirstChild("Head")
	if not head then
		return nil
	end

	local existing = playerBillboards[player.UserId]
	if existing and existing.Parent == head then
		return existing
	end

	local billboard = newBillboardBar(head, UDim2.new(3, 0, 0.4, 0), Vector3.new(0, 2.5, 0), "StageHpBar")
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, 0, 1, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextSize = 10
	statusLabel.TextColor3 = Color3.new(1, 1, 1)
	statusLabel.Text = ""
	statusLabel.Parent = billboard

	playerBillboards[player.UserId] = billboard
	return billboard
end

function LaneSystem.setPlayerHPBar(player: Player, fraction: number, downed: boolean)
	local billboard = ensurePlayerBillboard(player)
	if not billboard then
		return
	end
	local fill = billboard.Back:FindFirstChild("Fill") :: Frame?
	if fill then
		fill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
		fill.BackgroundColor3 = if downed then Color3.fromRGB(120, 120, 120) else Color3.fromRGB(80, 190, 90)
	end
	local status = billboard:FindFirstChild("Status") :: TextLabel?
	if status then
		status.Text = if downed then "DOWNED - recovering" else ""
	end
end

function LaneSystem.popText(player: Player, text: string, color: Color3, atMarker: boolean)
	local character = player.Character
	local index = getLaneIndex(player)
	if not character or not index then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local anchorPosition = if atMarker then markerPosition(index) else (rootPart and rootPart.Position)
	if not anchorPosition then
		return
	end

	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = anchorPosition + Vector3.new(0, 3, 0)
	part.Parent = ensureLanesFolder()

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(4, 0, 1, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = color
	label.Text = text
	label.Parent = billboard

	task.delay(1, function()
		part:Destroy()
	end)
end

local function teleportToOrigin(player: Player)
	local index = laneIndexByUserId[player.UserId]
	local character = player.Character
	if not index or not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.CFrame = CFrame.new(laneOrigin(index), markerPosition(index))
	end
end

local function assign(player: Player)
	local index = table.remove(freeLaneIndices)
	if not index then
		index = nextLaneIndex
		nextLaneIndex += 1
	end
	laneIndexByUserId[player.UserId] = index
	buildLaneFloor(index)

	player.CharacterAdded:Connect(function()
		teleportToOrigin(player)
	end)
	if player.Character then
		teleportToOrigin(player)
	end
end

local function release(player: Player)
	local index = laneIndexByUserId[player.UserId]
	if index then
		table.insert(freeLaneIndices, index)
	end
	laneIndexByUserId[player.UserId] = nil
	waveHandles[player.UserId] = nil
	playerBillboards[player.UserId] = nil
end

function LaneSystem.init()
	Players.PlayerAdded:Connect(assign)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		assign(player)
	end
end

return LaneSystem
