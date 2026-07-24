-- StarterPlayerScripts/Modules/UIManager.lua
-- Programmatic HUD - no pre-built UI assets required to run the project.
-- Bright, high-contrast, pill/ribbon-based chrome (white currency pills, a
-- dark stage pill with progress pips, equal-square equipment slots with a
-- rarity ring, a red ribbon banner for the Forge, and bottom sheets instead
-- of centered dialogs) sitting thin over the always-visible 3D lane - not a
-- dark "app" skin. There are no image assets (see README), so "icons" are
-- small colored circular badges with a short bold letter code, built so a
-- real ImageLabel/Decal can drop in later without touching call sites.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local GearDefinitions = require(ReplicatedStorage.Modules.GearDefinitions)
local PetDefinitions = require(ReplicatedStorage.Modules.PetDefinitions)
local SkillDefinitions = require(ReplicatedStorage.Modules.SkillDefinitions)
local TechTreeDefinitions = require(ReplicatedStorage.Modules.TechTreeDefinitions)
local DungeonDefinitions = require(ReplicatedStorage.Modules.DungeonDefinitions)

local player = Players.LocalPlayer

local UIManager = {}

-- ============================================================ Palette ====

local COLOR_BG = Color3.fromRGB(251, 247, 238) -- dock background (warm cream, not white-white)
local COLOR_CARD = Color3.fromRGB(255, 255, 255)
local COLOR_CARD_LIGHT = Color3.fromRGB(250, 247, 240) -- rows/inputs sitting on a card
local COLOR_DOCK_BORDER = Color3.fromRGB(232, 223, 201)
local COLOR_ACCENT = Color3.fromRGB(46, 161, 230) -- primary CTA (Equip/Battle/Upgrade)
local COLOR_GOLD = Color3.fromRGB(240, 185, 58) -- reward CTA (Enter/Claim/Hatch)
local COLOR_GOOD = Color3.fromRGB(92, 191, 77) -- craft/positive
local COLOR_BAD = Color3.fromRGB(239, 75, 69) -- sell/danger/the Forge ribbon
local COLOR_TEXT = Color3.fromRGB(34, 40, 44) -- dark ink - chrome is light now, not dark
local COLOR_SUBTEXT = Color3.fromRGB(138, 132, 120)
local COLOR_DISABLED = Color3.fromRGB(199, 194, 184)

local RARITY_COLORS = {}
for _, rarity in GearDefinitions.Rarities do
	RARITY_COLORS[rarity.id] = rarity.color
end

-- Bright rarity/accent hues read fine as a ring or a badge background, but
-- washed out as text on the new light cards - this darkens a color for text
-- use without needing a second hand-picked palette to keep in sync.
local function textTone(color: Color3): Color3
	return Color3.new(color.R * 0.55, color.G * 0.55, color.B * 0.55)
end

local SUBSTAT_ICON = {
	HP = { code = "HP", color = Color3.fromRGB(230, 90, 110) },
	Damage = { code = "DMG", color = Color3.fromRGB(255, 140, 60) },
	RangedDamage = { code = "RNG", color = Color3.fromRGB(255, 160, 90) },
	MeleeDamage = { code = "MEL", color = Color3.fromRGB(255, 120, 80) },
	CritRate = { code = "CRT", color = Color3.fromRGB(190, 120, 230) },
	CritDamage = { code = "CDM", color = Color3.fromRGB(160, 90, 220) },
	HealthRegen = { code = "REG", color = Color3.fromRGB(110, 200, 140) },
	AttackSpeed = { code = "SPD", color = Color3.fromRGB(90, 180, 230) },
}

local DUNGEON_TINT = {
	OreVault = Color3.fromRGB(243, 224, 168),
	BeastDen = Color3.fromRGB(196, 224, 176),
	RuneChamber = Color3.fromRGB(217, 200, 240),
}

-- ============================================================= State =====

local screenGui: ScreenGui
local lastState: any = nil
local activeMainTab = "Home"
local activeCollectionTab = "Pets"

-- Top bar
local oreValueLabel: TextLabel
local coinsValueLabel: TextLabel
local gachaValueLabel: TextLabel
local researchValueLabel: TextLabel
local powerValueLabel: TextLabel

-- Stage world panel
local stageLabelText: TextLabel
local stageDotsFrame: Frame
local enemyNameLabel: TextLabel
local enemyBarFill: Frame
local playerBarFill: Frame
local playerStatusLabel: TextLabel
local stageEventLabel: TextLabel
local stageEventClearAt = 0

-- Tabs
local tabContentHost: Frame
local tabContents: { [string]: ScrollingFrame } = {}
local tabButtons: { [string]: TextButton } = {}
local tabIndicator: Frame

-- Home tab
local ageLabel: TextLabel
local idleLabel: TextLabel
local prestigeButton: TextButton
local prestigeInfoLabel: TextLabel
local claimButton: TextButton
local claimInfoLabel: TextLabel
local equipmentStrip: ScrollingFrame
local gearListFrame: Frame
local gearGridLayout: UIGridLayout

-- Dungeon tab
local dungeonListFrame: Frame
local dungeonGridLayout: UIGridLayout

-- Arena tab
local arenaRatingLabel: TextLabel
local arenaAttemptsLabel: TextLabel
local arenaButton: TextButton
local arenaResultLabel: TextLabel

-- Collection tab
local pillPetsButton: TextButton
local pillSkillsButton: TextButton
local petLoadoutFrame: Frame
local skillLoadoutFrame: Frame
local petListFrame: Frame
local petGridLayout: UIGridLayout
local eggListFrame: Frame
local eggGridLayout: UIGridLayout
local skillListFrame: Frame
local skillGridLayout: UIGridLayout
local gachaResultLabel: TextLabel

-- Tech tab
local techTreeFrame: Frame
local techNodeRows: { [string]: any } = {}

-- Forge ribbon + sheet
local forgeRibbonButton: TextButton
local forgeSheetRoot: Frame
local forgeCraftButton: TextButton
local forgeUpgradeButton: TextButton
local forgeLevelLabel: TextLabel
local forgeResultLabel: TextLabel
local forgeResultClearAt = 0

-- Gear detail sheet
local gearSheetRoot: Frame
local gearSheetBody: Frame

-- Scene overlay (Dungeon runs + Arena duels)
local sceneOverlayRoot: Frame
local sceneTitleLabel: TextLabel
local sceneSubLabel: TextLabel
local sceneLeftName: TextLabel
local sceneLeftBarFill: Frame
local sceneRightName: TextLabel
local sceneRightBarFill: Frame
local sceneStatusLabel: TextLabel
local sceneCloseButton: TextButton
local activeDungeonId: string? = nil

-- ========================================================== Utilities ====

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

-- ================================================= Responsive layout =====
-- Roblox is played landscape on every device, including phones - there is
-- no portrait "mobile app" mode to design for here. The split below is
-- purely about how many horizontal pixels are actually available: a phone
-- or small window still gets a single column (same reading order as the
-- reference game), while a PC-sized viewport reflows the same lists into a
-- multi-column grid so the extra width gets used instead of just stretching
-- empty panels edge to edge.
local WIDE_BREAKPOINT = 700
local GRID_GAP = 8

local function isWideScreen(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and camera.ViewportSize.X >= WIDE_BREAKPOINT
end

-- A Frame + UIGridLayout pair. Cards inside must NOT use AutomaticSize (the
-- grid layout owns Size/Position for every child), so callers give cards a
-- fixed height sized for their content instead.
local function newGridList(parent: Instance): (Frame, UIGridLayout)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.Parent = parent

	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = frame

	return frame, grid
end

-- CellSize.X is shrunk by a fraction of the gap so `columns` cells plus
-- `columns - 1` gaps add back up to exactly the container's full width.
local function setGridColumns(grid: UIGridLayout, columns: number, cellHeight: number)
	grid.CellPadding = UDim2.new(0, GRID_GAP, 0, GRID_GAP)
	grid.CellSize = UDim2.new(1 / columns, -(GRID_GAP * (columns - 1) / columns), 0, cellHeight)
end

-- ============================================================ Atoms ======

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
	return s
end

local function padAll(parent: Instance, amount: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, amount)
	p.PaddingBottom = UDim.new(0, amount)
	p.PaddingLeft = UDim.new(0, amount)
	p.PaddingRight = UDim.new(0, amount)
	p.Parent = parent
	return p
end

local function label(parent: Instance, text: string, size: number, color: Color3, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = text
	l.Size = UDim2.new(1, 0, 0, size + 6)
	l.Parent = parent
	return l
end

-- Press-scale feedback on every button (native, not decorative) - a quick
-- shrink on press and spring back, the same idiom every mobile game uses.
local PRESS_TWEEN_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function addPressFeedback(gui: GuiButton)
	gui.AutoButtonColor = false
	-- Captured fresh on every press (not once at construction time) since
	-- callers routinely set their own Size *after* button()/addPressFeedback
	-- return - capturing early would shrink toward the wrong dimensions.
	local capturedSize: UDim2? = nil
	gui.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			capturedSize = gui.Size
			TweenService:Create(gui, PRESS_TWEEN_INFO, { Size = capturedSize - UDim2.new(0, 4, 0, 3) }):Play()
		end
	end)
	gui.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if capturedSize then
				TweenService:Create(gui, RELEASE_TWEEN_INFO, { Size = capturedSize }):Play()
			end
		end
	end)
end

local function button(parent: Instance, text: string, bgColor: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.Text = text
	b.BackgroundColor3 = bgColor
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Parent = parent
	corner(b, 10)
	addPressFeedback(b)
	return b
end

-- Small circular badge with a short bold code - stands in for an icon.
-- Centralized here so swapping every badge for a real Image later (once
-- assets are uploaded in Studio) only touches this one function.
local function iconBadge(parent: Instance, diameter: number, bgColor: Color3, code: string): Frame
	local badge = Instance.new("Frame")
	badge.Size = UDim2.new(0, diameter, 0, diameter)
	badge.BackgroundColor3 = bgColor
	corner(badge, diameter / 2)
	badge.Parent = parent

	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = math.max(9, diameter * 0.32)
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextScaled = false
	text.Text = code
	text.Parent = badge

	return badge
end

local function progressBar(parent: Instance, fillColor: Color3, height: number): (Frame, Frame)
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, height)
	back.BackgroundColor3 = Color3.fromRGB(225, 219, 205)
	corner(back, height / 2)
	back.Parent = parent

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	corner(fill, height / 2)
	fill.Parent = back

	return back, fill
