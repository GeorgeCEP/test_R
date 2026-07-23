-- ReplicatedStorage/Modules/CombatStats.lua
-- Pure math: aggregates gear/pet/skill bonuses into one stat sheet and
-- collapses that sheet into a single comparable "Power" scalar used by the
-- dungeon and arena stat-check resolvers. No state, safe to share both sides.

local CombatStats = {}

local STAT_KEYS = {
	"HP",
	"Damage",
	"RangedDamage",
	"MeleeDamage",
	"CritRate",
	"CritDamage",
	"HealthRegen",
	"AttackSpeed",
	"Burn",
	"Poison",
	"Stun",
}

function CombatStats.newStats()
	local stats = {}
	for _, key in STAT_KEYS do
		stats[key] = 0
	end
	return stats
end

function CombatStats.addGear(stats, gearItem)
	for _, sub in gearItem.substats do
		stats[sub.stat] = (stats[sub.stat] or 0) + sub.value
	end
	if gearItem.uniqueEffect then
		local id = gearItem.uniqueEffect.id
		stats[id] = (stats[id] or 0) + gearItem.uniqueEffect.chance
	end
end

function CombatStats.addFlatBonuses(stats, bonuses)
	if not bonuses then
		return
	end
	for stat, value in bonuses do
		stats[stat] = (stats[stat] or 0) + value
	end
end

-- Not meant to model "real" combat - it's a weighted scalar so dungeons and
-- the arena can resolve instantly as a stat-check simulation.
function CombatStats.computePower(stats): number
	local critMultiplier = 1 + (stats.CritRate / 100) * (stats.CritDamage / 100)
	local speedMultiplier = 1 + (stats.AttackSpeed / 100)
	local effectiveDamage = (stats.Damage + stats.RangedDamage + stats.MeleeDamage) * critMultiplier * speedMultiplier
	local effectiveHealth = stats.HP * (1 + stats.HealthRegen / 100)
	local uniqueEffectBonus = 1 + ((stats.Burn + stats.Poison + stats.Stun) / 100) * 0.5

	return (effectiveDamage + effectiveHealth * 0.15) * uniqueEffectBonus
end

return CombatStats
