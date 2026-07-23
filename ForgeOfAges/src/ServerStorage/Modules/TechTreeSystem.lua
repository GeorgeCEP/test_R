-- ServerStorage/Modules/TechTreeSystem.lua
-- Purchases and bonus aggregation for the tech tree. data.techTree is a plain
-- { [nodeId]: level } map. Other systems call TechTreeSystem.getBonus(data,
-- effectKey) rather than reading data.techTree directly, so adding a node
-- never requires touching EconomySystem/CombatStats/ForgeSystem.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TechTreeDefinitions = require(ReplicatedStorage.Modules.TechTreeDefinitions)
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)

local TechTreeSystem = {}

function TechTreeSystem.getLevel(data, nodeId: string): number
	return data.techTree[nodeId] or 0
end

-- Sums effectPerLevel * ownedLevel across every node that shares this
-- effectKey (e.g. multiple nodes could both contribute "damagePercent").
function TechTreeSystem.getBonus(data, effectKey: string): number
	local total = 0
	for _, node in TechTreeDefinitions.Nodes do
		if node.effectKey == effectKey then
			local level = TechTreeSystem.getLevel(data, node.id)
			total += level * node.effectPerLevel
		end
	end
	return total
end

function TechTreeSystem.getForgeSlotCount(data): number
	return 1 + math.floor(TechTreeSystem.getBonus(data, "forgeSlot"))
end

function TechTreeSystem.canAfford(data, nodeId: string): boolean
	local node = TechTreeDefinitions.get(nodeId)
	if not node then
		return false
	end
	local level = TechTreeSystem.getLevel(data, nodeId)
	if level >= node.maxLevel then
		return false
	end
	if node.prerequisite and TechTreeSystem.getLevel(data, node.prerequisite) < 1 then
		return false
	end
	return data.researchPoints >= TechTreeDefinitions.getCost(node, level)
end

function TechTreeSystem.purchase(player: Player, data, nodeId: string): boolean
	if not TechTreeSystem.canAfford(data, nodeId) then
		return false
	end

	local node = TechTreeDefinitions.get(nodeId) :: any
	local level = TechTreeSystem.getLevel(data, nodeId)
	local cost = TechTreeDefinitions.getCost(node, level)

	data.researchPoints -= cost
	data.techTree[nodeId] = level + 1

	-- Lazy require: EconomySystem requires TechTreeSystem (for passive-ore
	-- bonuses), so this can't be a top-level require without creating a cycle.
	require(script.Parent.EconomySystem).pushState(player, data)
	return true
end

function TechTreeSystem.init()
	NetworkEvents.get("RequestTechUpgrade").OnServerEvent:Connect(function(player, nodeId)
		if type(nodeId) ~= "string" then
			return
		end
		local data = DataManager.getData(player)
		if not data then
			return
		end
		TechTreeSystem.purchase(player, data, nodeId)
	end)
end

return TechTreeSystem