end

-- A card: rounded white panel with a bold title, used inside tab content.
local function newCard(parent: Instance, title: string, order: number): Frame
	local card = Instance.new("Frame")
	card.Name = title
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, 0, 0, 0)
	card.BackgroundColor3 = COLOR_CARD
	card.LayoutOrder = order
	corner(card, 12)
	padAll(card, 10)
	card.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card

	if title ~= "" then
		local titleLabel = label(card, title, 16, COLOR_TEXT, true)
		titleLabel.LayoutOrder = 0
	end

	return card
end

local function newVerticalTabContent(parent: Instance, name: string): ScrollingFrame
	local frame = Instance.new("ScrollingFrame")
	frame.Name = name
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ScrollBarThickness = 5
	frame.CanvasSize = UDim2.new(0, 0, 0, 0)
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.Visible = false
	frame.Parent = parent

	padAll(frame, 6)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	return frame
end

-- Bottom sheet: docks flush above the tab dock and slides up into place
-- instead of a centered dialog fading in - same idiom the reference uses
-- for "Equipped"/"The Forge".
local SHEET_IN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

-- The dim backdrop is a full-screen sibling of `root` (root itself is a
-- small docked panel, not full-screen), so it's referenced indirectly via
-- an ObjectValue named "Dim" parented under `root` - see buildForgeSheet/
-- buildGearSheet. The backdrop must be fully hidden (not just transparent)
-- while closed, or its invisible click-catcher would swallow every input
-- meant for the game world underneath.
local function getSheetDim(root: Frame): Frame?
	local holder = root:FindFirstChild("Dim") :: ObjectValue?
	return if holder then holder.Value :: Frame? else nil
end

local function openSheet(root: Frame, restingPosition: UDim2)
	local dim = getSheetDim(root)
	if dim then
		dim.Visible = true
		dim.BackgroundTransparency = 1
		TweenService:Create(dim, SHEET_IN_INFO, { BackgroundTransparency = 0.45 }):Play()
	end

	root.Visible = true
	root.Position = restingPosition + UDim2.new(0, 0, 0, 40)
	TweenService:Create(root, SHEET_IN_INFO, { Position = restingPosition }):Play()
end

local function closeSheet(root: Frame)
	root.Visible = false
	local dim = getSheetDim(root)
	if dim then
		dim.Visible = false
	end
end

-- ================================================ Forward declares ========

local openGearSheet
local closeGearSheet
local openForgeSheet
local closeForgeSheet
local refreshHomeTab
local refreshDungeonTab
local refreshArenaTab
local refreshCollectionTab
local refreshTechTab
local setActiveMainTab
local setActiveCollectionTab
local refreshCurrentTab

-- ============================================================ Root =======

local function buildTopBar()
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, -20, 0, 40)
	topBar.Position = UDim2.new(0, 10, 0, 10)
	topBar.BackgroundTransparency = 1
	topBar.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = topBar

	local function pill(order: number, code: string, iconColor: Color3): TextLabel
		local pillFrame = Instance.new("Frame")
		pillFrame.Size = UDim2.new(0, 100, 1, 0)
		pillFrame.BackgroundColor3 = COLOR_CARD
		pillFrame.LayoutOrder = order
		corner(pillFrame, 20)
		stroke(pillFrame, COLOR_DOCK_BORDER, 1)
		pillFrame.Parent = topBar

		local badge = iconBadge(pillFrame, 28, iconColor, code)
		badge.Position = UDim2.new(0, 4, 0.5, -14)

		local value = Instance.new("TextLabel")
		value.Size = UDim2.new(1, -40, 1, 0)
		value.Position = UDim2.new(0, 36, 0, 0)
		value.BackgroundTransparency = 1
		value.Font = Enum.Font.GothamBold
		value.TextSize = 14
		value.TextColor3 = COLOR_TEXT
		value.TextXAlignment = Enum.TextXAlignment.Left
		value.Text = "0"
		value.Parent = pillFrame

		return value
	end

	oreValueLabel = pill(1, "O", COLOR_GOOD)
	coinsValueLabel = pill(2, "C", COLOR_GOLD)
	gachaValueLabel = pill(3, "G", Color3.fromRGB(90, 196, 224))
	researchValueLabel = pill(4, "R", Color3.fromRGB(79, 214, 176))

	local spacer = Instance.new("Frame")
	spacer.Size = UDim2.new(1, 0, 1, 0)
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = 5
	spacer.Parent = topBar
	local uiFlex = Instance.new("UIFlexItem")
	uiFlex.FlexMode = Enum.UIFlexMode.Fill
	uiFlex.Parent = spacer

	local powerBadge = Instance.new("Frame")
	powerBadge.Size = UDim2.new(0, 78, 1, 0)
	powerBadge.BackgroundColor3 = COLOR_TEXT
	powerBadge.BackgroundTransparency = 0.35
	powerBadge.LayoutOrder = 6
	corner(powerBadge, 20)
	powerBadge.Parent = topBar

	local powerIcon = iconBadge(powerBadge, 22, COLOR_BAD, "P")
	powerIcon.Position = UDim2.new(0, 4, 0.5, -11)

	powerValueLabel = Instance.new("TextLabel")
	powerValueLabel.Size = UDim2.new(1, -32, 1, 0)
	powerValueLabel.Position = UDim2.new(0, 28, 0, 0)
	powerValueLabel.BackgroundTransparency = 1
	powerValueLabel.Font = Enum.Font.GothamBold
	powerValueLabel.TextSize = 13
	powerValueLabel.TextColor3 = Color3.new(1, 1, 1)
	powerValueLabel.TextXAlignment = Enum.TextXAlignment.Left
	powerValueLabel.Text = "0"
	powerValueLabel.Parent = powerBadge
end

local function buildStagePanel()
	local stagePanel = Instance.new("Frame")
	stagePanel.Name = "StagePanel"
	stagePanel.Size = UDim2.new(0, 220, 0, 0)
	stagePanel.AutomaticSize = Enum.AutomaticSize.Y
	stagePanel.Position = UDim2.new(0.5, -110, 0, 58)
	stagePanel.BackgroundColor3 = COLOR_TEXT
	corner(stagePanel, 16)
	padAll(stagePanel, 10)
	stagePanel.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = stagePanel

	stageLabelText = label(stagePanel, "Stage 1-1", 15, Color3.new(1, 1, 1), true)
	stageLabelText.TextXAlignment = Enum.TextXAlignment.Center
	stageLabelText.LayoutOrder = 1

	stageDotsFrame = Instance.new("Frame")
	stageDotsFrame.Size = UDim2.new(1, 0, 0, 8)
	stageDotsFrame.BackgroundTransparency = 1
	stageDotsFrame.LayoutOrder = 2
	stageDotsFrame.Parent = stagePanel
	local dotsLayout = Instance.new("UIListLayout")
	dotsLayout.FillDirection = Enum.FillDirection.Horizontal
	dotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotsLayout.Padding = UDim.new(0, 5)
	dotsLayout.Parent = stageDotsFrame
	for i = 1, 5 do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. i
		dot.Size = UDim2.new(0, 6, 0, 6)
		dot.BackgroundColor3 = Color3.fromRGB(90, 96, 100)
		corner(dot, 3)
		dot.LayoutOrder = i
		dot.Parent = stageDotsFrame
	end

	-- Slim combat readout - the detailed per-enemy HP already floats above
	-- the actual 3D dummy/avatar as a billboard (see LaneSystem); this is
	-- just a compact at-a-glance summary, not a duplicate big panel.
	local enemyRow = Instance.new("Frame")
	enemyRow.Size = UDim2.new(1, 0, 0, 8)
	enemyRow.BackgroundTransparency = 1
	enemyRow.LayoutOrder = 3
	enemyRow.Parent = stagePanel
	local _enemyBack, enemyFill = progressBar(enemyRow, COLOR_BAD, 8)
	enemyBarFill = enemyFill

	local playerRow = Instance.new("Frame")
	playerRow.Size = UDim2.new(1, 0, 0, 8)
	playerRow.BackgroundTransparency = 1
	playerRow.LayoutOrder = 4
	playerRow.Parent = stagePanel
	local _playerBack, playerFill = progressBar(playerRow, COLOR_GOOD, 8)
	playerBarFill = playerFill

	enemyNameLabel = label(stagePanel, "-", 10, Color3.fromRGB(200, 200, 205))
	enemyNameLabel.TextXAlignment = Enum.TextXAlignment.Center
	enemyNameLabel.LayoutOrder = 5

	playerStatusLabel = label(stagePanel, "", 11, COLOR_GOLD, true)
	playerStatusLabel.TextXAlignment = Enum.TextXAlignment.Center
	playerStatusLabel.LayoutOrder = 6

	stageEventLabel = label(stagePanel, "", 11, COLOR_GOLD, true)
	stageEventLabel.TextXAlignment = Enum.TextXAlignment.Center
	stageEventLabel.LayoutOrder = 7
end

local MAIN_TABS = { "Home", "Dungeon", "Arena", "Collection", "Tech" }
local TAB_ICON = { Home = "H", Dungeon = "D", Arena = "A", Collection = "C", Tech = "T" }

