-- ReplicatedStorage/Modules/SkillDefinitions.lua
-- Same gacha pattern as PetDefinitions.lua: fixed bonuses, rarity only
-- affects pull odds. A few Legendary skills grant the rare unique-effect
-- stats (Burn/Poison/Stun) instead of raw damage, mirroring gear.

local SkillDefinitions = {}

SkillDefinitions.Skills = {
	{ id = "skill_stone_throw", name = "Rock Throw", ageId = 1, rarity = "Common", bonuses = { Damage = 8 } },
	{ id = "skill_stone_frenzy", name = "Primal Frenzy", ageId = 1, rarity = "Legendary", bonuses = { AttackSpeed = 8, MeleeDamage = 20 } },

	{ id = "skill_medieval_slash", name = "Broadsword Slash", ageId = 2, rarity = "Common", bonuses = { MeleeDamage = 40 } },
	{ id = "skill_medieval_bless", name = "Knight's Blessing", ageId = 2, rarity = "Legendary", bonuses = { HP = 300, HealthRegen = 4 } },

	{ id = "skill_industrial_shot", name = "Musket Volley", ageId = 3, rarity = "Common", bonuses = { RangedDamage = 220 } },
	{ id = "skill_industrial_forge", name = "Furnace Overdrive", ageId = 3, rarity = "Legendary", bonuses = { Damage = 500, Burn = 6 } },

	{ id = "skill_modern_barrage", name = "Missile Barrage", ageId = 4, rarity = "Common", bonuses = { RangedDamage = 900 } },
	{ id = "skill_modern_shield", name = "Riot Shield", ageId = 4, rarity = "Legendary", bonuses = { HP = 4000, HealthRegen = 6 } },

	{ id = "skill_space_laser", name = "Plasma Lance", ageId = 5, rarity = "Common", bonuses = { Damage = 2500 } },
	{ id = "skill_space_overclock", name = "Reactor Overclock", ageId = 5, rarity = "Legendary", bonuses = { CritDamage = 30, AttackSpeed = 8 } },

	{ id = "skill_digital_hack", name = "System Hack", ageId = 6, rarity = "Common", bonuses = { CritRate = 6 } },
	{ id = "skill_digital_virus", name = "Corrupting Virus", ageId = 6, rarity = "Legendary", bonuses = { Poison = 8, Damage = 6000 } },

	{ id = "skill_alien_beam", name = "Bio-Plasma Beam", ageId = 7, rarity = "Common", bonuses = { Damage = 15000 } },
	{ id = "skill_alien_swarm", name = "Spore Swarm", ageId = 7, rarity = "Legendary", bonuses = { Poison = 10, RangedDamage = 20000 } },

	{ id = "skill_heaven_light", name = "Holy Light", ageId = 8, rarity = "Common", bonuses = { HealthRegen = 8, HP = 40000 } },
	{ id = "skill_heaven_judgement", name = "Divine Judgement", ageId = 8, rarity = "Legendary", bonuses = { Damage = 200000, Stun = 6 } },

	{ id = "skill_hell_flame", name = "Hellfire Wave", ageId = 9, rarity = "Common", bonuses = { Burn = 8, Damage = 80000 } },
	{ id = "skill_hell_curse", name = "Soul Curse", ageId = 9, rarity = "Legendary", bonuses = { Damage = 700000, Stun = 8, CritDamage = 60 } },
}

return SkillDefinitions
