-- ReplicatedStorage/Modules/TechTreeDefinitions.lua
-- Replaces the old "buy buildings for passive income" loop. Research Points
-- (earned from stage clears, see StageDefinitions) buy permanent levels here.
-- Effects are keyed percentages/flags that TechTreeSystem.getBonus aggregates
-- and EconomySystem/CombatStats/ForgeSystem read - add a node by appending an
-- entry, no other module needs to change.

export type TechNodeDef = {
	id: string,
	name: string,
	description: string,
	maxLevel: number,
	baseCost: number,
	costGrowth: number,
	effectKey: string,
	effectPerLevel: number,
	prerequisite: string?,
}

local TechTreeDefinitions = {}

local nodes: { TechNodeDef } = {
	{
		id = "damage",
		name = "Weapon Mastery",
		description = "+5% stage damage per level",
		maxLevel = 20,
		baseCost = 5,
		costGrowth = 1.35,
		effectKey = "damagePercent",
		effectPerLevel = 5,
	},
	{
		id = "vitality",
		name = "Vitality",
		description = "+6% max HP per level",
		maxLevel = 20,
		baseCost = 5,
		costGrowth = 1.35,
		effectKey = "maxHPPercent",
		effectPerLevel = 6,
	},
	{
		id = "passive_ore",
		name = "Automated Mining",
		description = "+8% passive Ore/sec per level",
		maxLevel = 25,
		baseCost = 4,
		costGrowth = 1.3,
		effectKey = "passiveOrePercent",
		effectPerLevel = 8,
	},
	{
		id = "stage_ore",
		name = "Plundering",
		description = "+8% Ore from stage clears per level",
		maxLevel = 25,
		baseCost = 4,
		costGrowth = 1.3,
		effectKey = "stageOrePercent",
		effectPerLevel = 8,
	},
	{
		id = "research_gain",
		name = "Field Research",
		description = "+10% Research Points from stage clears per level",
		maxLevel = 15,
		baseCost = 6,
		costGrowth = 1.4,
		effectKey = "researchPercent",
		effectPerLevel = 10,
	},
	{
		id = "forge_speed",
		name = "Efficient Tongs",
		description = "-6% forge craft time per level",
		maxLevel = 10,
		baseCost = 6,
		costGrowth = 1.35,
		effectKey = "forgeSpeedPercent",
		effectPerLevel = 6,
	},
	{
		id = "forge_slot_2",
		name = "Second Forge",
		description = "Unlocks a second forge slot - craft two items at once",
		maxLevel = 1,
		baseCost = 60,
		costGrowth = 1,
		effectKey = "forgeSlot",
		effectPerLevel = 1,
	},
	{
		id = "forge_slot_3",
		name = "Third Forge",
		description = "Unlocks a third forge slot",
		maxLevel = 1,
		baseCost = 400,
		costGrowth = 1,
		effectKey = "forgeSlot",
		effectPerLevel = 1,
		prerequisite = "forge_slot_2",
	},
}

TechTreeDefinitions.Nodes = nodes

function TechTreeDefinitions.get(nodeId: string): TechNodeDef?
	for _, node in TechTreeDefinitions.Nodes do
		if node.id == nodeId then
			return node
		end
	end
	return nil
end

-- Cost to buy the *next* level, given the level currently owned (0 = unowned).
function TechTreeDefinitions.getCost(node: TechNodeDef, currentLevel: number): number
	return math.floor(node.baseCost * (node.costGrowth ^ currentLevel))
end

return TechTreeDefinitions