local function buildTabBar()
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, -20, 0, 56)
	tabBar.Position = UDim2.new(0, 10, 1, -64)
	tabBar.BackgroundColor3 = COLOR_BG
	corner(tabBar, 16)
	stroke(tabBar, COLOR_DOCK_BORDER, 1)
	tabBar.Parent = screenGui

	local tabWidth = 1 / #MAIN_TABS

	tabIndicator = Instance.new("Frame")
	tabIndicator.Size = UDim2.new(tabWidth, -8, 1, -8)
	tabIndicator.Position = UDim2.new(0, 4, 0, 4)
	tabIndicator.BackgroundColor3 = Color3.fromRGB(232, 243, 222)
	corner(tabIndicator, 12)
	tabIndicator.ZIndex = 1
	tabIndicator.Parent = tabBar

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = tabBar

	for index, name in MAIN_TABS do
		local tabButton = Instance.new("TextButton")
		tabButton.Name = name
		tabButton.Size = UDim2.new(tabWidth, 0, 1, 0)
		tabButton.LayoutOrder = index
		tabButton.BackgroundTransparency = 1
		tabButton.ZIndex = 2
		tabButton.Text = ""
		tabButton.Parent = tabBar
		addPressFeedback(tabButton)

		local icon = iconBadge(tabButton, 22, COLOR_DISABLED, TAB_ICON[name])
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 4)
		icon.ZIndex = 2

		local tabLabel = label(tabButton, name, 9, COLOR_SUBTEXT, true)
		tabLabel.TextXAlignment = Enum.TextXAlignment.Center
		tabLabel.Position = UDim2.new(0, 0, 0, 30)
		tabLabel.Size = UDim2.new(1, 0, 0, 14)
		tabLabel.ZIndex = 2

		tabButton.Activated:Connect(function()
			setActiveMainTab(name)
		end)
		tabButtons[name] = tabButton
	end

	-- A fixed-height dock, not "everything between the stage panel and the
	-- tab bar" - this is a Roblox place, not a full-screen mobile app, so
	-- the 3D lane behind the HUD (avatar + monster wave, see LaneSystem)
	-- has to stay the dominant thing on screen. The dock only grows if a
	-- tab's content needs scrolling, never by claiming more of the screen.
	tabContentHost = Instance.new("Frame")
	tabContentHost.Name = "TabContentHost"
	tabContentHost.Size = UDim2.new(1, -20, 0, 250)
	tabContentHost.Position = UDim2.new(0, 10, 1, -322)
	tabContentHost.BackgroundColor3 = COLOR_BG
	corner(tabContentHost, 16)
	stroke(tabContentHost, COLOR_DOCK_BORDER, 1)
	tabContentHost.Parent = screenGui

	for _, name in MAIN_TABS do
		tabContents[name] = newVerticalTabContent(tabContentHost, name)
	end
end

setActiveMainTab = function(name: string)
	activeMainTab = name
	for tabName, frame in tabContents do
		frame.Visible = tabName == name
	end

	local activeIndex = table.find(MAIN_TABS, name) or 1
	local tabWidth = 1 / #MAIN_TABS
	TweenService:Create(tabIndicator, SHEET_IN_INFO, {
		Position = UDim2.new(tabWidth * (activeIndex - 1), 4, 0, 4),
	}):Play()

	for tabName, tabButton in tabButtons do
		local isActive = tabName == name
		local icon = tabButton:FindFirstChildWhichIsA("Frame")
		local tabLabel = tabButton:FindFirstChildWhichIsA("TextLabel")
		if icon then
			icon.BackgroundColor3 = if isActive then COLOR_GOOD else COLOR_DISABLED
		end
		if tabLabel then
			tabLabel.TextColor3 = if isActive then textTone(COLOR_GOOD) else COLOR_SUBTEXT
		end
	end

	if lastState then
		if name == "Dungeon" then
			refreshDungeonTab(lastState)
		elseif name == "Arena" then
			refreshArenaTab(lastState)
		elseif name == "Collection" then
			refreshCollectionTab(lastState)
		elseif name == "Tech" then
			refreshTechTab(lastState)
		elseif name == "Home" then
			refreshHomeTab(lastState)
		end
	end
end

-- ==================================================== Home tab content ===

local function buildHomeTab()
	local host = tabContents.Home

	local progressCard = newCard(host, "Progress", 1)
	ageLabel = label(progressCard, "Stone Age", 14, COLOR_TEXT, true)
	ageLabel.LayoutOrder = 1
	idleLabel = label(progressCard, "+0/sec", 12, COLOR_SUBTEXT)
	idleLabel.LayoutOrder = 2

	local prestigeRow = Instance.new("Frame")
	prestigeRow.Size = UDim2.new(1, 0, 0, 32)
	prestigeRow.BackgroundTransparency = 1
	prestigeRow.LayoutOrder = 3
	prestigeRow.Parent = progressCard
	prestigeInfoLabel = label(prestigeRow, "", 12, COLOR_SUBTEXT)
	prestigeInfoLabel.Size = UDim2.new(0.6, 0, 1, 0)
	prestigeButton = button(prestigeRow, "Prestige", Color3.fromRGB(150, 100, 210))
	prestigeButton.Size = UDim2.new(0.4, -6, 1, 0)
	prestigeButton.Position = UDim2.new(0.6, 6, 0, 0)
	prestigeButton.Visible = false
	prestigeButton.Parent = prestigeRow
	prestigeButton.Activated:Connect(function()
		NetworkEvents.get("RequestPrestige"):FireServer()
	end)

	local claimRow = Instance.new("Frame")
	claimRow.Size = UDim2.new(1, 0, 0, 32)
	claimRow.BackgroundTransparency = 1
	claimRow.LayoutOrder = 4
	claimRow.Parent = progressCard
	claimInfoLabel = label(claimRow, "Hourly Ore claim", 12, COLOR_SUBTEXT)
	claimInfoLabel.Size = UDim2.new(0.6, 0, 1, 0)
	claimButton = button(claimRow, "Claim", COLOR_GOLD)
	claimButton.TextColor3 = Color3.fromRGB(48, 36, 8)
	claimButton.Size = UDim2.new(0.4, -6, 1, 0)
	claimButton.Position = UDim2.new(0.6, 6, 0, 0)
	claimButton.Parent = claimRow
	claimButton.Activated:Connect(function()
		NetworkEvents.get("RequestClaimHourlyOre"):FireServer()
	end)

	local equipmentCard = newCard(host, "Equipment (tap a slot for details)", 2)
	equipmentStrip = Instance.new("ScrollingFrame")
	equipmentStrip.Size = UDim2.new(1, 0, 0, 76)
	equipmentStrip.BackgroundTransparency = 1
	equipmentStrip.BorderSizePixel = 0
	equipmentStrip.ScrollingDirection = Enum.ScrollingDirection.X
	equipmentStrip.ScrollBarThickness = 5
	equipmentStrip.CanvasSize = UDim2.new(0, 0, 0, 0)
	equipmentStrip.AutomaticCanvasSize = Enum.AutomaticSize.X
	equipmentStrip.LayoutOrder = 1
	equipmentStrip.Parent = equipmentCard
	local stripLayout = Instance.new("UIListLayout")
	stripLayout.FillDirection = Enum.FillDirection.Horizontal
	stripLayout.Padding = UDim.new(0, 8)
	stripLayout.Parent = equipmentStrip

	local inventoryCard = newCard(host, "Gear Inventory", 3)
	gearListFrame, gearGridLayout = newGridList(inventoryCard)
	gearListFrame.LayoutOrder = 1
end

local function renderSubstatPill(parent: Instance, statId: string, value: number, order: number)
	local def = GearDefinitions.Substats[statId]
	local icon = SUBSTAT_ICON[statId] or { code = "?", color = Color3.fromRGB(150, 150, 150) }

	local pill = Instance.new("Frame")
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.new(0, 0, 0, 22)
	pill.BackgroundColor3 = COLOR_CARD_LIGHT
	pill.LayoutOrder = order
	corner(pill, 11)
	pill.Parent = parent

	local pillLayout = Instance.new("UIListLayout")
	pillLayout.FillDirection = Enum.FillDirection.Horizontal
	pillLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pillLayout.Padding = UDim.new(0, 4)
	pillLayout.Parent = pill
	padAll(pill, 3)

	local badge = iconBadge(pill, 16, icon.color, icon.code)
	badge.LayoutOrder = 1

	local valueLabel = Instance.new("TextLabel")
	valueLabel.AutomaticSize = Enum.AutomaticSize.X
	valueLabel.Size = UDim2.new(0, 0, 1, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextSize = 12
	valueLabel.TextColor3 = COLOR_TEXT
	valueLabel.LayoutOrder = 2
	valueLabel.Text = string.format("%s +%s%s", def.label, formatNumber(value), if def.kind == "percent" then "%" else "")
	valueLabel.Parent = pill
end

local function renderGearRow(parent: Instance, item, equippedGear, order: number)
	-- No AutomaticSize here - this row lives inside gearGridLayout, which
	-- owns Size/Position for every child (see newGridList).
	local row = Instance.new("Frame")
	row.Name = item.id
	row.BackgroundColor3 = COLOR_CARD_LIGHT
	row.LayoutOrder = order
	corner(row, 10)
	stroke(row, RARITY_COLORS[item.rarity] or COLOR_DISABLED, 2)
	padAll(row, 8)
	row.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 5)
	layout.Parent = row

	local headerRow = Instance.new("Frame")
	headerRow.Size = UDim2.new(1, 0, 0, 22)
	headerRow.BackgroundTransparency = 1
	headerRow.LayoutOrder = 1
	headerRow.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.65, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = textTone(RARITY_COLORS[item.rarity] or COLOR_TEXT)
	nameLabel.Text = string.format("%s - %s", item.slot, item.rarity)
	nameLabel.Parent = headerRow

	local isEquipped = equippedGear[item.slot] == item.id
	local equipButton = button(headerRow, if isEquipped then "Unequip" else "Equip", if isEquipped then COLOR_BAD else COLOR_ACCENT)
	equipButton.Size = UDim2.new(0.35, 0, 1, 0)
	equipButton.Position = UDim2.new(0.65, 0, 0, 0)
	equipButton.Parent = headerRow
	equipButton.Activated:Connect(function()
		if isEquipped then
			NetworkEvents.get("RequestUnequipGear"):FireServer(item.slot)
		else
			NetworkEvents.get("RequestEquipGear"):FireServer(item.id)
		end
	end)

	local pillRow = Instance.new("Frame")
	pillRow.Size = UDim2.new(1, 0, 0, 24)
	pillRow.BackgroundTransparency = 1
	pillRow.LayoutOrder = 2
	pillRow.Parent = row
	local pillLayout = Instance.new("UIListLayout")
	pillLayout.FillDirection = Enum.FillDirection.Horizontal
	pillLayout.Padding = UDim.new(0, 4)
	pillLayout.Parent = pillRow

	for index, sub in item.substats do
		renderSubstatPill(pillRow, sub.stat, sub.value, index)
	end
	if item.uniqueEffect then
		local pill = Instance.new("Frame")
		pill.AutomaticSize = Enum.AutomaticSize.X
		pill.Size = UDim2.new(0, 0, 0, 22)
		pill.BackgroundColor3 = Color3.fromRGB(252, 235, 200)
		corner(pill, 11)
		padAll(pill, 3)
		pill.LayoutOrder = #item.substats + 1
		pill.Parent = pillRow
		local uniqueLabel = Instance.new("TextLabel")
		uniqueLabel.AutomaticSize = Enum.AutomaticSize.X
		uniqueLabel.Size = UDim2.new(0, 0, 1, 0)
		uniqueLabel.BackgroundTransparency = 1
		uniqueLabel.Font = Enum.Font.GothamBold
		uniqueLabel.TextSize = 12
		uniqueLabel.TextColor3 = textTone(COLOR_GOLD)
		uniqueLabel.Text = string.format("%s %.1f%%", item.uniqueEffect.label, item.uniqueEffect.chance)
		uniqueLabel.Parent = pill
	end

	row.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			openGearSheet(item, equippedGear)
		end
	end)
