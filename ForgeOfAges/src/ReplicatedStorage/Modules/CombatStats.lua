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

-- Not meant to model "real" combat - it's a weighted scalar so the arena can
-- resolve a bot fight instantly as a stat-check simulation.
function CombatStats.computePower(stats): number
	local critMultiplier = 1 + (stats.CritRate / 100) * (stats.CritDamage / 100)
	local speedMultiplier = 1 + (stats.AttackSpeed / 100)
	local effectiveDamage = (stats.Damage + stats.RangedDamage + stats.MeleeDamage) * critMultiplier * speedMultiplier
	local effectiveHealth = stats.HP * (1 + stats.HealthRegen / 100)
	local uniqueEffectBonus = 1 + ((stats.Burn + stats.Poison + stats.Stun) / 100) * 0.5

	return (effectiveDamage + effectiveHealth * 0.15) * uniqueEffectBonus
end

-- Flat floors so a fresh, ungeared player still has nonzero DPS/HP - stage
-- combat is a DPS race (see StageSystem), never a hard RNG wall, but a zero
-- floor would still make the very first wave take forever to even scratch.
local BASE_DPS = 4
local BASE_HP = 80

-- Concrete numbers for the real-time stage combat tick loop, as opposed to
-- computePower's single abstract scalar. techBonusPercent is a table of
-- {damagePercent, maxHPPercent} from TechTreeSystem.getBonus.
function CombatStats.computeCombatant(stats, techBonusPercent)
	techBonusPercent = techBonusPercent or {}
	local critMultiplier = 1 + (stats.CritRate / 100) * (stats.CritDamage / 100)
	local speedMultiplier = 1 + (stats.AttackSpeed / 100)
	local rawDamage = stats.Damage + stats.RangedDamage + stats.MeleeDamage
	local dps = (BASE_DPS + rawDamage) * critMultiplier * speedMultiplier * (1 + (techBonusPercent.damagePercent or 0) / 100)

	local maxHP = (BASE_HP + stats.HP) * (1 + (techBonusPercent.maxHPPercent or 0) / 100)
	-- HealthRegen is "% of max HP restored per ~50 seconds" - a slow idle trickle, not a combat sustain stat.
	local regenPerSecond = maxHP * (stats.HealthRegen / 100) * 0.02

	return { dps = dps, maxHP = maxHP, regenPerSecond = regenPerSecond }
end

return CombatStats
