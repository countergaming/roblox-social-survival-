local ProgressionMath = {}

local BASE_EXPERIENCE = 50
local PER_LEVEL_GROWTH = 20
local MASTERY_BASE_EXPERIENCE = 30
local MASTERY_PER_LEVEL_GROWTH = 15

local function getExperienceForNextLevel(level: number, baseExperience: number, growth: number): number
	return baseExperience + ((level - 1) * growth)
end

local function getLevelForExperienceWithCurve(totalExperience: number, baseExperience: number, growth: number): number
	local normalizedExperience = math.max(0, math.floor(totalExperience))
	local currentLevel = 1
	local remainingExperience = normalizedExperience

	while remainingExperience >= getExperienceForNextLevel(currentLevel, baseExperience, growth) do
		remainingExperience -= getExperienceForNextLevel(currentLevel, baseExperience, growth)
		currentLevel += 1
	end

	return currentLevel
end

local function getExperienceIntoCurrentLevelWithCurve(
	totalExperience: number,
	baseExperience: number,
	growth: number
): number
	local normalizedExperience = math.max(0, math.floor(totalExperience))
	local currentLevel = 1
	local remainingExperience = normalizedExperience

	while remainingExperience >= getExperienceForNextLevel(currentLevel, baseExperience, growth) do
		remainingExperience -= getExperienceForNextLevel(currentLevel, baseExperience, growth)
		currentLevel += 1
	end

	return remainingExperience
end

function ProgressionMath.getLevelForExperience(totalExperience: number): number
	return getLevelForExperienceWithCurve(totalExperience, BASE_EXPERIENCE, PER_LEVEL_GROWTH)
end

function ProgressionMath.getExperienceIntoCurrentLevel(totalExperience: number): number
	return getExperienceIntoCurrentLevelWithCurve(totalExperience, BASE_EXPERIENCE, PER_LEVEL_GROWTH)
end

function ProgressionMath.getExperienceNeededForNextLevel(totalExperience: number): number
	local currentLevel = ProgressionMath.getLevelForExperience(totalExperience)
	return getExperienceForNextLevel(currentLevel, BASE_EXPERIENCE, PER_LEVEL_GROWTH)
end

function ProgressionMath.getMasteryLevelForExperience(totalExperience: number): number
	return getLevelForExperienceWithCurve(totalExperience, MASTERY_BASE_EXPERIENCE, MASTERY_PER_LEVEL_GROWTH)
end

function ProgressionMath.getMasteryExperienceIntoCurrentLevel(totalExperience: number): number
	return getExperienceIntoCurrentLevelWithCurve(totalExperience, MASTERY_BASE_EXPERIENCE, MASTERY_PER_LEVEL_GROWTH)
end

function ProgressionMath.getMasteryExperienceNeededForNextLevel(totalExperience: number): number
	local currentLevel = ProgressionMath.getMasteryLevelForExperience(totalExperience)
	return getExperienceForNextLevel(currentLevel, MASTERY_BASE_EXPERIENCE, MASTERY_PER_LEVEL_GROWTH)
end

return ProgressionMath