end

-- Equal-square slot, rarity shown as a colored ring rather than mixed
-- treatments - matches the reference's equipment row exactly.
local function renderEquipmentSlotCard(slot: string, item, order: number)
	local card = Instance.new("TextButton")
	card.Name = slot
	card.Size = UDim2.new(0, 68, 0, 68)
	card.LayoutOrder = order
	card.BackgroundColor3 = COLOR_CARD
	card.Text = ""
	card.Parent = equipmentStrip
	addPressFeedback(card)
	corner(card, 14)
	stroke(card, if item then (RARITY_COLORS[item.rarity] or COLOR_DISABLED) else COLOR_DISABLED, 3)

	local slotBadge = iconBadge(card, 30, if item then (RARITY_COLORS[item.rarity] or COLOR_DISABLED) else COLOR_DISABLED, string.sub(slot, 1, 1))
	slotBadge.AnchorPoint = Vector2.new(0.5, 0)
	slotBadge.Position = UDim2.new(0.5, 0, 0, 8)

	local slotLabel = Instance.new("TextLabel")
	slotLabel.Size = UDim2.new(1, -6, 0, 14)
	slotLabel.Position = UDim2.new(0, 3, 1, -18)
	slotLabel.BackgroundTransparency = 1
	slotLabel.Font = Enum.Font.GothamBold
	slotLabel.TextSize = 10
	slotLabel.TextXAlignment = Enum.TextXAlignment.Center
	slotLabel.TextColor3 = if item then textTone(RARITY_COLORS[item.rarity] or COLOR_TEXT) else COLOR_SUBTEXT
	slotLabel.Text = if item then item.rarity else slot
	slotLabel.Parent = card

	if item then
		card.Activated:Connect(function()
			openGearSheet(item, lastState.equippedGear)
		end)
	end
end

refreshHomeTab = function(state)
	ageLabel.Text = state.ageName
	idleLabel.Text = "+" .. formatNumber(state.idlePerSecond) .. "/sec Ore"

	if state.atPrestigeCap then
		prestigeButton.Visible = true
		prestigeInfoLabel.Text = string.format("Prestige +%d pts", state.prestigePoints)
	else
		prestigeButton.Visible = false
		prestigeInfoLabel.Text = string.format("Prestige Points: %d", state.prestigePoints)
	end

	if state.secondsUntilClaim > 0 then
		claimInfoLabel.Text = string.format("Next claim in %ds", math.ceil(state.secondsUntilClaim))
		claimButton.Text = "Claim"
		claimButton.Active = false
		claimButton.BackgroundColor3 = COLOR_DISABLED
	else
		claimInfoLabel.Text = "Hourly Ore ready!"
		claimButton.Text = "Claim +" .. formatNumber(state.oreClaimAmount)
		claimButton.Active = true
		claimButton.BackgroundColor3 = COLOR_GOLD
	end

	clearChildren(equipmentStrip)
	local order = 0
	for _, slot in GearDefinitions.Slots do
		order += 1
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
		renderEquipmentSlotCard(slot, item, order)
	end

	setGridColumns(gearGridLayout, if isWideScreen() then 2 else 1, 84)
	clearChildren(gearListFrame)
	for index, item in state.gear do
		renderGearRow(gearListFrame, item, state.equippedGear, index)
	end
end

-- ================================================= Dungeon tab content ===

local function buildDungeonTab()
	local host = tabContents.Dungeon
	dungeonListFrame, dungeonGridLayout = newGridList(host)
end

-- Rebuilt fresh every refresh (same pattern gear/pet/skill lists already
-- use) rather than built once and patched in place - simplest way to let a
-- card's own Size stay under dungeonGridLayout's control across column
-- changes, and cheap enough for exactly 3 cards.
local function renderDungeonCard(dungeonId: string, order: number, state)
	local def = DungeonDefinitions.get(dungeonId)
	local progress = state.dungeonProgress[dungeonId]
	local cooldownLeft = state.dungeonCooldownsRemaining[dungeonId] or 0

	local card = Instance.new("Frame")
	card.Name = dungeonId
	card.BackgroundColor3 = COLOR_CARD
	card.LayoutOrder = order
	corner(card, 12)
	stroke(card, COLOR_DOCK_BORDER, 1)
	padAll(card, 10)
	card.Parent = dungeonListFrame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = card

	local title = label(card, def.name, 16, COLOR_TEXT, true)
	title.LayoutOrder = 1
	local flavorLabel = label(card, def.flavor, 12, COLOR_SUBTEXT)
	flavorLabel.LayoutOrder = 2
	local favorLabel = label(card, "Favors: " .. def.favorLabel, 12, textTone(COLOR_GOLD), true)
	favorLabel.LayoutOrder = 3

	local selectorRow = Instance.new("Frame")
	selectorRow.Size = UDim2.new(1, 0, 0, 32)
	selectorRow.BackgroundTransparency = 1
	selectorRow.LayoutOrder = 4
	selectorRow.Parent = card

	local prevButton = button(selectorRow, "<", COLOR_CARD_LIGHT)
	prevButton.TextColor3 = COLOR_TEXT
	prevButton.Size = UDim2.new(0, 36, 1, 0)
	prevButton.Active = progress.selectedStage > 1
	prevButton.Parent = selectorRow
	prevButton.Activated:Connect(function()
		local target = math.max(1, progress.selectedStage - 1)
		NetworkEvents.get("RequestSelectDungeonStage"):FireServer(dungeonId, target)
	end)

	local stageLabel = label(selectorRow, string.format("Stage %d / %d", progress.selectedStage, progress.highestStage + 1), 14, COLOR_TEXT, true)
	stageLabel.Size = UDim2.new(1, -152, 1, 0)
	stageLabel.Position = UDim2.new(0, 40, 0, 0)
	stageLabel.TextXAlignment = Enum.TextXAlignment.Center

	local nextButton = button(selectorRow, ">", COLOR_CARD_LIGHT)
	nextButton.TextColor3 = COLOR_TEXT
	nextButton.Size = UDim2.new(0, 36, 1, 0)
	nextButton.Position = UDim2.new(1, -36, 0, 0)
	nextButton.Active = progress.selectedStage < math.min(DungeonDefinitions.MAX_STAGE, progress.highestStage + 1)
	nextButton.Parent = selectorRow
	nextButton.Activated:Connect(function()
		local target = math.min(DungeonDefinitions.MAX_STAGE, progress.selectedStage + 1)
		NetworkEvents.get("RequestSelectDungeonStage"):FireServer(dungeonId, target)
	end)

	local enterButton = button(
		card,
		if cooldownLeft > 0 then string.format("Ready in %ds", math.ceil(cooldownLeft)) else "Enter",
		if cooldownLeft > 0 then COLOR_DISABLED else COLOR_GOLD
	)
	enterButton.Size = UDim2.new(1, 0, 0, 32)
	enterButton.TextColor3 = if cooldownLeft > 0 then Color3.fromRGB(120, 114, 104) else Color3.fromRGB(48, 36, 8)
	enterButton.Active = cooldownLeft <= 0
	enterButton.LayoutOrder = 5
	enterButton.Parent = card
	enterButton.Activated:Connect(function()
		NetworkEvents.get("RequestEnterDungeon"):FireServer(dungeonId)
	end)
end

refreshDungeonTab = function(state)
	setGridColumns(dungeonGridLayout, if isWideScreen() then 3 else 1, 196)
	clearChildren(dungeonListFrame)
	for order, dungeonId in DungeonDefinitions.Order do
		renderDungeonCard(dungeonId, order, state)
	end
end

-- =================================================== Arena tab content ===

local function buildArenaTab()
	local host = tabContents.Arena
	local card = newCard(host, "Arena", 1)

	arenaRatingLabel = label(card, "Rating: 1000", 18, textTone(COLOR_GOLD), true)
	arenaRatingLabel.LayoutOrder = 1
	arenaAttemptsLabel = label(card, "Attempts left: 3", 12, COLOR_SUBTEXT)
	arenaAttemptsLabel.LayoutOrder = 2

	arenaButton = button(card, "Battle", COLOR_ACCENT)
	arenaButton.Size = UDim2.new(1, 0, 0, 34)
	arenaButton.LayoutOrder = 3
	arenaButton.Parent = card
	arenaButton.Activated:Connect(function()
		NetworkEvents.get("RequestArenaBattle"):FireServer()
	end)

	arenaResultLabel = label(card, "", 12, COLOR_SUBTEXT)
	arenaResultLabel.LayoutOrder = 4
end

refreshArenaTab = function(state)
	arenaRatingLabel.Text = "Rating: " .. formatNumber(state.arenaRating)
	arenaAttemptsLabel.Text = "Attempts left: " .. tostring(state.arenaAttemptsLeft)
	arenaButton.Active = state.arenaAttemptsLeft > 0
end

-- =============================================== Collection tab content ==

