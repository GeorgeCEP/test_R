-- ServerStorage/Modules/GearSystem.lua
-- Rolls gear drops (called by ForgeSystem on every instant craft) and
-- handles equip/unequip/sell. Gear slot is inherent to the item, so
-- equipping just needs the item id - the server looks up which slot it
-- belongs to and swaps whatever was there. Equip/unequip also drive
-- GearVisuals so the item shows up on the avatar (see that module for why
-- this is best-effort, not guaranteed).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local GearDefinitions = require(ReplicatedStorage.Modules.GearDefinitions)
local AgeDefinitions = require(ReplicatedStorage.Modules.AgeDefinitions)
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)
local GearVisuals = require(script.Parent.GearVisuals)

local GearSystem = {}

local SELL_BASE_VALUE = 20 -- Coins, before age scale/rarity multiplier

local function findRarity(rarityId: string)
	for _, entry in GearDefinitions.Rarities do
		if entry.id == rarityId then
			return entry
		end
	end
	return GearDefinitions.Rarities[1]
end

local function computeSellValue(ageId: number, rarity): number
	return math.floor(SELL_BASE_VALUE * AgeDefinitions.getScale(ageId) * rarity.valueMultiplier)
end

local function rollSubstat(ageId: number, rarity)
	local statId = GearDefinitions.SubstatIds[math.random(1, #GearDefinitions.SubstatIds)]
	local maxValue = GearDefinitions.getMaxValue(statId, ageId) * rarity.valueMultiplier
	local value = maxValue * (0.5 + math.random() * 0.5)
	return { stat = statId, value = math.floor(value * 100) / 100 }
end

local function rollUniqueEffect()
	local effect = GearDefinitions.UniqueEffects[math.random(1, #GearDefinitions.UniqueEffects)]
	local chance = effect.minChance + math.random() * (effect.maxChance - effect.minChance)
	return { id = effect.id, label = effect.label, chance = math.floor(chance * 10) / 10 }
end

-- rarityId is forced by the caller now (ForgeSystem rolls it against the
-- Forge Level weight curve) rather than re-rolled here against the flat
-- table weights - those flat weights are still used elsewhere (gacha-style
-- systems, if any ever roll gear directly again).
function GearSystem.rollGear(ageId: number, rarityId: string)
	local rarity = findRarity(rarityId)
	local slot = GearDefinitions.Slots[math.random(1, #GearDefinitions.Slots)]
	local substatCount = GearDefinitions.getSubstatCount(ageId)

	local substats = {}
	local usedStats = {}
	while #substats < substatCount do
		local roll = rollSubstat(ageId, rarity)
		if not usedStats[roll.stat] then
			usedStats[roll.stat] = true
			table.insert(substats, roll)
		end
	end

	local uniqueEffect = nil
	if rarity.id == "Legendary" and math.random() < GearDefinitions.UNIQUE_EFFECT_ROLL_CHANCE then
		uniqueEffect = rollUniqueEffect()
	end

	return {
		id = HttpService:GenerateGUID(false),
		slot = slot,
		ageId = ageId,
		rarity = rarity.id,
		substats = substats,
		uniqueEffect = uniqueEffect,
		-- Computed once here and stored, rather than recomputed at sell time,
		-- same reasoning the substats themselves are stored: it shouldn't
		-- drift if the balance formula changes after the item already exists.
		sellValue = computeSellValue(ageId, rarity),
	}
end

function GearSystem.equip(player: Player, data, itemId: string): boolean
	local item = nil
	for _, gear in data.gear do
		if gear.id == itemId then
			item = gear
			break
		end
	end
	if not item then
		return false
	end

	data.equippedGear[item.slot] = itemId
	EconomySystem.pushState(player, data)

	local character = player.Character
	if character then
		GearVisuals.equip(character, item)
	end
	return true
end

function GearSystem.unequip(player: Player, data, slot: string): boolean
	if not data.equippedGear[slot] then
		return false
	end
	data.equippedGear[slot] = nil
	EconomySystem.pushState(player, data)

	local character = player.Character
	if character then
		GearVisuals.unequip(character, slot)
	end
	return true
end

function GearSystem.sell(player: Player, data, itemId: string): boolean
	local index = nil
	local item = nil
	for i, gear in data.gear do
		if gear.id == itemId then
			index = i
			item = gear
			break
		end
	end
	if not item then
		return false
	end

	if data.equippedGear[item.slot] == itemId then
		data.equippedGear[item.slot] = nil
		local character = player.Character
		if character then
			GearVisuals.unequip(character, item.slot)
		end
	end

	table.remove(data.gear, index)
	data.coins += item.sellValue or 0

	EconomySystem.pushState(player, data)
	return true
end

-- v1 allows unlimited enchantments per item (simplest to ship) - "one per
-- item, re-applying overwrites the old one" is an easy tightening pass
-- later if stacking turns out too strong once real numbers exist (README §2.7).
function GearSystem.applyEnchantment(player: Player, data, itemId: string, enchantmentId: string): boolean
	local item = nil
	for _, gear in data.gear do
		if gear.id == itemId then
			item = gear
			break
		end
	end
	if not item then
		return false
	end

	local enchantIndex, enchantment = nil, nil
	for i, entry in data.enchantments do
		if entry.id == enchantmentId then
			enchantIndex, enchantment = i, entry
			break
		end
	end
	if not enchantment then
		return false
	end

	-- Reuses the same substat shape/rendering gear already has - the UI
	-- doesn't need to know an enchantment produced this entry vs. a roll.
	table.insert(item.substats, { stat = enchantment.statBonus.stat, value = enchantment.statBonus.value })
	table.remove(data.enchantments, enchantIndex)

	EconomySystem.pushState(player, data)
	return true
end

-- Re-applies visuals for whatever's equipped when the character (re)spawns -
-- GearVisuals' accessories live on the character Model, so they don't
-- survive a respawn on their own.
local function reapplyVisuals(player: Player, character: Model)
	local data = DataManager.getData(player)
	if not data then
		return
	end
	for slot, itemId in data.equippedGear do
		if itemId then
			for _, gear in data.gear do
				if gear.id == itemId then
					GearVisuals.equip(character, gear)
					break
				end
			end
		end
	end
end

function GearSystem.init()
	NetworkEvents.get("RequestEquipGear").OnServerEvent:Connect(function(player, itemId)
		if type(itemId) ~= "string" then
			return
		end
		local data = DataManager.getData(player)
		if not data then
			return
		end
		GearSystem.equip(player, data, itemId)
	end)

	NetworkEvents.get("RequestUnequipGear").OnServerEvent:Connect(function(player, slot)
		if type(slot) ~= "string" then
			return
		end
		local data = DataManager.getData(player)
		if not data then
			return
		end
		GearSystem.unequip(player, data, slot)
	end)

	NetworkEvents.get("RequestSellGear").OnServerEvent:Connect(function(player, itemId)
		if type(itemId) ~= "string" then
			return
		end
		local data = DataManager.getData(player)
		if not data then
			return
		end
		GearSystem.sell(player, data, itemId)
	end)

	NetworkEvents.get("RequestApplyEnchantment").OnServerEvent:Connect(function(player, itemId, enchantmentId)
		if type(itemId) ~= "string" or type(enchantmentId) ~= "string" then
			return
		end
		local data = DataManager.getData(player)
		if not data then
			return
		end
		GearSystem.applyEnchantment(player, data, itemId, enchantmentId)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			reapplyVisuals(player, character)
		end)
	end)
end

return GearSystem
