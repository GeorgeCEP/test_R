-- ServerStorage/Modules/LoadoutSystem.lua
-- Skills still use plain numbered slots (up to 3, gacha-rolled - see
-- GachaSystem). Pets no longer do: data.pets carries its own `equipped`
-- flag per instance (see PetSystem/DataManager), so "up to 3 equipped" is
-- just a count check, not slot-index bookkeeping. Gear equip lives in
-- GearSystem since a gear item's slot is inherent to the item.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)

local LoadoutSystem = {}

local MAX_SLOTS = 3
local MAX_EQUIPPED_PETS = 3

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

-- Skills only - see LoadoutSystem.setPetEquipped for Pets.
function LoadoutSystem.equip(player: Player, data, id: string?, slotIndex: number?): boolean
	if id == nil and slotIndex == nil then
		return false
	end

	local ownedList = data.skills
	local equippedList = data.equippedSkillIds

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

function LoadoutSystem.setPetEquipped(player: Player, data, defId: string, equipped: boolean): boolean
	local entry = nil
	for _, pet in data.pets do
		if pet.defId == defId then
			entry = pet
			break
		end
	end
	if not entry then
		return false
	end

	if equipped and not entry.equipped then
		local equippedCount = 0
		for _, pet in data.pets do
			if pet.equipped then
				equippedCount += 1
			end
		end
		if equippedCount >= MAX_EQUIPPED_PETS then
			return false
		end
	end

	entry.equipped = equipped
	EconomySystem.pushState(player, data)
	return true
end

function LoadoutSystem.init()
	NetworkEvents.get("RequestEquipCollectible").OnServerEvent:Connect(function(player, kind, id, slotIndex)
		if kind ~= "Skill" then
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

		LoadoutSystem.equip(player, data, id, slotIndex)
	end)

	NetworkEvents.get("RequestSetPetEquipped").OnServerEvent:Connect(function(player, defId, equipped)
		if type(defId) ~= "string" or type(equipped) ~= "boolean" then
			return
		end

		local data = DataManager.getData(player)
		if not data then
			return
		end

		LoadoutSystem.setPetEquipped(player, data, defId, equipped)
	end)
end

return LoadoutSystem