-- Skills only now - Pets have their own row shape (level/equipped instead
-- of a flat owned-id list), see renderPetRow.
local function renderSkillRow(parent: Instance, def, isEquipped: boolean, order: number)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundColor3 = COLOR_CARD_LIGHT
	row.LayoutOrder = order
	corner(row, 8)
	stroke(row, RARITY_COLORS[def.rarity] or COLOR_DISABLED, 2)
	row.Parent = parent

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -78, 1, 0)
	nameLabel.Position = UDim2.new(0, 8, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = textTone(RARITY_COLORS[def.rarity] or COLOR_TEXT)
	nameLabel.Text = string.format("%s (%s)", def.name, def.rarity)
	nameLabel.Parent = row

	local equipButton = button(row, if isEquipped then "Unequip" else "Equip", if isEquipped then COLOR_BAD else COLOR_ACCENT)
	equipButton.Size = UDim2.new(0, 70, 0, 22)
	equipButton.Position = UDim2.new(1, -74, 0.5, -11)
	equipButton.Parent = row
	equipButton.Activated:Connect(function()
		if isEquipped then
			for index, id in lastState.equippedSkillIds do
				if id == def.id then
					NetworkEvents.get("RequestEquipCollectible"):FireServer("Skill", nil, index)
					break
				end
			end
		else
			NetworkEvents.get("RequestEquipCollectible"):FireServer("Skill", def.id, nil)
		end
	end)
end

local function renderPetRow(parent: Instance, pet, def, order: number)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundColor3 = COLOR_CARD_LIGHT
	row.LayoutOrder = order
	corner(row, 8)
	stroke(row, RARITY_COLORS[def.rarity] or COLOR_DISABLED, 2)
	row.Parent = parent

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -78, 1, 0)
	nameLabel.Position = UDim2.new(0, 8, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = textTone(RARITY_COLORS[def.rarity] or COLOR_TEXT)
	nameLabel.Text = string.format("%s (%s) Lv.%d", def.name, def.rarity, pet.level)
	nameLabel.Parent = row

	local equipButton = button(row, if pet.equipped then "Unequip" else "Equip", if pet.equipped then COLOR_BAD else COLOR_ACCENT)
	equipButton.Size = UDim2.new(0, 70, 0, 22)
	equipButton.Position = UDim2.new(1, -74, 0.5, -11)
	equipButton.Parent = row
	equipButton.Activated:Connect(function()
		NetworkEvents.get("RequestSetPetEquipped"):FireServer(pet.defId, not pet.equipped)
	end)
end

local function renderEggRow(parent: Instance, egg, order: number)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundColor3 = COLOR_CARD_LIGHT
	row.LayoutOrder = order
	corner(row, 8)
	stroke(row, RARITY_COLORS[egg.rarity] or COLOR_DISABLED, 2)
	row.Parent = parent

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -78, 1, 0)
	nameLabel.Position = UDim2.new(0, 8, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = textTone(RARITY_COLORS[egg.rarity] or COLOR_TEXT)
	nameLabel.Text = string.format("%s Egg", egg.rarity)
	nameLabel.Parent = row

	local hatchButton = button(row, "Hatch", COLOR_GOLD)
	hatchButton.TextColor3 = Color3.fromRGB(48, 36, 8)
	hatchButton.Size = UDim2.new(0, 70, 0, 22)
	hatchButton.Position = UDim2.new(1, -74, 0.5, -11)
	hatchButton.Parent = row
	hatchButton.Activated:Connect(function()
		NetworkEvents.get("RequestHatchEgg"):FireServer(egg.id)
	end)
end

local function renderLoadoutRow(parent: Instance, name: string, def, order: number)
	local row = label(parent, if def then string.format("%s: %s", name, def.name) else string.format("%s: (empty)", name), 12, COLOR_SUBTEXT)
	row.LayoutOrder = order
end

local function buildCollectionTab()
	local host = tabContents.Collection

	local pillRow = Instance.new("Frame")
	pillRow.Size = UDim2.new(1, 0, 0, 32)
	pillRow.BackgroundTransparency = 1
	pillRow.LayoutOrder = 1
	pillRow.Parent = host
	local pillLayout = Instance.new("UIListLayout")
	pillLayout.FillDirection = Enum.FillDirection.Horizontal
	pillLayout.Padding = UDim.new(0, 8)
	pillLayout.Parent = pillRow

	pillPetsButton = button(pillRow, "Pets", COLOR_GOOD)
	pillPetsButton.Size = UDim2.new(0.5, -4, 1, 0)
	pillPetsButton.Parent = pillRow
	pillSkillsButton = button(pillRow, "Skills", COLOR_CARD_LIGHT)
	pillSkillsButton.TextColor3 = COLOR_TEXT
	pillSkillsButton.Size = UDim2.new(0.5, -4, 1, 0)
	pillSkillsButton.Parent = pillRow

	pillPetsButton.Activated:Connect(function()
		setActiveCollectionTab("Pets")
	end)
	pillSkillsButton.Activated:Connect(function()
		setActiveCollectionTab("Skills")
	end)

	local gachaCard = newCard(host, "Skill Gacha (100 currency/roll)", 2)
	local rollSkillButton = button(gachaCard, "Roll Skill", COLOR_GOLD)
	rollSkillButton.TextColor3 = Color3.fromRGB(48, 36, 8)
	rollSkillButton.Size = UDim2.new(1, 0, 0, 30)
	rollSkillButton.LayoutOrder = 1
	rollSkillButton.Parent = gachaCard
	rollSkillButton.Activated:Connect(function()
		NetworkEvents.get("RequestGachaRoll"):FireServer()
	end)

	gachaResultLabel = label(gachaCard, "", 12, COLOR_SUBTEXT)
	gachaResultLabel.LayoutOrder = 2

	local loadoutCard = newCard(host, "Equipped", 3)
	petLoadoutFrame = Instance.new("Frame")
	petLoadoutFrame.Size = UDim2.new(1, 0, 0, 0)
	petLoadoutFrame.AutomaticSize = Enum.AutomaticSize.Y
	petLoadoutFrame.BackgroundTransparency = 1
	petLoadoutFrame.LayoutOrder = 1
	petLoadoutFrame.Parent = loadoutCard
	local petLoadoutLayout = Instance.new("UIListLayout")
	petLoadoutLayout.Parent = petLoadoutFrame

	skillLoadoutFrame = Instance.new("Frame")
	skillLoadoutFrame.Size = UDim2.new(1, 0, 0, 0)
	skillLoadoutFrame.AutomaticSize = Enum.AutomaticSize.Y
	skillLoadoutFrame.BackgroundTransparency = 1
	skillLoadoutFrame.LayoutOrder = 2
	skillLoadoutFrame.Parent = loadoutCard
	local skillLoadoutLayout = Instance.new("UIListLayout")
	skillLoadoutLayout.Parent = skillLoadoutFrame

	local eggsCard = newCard(host, "Eggs (tap to hatch)", 4)
	eggsCard.Name = "EggsCard"
	eggListFrame, eggGridLayout = newGridList(eggsCard)
	eggListFrame.LayoutOrder = 1

	local petsCard = newCard(host, "Pets", 5)
	petsCard.Name = "PetsCard"
	petListFrame, petGridLayout = newGridList(petsCard)
	petListFrame.LayoutOrder = 1

	local skillsCard = newCard(host, "Skills", 6)
	skillsCard.Name = "SkillsCard"
	skillListFrame, skillGridLayout = newGridList(skillsCard)
	skillListFrame.LayoutOrder = 1
end

setActiveCollectionTab = function(name: string)
	activeCollectionTab = name
	pillPetsButton.BackgroundColor3 = if name == "Pets" then COLOR_GOOD else COLOR_CARD_LIGHT
	pillPetsButton.TextColor3 = if name == "Pets" then Color3.new(1, 1, 1) else COLOR_TEXT
	pillSkillsButton.BackgroundColor3 = if name == "Skills" then COLOR_GOOD else COLOR_CARD_LIGHT
	pillSkillsButton.TextColor3 = if name == "Skills" then Color3.new(1, 1, 1) else COLOR_TEXT
	local eggsCard = tabContents.Collection:FindFirstChild("EggsCard")
	local petsCard = tabContents.Collection:FindFirstChild("PetsCard")
	local skillsCard = tabContents.Collection:FindFirstChild("SkillsCard")
	if eggsCard then
		eggsCard.Visible = name == "Pets"
	end
	if petsCard then
		petsCard.Visible = name == "Pets"
	end
	if skillsCard then
		skillsCard.Visible = name == "Skills"
	end
end

refreshCollectionTab = function(state)
	local columns = if isWideScreen() then 2 else 1
	setGridColumns(petGridLayout, columns, 30)
	setGridColumns(eggGridLayout, columns, 30)
	setGridColumns(skillGridLayout, columns, 30)

	clearChildren(petLoadoutFrame)
	local equippedOrder = 0
	for _, pet in state.pets do
		if pet.equipped then
			equippedOrder += 1
			renderLoadoutRow(petLoadoutFrame, "Pet " .. equippedOrder, findPetDef(pet.defId), equippedOrder)
		end
	end
	if equippedOrder == 0 then
		renderLoadoutRow(petLoadoutFrame, "Pets", nil, 1)
	end

	clearChildren(skillLoadoutFrame)
	for index, skillId in state.equippedSkillIds do
		renderLoadoutRow(skillLoadoutFrame, "Skill " .. index, if skillId then findSkillDef(skillId) else nil, index)
	end

	clearChildren(eggListFrame)
	for index, egg in state.eggs do
		renderEggRow(eggListFrame, egg, index)
	end

	clearChildren(petListFrame)
	for index, pet in state.pets do
		local def = findPetDef(pet.defId)
		if def then
			renderPetRow(petListFrame, pet, def, index)
		end
	end

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
			renderSkillRow(skillListFrame, def, isEquipped, index)
		end
	end
end

-- ==================================================== Tech tab content ===

local function buildTechTab()
	techTreeFrame = tabContents.Tech
end

-- Indentation-only first pass (README §2.6): each node sits in a full-width
-- "slot" with a left spacer sized to its prerequisite depth, so the tree
-- reads as nested without needing connector lines drawn between Frames.
local INDENT_WIDTH = 20

local function getOrCreateTechRow(nodeId: string, order: number)
	local row = techNodeRows[nodeId]
	if row then
		return row
	end

	local depth = TechTreeDefinitions.getDepth(nodeId)

	local slot = Instance.new("Frame")
	slot.Name = nodeId .. "Slot"
	slot.AutomaticSize = Enum.AutomaticSize.Y
	slot.Size = UDim2.new(1, 0, 0, 0)
	slot.BackgroundTransparency = 1
	slot.LayoutOrder = order
	slot.Parent = techTreeFrame

	local slotLayout = Instance.new("UIListLayout")
	slotLayout.FillDirection = Enum.FillDirection.Horizontal
	slotLayout.Parent = slot

	if depth > 0 then
		local spacer = Instance.new("Frame")
		spacer.Size = UDim2.new(0, depth * INDENT_WIDTH, 0, 1)
		spacer.BackgroundTransparency = 1
		spacer.LayoutOrder = 1
		spacer.Parent = slot
	end

	local frame = Instance.new("Frame")
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Size = UDim2.new(1, -depth * INDENT_WIDTH, 0, 0)
	frame.BackgroundColor3 = COLOR_CARD
	frame.LayoutOrder = 2
	corner(frame, 10)
	stroke(frame, COLOR_DOCK_BORDER, 1)
	padAll(frame, 8)
	frame.Parent = slot

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.Parent = frame

	local nameLabel = label(frame, "", 14, COLOR_TEXT, true)
	nameLabel.LayoutOrder = 1
	local descLabel = label(frame, "", 11, COLOR_SUBTEXT)
	descLabel.LayoutOrder = 2

	local btn = button(frame, "", COLOR_GOOD)
	btn.Size = UDim2.new(1, 0, 0, 28)
	btn.LayoutOrder = 3
	btn.Parent = frame
	btn.Activated:Connect(function()
		NetworkEvents.get("RequestTechUpgrade"):FireServer(nodeId)
	end)

	row = { frame = frame, nameLabel = nameLabel, descLabel = descLabel, button = btn }
	techNodeRows[nodeId] = row
	return row
end

refreshTechTab = function(state)
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
			row.button.BackgroundColor3 = COLOR_DISABLED
			row.button.TextColor3 = COLOR_SUBTEXT
		elseif not prereqMet then
			row.button.Text = "Locked"
			row.button.Active = false
			row.button.BackgroundColor3 = COLOR_DISABLED
			row.button.TextColor3 = COLOR_SUBTEXT
		else
			row.button.Text = string.format("%s RP", formatNumber(cost))
			row.button.Active = state.researchPoints >= cost
			row.button.BackgroundColor3 = if state.researchPoints >= cost then COLOR_GOOD else Color3.fromRGB(216, 130, 120)
			row.button.TextColor3 = Color3.new(1, 1, 1)
		end
	end
end

-- ================================================= Forge ribbon + sheet ===

-- Signature action banner: a rounded red button reading "Forge" - the
-- reference's scroll-ribbon shape needs either an uploaded 9-slice image or
-- rotated-frame notch masking to render exactly; this ships the safe
-- zero-asset approximation (bold color + icon + label) and can upgrade to
-- the literal ribbon cutout once art is in Studio.
local function buildForgeRibbon()
	forgeRibbonButton = Instance.new("TextButton")
	forgeRibbonButton.Name = "ForgeRibbon"
	forgeRibbonButton.Size = UDim2.new(0, 150, 0, 34)
	forgeRibbonButton.Position = UDim2.new(0.5, -75, 1, -92)
	forgeRibbonButton.BackgroundColor3 = COLOR_BAD
	forgeRibbonButton.Text = ""
	forgeRibbonButton.ZIndex = 5
	corner(forgeRibbonButton, 17)
	forgeRibbonButton.Parent = screenGui
	addPressFeedback(forgeRibbonButton)

	local icon = iconBadge(forgeRibbonButton, 22, Color3.fromRGB(255, 255, 255), "F")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 8, 0.5, 0)
	local iconText = icon:FindFirstChildWhichIsA("TextLabel")
	if iconText then
		iconText.TextColor3 = COLOR_BAD
	end

	local ribbonLabel = Instance.new("TextLabel")
	ribbonLabel.Size = UDim2.new(1, -40, 1, 0)
	ribbonLabel.Position = UDim2.new(0, 36, 0, 0)
	ribbonLabel.BackgroundTransparency = 1
	ribbonLabel.Font = Enum.Font.GothamBold
	ribbonLabel.TextSize = 14
	ribbonLabel.TextColor3 = Color3.new(1, 1, 1)
	ribbonLabel.TextXAlignment = Enum.TextXAlignment.Left
	ribbonLabel.Text = "FORGE"
	ribbonLabel.Parent = forgeRibbonButton

	forgeRibbonButton.Activated:Connect(function()
		openForgeSheet()
	end)
