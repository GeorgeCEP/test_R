-- ServerStorage/Modules/ForgeSystem.lua
-- Crafting is instant now, not a timed queue: paying the cost immediately
-- produces `slotCount` rolled gear items (one per Forge slot). "Forge slot"
-- is still a Tech Tree upgrade (more items per craft), but "Forge Level" is
-- new and separate - it's bought with Coins (from selling gear, see
-- GearSystem.sell) and shifts the rarity-roll weights toward higher tiers
-- instead of adding slots. Clicking the physical Forge part in the world and
-- the UI's Forge button both call the same craft() - same "server is truth"
-- pattern the old tap-for-Ore version used.

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
local FORGE_UPGRADE_BASE_COST = 250
local FORGE_UPGRADE_GROWTH = 1.4
local RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary" }

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

-- Pay for every slot - a Forge with 3 slots costs 3x a single craft, before
-- the Tech Tree's "Efficient Tongs" discount.
function ForgeSystem.getCraftCost(data): number
	local ageId = EconomySystem.getAgeId(data)
	local slotCount = TechTreeSystem.getForgeSlotCount(data)
	local discount = TechTreeSystem.getBonus(data, "forgeCostDiscountPercent")
	local base = CRAFT_BASE_COST * AgeDefinitions.getScale(ageId) * slotCount
	return math.floor(base * math.max(0.4, 1 - discount / 100))
end

function ForgeSystem.getUpgradeCost(data): number
	return math.floor(FORGE_UPGRADE_BASE_COST * (FORGE_UPGRADE_GROWTH ^ (data.forgeLevel - 1)))
end

-- Illustrative starting curve, same "not simulated yet" caveat as every
-- other balance number here - needs tuning once real gear/stat totals exist.
function ForgeSystem.rollRarity(forgeLevel: number): string
	local bonus = math.max(0, forgeLevel - 1)
	local weights = {
		Common = math.max(5, 55 - bonus * 4),
		Rare = 30,
		Epic = 12 + bonus * 2,
		Legendary = 3 + bonus * 2,
	}

	local total = 0
	for _, weight in weights do
		total += weight
	end

	local roll = math.random() * total
	local cursor = 0
	for _, rarityId in RARITY_ORDER do
		cursor += weights[rarityId]
		if roll <= cursor then
			return rarityId
		end
	end
	return "Common"
end

function ForgeSystem.craft(player: Player, data): { any }?
	local slotCount = TechTreeSystem.getForgeSlotCount(data)
	local cost = ForgeSystem.getCraftCost(data)
	if data.ore < cost then
		return nil
	end
	data.ore -= cost

	local ageId = EconomySystem.getAgeId(data)
	local results = {}
	for _ = 1, slotCount do
		local rarityId = ForgeSystem.rollRarity(data.forgeLevel)
		local item = GearSystem.rollGear(ageId, rarityId)
		table.insert(data.gear, item)
		table.insert(results, item)
	end

	EconomySystem.pushState(player, data)
	return results
end

function ForgeSystem.tryUpgrade(player: Player, data): boolean
	local cost = ForgeSystem.getUpgradeCost(data)
	if data.coins < cost then
		return false
	end
	data.coins -= cost
	data.forgeLevel += 1
	EconomySystem.pushState(player, data)
	return true
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
	local items = ForgeSystem.craft(player, data)
	if items then
		forgeResult:FireClient(player, { items = items })
	end
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
		local items = ForgeSystem.craft(player, data)
		if items then
			forgeResult:FireClient(player, { items = items })
		end
	end)

	NetworkEvents.get("RequestUpgradeForge").OnServerEvent:Connect(function(player)
		local data = DataManager.getData(player)
		if not data then
			return
		end
		ForgeSystem.tryUpgrade(player, data)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastClick[player.UserId] = nil
	end)
end

return ForgeSystem
