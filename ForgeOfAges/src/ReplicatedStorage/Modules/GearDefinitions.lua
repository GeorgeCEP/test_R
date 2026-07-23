-- ReplicatedStorage/Modules/GearDefinitions.lua
-- Data tables for the gear substat system. Ages 1-4 roll 1 substat, age 5+
-- rolls 2 (see getSubstatCount). Values are illustrative placeholders -
-- balance against real playtesting once dungeon difficulty is tuned.

local GearDefinitions = {}

GearDefinitions.Slots = { "Weapon", "Armor", "Accessory" }

-- "flat" stats grow ~12x per age like the economy; "percent" stats grow
-- mildly and are capped so they never exceed a sane percentage.
GearDefinitions.Substats = {
	HP = { label = "Health", kind = "flat", base = 50, growth = 12 },
	Damage = { label = "Damage", kind = "flat", base = 10, growth = 12 },
	RangedDamage = { label = "Ranged Damage", kind = "flat", base = 8, growth = 12 },
	MeleeDamage = { label = "Melee Damage", kind = "flat", base = 8, growth = 12 },
	CritRate = { label = "Crit Rate", kind = "percent", base = 5, perAge = 2, cap = 60 },
	CritDamage = { label = "Crit Damage", kind = "percent", base = 20, perAge = 5, cap = 150 },
	HealthRegen = { label = "Health Regen", kind = "percent", base = 3, perAge = 1.5, cap = 40 },
	AttackSpeed = { label = "Attack Speed", kind = "percent", base = 5, perAge = 2, cap = 50 },
}

GearDefinitions.SubstatIds =
	{ "HP", "Damage", "RangedDamage", "MeleeDamage", "CritRate", "CritDamage", "HealthRegen", "AttackSpeed" }

-- Ages 1-4 roll a single substat; age 5 and beyond roll two.
function GearDefinitions.getSubstatCount(ageId: number): number
	return if ageId <= 4 then 1 else 2
end

GearDefinitions.Rarities = {
	{ id = "Common", weight = 60, valueMultiplier = 0.6, color = Color3.fromRGB(190, 190, 190) },
	{ id = "Rare", weight = 30, valueMultiplier = 0.8, color = Color3.fromRGB(90, 160, 230) },
	{ id = "Epic", weight = 8, valueMultiplier = 1.0, color = Color3.fromRGB(170, 100, 230) },
	{ id = "Legendary", weight = 2, valueMultiplier = 1.3, color = Color3.fromRGB(240, 180, 60) },
}

-- Only Legendary gear has a small chance to roll one of these on top of its
-- normal substats - very rare by design.
GearDefinitions.UniqueEffects = {
	{ id = "Burn", label = "Burn Chance", minChance = 3, maxChance = 10 },
	{ id = "Poison", label = "Poison Chance", minChance = 3, maxChance = 10 },
	{ id = "Stun", label = "Stun Chance", minChance = 3, maxChance = 8 },
}
GearDefinitions.UNIQUE_EFFECT_ROLL_CHANCE = 0.10 -- 10% of Legendary drops also roll a unique effect

function GearDefinitions.getMaxValue(substatId: string, ageId: number): number
	local def = GearDefinitions.Substats[substatId]
	if def.kind == "flat" then
		return def.base * (def.growth ^ (ageId - 1))
	else
		return math.min(def.cap, def.base + def.perAge * (ageId - 1))
	end
end

return GearDefinitions