end

local function buildForgeSheet()
	forgeSheetRoot = Instance.new("Frame")
	forgeSheetRoot.Name = "ForgeSheet"
	forgeSheetRoot.Size = UDim2.new(0, 280, 0, 0)
	forgeSheetRoot.AutomaticSize = Enum.AutomaticSize.Y
	forgeSheetRoot.AnchorPoint = Vector2.new(0.5, 1)
	forgeSheetRoot.Position = UDim2.new(0.5, 0, 1, -332)
	forgeSheetRoot.BackgroundColor3 = COLOR_CARD
	forgeSheetRoot.Visible = false
	forgeSheetRoot.ZIndex = 12
	corner(forgeSheetRoot, 16)
	padAll(forgeSheetRoot, 14)
	forgeSheetRoot.Parent = screenGui

	local dim = Instance.new("Frame")
	dim.Name = "ForgeDim"
	dim.Size = UDim2.new(1, 0, 1, 0)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Visible = false
	dim.ZIndex = 11
	dim.Parent = screenGui

	local dimClickCatcher = Instance.new("TextButton")
	dimClickCatcher.Size = UDim2.new(1, 0, 1, 0)
	dimClickCatcher.BackgroundTransparency = 1
	dimClickCatcher.Text = ""
	dimClickCatcher.ZIndex = 11
	dimClickCatcher.Parent = dim
	dimClickCatcher.Activated:Connect(function()
		closeForgeSheet()
	end)

	-- Keep the dim frame findable from the sheet without a second global -
	-- see getSheetDim.
	local dimHolder = Instance.new("ObjectValue")
	dimHolder.Name = "Dim"
	dimHolder.Value = dim
	dimHolder.Parent = forgeSheetRoot

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = forgeSheetRoot

	local titleRow = Instance.new("Frame")
	titleRow.Size = UDim2.new(1, 0, 0, 20)
	titleRow.BackgroundTransparency = 1
	titleRow.LayoutOrder = 1
	titleRow.Parent = forgeSheetRoot
	local title = label(titleRow, "The Forge", 16, COLOR_TEXT, true)
	title.Size = UDim2.new(0.8, 0, 1, 0)
	local closeX = button(titleRow, "x", COLOR_CARD_LIGHT)
	closeX.TextColor3 = COLOR_SUBTEXT
	closeX.Size = UDim2.new(0, 22, 0, 22)
	closeX.Position = UDim2.new(1, -22, 0, -1)
	closeX.Parent = titleRow
	closeX.Activated:Connect(function()
		closeForgeSheet()
	end)

	forgeLevelLabel = label(forgeSheetRoot, "", 12, COLOR_SUBTEXT)
	forgeLevelLabel.LayoutOrder = 2

	forgeCraftButton = button(forgeSheetRoot, "Craft Gear", COLOR_GOOD)
	forgeCraftButton.Size = UDim2.new(1, 0, 0, 36)
	forgeCraftButton.LayoutOrder = 3
	forgeCraftButton.Parent = forgeSheetRoot
	forgeCraftButton.Activated:Connect(function()
		NetworkEvents.get("RequestForgeCraft"):FireServer()
	end)

	forgeUpgradeButton = button(forgeSheetRoot, "Upgrade Forge", COLOR_ACCENT)
	forgeUpgradeButton.Size = UDim2.new(1, 0, 0, 36)
	forgeUpgradeButton.LayoutOrder = 4
	forgeUpgradeButton.Parent = forgeSheetRoot
	forgeUpgradeButton.Activated:Connect(function()
		NetworkEvents.get("RequestUpgradeForge"):FireServer()
	end)

	forgeResultLabel = label(forgeSheetRoot, "", 13, textTone(COLOR_GOLD), true)
	forgeResultLabel.TextWrapped = true
	forgeResultLabel.LayoutOrder = 5
end

openForgeSheet = function()
	if lastState then
		forgeLevelLabel.Text = string.format(
			"Forge Level %d - %d slot%s per craft",
			lastState.forgeLevel,
			lastState.forgeSlotCount,
			if lastState.forgeSlotCount == 1 then "" else "s"
		)

		forgeCraftButton.Text = string.format("Craft Gear (%s Ore)", formatNumber(lastState.forgeCraftCost))
		forgeCraftButton.Active = lastState.ore >= lastState.forgeCraftCost

		forgeUpgradeButton.Text = string.format("Upgrade Forge (%s Coins)", formatNumber(lastState.forgeUpgradeCost))
		forgeUpgradeButton.Active = lastState.coins >= lastState.forgeUpgradeCost
	end
	openSheet(forgeSheetRoot, UDim2.new(0.5, 0, 1, -332))
end

closeForgeSheet = function()
	closeSheet(forgeSheetRoot)
end

-- =================================================== Gear detail sheet ===

local function buildGearSheet()
	gearSheetRoot = Instance.new("Frame")
	gearSheetRoot.Name = "GearSheet"
	gearSheetRoot.Size = UDim2.new(0, 300, 0, 0)
	gearSheetRoot.AutomaticSize = Enum.AutomaticSize.Y
	gearSheetRoot.AnchorPoint = Vector2.new(0.5, 1)
	gearSheetRoot.Position = UDim2.new(0.5, 0, 1, -332)
	gearSheetRoot.BackgroundColor3 = COLOR_CARD
	gearSheetRoot.Visible = false
	gearSheetRoot.ZIndex = 12
	corner(gearSheetRoot, 16)
	padAll(gearSheetRoot, 14)
	gearSheetRoot.Parent = screenGui

	local dim = Instance.new("Frame")
	dim.Name = "GearDim"
	dim.Size = UDim2.new(1, 0, 1, 0)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Visible = false
	dim.ZIndex = 11
	dim.Parent = screenGui
	local dimClickCatcher = Instance.new("TextButton")
	dimClickCatcher.Size = UDim2.new(1, 0, 1, 0)
	dimClickCatcher.BackgroundTransparency = 1
	dimClickCatcher.Text = ""
	dimClickCatcher.ZIndex = 11
	dimClickCatcher.Parent = dim
	dimClickCatcher.Activated:Connect(function()
		closeGearSheet()
	end)
	local dimHolder = Instance.new("ObjectValue")
	dimHolder.Name = "Dim"
	dimHolder.Value = dim
	dimHolder.Parent = gearSheetRoot

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = gearSheetRoot

	gearSheetBody = gearSheetRoot
