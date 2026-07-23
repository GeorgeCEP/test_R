-- ServerStorage/Modules/LoadoutSystem.lua
-- Equip/unequip for pets and skills (up to 3 slots each). Gear equip lives in
-- GearSystem since a gear item's slot is inherent to the item; pets/skills
-- use plain numbered slots instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)

local LoadoutSystem = {}

local MAX_SLOTS = 3

local function isOwned(ownedList, id): boolean
	for _, ownedId in ownedList do
		if ownedId == id then
			return true
		end
	end
	return false
end

local function findOpenSlot(equippedList): number
	for i = 1, MAX_SLOTS do
		if equippedList[i] == nil then
			return i
		end
	end
	return 1 -- overwrite the first slot if all are full
end

function LoadoutSystem.equip(player: Player, data, kind: string, id: string?, slotIndex: number?): boolean
	if id == nil and slotIndex == nil then
		return false
	end

	local ownedList = if kind == "Pet" then data.pets else data.skills
	local equippedList = if kind == "Pet" then data.equippedPetIds else data.equippedSkillIds

	if id ~= nil and not isOwned(ownedList, id) then
		return false
	end

	local targetSlot = slotIndex
	if id ~= nil and (targetSlot == nil or targetSlot < 1 or targetSlot > MAX_SLOTS) then
		targetSlot = findOpenSlot(equippedList)
	end

	if targetSlot == nil or targetSlot < 1 or targetSlot > MAX_SLOTS then
		return false
	end

	equippedList[targetSlot] = id
	EconomySystem.pushState(player, data)
	return true
end

function LoadoutSystem.init()
	NetworkEvents.get("RequestEquipCollectible").OnServerEvent:Connect(function(player, kind, id, slotIndex)
		if kind ~= "Pet" and kind ~= "Skill" then
			return
		end
		if id ~= nil and type(id) ~= "string" then
			return
		end
		if slotIndex ~= nil and type(slotIndex) ~= "number" then
			return
		end

		local data = DataManager.getData(player)
		if not data then
			return
		end

		LoadoutSystem.equip(player, data, kind, id, slotIndex)
	end)
end

return LoadoutSystem
