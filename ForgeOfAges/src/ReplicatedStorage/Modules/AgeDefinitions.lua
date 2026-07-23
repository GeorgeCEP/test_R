-- ReplicatedStorage/Modules/AgeDefinitions.lua
-- Data-driven age ladder. Add a new age by appending one entry to AGE_META below;
-- building costs/outputs and prestige cap logic scale automatically.

export type BuildingDef = {
	id: string,
	name: string,
	baseCost: number,
	baseOutput: number,
	costGrowth: number,
}

export type AgeDef = {
	id: number,
	name: string,
	resourceLabel: string,
	tapBase: number,
	ageUpCost: number?,
	buildings: { BuildingDef },
}

local AGE_META = {
	{ name = "Stone Age", resourceLabel = "Stone", tapBase = 1, ageUpCost = 500 },
	{ name = "Medieval Age", resourceLabel = "Iron", tapBase = 8, ageUpCost = 6000 },
	{ name = "Industrial Age", resourceLabel = "Coal", tapBase = 60, ageUpCost = 75000 },
	{ name = "Modern Age", resourceLabel = "Steel", tapBase = 450, ageUpCost = 900000 },
	{ name = "Space Age", resourceLabel = "Alloy", tapBase = 3200, ageUpCost = 12000000 },
	{ name = "Digital Age", resourceLabel = "Data", tapBase = 24000, ageUpCost = 150000000 },
	{ name = "Alien Age", resourceLabel = "Bio-Crystal", tapBase = 180000, ageUpCost = 2000000000 },
	{ name = "Heaven", resourceLabel = "Aether", tapBase = 1300000, ageUpCost = 26000000000 },
	{ name = "Hell", resourceLabel = "Brimstone", tapBase = 9000000, ageUpCost = nil },
}

-- Two building archetypes reused every age, scaled up per age tier.
local BUILDING_TEMPLATES = {
	{ id = "worker", name = "Worker", baseCost = 10, baseOutput = 0.5, costGrowth = 1.15 },
	{ id = "facility", name = "Facility", baseCost = 150, baseOutput = 5, costGrowth = 1.17 },
}

local AGE_SCALE = 12 -- each age's economy is ~12x the previous
local PRESTIGE_BASE_CAP = 5 -- Space Age index; first prestige unlocks the next tier beyond it

local AgeDefinitions = {}

local ages: { AgeDef } = {}
for index, meta in AGE_META do
	local scale = AGE_SCALE ^ (index - 1)
	local buildings: { BuildingDef } = {}
	for _, template in BUILDING_TEMPLATES do
		table.insert(buildings, {
			id = template.id,
			name = template.name,
			baseCost = template.baseCost * scale,
			baseOutput = template.baseOutput * scale,
			costGrowth = template.costGrowth,
		})
	end

	table.insert(ages, {
		id = index,
		name = meta.name,
		resourceLabel = meta.resourceLabel,
		tapBase = meta.tapBase,
		ageUpCost = meta.ageUpCost,
		buildings = buildings,
	})
end

AgeDefinitions.Ages = ages

function AgeDefinitions.get(ageId: number): AgeDef
	return ages[ageId]
end

function AgeDefinitions.getBuilding(ageId: number, buildingId: string): BuildingDef?
	local age = ages[ageId]
	if not age then
		return nil
	end
	for _, building in age.buildings do
		if building.id == buildingId then
			return building
		end
	end
	return nil
end

-- Each prestige raises the reachable age cap by one tier beyond Space Age,
-- so the exotic ages (Digital/Alien/Heaven/Hell) are unlocked one rebirth at a time.
function AgeDefinitions.getMaxAgeUnlocked(prestigeCount: number): number
	return math.min(#ages, PRESTIGE_BASE_CAP + prestigeCount)
end

return AgeDefinitions
