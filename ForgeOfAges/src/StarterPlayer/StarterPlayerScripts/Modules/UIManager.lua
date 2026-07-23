-- StarterPlayerScripts/Modules/UIManager.lua
-- Programmatic HUD - no pre-built UI assets required to run the project.
-- Functional, not polished: rarity is shown as colored text, lists rebuild
-- on every state update rather than being incrementally pooled. Fine for the
-- list sizes this game produces; revisit if the collection grows huge.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local GearDefinitions = require(ReplicatedStorage.Modules.GearDefinitions)
local PetDefinitions = require(ReplicatedStorage.Modules.PetDefinitions)
local SkillDefinitions = require(ReplicatedStorage.Modules.SkillDefinitions)
local TechTreeDefinitions = require(ReplicatedStorage.Modules.TechTreeDefinitions)

local player = Players.LocalPlayer

local UIManager = {}

local screenGui: ScreenGui

-- Stats panel
local ageLabel: TextLabel
local oreLabel: TextLabel
local idleLabel: TextLabel
local powerLabel: TextLabel
local gachaLabel: TextLabel
local researchLabel: TextLabel

-- Stage combat panel (always visible - this is the core idle loop)
local stageLabelText: TextLabel
local enemyNameLabel: TextLabel
local enemyBarFill: Frame
local playerBarFill: Frame
local playerStatusLabel: TextLabel
local stageEventLabel: TextLabel
local stageEventClearAt = 0

-- Forge panel
local forgeCraftButton: TextButton
local forgeSlotsFrame: Frame
local forgeResultLabel: TextLabel
local forgeResultClearAt = 0

-- Bottom bar
local prestigeButton: TextButton
local prestigeInfoLabel: TextLabel

local adventureFrame: Frame
local adventureVisible = false
local techTreeFrame: Frame
local arenaLabel: TextLabel
local arenaButton: TextButton
local arenaResultLabel: TextLabel
local gachaResultLabel: TextLabel
local gearListFrame: Frame
local petListFrame: Frame
local skillListFrame: Frame
local petLoadoutFrame: Frame
local skillLoadoutFrame: Frame
local gearLoadoutFrame: Frame

local lastState: any = nil

local RARITY_COLORS = {}
for _, rarity in GearDefinitions.Rarities do
	RARITY_COLORS[rarity.id] = rarity.color
end

local function formatNumber(n: number): string
	local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc" }
	local tier = 0
	local value = n
	while math.abs(value) >= 1000 and tier < #suffixes - 1 do
		value /= 1000
		tier += 1
	end
	if tier == 0 then
		return string.format("%d", value)
	end
	return string.format("%.2f%s", value, suffixes[tier + 1])
end

local function findPetDef(id: string)
	for _, def in PetDefinitions.Pets do
		if def.id == id then
			return def
		end
	end
	return nil
end

local function findSkillDef(id: string)
	for _, def in SkillDefinitions.Skills do
		if def.id == id then
			return def
		end
	end
	return nil
end

