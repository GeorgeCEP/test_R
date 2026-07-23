-- StarterPlayerScripts/Modules/BackgroundSystem.lua
-- Swaps the *feel* of the world per age using only numeric Lighting/
-- Atmosphere properties (no skybox texture asset IDs - this project has
-- never been opened in Studio, see README, so an unverified asset ID is a
-- real risk). Applied entirely client-side: Lighting properties set locally
-- only affect this client's own view, which is exactly what we want since
-- different players can be in different ages/chapters at once.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AgeDefinitions = require(ReplicatedStorage.Modules.AgeDefinitions)

local BackgroundSystem = {}

local TWEEN_INFO = TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local currentAgeId: number? = nil
local atmosphere: Atmosphere

local function ensureAtmosphere(): Atmosphere
	if atmosphere then
		return atmosphere
	end
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing then
		atmosphere = existing :: Atmosphere
	else
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	return atmosphere
end

function BackgroundSystem.applyAge(ageId: number)
	if ageId == currentAgeId then
		return
	end
	currentAgeId = ageId

	local env = AgeDefinitions.get(ageId).environment
	local atmo = ensureAtmosphere()

	TweenService:Create(Lighting, TWEEN_INFO, {
		Ambient = env.ambient,
		OutdoorAmbient = env.outdoorAmbient,
		FogColor = env.fogColor,
		FogEnd = env.fogEnd,
		ClockTime = env.clockTime,
	}):Play()

	TweenService:Create(atmo, TWEEN_INFO, {
		Color = env.atmosphereColor,
		Decay = env.atmosphereDecay,
		Density = env.atmosphereDensity,
		Haze = env.atmosphereHaze,
		Glare = env.atmosphereGlare,
	}):Play()
end

function BackgroundSystem.init()
	ensureAtmosphere()
end

return BackgroundSystem