end

openGearSheet = function(item, equippedGear)
	clearChildren(gearSheetBody)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local titleRow = Instance.new("Frame")
	titleRow.Size = UDim2.new(1, 0, 0, 22)
	titleRow.BackgroundTransparency = 1
	titleRow.LayoutOrder = nextOrder()
	titleRow.Parent = gearSheetBody
	local title = label(titleRow, string.format("%s - %s", item.slot, item.rarity), 18, textTone(RARITY_COLORS[item.rarity] or COLOR_TEXT), true)
	title.Size = UDim2.new(0.8, 0, 1, 0)
	local closeX = button(titleRow, "x", COLOR_CARD_LIGHT)
	closeX.TextColor3 = COLOR_SUBTEXT
	closeX.Size = UDim2.new(0, 22, 0, 22)
	closeX.Position = UDim2.new(1, -22, 0, -1)
	closeX.Parent = titleRow
	closeX.Activated:Connect(function()
		closeGearSheet()
	end)

	local substatsHeader = label(gearSheetBody, "Substats", 13, COLOR_SUBTEXT, true)
	substatsHeader.LayoutOrder = nextOrder()

	for _, sub in item.substats do
		local def = GearDefinitions.Substats[sub.stat]
		local icon = SUBSTAT_ICON[sub.stat] or { code = "?", color = Color3.fromRGB(150, 150, 150) }

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 28)
		row.BackgroundColor3 = COLOR_CARD_LIGHT
		row.LayoutOrder = nextOrder()
		corner(row, 8)
		row.Parent = gearSheetBody

		local badge = iconBadge(row, 22, icon.color, icon.code)
		badge.Position = UDim2.new(0, 4, 0.5, -11)

		local statLabel = Instance.new("TextLabel")
		statLabel.Size = UDim2.new(1, -34, 1, 0)
		statLabel.Position = UDim2.new(0, 30, 0, 0)
		statLabel.BackgroundTransparency = 1
		statLabel.Font = Enum.Font.GothamBold
		statLabel.TextSize = 14
		statLabel.TextXAlignment = Enum.TextXAlignment.Left
		statLabel.TextColor3 = COLOR_TEXT
		statLabel.Text = string.format("%s: +%s%s", def.label, formatNumber(sub.value), if def.kind == "percent" then "%" else "")
		statLabel.Parent = row
	end

	if item.uniqueEffect then
		local uniqueRow = label(gearSheetBody, string.format("Unique: %s (%.1f%%)", item.uniqueEffect.label, item.uniqueEffect.chance), 13, textTone(COLOR_GOLD), true)
		uniqueRow.LayoutOrder = nextOrder()
	end

	if lastState and #lastState.enchantments > 0 then
		local enchantHeader = label(gearSheetBody, "Apply an Enchantment", 13, COLOR_SUBTEXT, true)
		enchantHeader.LayoutOrder = nextOrder()

		for _, enchantment in lastState.enchantments do
			local def = GearDefinitions.Substats[enchantment.statBonus.stat]

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 28)
			row.BackgroundColor3 = COLOR_CARD_LIGHT
			row.LayoutOrder = nextOrder()
			corner(row, 8)
			stroke(row, RARITY_COLORS[enchantment.rarity] or COLOR_DISABLED, 2)
			row.Parent = gearSheetBody

			local enchantLabel = Instance.new("TextLabel")
			enchantLabel.Size = UDim2.new(1, -74, 1, 0)
			enchantLabel.Position = UDim2.new(0, 8, 0, 0)
			enchantLabel.BackgroundTransparency = 1
			enchantLabel.Font = Enum.Font.GothamBold
			enchantLabel.TextSize = 12
			enchantLabel.TextXAlignment = Enum.TextXAlignment.Left
			enchantLabel.TextColor3 = textTone(RARITY_COLORS[enchantment.rarity] or COLOR_TEXT)
			enchantLabel.Text = string.format("%s +%s%s", def.label, formatNumber(enchantment.statBonus.value), if def.kind == "percent" then "%" else "")
			enchantLabel.Parent = row

			local applyButton = button(row, "Apply", COLOR_GOOD)
			applyButton.Size = UDim2.new(0, 60, 0, 22)
			applyButton.Position = UDim2.new(1, -64, 0.5, -11)
			applyButton.Parent = row
			applyButton.Activated:Connect(function()
				NetworkEvents.get("RequestApplyEnchantment"):FireServer(item.id, enchantment.id)
				closeGearSheet()
			end)
		end
	end

	local isEquipped = equippedGear[item.slot] == item.id
	local actionRow = Instance.new("Frame")
	actionRow.Size = UDim2.new(1, 0, 0, 34)
	actionRow.BackgroundTransparency = 1
	actionRow.LayoutOrder = nextOrder()
	actionRow.Parent = gearSheetBody
	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.Padding = UDim.new(0, 8)
	actionLayout.Parent = actionRow

	local sellButton = button(actionRow, string.format("Sell +%s", formatNumber(item.sellValue or 0)), COLOR_BAD)
	sellButton.Size = UDim2.new(0.5, -4, 1, 0)
	sellButton.Parent = actionRow
	sellButton.Activated:Connect(function()
		NetworkEvents.get("RequestSellGear"):FireServer(item.id)
		closeGearSheet()
	end)

	local equipButton = button(actionRow, if isEquipped then "Unequip" else "Equip", COLOR_ACCENT)
	equipButton.Size = UDim2.new(0.5, -4, 1, 0)
	equipButton.Parent = actionRow
	equipButton.Activated:Connect(function()
		if isEquipped then
			NetworkEvents.get("RequestUnequipGear"):FireServer(item.slot)
		else
			NetworkEvents.get("RequestEquipGear"):FireServer(item.id)
		end
		closeGearSheet()
	end)

	openSheet(gearSheetRoot, UDim2.new(0.5, 0, 1, -332))
end

closeGearSheet = function()
	closeSheet(gearSheetRoot)
end

-- ============================================ Scene overlay (shared) =====

local function buildSceneOverlay()
	sceneOverlayRoot = Instance.new("Frame")
	sceneOverlayRoot.Name = "SceneOverlay"
	sceneOverlayRoot.Size = UDim2.new(1, 0, 1, 0)
	sceneOverlayRoot.BackgroundColor3 = Color3.fromRGB(232, 226, 210)
	sceneOverlayRoot.BackgroundTransparency = 0.1
	sceneOverlayRoot.Visible = false
	sceneOverlayRoot.ZIndex = 20
	sceneOverlayRoot.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 320, 0, 280)
	panel.Position = UDim2.new(0.5, -160, 0.5, -140)
	panel.BackgroundColor3 = COLOR_CARD
	panel.ZIndex = 21
	corner(panel, 18)
	padAll(panel, 16)
	panel.Parent = sceneOverlayRoot

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = panel

	sceneTitleLabel = label(panel, "", 18, COLOR_TEXT, true)
	sceneTitleLabel.TextXAlignment = Enum.TextXAlignment.Center
	sceneTitleLabel.LayoutOrder = 1

	sceneSubLabel = label(panel, "", 12, COLOR_SUBTEXT)
	sceneSubLabel.TextXAlignment = Enum.TextXAlignment.Center
	sceneSubLabel.LayoutOrder = 2

	local leftRow = Instance.new("Frame")
	leftRow.Size = UDim2.new(1, 0, 0, 44)
	leftRow.BackgroundTransparency = 1
	leftRow.LayoutOrder = 3
	leftRow.Parent = panel
	sceneLeftName = label(leftRow, "You", 13, textTone(COLOR_GOOD), true)
	sceneLeftName.Size = UDim2.new(1, 0, 0, 16)
	local _leftBack, leftFill = progressBar(leftRow, COLOR_GOOD, 18)
	leftRow:FindFirstChildWhichIsA("Frame").Position = UDim2.new(0, 0, 0, 20)
	sceneLeftBarFill = leftFill

	local rightRow = Instance.new("Frame")
	rightRow.Size = UDim2.new(1, 0, 0, 44)
	rightRow.BackgroundTransparency = 1
	rightRow.LayoutOrder = 4
	rightRow.Parent = panel
	sceneRightName = label(rightRow, "Enemy", 13, textTone(COLOR_BAD), true)
	sceneRightName.Size = UDim2.new(1, 0, 0, 16)
	local _rightBack, rightFill = progressBar(rightRow, COLOR_BAD, 18)
	rightRow:FindFirstChildWhichIsA("Frame").Position = UDim2.new(0, 0, 0, 20)
	sceneRightBarFill = rightFill

	sceneStatusLabel = label(panel, "", 13, textTone(COLOR_GOLD), true)
	sceneStatusLabel.TextXAlignment = Enum.TextXAlignment.Center
	sceneStatusLabel.LayoutOrder = 5
	sceneStatusLabel.Size = UDim2.new(1, 0, 0, 40)

	sceneCloseButton = button(panel, "Minimize", COLOR_CARD_LIGHT)
	sceneCloseButton.TextColor3 = COLOR_TEXT
	sceneCloseButton.Size = UDim2.new(1, 0, 0, 32)
	sceneCloseButton.LayoutOrder = 6
	sceneCloseButton.Parent = panel
	sceneCloseButton.Activated:Connect(function()
		sceneOverlayRoot.Visible = false
	end)
end

-- ============================================================= Build =====