local function clearChildren(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function newSection(parent: Instance, title: string, order: number, height: number): Frame
	local section = Instance.new("Frame")
	section.Name = title
	section.LayoutOrder = order
	section.Size = UDim2.new(1, 0, 0, height)
	section.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	section.BackgroundTransparency = 0.1
	section.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = section

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = section

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = section

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 15
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = title
	titleLabel.LayoutOrder = 0
	titleLabel.Parent = section

	return section
end

local function newButton(parent: Instance, text: string, order: number, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 26)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.Text = text
	button.BackgroundColor3 = color
	button.TextColor3 = Color3.new(1, 1, 1)
	button.LayoutOrder = order
	button.Parent = parent
	return button
end

local function newLabel(parent: Instance, text: string, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.TextColor3 = Color3.fromRGB(220, 220, 220)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Text = text
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

local function newBar(parent: Instance, order: number, fillColor: Color3): (Frame, Frame)
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, 14)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	back.LayoutOrder = order
	back.Parent = parent

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Parent = back

	return back, fill
end

local buildAdventurePanel

local function buildRoot()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ForgeHud"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player:WaitForChild("PlayerGui")

	-- Stats panel (top-left)
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.Size = UDim2.new(0, 280, 0, 180)
	stats.Position = UDim2.new(0, 12, 0, 12)
	stats.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	stats.BackgroundTransparency = 0.15
	stats.Parent = screenGui

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.Parent = stats

	ageLabel = newLabel(stats, "Stone Age", 1)
	ageLabel.Font = Enum.Font.GothamBold
	ageLabel.TextSize = 20
	ageLabel.TextColor3 = Color3.new(1, 1, 1)
	ageLabel.Size = UDim2.new(1, 0, 0, 28)

	oreLabel = newLabel(stats, "0", 2)
	oreLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	oreLabel.TextSize = 18
	oreLabel.Size = UDim2.new(1, 0, 0, 26)

	idleLabel = newLabel(stats, "+0/sec", 3)
	idleLabel.Size = UDim2.new(1, 0, 0, 22)

	powerLabel = newLabel(stats, "Arena Power: 0", 4)
	powerLabel.TextColor3 = Color3.fromRGB(230, 100, 100)
	powerLabel.Size = UDim2.new(1, 0, 0, 22)

	gachaLabel = newLabel(stats, "Gacha Currency: 0", 5)
	gachaLabel.TextColor3 = Color3.fromRGB(150, 220, 255)
	gachaLabel.Size = UDim2.new(1, 0, 0, 22)

	researchLabel = newLabel(stats, "Research Points: 0", 6)
	researchLabel.TextColor3 = Color3.fromRGB(150, 255, 180)
	researchLabel.Size = UDim2.new(1, 0, 0, 22)

	-- Stage combat panel (top-center) - always visible, this is the core loop
	local stagePanel = Instance.new("Frame")
	stagePanel.Name = "StagePanel"
	stagePanel.Size = UDim2.new(0, 300, 0, 130)
	stagePanel.Position = UDim2.new(0.5, -150, 0, 12)
	stagePanel.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	stagePanel.BackgroundTransparency = 0.15
	stagePanel.Parent = screenGui

	local stagePadding = Instance.new("UIPadding")
	stagePadding.PaddingTop = UDim.new(0, 6)
	stagePadding.PaddingLeft = UDim.new(0, 8)
	stagePadding.PaddingRight = UDim.new(0, 8)
	stagePadding.Parent = stagePanel

	local stageLayout = Instance.new("UIListLayout")
	stageLayout.Padding = UDim.new(0, 3)
	stageLayout.Parent = stagePanel

	stageLabelText = newLabel(stagePanel, "Stage 1-1", 1)
	stageLabelText.Font = Enum.Font.GothamBold
	stageLabelText.TextSize = 16
	stageLabelText.TextColor3 = Color3.new(1, 1, 1)
	stageLabelText.TextXAlignment = Enum.TextXAlignment.Center
	stageLabelText.Size = UDim2.new(1, 0, 0, 22)

	enemyNameLabel = newLabel(stagePanel, "-", 2)
	enemyNameLabel.TextXAlignment = Enum.TextXAlignment.Center
	enemyNameLabel.Size = UDim2.new(1, 0, 0, 16)

	local _enemyBack, enemyFill = newBar(stagePanel, 3, Color3.fromRGB(200, 60, 60))
	enemyBarFill = enemyFill

	local _playerBack, playerFill = newBar(stagePanel, 4, Color3.fromRGB(80, 190, 90))
	playerBarFill = playerFill

	playerStatusLabel = newLabel(stagePanel, "", 5)
	playerStatusLabel.TextXAlignment = Enum.TextXAlignment.Center
	playerStatusLabel.TextColor3 = Color3.fromRGB(220, 220, 120)
	playerStatusLabel.Size = UDim2.new(1, 0, 0, 16)

	stageEventLabel = newLabel(stagePanel, "", 6)
	stageEventLabel.TextXAlignment = Enum.TextXAlignment.Center
	stageEventLabel.TextColor3 = Color3.fromRGB(255, 220, 150)
	stageEventLabel.Size = UDim2.new(1, 0, 0, 18)

	-- Forge panel (top-right)
	local forgePanel = Instance.new("Frame")
	forgePanel.Name = "Forge"
	forgePanel.Size = UDim2.new(0, 260, 0, 170)
	forgePanel.Position = UDim2.new(1, -272, 0, 12)
	forgePanel.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	forgePanel.BackgroundTransparency = 0.15
	forgePanel.Parent = screenGui

	local forgePadding = Instance.new("UIPadding")
	forgePadding.PaddingTop = UDim.new(0, 6)
	forgePadding.PaddingLeft = UDim.new(0, 8)
	forgePadding.PaddingRight = UDim.new(0, 8)
	forgePadding.Parent = forgePanel

	local forgeLayout = Instance.new("UIListLayout")
	forgeLayout.Padding = UDim.new(0, 4)
	forgeLayout.Parent = forgePanel

	local forgeTitle = newLabel(forgePanel, "Forge", 1)
	forgeTitle.Font = Enum.Font.GothamBold
	forgeTitle.TextSize = 16
	forgeTitle.TextColor3 = Color3.new(1, 1, 1)
	forgeTitle.Size = UDim2.new(1, 0, 0, 22)

	forgeCraftButton = newButton(forgePanel, "Craft Gear", 2, Color3.fromRGB(160, 100, 60))
	forgeCraftButton.Activated:Connect(function()
		NetworkEvents.get("RequestForgeCraft"):FireServer()
	end)

	forgeSlotsFrame = Instance.new("Frame")
	forgeSlotsFrame.Size = UDim2.new(1, 0, 0, 60)
	forgeSlotsFrame.BackgroundTransparency = 1
	forgeSlotsFrame.LayoutOrder = 3
	forgeSlotsFrame.Parent = forgePanel
	local forgeSlotsLayout = Instance.new("UIListLayout")
	forgeSlotsLayout.Padding = UDim.new(0, 3)
	forgeSlotsLayout.Parent = forgeSlotsFrame

	forgeResultLabel = newLabel(forgePanel, "", 4)
	forgeResultLabel.Size = UDim2.new(1, 0, 0, 32)

	-- Bottom bar: Prestige only (Age Up is gone - chapters advance automatically)
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.new(0, 320, 0, 44)
	bottomBar.Position = UDim2.new(0.5, -160, 1, -60)
	bottomBar.BackgroundTransparency = 1
	bottomBar.Parent = screenGui

	local bottomLayout = Instance.new("UIListLayout")
	bottomLayout.FillDirection = Enum.FillDirection.Horizontal
	bottomLayout.Padding = UDim.new(0, 8)
	bottomLayout.Parent = bottomBar

	prestigeInfoLabel = newLabel(bottomBar, "", 1)
	prestigeInfoLabel.Size = UDim2.new(0, 170, 1, 0)
	prestigeInfoLabel.TextXAlignment = Enum.TextXAlignment.Right

	prestigeButton = newButton(bottomBar, "Prestige", 2, Color3.fromRGB(140, 90, 180))
	prestigeButton.Size = UDim2.new(0, 140, 1, 0)
	prestigeButton.Visible = false
	prestigeButton.Activated:Connect(function()
		NetworkEvents.get("RequestPrestige"):FireServer()
	end)

	-- Menu toggle (bottom-right)
	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "MenuToggle"
	toggleButton.Size = UDim2.new(0, 140, 0, 36)
	toggleButton.Position = UDim2.new(1, -152, 1, -48)
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.TextSize = 14
	toggleButton.Text = "Menu"
	toggleButton.BackgroundColor3 = Color3.fromRGB(180, 90, 60)
	toggleButton.TextColor3 = Color3.new(1, 1, 1)
	toggleButton.Parent = screenGui
	toggleButton.Activated:Connect(function()
		adventureVisible = not adventureVisible
		adventureFrame.Visible = adventureVisible
	end)

	buildAdventurePanel()
end

buildAdventurePanel = function()
	adventureFrame = Instance.new("ScrollingFrame")
	adventureFrame.Name = "Menu"
	adventureFrame.Size = UDim2.new(0, 320, 0, 560)
	adventureFrame.Position = UDim2.new(1, -334, 0, 200)
	adventureFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	adventureFrame.BackgroundTransparency = 0.1
	adventureFrame.BorderSizePixel = 0
	adventureFrame.ScrollBarThickness = 6
	adventureFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	adventureFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	adventureFrame.Visible = false
	adventureFrame.Parent = screenGui

	local outerPadding = Instance.new("UIPadding")
	outerPadding.PaddingTop = UDim.new(0, 8)
	outerPadding.PaddingLeft = UDim.new(0, 8)
	outerPadding.PaddingRight = UDim.new(0, 8)
	outerPadding.PaddingBottom = UDim.new(0, 8)
	outerPadding.Parent = adventureFrame

	local outerLayout = Instance.new("UIListLayout")
	outerLayout.Padding = UDim.new(0, 8)
	outerLayout.Parent = adventureFrame

	-- Tech tree section
	local techSection = newSection(adventureFrame, "Tech Tree", 1, 26 + #TechTreeDefinitions.Nodes * 46)
	techTreeFrame = Instance.new("Frame")
	techTreeFrame.Size = UDim2.new(1, 0, 0, #TechTreeDefinitions.Nodes * 46)
	techTreeFrame.BackgroundTransparency = 1
	techTreeFrame.LayoutOrder = 1
	techTreeFrame.Parent = techSection
	local techTreeLayout = Instance.new("UIListLayout")
	techTreeLayout.Padding = UDim.new(0, 4)
	techTreeLayout.Parent = techTreeFrame

	-- Arena section
	local arenaSection = newSection(adventureFrame, "Arena (3/day)", 2, 92)
	arenaLabel = newLabel(arenaSection, "Attempts left: 3", 1)
	arenaButton = newButton(arenaSection, "Battle", 2, Color3.fromRGB(70, 90, 140))
	arenaButton.Activated:Connect(function()
		NetworkEvents.get("RequestArenaBattle"):FireServer()
	end)
	arenaResultLabel = newLabel(arenaSection, "", 3)

	-- Gacha section
	local gachaSection = newSection(adventureFrame, "Gacha (100 currency/roll)", 3, 92)
	local rollButtons = Instance.new("Frame")
	rollButtons.Size = UDim2.new(1, 0, 0, 26)
	rollButtons.BackgroundTransparency = 1
	rollButtons.LayoutOrder = 1
	rollButtons.Parent = gachaSection
	local rollLayout = Instance.new("UIListLayout")
	rollLayout.FillDirection = Enum.FillDirection.Horizontal
	rollLayout.Padding = UDim.new(0, 6)
	rollLayout.Parent = rollButtons

	local rollPetButton = newButton(rollButtons, "Roll Pet", 1, Color3.fromRGB(90, 140, 90))
	rollPetButton.Size = UDim2.new(0.5, -3, 1, 0)
	rollPetButton.Activated:Connect(function()
		NetworkEvents.get("RequestGachaRoll"):FireServer("Pet")
	end)

	local rollSkillButton = newButton(rollButtons, "Roll Skill", 2, Color3.fromRGB(140, 120, 60))
	rollSkillButton.Size = UDim2.new(0.5, -3, 1, 0)
	rollSkillButton.Activated:Connect(function()
		NetworkEvents.get("RequestGachaRoll"):FireServer("Skill")
	end)

	gachaResultLabel = newLabel(gachaSection, "", 2)

	-- Equipped loadout section
	local loadoutSection = newSection(adventureFrame, "Equipped", 4, 160)
	gearLoadoutFrame = Instance.new("Frame")
	gearLoadoutFrame.Size = UDim2.new(1, 0, 0, 60)
	gearLoadoutFrame.BackgroundTransparency = 1
	gearLoadoutFrame.LayoutOrder = 1
	gearLoadoutFrame.Parent = loadoutSection
	local gearLoadoutLayout = Instance.new("UIListLayout")
	gearLoadoutLayout.Parent = gearLoadoutFrame

	petLoadoutFrame = Instance.new("Frame")
	petLoadoutFrame.Size = UDim2.new(1, 0, 0, 50)
	petLoadoutFrame.BackgroundTransparency = 1
	petLoadoutFrame.LayoutOrder = 2
	petLoadoutFrame.Parent = loadoutSection
	local petLoadoutLayout = Instance.new("UIListLayout")
	petLoadoutLayout.Parent = petLoadoutFrame

	skillLoadoutFrame = Instance.new("Frame")
	skillLoadoutFrame.Size = UDim2.new(1, 0, 0, 50)
	skillLoadoutFrame.BackgroundTransparency = 1
	skillLoadoutFrame.LayoutOrder = 3
	skillLoadoutFrame.Parent = loadoutSection
	local skillLoadoutLayout = Instance.new("UIListLayout")
	skillLoadoutLayout.Parent = skillLoadoutFrame

	-- Gear inventory section
	local gearSection = newSection(adventureFrame, "Gear Inventory", 5, 150)
	gearListFrame = Instance.new("Frame")
	gearListFrame.Size = UDim2.new(1, 0, 0, 130)
	gearListFrame.BackgroundTransparency = 1
	gearListFrame.LayoutOrder = 1
	gearListFrame.Parent = gearSection
	local gearListLayout = Instance.new("UIListLayout")
	gearListLayout.Padding = UDim.new(0, 4)
	gearListLayout.Parent = gearListFrame

	-- Pet collection section
	local petSection = newSection(adventureFrame, "Pets", 6, 130)
	petListFrame = Instance.new("Frame")
	petListFrame.Size = UDim2.new(1, 0, 0, 110)
	petListFrame.BackgroundTransparency = 1
	petListFrame.LayoutOrder = 1
	petListFrame.Parent = petSection
	local petListLayout = Instance.new("UIListLayout")
	petListLayout.Padding = UDim.new(0, 4)
	petListLayout.Parent = petListFrame

	-- Skill collection section
	local skillSection = newSection(adventureFrame, "Skills", 7, 130)
	skillListFrame = Instance.new("Frame")
	skillListFrame.Size = UDim2.new(1, 0, 0, 110)
	skillListFrame.BackgroundTransparency = 1
	skillListFrame.LayoutOrder = 1
	skillListFrame.Parent = skillSection
	local skillListLayout = Instance.new("UIListLayout")
	skillListLayout.Padding = UDim.new(0, 4)
	skillListLayout.Parent = skillListFrame
end

local function renderGearRow(parent: Instance, item, equippedGear, order: number)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 50)
	frame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	frame.LayoutOrder = order
	frame.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingTop = UDim.new(0, 2)
	padding.Parent = frame

	local substatParts = {}
	for _, sub in item.substats do
		local def = GearDefinitions.Substats[sub.stat]
		table.insert(substatParts, string.format("%s +%s", def.label, formatNumber(sub.value)))
	end
	if item.uniqueEffect then
		table.insert(substatParts, string.format("%s %.1f%%", item.uniqueEffect.label, item.uniqueEffect.chance))
	end

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.7, 0, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = RARITY_COLORS[item.rarity] or Color3.new(1, 1, 1)
	nameLabel.Text = string.format("[%s] %s (%s)", item.rarity, item.slot, table.concat(substatParts, ", "))
	nameLabel.TextWrapped = true
	nameLabel.Size = UDim2.new(1, -70, 0, 44)
	nameLabel.Parent = frame

	local isEquipped = equippedGear[item.slot] == item.id
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 64, 0, 22)
	button.Position = UDim2.new(1, -64, 0, 12)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 11
	button.Text = if isEquipped then "Unequip" else "Equip"
	button.BackgroundColor3 = if isEquipped then Color3.fromRGB(140, 70, 70) else Color3.fromRGB(70, 140, 90)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Parent = frame
	button.Activated:Connect(function()
		if isEquipped then
			NetworkEvents.get("RequestUnequipGear"):FireServer(item.slot)
		else
			NetworkEvents.get("RequestEquipGear"):FireServer(item.id)
		end
	end)
end

local function renderCollectibleRow(parent: Instance, kind: string, def, isEquipped: boolean, order: number)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 24)
	frame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	frame.LayoutOrder = order
	frame.Parent = parent

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -70, 1, 0)
	nameLabel.Position = UDim2.new(0, 4, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 11
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = RARITY_COLORS[def.rarity] or Color3.new(1, 1, 1)
	nameLabel.Text = string.format("[%s] %s", def.rarity, def.name)
	nameLabel.Parent = frame

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 64, 0, 20)
	button.Position = UDim2.new(1, -64, 0, 2)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 11
	button.Text = if isEquipped then "Unequip" else "Equip"
	button.BackgroundColor3 = if isEquipped then Color3.fromRGB(140, 70, 70) else Color3.fromRGB(70, 140, 90)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Parent = frame
	button.Activated:Connect(function()
		if isEquipped then
			-- Find which slot it's in and clear that slot.
			local equippedList = if kind == "Pet" then lastState.equippedPetIds else lastState.equippedSkillIds
			for index, id in equippedList do
				if id == def.id then
					NetworkEvents.get("RequestEquipCollectible"):FireServer(kind, nil, index)
					break
				end
			end
		else
			NetworkEvents.get("RequestEquipCollectible"):FireServer(kind, def.id, nil)
		end
	end)
