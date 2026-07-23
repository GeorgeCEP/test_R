-- ServerStorage/Modules/GearSystem.lua
-- Rolls gear drops (called by ForgeSystem when a craft job finishes) and
-- handles equip/unequip.
-- Gear slot is inherent to the item, so equipping just needs the item id -
-- the server looks up which slot it belongs to and swaps whatever was there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local GearDefinitions = require(ReplicatedStorage.Modules.GearDefinitions)
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)

local GearSystem = {}

local function pickWeighted(entries, weightKey)
	local total = 0
	for _, entry in entries do
		total += entry[weightKey]
	end
	local roll = math.random() * total
	local cursor = 0
	for _, entry in entries do
		cursor += entry[weightKey]
		if roll <= cursor then
			return entry
		end
	end
	return entries[#entries]
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

function GearSystem.rollGear(ageId: number)
	local rarity = pickWeighted(GearDefinitions.Rarities, "weight")
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
	return true
end

function GearSystem.unequip(player: Player, data, slot: string): boolean
	if not data.equippedGear[slot] then
		return false
	end
	data.equippedGear[slot] = nil
	EconomySystem.pushState(player, data)
	return true
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
end

return GearSystem