-- Re-renders whichever tab is currently open using the last known state -
-- used as an immediate response to a window/device resize (see buildRoot)
-- so switching from a PC window to a phone-sized viewport reflows the grid
-- columns right away instead of waiting for the next ~1s state push.
refreshCurrentTab = function()
	if not lastState then
		return
	end
	if activeMainTab == "Home" then
		refreshHomeTab(lastState)
	elseif activeMainTab == "Dungeon" then
		refreshDungeonTab(lastState)
	elseif activeMainTab == "Arena" then
		refreshArenaTab(lastState)
	elseif activeMainTab == "Collection" then
		refreshCollectionTab(lastState)
	elseif activeMainTab == "Tech" then
		refreshTechTab(lastState)
	end
end

local function buildRoot()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ForgeHud"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player:WaitForChild("PlayerGui")

	buildTopBar()
	buildStagePanel()
	buildTabBar()
	buildHomeTab()
	buildDungeonTab()
	buildArenaTab()
	buildCollectionTab()
	buildTechTab()
	buildForgeRibbon()
	buildForgeSheet()
	buildGearSheet()
	buildSceneOverlay()

	setActiveMainTab("Home")
	setActiveCollectionTab("Pets")

	-- Reflow grid columns immediately on resize (window resize on PC, or a
	-- device rotation) instead of waiting for the next state push.
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshCurrentTab)
	end
end

-- ============================================================== API ======

function UIManager.init()
	buildRoot()
end

function UIManager.render(state)
	lastState = state

	oreValueLabel.Text = formatNumber(state.ore)
	coinsValueLabel.Text = formatNumber(state.coins)
	gachaValueLabel.Text = formatNumber(state.gachaCurrency)
	researchValueLabel.Text = formatNumber(state.researchPoints)
	powerValueLabel.Text = formatNumber(state.power)

	stageLabelText.Text = string.format(
		"Stage %s%s",
		state.stageLabel,
		if state.stageCycle > 0 then string.format(" (Cycle %d)", state.stageCycle) else ""
	)
	local dotPosition = ((state.stageStage - 1) % 5) + 1
	for i = 1, 5 do
		local dot = stageDotsFrame:FindFirstChild("Dot" .. i)
		if dot then
			dot.BackgroundColor3 = if i <= dotPosition then COLOR_GOLD else Color3.fromRGB(90, 96, 100)
		end
	end

	if os.clock() > forgeResultClearAt then
		forgeResultLabel.Text = ""
	end
	if os.clock() > stageEventClearAt then
		stageEventLabel.Text = ""
	end

	refreshHomeTab(state)
	if activeMainTab == "Dungeon" then
		refreshDungeonTab(state)
	elseif activeMainTab == "Arena" then
		refreshArenaTab(state)
	elseif activeMainTab == "Collection" then
		refreshCollectionTab(state)
	elseif activeMainTab == "Tech" then
		refreshTechTab(state)
	end
end

-- Fed by the CombatTick remote at ~1Hz - lightweight numeric-only payload,
-- kept separate from the full state push so it can run every tick cheaply.
function UIManager.renderCombatTick(tick)
	enemyNameLabel.Text = string.format("%s (%d/%d left)", tick.label, tick.enemiesLeft, tick.totalEnemies)
	enemyBarFill.Size = UDim2.new(math.clamp(tick.enemyHP / tick.enemyMaxHP, 0, 1), 0, 1, 0)
	playerBarFill.Size = UDim2.new(math.clamp(tick.playerHP / tick.playerMaxHP, 0, 1), 0, 1, 0)
	playerBarFill.BackgroundColor3 = if tick.downed then COLOR_DISABLED else COLOR_GOOD
	playerStatusLabel.Text = if tick.downed then "DOWNED - recovering..." else ""
end

function UIManager.showStageEvent(event)
	if event.kind == "WaveCleared" then
		local advanceText = if event.advanceKind == "Chapter"
			then " - Chapter cleared!"
			elseif event.advanceKind == "Cycle" then " - Endless Cycle (Prestige to unlock more)"
			else ""
		stageEventLabel.Text = string.format(
			"Cleared %s: +%d RP, +%d Gacha%s",
			event.label,
			event.researchGain,
			event.gachaGain,
			advanceText
		)
		stageEventClearAt = os.clock() + 4
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

function UIManager.showHatchResult(result)
	if result.duplicate then
		gachaResultLabel.Text = string.format("Hatched a duplicate %s - now Lv.%d!", result.name, result.level)
	else
		gachaResultLabel.Text = string.format("Hatched %s [%s]!", result.name, result.rarity)
	end
end

function UIManager.showForgeResult(result)
	local parts = {}
	local bestRarityColor = COLOR_TEXT
	for _, item in result.items do
		table.insert(parts, string.format("[%s] %s", item.rarity, item.slot))
		bestRarityColor = textTone(RARITY_COLORS[item.rarity] or bestRarityColor)
	end
	forgeResultLabel.Text = "Forged " .. table.concat(parts, ", ") .. "!"
	forgeResultLabel.TextColor3 = bestRarityColor
	forgeResultClearAt = os.clock() + 4
	if forgeSheetRoot.Visible then
		openForgeSheet()
	end
end

-- ---- Dungeon scene (full-screen "you entered the dungeon" experience) ---

function UIManager.onDungeonSceneEvent(event)
	if event.kind == "Start" or event.kind == "WaveStart" then
		activeDungeonId = event.dungeonId or activeDungeonId
		sceneOverlayRoot.BackgroundColor3 = DUNGEON_TINT[activeDungeonId] or Color3.fromRGB(232, 226, 210)
		sceneTitleLabel.Text = event.label or "Dungeon Run"
		sceneSubLabel.Text = string.format("Wave %d / %d", event.waveIndex or 1, event.totalWaves or 1)
		sceneLeftName.Text = "You"
		sceneRightName.Text = event.enemyName or "Enemy"
		sceneStatusLabel.Text = ""
		sceneLeftBarFill.Size = UDim2.new(1, 0, 1, 0)
		sceneRightBarFill.Size = UDim2.new(1, 0, 1, 0)
		sceneOverlayRoot.Visible = true
	elseif event.kind == "Tick" then
		sceneLeftBarFill.Size = UDim2.new(math.clamp(event.playerHP / event.playerMaxHP, 0, 1), 0, 1, 0)
		sceneLeftBarFill.BackgroundColor3 = if event.downed then COLOR_DISABLED else COLOR_GOOD
		sceneRightBarFill.Size = UDim2.new(math.clamp(event.enemyHP / event.enemyMaxHP, 0, 1), 0, 1, 0)
		sceneStatusLabel.Text = if event.downed then "DOWNED - recovering..." else ""
	elseif event.kind == "WaveCleared" then
		sceneStatusLabel.Text = string.format("Wave %d cleared!", event.waveIndex)
	end
end

function UIManager.onDungeonRunResult(result)
	sceneSubLabel.Text = "Run complete!"

	local reward = result.reward
	local rewardText
	if reward.kind == "Ore" then
		rewardText = string.format("+%s Ore", formatNumber(reward.oreAmount))
	elseif reward.kind == "Egg" then
		rewardText = string.format("+1 %s Egg", reward.eggRarity)
	else
		rewardText = string.format("+1 %s Enchantment", reward.enchantRarity)
	end

	sceneStatusLabel.Text = rewardText .. (if result.newStageUnlocked then " - Next stage unlocked!" else "")
	sceneCloseButton.Text = "Claim & Close"
	sceneOverlayRoot.Visible = true
end

-- ---- Arena scene (full-screen live duel) ---------------------------------

function UIManager.onArenaSceneEvent(event)
	if event.kind == "Searching" then
		sceneOverlayRoot.BackgroundColor3 = Color3.fromRGB(224, 214, 236)
		sceneTitleLabel.Text = "Arena Duel"
		sceneSubLabel.Text = "Searching for an opponent..."
		sceneLeftName.Text = "You"
		sceneRightName.Text = "???"
		sceneLeftBarFill.Size = UDim2.new(1, 0, 1, 0)
		sceneRightBarFill.Size = UDim2.new(1, 0, 1, 0)
		sceneLeftBarFill.BackgroundColor3 = COLOR_GOOD
		sceneStatusLabel.Text = ""
		sceneCloseButton.Text = "Minimize"
		sceneOverlayRoot.Visible = true
	elseif event.kind == "Start" then
		sceneOverlayRoot.BackgroundColor3 = Color3.fromRGB(224, 214, 236)
		sceneTitleLabel.Text = "Arena Duel"
		sceneSubLabel.Text = if event.isBot then "Fight! (bot opponent)" else "Fight! (live opponent)"
		sceneLeftName.Text = "You"
		sceneRightName.Text = event.opponentName or "Rival"
		sceneLeftBarFill.Size = UDim2.new(1, 0, 1, 0)
		sceneRightBarFill.Size = UDim2.new(1, 0, 1, 0)
		sceneLeftBarFill.BackgroundColor3 = COLOR_GOOD
		sceneStatusLabel.Text = ""
		sceneCloseButton.Text = "Minimize"
		sceneOverlayRoot.Visible = true
	elseif event.kind == "Tick" then
		sceneLeftBarFill.Size = UDim2.new(math.clamp(event.playerHP / event.playerMaxHP, 0, 1), 0, 1, 0)
		sceneRightBarFill.Size = UDim2.new(math.clamp(event.opponentHP / event.opponentMaxHP, 0, 1), 0, 1, 0)
	end
end

function UIManager.showArenaResult(result)
	arenaResultLabel.Text = if result.won
		then string.format(
			"Victory vs %s! +%d currency, rating %+d (%d left today)",
			result.opponentName,
			result.gachaReward or 0,
			result.ratingChange,
			result.attemptsLeft
		)
		else string.format("Defeat vs %s. Rating %+d (%d attempts left today)", result.opponentName, result.ratingChange, result.attemptsLeft)

	sceneTitleLabel.Text = "Arena Duel"
	sceneSubLabel.Text = if result.won then "Victory!" else "Defeat"
	sceneStatusLabel.Text = string.format("Rating %+d (now %d)", result.ratingChange, result.ratingAfter)
	sceneStatusLabel.TextColor3 = if result.won then textTone(COLOR_GOOD) else textTone(COLOR_BAD)
	sceneCloseButton.Text = "Close"
	sceneOverlayRoot.Visible = true
end

return UIManager