end

local function renderLoadoutRow(parent: Instance, label: string, def, order: number)
	local row = Instance.new("TextLabel")
	row.Size = UDim2.new(1, 0, 0, 16)
	row.BackgroundTransparency = 1
	row.Font = Enum.Font.Gotham
	row.TextSize = 11
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextColor3 = Color3.fromRGB(200, 200, 200)
	row.Text = if def then string.format("%s: %s", label, def.name) else string.format("%s: (empty)", label)
	row.LayoutOrder = order
	row.Parent = parent
end

local techNodeRows: { [string]: any } = {}

local function getOrCreateTechRow(nodeId: string, order: number)
	local row = techNodeRows[nodeId]
	if row then
		return row
	end

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 42)
	frame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	frame.LayoutOrder = order
	frame.Parent = techTreeFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingTop = UDim.new(0, 2)
	padding.Parent = frame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -80, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Parent = frame

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -80, 0, 22)
	descLabel.Position = UDim2.new(0, 0, 0, 16)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 10
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextColor3 = Color3.fromRGB(190, 190, 190)
	descLabel.Parent = frame

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 74, 0, 36)
	button.Position = UDim2.new(1, -74, 0, 2)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 11
	button.BackgroundColor3 = Color3.fromRGB(70, 140, 90)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Parent = frame
	button.Activated:Connect(function()
		NetworkEvents.get("RequestTechUpgrade"):FireServer(nodeId)
	end)

	row = { frame = frame, nameLabel = nameLabel, descLabel = descLabel, button = button }
	techNodeRows[nodeId] = row
	return row
