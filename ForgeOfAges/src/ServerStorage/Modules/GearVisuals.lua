-- ServerStorage/Modules/GearVisuals.lua
-- Turns an equipped gear item into something visible on the avatar via
-- InsertService:LoadAsset + Humanoid:AddAccessory - this is the *mechanism*
-- only. Which specific catalog IDs to use per slot+rarity is curated by
-- hand in MarketplaceAssets.lua, and that table ships empty until someone
-- browses the catalog in Studio's Avatar Editor and fills it in (see its
-- header - there's no script API to do that browsing for you). Until then,
-- equip/unequip still work correctly for stats, they just don't change how
-- the avatar looks yet.
--
-- Runs server-side only, inside GearSystem.equip/unequip - the accessory
-- needs to exist on the server's copy of the character to replicate to
-- every other player in the server, not just show up locally.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceAssets = require(ReplicatedStorage.Modules.MarketplaceAssets)

local GearVisuals = {}

local function tagFor(slot: string): string
	return "GearVisual_" .. slot
end

local function pickAssetId(slot: string, rarity: string): number?
	local bySlot = MarketplaceAssets[slot]
	local pool = bySlot and bySlot[rarity]
	if not pool or #pool == 0 then
		return nil
	end
	return pool[math.random(1, #pool)]
end

-- Named per-slot (not per-item) so equipping a new item in the same slot
-- cleanly replaces the old accessory instead of stacking visuals.
function GearVisuals.unequip(character: Model, slot: string)
	local existing = character:FindFirstChild(tagFor(slot))
	if existing then
		existing:Destroy()
	end
end

function GearVisuals.equip(character: Model, item)
	GearVisuals.unequip(character, item.slot)

	local assetId = pickAssetId(item.slot, item.rarity)
	if not assetId then
		return -- no curated asset for this slot+rarity yet - stats still apply, just no visual
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Assets get deleted or moderated after being hardcoded here, so a
	-- failed load must never block the stat side of equipping - warn and
	-- move on instead of erroring.
	local ok, model = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not model then
		warn("[GearVisuals] Failed to load asset", assetId, "for", item.slot, item.rarity)
		return
	end

	local accessory = model:FindFirstChildOfClass("Accessory")
	if accessory then
		accessory.Name = tagFor(item.slot)
		humanoid:AddAccessory(accessory)
	end
	model:Destroy()
end

return GearVisuals
