-- ReplicatedStorage/Modules/PetDefinitions.lua
-- Hand-authored gacha pool. Each pet is themed to the age it unlocks at
-- (ageId), so the pool of obtainable pets grows as a player advances through
-- the ages. Stat bonuses are flat additions applied via CombatStats.addFlatBonuses.
-- Rarity only affects gacha odds here - the bonus values themselves are fixed
-- per pet (unlike gear, which rolls randomly).

local PetDefinitions = {}

PetDefinitions.Pets = {
	{ id = "pet_stone_cub", name = "Sabertooth Cub", ageId = 1, rarity = "Common", bonuses = { MeleeDamage = 5, CritRate = 1 } },
	{ id = "pet_stone_mammoth", name = "Baby Mammoth", ageId = 1, rarity = "Legendary", bonuses = { HP = 80, MeleeDamage = 15 } },

	{ id = "pet_medieval_hound", name = "War Hound", ageId = 2, rarity = "Common", bonuses = { MeleeDamage = 30, AttackSpeed = 2 } },
	{ id = "pet_medieval_falcon", name = "Battle Falcon", ageId = 2, rarity = "Legendary", bonuses = { RangedDamage = 90, CritRate = 3 } },

	{ id = "pet_industrial_dog", name = "Steam Terrier", ageId = 3, rarity = "Common", bonuses = { HP = 200, AttackSpeed = 3 } },
	{ id = "pet_industrial_golem", name = "Iron Golem", ageId = 3, rarity = "Legendary", bonuses = { HP = 900, MeleeDamage = 120 } },

	{ id = "pet_modern_drone", name = "Recon Drone", ageId = 4, rarity = "Common", bonuses = { RangedDamage = 250, CritRate = 2 } },
	{ id = "pet_modern_tank", name = "Mini Tank", ageId = 4, rarity = "Legendary", bonuses = { HP = 3000, RangedDamage = 500 } },

	{ id = "pet_space_bot", name = "Astro Bot", ageId = 5, rarity = "Common", bonuses = { RangedDamage = 1200, AttackSpeed = 4 } },
	{ id = "pet_space_hound", name = "Cyber Wolf", ageId = 5, rarity = "Legendary", bonuses = { CritRate = 8, CritDamage = 25 } },

	{ id = "pet_digital_wisp", name = "Data Wisp", ageId = 6, rarity = "Common", bonuses = { HealthRegen = 6, HP = 8000 } },
	{ id = "pet_digital_ai", name = "Rogue AI Core", ageId = 6, rarity = "Legendary", bonuses = { Damage = 9000, CritDamage = 35 } },

	{ id = "pet_alien_hatchling", name = "Xeno Hatchling", ageId = 7, rarity = "Common", bonuses = { MeleeDamage = 12000, HealthRegen = 5 } },
	{ id = "pet_alien_queen", name = "Hive Queen", ageId = 7, rarity = "Legendary", bonuses = { HP = 90000, Damage = 20000 } },

	{ id = "pet_heaven_seraph", name = "Seraphling", ageId = 8, rarity = "Common", bonuses = { HealthRegen = 10, HP = 60000 } },
	{ id = "pet_heaven_phoenix", name = "Radiant Phoenix", ageId = 8, rarity = "Legendary", bonuses = { Damage = 150000, CritDamage = 40 } },

	{ id = "pet_hell_imp", name = "Imp Familiar", ageId = 9, rarity = "Common", bonuses = { Damage = 100000, AttackSpeed = 6 } },
	{ id = "pet_hell_devourer", name = "Soul Devourer", ageId = 9, rarity = "Legendary", bonuses = { Damage = 900000, CritRate = 12, CritDamage = 50 } },
}

return PetDefinitions