end

function UIManager.init()
	buildRoot()
end

function UIManager.render(state)
	lastState = state

	ageLabel.Text = state.ageName
	oreLabel.Text = formatNumber(state.ore) .. " " .. state.resourceLabel
	idleLabel.Text = "+" .. formatNumber(state.idlePerSecond) .. "/sec"
	powerLabel.Text = "Arena Power: " .. formatNumber(state.power)
	gachaLabel.Text = "Gacha Currency: " .. formatNumber(state.gachaCurrency)
	researchLabel.Text = "Research Points: " .. formatNumber(state.researchPoints)

	stageLabelText.Text = string.format("Stage %s%s", state.stageLabel, if state.stageCycle > 0 then string.format(" (Cycle %d)", state.stageCycle) else "")

	-- Prestige
	if state.atPrestigeCap then
		prestigeButton.Visible = true
		prestigeInfoLabel.Text = string.format("Prestige +%d pts", state.prestigePoints)
	else
		prestigeButton.Visible = false
		prestigeInfoLabel.Text = string.format("Prestige Points: %d", state.prestigePoints)
	end

	-- Arena
	arenaLabel.Text = "Attempts left: " .. tostring(state.arenaAttemptsLeft)
	arenaButton.Active = state.arenaAttemptsLeft > 0

	-- Forge
	forgeCraftButton.Text = string.format("Craft Gear (slots %d/%d)", #state.forgeJobs, state.forgeSlotCount)
	forgeCraftButton.Active = #state.forgeJobs < state.forgeSlotCount

	clearChildren(forgeSlotsFrame)
	for index, job in state.forgeJobs do
		local row = newLabel(forgeSlotsFrame, string.format("Slot %d: %ds left", job.slot, math.ceil(job.secondsLeft)), index)
		row.TextColor3 = Color3.fromRGB(255, 200, 140)
	end

	if os.clock() > forgeResultClearAt then
		forgeResultLabel.Text = ""
	end
	if os.clock() > stageEventClearAt then
		stageEventLabel.Text = ""
	end

	-- Tech tree
	for order, node in TechTreeDefinitions.Nodes do
		local row = getOrCreateTechRow(node.id, order)
		local level = state.techTree[node.id] or 0
		local cost = TechTreeDefinitions.getCost(node, level)
		local prereqMet = not node.prerequisite or (state.techTree[node.prerequisite] or 0) >= 1
		local maxed = level >= node.maxLevel

		row.nameLabel.Text = string.format("%s (Lv %d/%d)", node.name, level, node.maxLevel)
		row.descLabel.Text = node.description
		if maxed then
			row.button.Text = "MAX"
			row.button.Active = false
			row.button.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		elseif not prereqMet then
			row.button.Text = "Locked"
			row.button.Active = false
			row.button.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		else
			row.button.Text = string.format("%s RP", formatNumber(cost))
			row.button.Active = state.researchPoints >= cost
			row.button.BackgroundColor3 = if state.researchPoints >= cost
				then Color3.fromRGB(70, 140, 90)
				else Color3.fromRGB(110, 70, 70)
		end
	end

	-- Equipped gear loadout
	clearChildren(gearLoadoutFrame)
	local slotOrder = 0
	for _, slot in GearDefinitions.Slots do
		slotOrder += 1
		local itemId = state.equippedGear[slot]
		local item = nil
		if itemId then
			for _, gear in state.gear do
				if gear.id == itemId then
					item = gear
					break
				end
			end
		end
		local text = if item then string.format("%s: [%s]", slot, item.rarity) else string.format("%s: (empty)", slot)
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, 0, 0, 16)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.Gotham
		row.TextSize = 11
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if item then (RARITY_COLORS[item.rarity] or Color3.new(1, 1, 1)) else Color3.fromRGB(150, 150, 150)
		row.Text = text
		row.LayoutOrder = slotOrder
		row.Parent = gearLoadoutFrame
	end

	clearChildren(petLoadoutFrame)
	for index, petId in state.equippedPetIds do
		renderLoadoutRow(petLoadoutFrame, "Pet " .. index, if petId then findPetDef(petId) else nil, index)
	end

	clearChildren(skillLoadoutFrame)
	for index, skillId in state.equippedSkillIds do
		renderLoadoutRow(skillLoadoutFrame, "Skill " .. index, if skillId then findSkillDef(skillId) else nil, index)
	end

	-- Gear inventory
	clearChildren(gearListFrame)
	for index, item in state.gear do
		renderGearRow(gearListFrame, item, state.equippedGear, index)
	end

	-- Pet collection
	clearChildren(petListFrame)
	for index, petId in state.pets do
		local def = findPetDef(petId)
		if def then
			local isEquipped = false
			for _, equippedId in state.equippedPetIds do
				if equippedId == petId then
					isEquipped = true
					break
				end
			end
			renderCollectibleRow(petListFrame, "Pet", def, isEquipped, index)
		end
	end

	-- Skill collection
	clearChildren(skillListFrame)
	for index, skillId in state.skills do
		local def = findSkillDef(skillId)
		if def then
			local isEquipped = false
			for _, equippedId in state.equippedSkillIds do
				if equippedId == skillId then
					isEquipped = true
					break
				end
			end
			renderCollectibleRow(skillListFrame, "Skill", def, isEquipped, index)
		end
	end
