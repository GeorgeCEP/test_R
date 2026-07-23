-- ReplicatedStorage/Modules/AgeDefinitions.lua
-- Data-driven age ladder. Ages are now purely a *theme* (resource name, gear
-- scale, environment colors) - progression through them is driven by
-- StageDefinitions/StageSystem clearing chapters, not by a manual "Age Up"
-- purchase. Add a new age by appending one entry to AGE_META below; gear
-- scale and environment theming follow automatically.

export type EnvironmentDef = {
	ambient: Color3,
	outdoorAmbient: Color3,
	fogColor: Color3,
	fogEnd: number,
	atmosphereColor: Color3,
	atmosphereDecay: Color3,
	atmosphereDensity: number,
	atmosphereHaze: number,
	atmosphereGlare: number,
	clockTime: number,
}

export type AgeDef = {
	id: number,
	name: string,
	resourceLabel: string,
	environment: EnvironmentDef,
}

local AGE_META = {
	{
		name = "Stone Age",
		resourceLabel = "Stone",
		environment = {
			ambient = Color3.fromRGB(90, 75, 55),
			outdoorAmbient = Color3.fromRGB(130, 115, 90),
			fogColor = Color3.fromRGB(150, 130, 95),
			fogEnd = 900,
			atmosphereColor = Color3.fromRGB(199, 170, 118),
			atmosphereDecay = Color3.fromRGB(92, 60, 40),
			atmosphereDensity = 0.35,
			atmosphereHaze = 2,
			atmosphereGlare = 0.2,
			clockTime = 14,
		},
	},
	{
		name = "Medieval Age",
		resourceLabel = "Iron",
		environment = {
			ambient = Color3.fromRGB(60, 65, 70),
			outdoorAmbient = Color3.fromRGB(100, 105, 100),
			fogColor = Color3.fromRGB(120, 130, 120),
			fogEnd = 800,
			atmosphereColor = Color3.fromRGB(180, 190, 180),
			atmosphereDecay = Color3.fromRGB(70, 80, 70),
			atmosphereDensity = 0.3,
			atmosphereHaze = 1.5,
			atmosphereGlare = 0.15,
			clockTime = 10,
		},
	},
	{
		name = "Industrial Age",
		resourceLabel = "Coal",
		environment = {
			ambient = Color3.fromRGB(50, 45, 45),
			outdoorAmbient = Color3.fromRGB(80, 75, 70),
			fogColor = Color3.fromRGB(90, 85, 80),
			fogEnd = 550,
			atmosphereColor = Color3.fromRGB(120, 110, 100),
			atmosphereDecay = Color3.fromRGB(60, 55, 50),
			atmosphereDensity = 0.55,
			atmosphereHaze = 4,
			atmosphereGlare = 0.1,
			clockTime = 16,
		},
	},
	{
		name = "Modern Age",
		resourceLabel = "Steel",
		environment = {
			ambient = Color3.fromRGB(55, 60, 70),
			outdoorAmbient = Color3.fromRGB(95, 100, 110),
			fogColor = Color3.fromRGB(140, 150, 165),
			fogEnd = 1000,
			atmosphereColor = Color3.fromRGB(190, 200, 215),
			atmosphereDecay = Color3.fromRGB(70, 75, 85),
			atmosphereDensity = 0.25,
			atmosphereHaze = 1,
			atmosphereGlare = 0.3,
			clockTime = 12,
		},
	},
	{
		name = "Space Age",
		resourceLabel = "Alloy",
		environment = {
			ambient = Color3.fromRGB(20, 22, 35),
			outdoorAmbient = Color3.fromRGB(30, 32, 50),
			fogColor = Color3.fromRGB(10, 10, 25),
			fogEnd = 1400,
			atmosphereColor = Color3.fromRGB(40, 45, 80),
			atmosphereDecay = Color3.fromRGB(10, 10, 30),
			atmosphereDensity = 0.4,
			atmosphereHaze = 3,
			atmosphereGlare = 0.6,
			clockTime = 0,
		},
	},
	{
		name = "Digital Age",
		resourceLabel = "Data",
		environment = {
			ambient = Color3.fromRGB(10, 30, 35),
			outdoorAmbient = Color3.fromRGB(15, 45, 50),
			fogColor = Color3.fromRGB(5, 40, 45),
			fogEnd = 1100,
			atmosphereColor = Color3.fromRGB(30, 200, 190),
			atmosphereDecay = Color3.fromRGB(5, 40, 40),
			atmosphereDensity = 0.35,
			atmosphereHaze = 2.5,
			atmosphereGlare = 0.8,
			clockTime = 0,
		},
	},
	{
		name = "Alien Age",
		resourceLabel = "Bio-Crystal",
		environment = {
			ambient = Color3.fromRGB(35, 15, 45),
			outdoorAmbient = Color3.fromRGB(60, 25, 75),
			fogColor = Color3.fromRGB(70, 20, 90),
			fogEnd = 750,
			atmosphereColor = Color3.fromRGB(160, 60, 200),
			atmosphereDecay = Color3.fromRGB(50, 15, 65),
			atmosphereDensity = 0.5,
			atmosphereHaze = 4,
			atmosphereGlare = 0.4,
			clockTime = 22,
		},
	},
	{
		name = "Heaven",
		resourceLabel = "Aether",
		environment = {
			ambient = Color3.fromRGB(200, 195, 160),
			outdoorAmbient = Color3.fromRGB(240, 235, 200),
			fogColor = Color3.fromRGB(255, 250, 220),
			fogEnd = 1600,
			atmosphereColor = Color3.fromRGB(255, 250, 225),
			atmosphereDecay = Color3.fromRGB(200, 190, 150),
			atmosphereDensity = 0.2,
			atmosphereHaze = 1,
			atmosphereGlare = 1.2,
			clockTime = 12,
		},
	},
	{
		name = "Hell",
		resourceLabel = "Brimstone",
		environment = {
			ambient = Color3.fromRGB(45, 10, 10),
			outdoorAmbient = Color3.fromRGB(70, 15, 10),
			fogColor = Color3.fromRGB(90, 15, 5),
			fogEnd = 500,
			atmosphereColor = Color3.fromRGB(180, 40, 20),
			atmosphereDecay = Color3.fromRGB(60, 10, 5),
			atmosphereDensity = 0.6,
			atmosphereHaze = 5,
			atmosphereGlare = 0.3,
			clockTime = 0,
		},
	},
}

-- Gear substat values and passive-ore base rates scale ~12x per age, same
-- curve the economy has always used.
local AGE_SCALE = 12

local AgeDefinitions = {}

local ages: { AgeDef } = {}
for index, meta in AGE_META do
	table.insert(ages, {
		id = index,
		name = meta.name,
		resourceLabel = meta.resourceLabel,
		environment = meta.environment,
	})
end

AgeDefinitions.Ages = ages
AgeDefinitions.AGE_SCALE = AGE_SCALE

function AgeDefinitions.get(ageId: number): AgeDef
	return ages[math.clamp(ageId, 1, #ages)]
end

function AgeDefinitions.getScale(ageId: number): number
	return AGE_SCALE ^ (math.clamp(ageId, 1, #ages) - 1)
end

return AgeDefinitions