end

-- Fed by the CombatTick remote at ~1Hz - lightweight numeric-only payload,
-- kept separate from the full state push so it can run every tick cheaply.
function UIManager.renderCombatTick(tick)
	enemyNameLabel.Text = string.format("%s x wave - %s", tick.zoneName, tick.label)
	enemyBarFill.Size = UDim2.new(math.clamp(tick.enemyHP / tick.enemyMaxHP, 0, 1), 0, 1, 0)
	playerBarFill.Size = UDim2.new(math.clamp(tick.playerHP / tick.playerMaxHP, 0, 1), 0, 1, 0)
	playerBarFill.BackgroundColor3 = if tick.downed then Color3.fromRGB(120, 120, 120) else Color3.fromRGB(80, 190, 90)
	playerStatusLabel.Text = if tick.downed then "DOWNED - recovering..." else ""
end

function UIManager.showStageEvent(event)
	if event.kind == "WaveCleared" then
		local advanceText = if event.advanceKind == "Chapter"
			then " - Chapter cleared!"
			elseif event.advanceKind == "Cycle" then " - Endless Cycle (Prestige to unlock more)"
			else ""
		stageEventLabel.Text = string.format(
			"Cleared %s: +%s Ore, +%d RP%s",
			event.label,
			formatNumber(event.oreGain),
			event.researchGain,
			advanceText
		)
	elseif event.kind == "WaveStart" then
		stageEventLabel.Text = ""
	end
end

function UIManager.showGachaResult(result)
	if result.duplicate then
		gachaResultLabel.Text = string.format("Duplicate %s [%s] - refunded currency", result.name, result.rarity)
	else
		gachaResultLabel.Text = string.format("Got %s: %s [%s]!", result.poolType, result.name, result.rarity)
	end
end

function UIManager.showArenaResult(result)
	if result.won then
		arenaResultLabel.Text = string.format("Victory! +%d currency (%d left today)", result.gachaReward, result.attemptsLeft)
	else
		arenaResultLabel.Text = string.format("Defeat. (%d attempts left today)", result.attemptsLeft)
	end
end

function UIManager.showForgeResult(result)
	local item = result.item
	forgeResultLabel.Text = string.format("Forged [%s] %s!", item.rarity, item.slot)
	forgeResultLabel.TextColor3 = RARITY_COLORS[item.rarity] or Color3.new(1, 1, 1)
	forgeResultClearAt = os.clock() + 4
end

return UIManager
