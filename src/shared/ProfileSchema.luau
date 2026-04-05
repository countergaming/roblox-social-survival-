local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionMath = require(Shared:WaitForChild("ProgressionMath"))

local ProfileSchema = {}

ProfileSchema.CurrentVersion = 2

local function clampWholeNumber(value: any, minimumValue: number): number
	local numericValue = tonumber(value)

	if numericValue == nil then
		return minimumValue
	end

	return math.max(minimumValue, math.floor(numericValue))
end

local function buildDefaultMasteryMap(order)
	local masteryMap = {}

	for _, name in ipairs(order) do
		masteryMap[name] = 0
	end

	return masteryMap
end

local function sanitizeMasteryMap(rawMasteryMap, order)
	local masteryMap = buildDefaultMasteryMap(order)
	local sourceMap = if type(rawMasteryMap) == "table" then rawMasteryMap else {}

	for _, name in ipairs(order) do
		masteryMap[name] = clampWholeNumber(sourceMap[name], 0)
	end

	return masteryMap
end

local function cloneMasteryMap(sourceMap, order)
	local masteryMap = {}

	for _, name in ipairs(order) do
		masteryMap[name] = sourceMap[name] or 0
	end

	return masteryMap
end

local function buildHonorSnapshot(baseTitle: string, milestone)
	return table.freeze({
		level = milestone.level,
		title = string.format("%s %s", baseTitle, milestone.titleSuffix),
		bannerTitle = string.format("%s %s", baseTitle, milestone.bannerSuffix),
	})
end

local function buildMasterySnapshots(sourceMap, definitions, order, milestones)
	local masterySnapshots = {}

	for _, name in ipairs(order) do
		local experience = sourceMap[name] or 0
		local definition = definitions[name]
		local level = ProgressionMath.getMasteryLevelForExperience(experience)
		local unlockedHonors = {}
		local highestHonorTitle = ""
		local highestBannerTitle = ""

		for _, milestone in ipairs(milestones) do
			if level >= milestone.level then
				local honorSnapshot = buildHonorSnapshot(definition.title, milestone)
				highestHonorTitle = honorSnapshot.title
				highestBannerTitle = honorSnapshot.bannerTitle
				table.insert(unlockedHonors, honorSnapshot)
			end
		end

		table.insert(
			masterySnapshots,
			table.freeze({
				name = name,
				title = definition.title,
				summary = definition.summary,
				experience = experience,
				level = level,
				currentLevelExperience = ProgressionMath.getMasteryExperienceIntoCurrentLevel(experience),
				nextLevelExperience = ProgressionMath.getMasteryExperienceNeededForNextLevel(experience),
				highestHonorTitle = highestHonorTitle,
				highestBannerTitle = highestBannerTitle,
				unlockedHonors = table.freeze(unlockedHonors),
			})
		)
	end

	return table.freeze(masterySnapshots)
end

local function getTopMasterySnapshot(masterySnapshots)
	local bestSnapshot = nil

	for _, masterySnapshot in ipairs(masterySnapshots) do
		if
			bestSnapshot == nil
			or masterySnapshot.level > bestSnapshot.level
			or (masterySnapshot.level == bestSnapshot.level and masterySnapshot.experience > bestSnapshot.experience)
		then
			bestSnapshot = masterySnapshot
		end
	end

	return bestSnapshot
end

local function flattenUnlockedHonors(masterySnapshots)
	local honorSnapshots = {}

	for _, masterySnapshot in ipairs(masterySnapshots) do
		for _, honorSnapshot in ipairs(masterySnapshot.unlockedHonors or {}) do
			table.insert(
				honorSnapshots,
				table.freeze({
					sourceName = masterySnapshot.name,
					sourceTitle = masterySnapshot.title,
					level = honorSnapshot.level,
					title = honorSnapshot.title,
					bannerTitle = honorSnapshot.bannerTitle,
				})
			)
		end
	end

	table.sort(honorSnapshots, function(left, right)
		if left.level == right.level then
			return left.title < right.title
		end

		return left.level < right.level
	end)

	return table.freeze(honorSnapshots)
end

local function buildFrozenProfile(profileData)
	return table.freeze({
		version = ProfileSchema.CurrentVersion,
		userId = profileData.userId,
		currency = table.freeze({
			coins = profileData.currency.coins,
		}),
		progression = table.freeze({
			experience = profileData.progression.experience,
			level = profileData.progression.level,
			roundsCompleted = profileData.progression.roundsCompleted,
			bestNight = profileData.progression.bestNight,
			sessionsPlayed = profileData.progression.sessionsPlayed,
		}),
		mastery = table.freeze({
			roles = table.freeze(profileData.mastery.roles),
			rites = table.freeze(profileData.mastery.rites),
		}),
		settings = table.freeze({
			musicEnabled = profileData.settings.musicEnabled,
			sfxEnabled = profileData.settings.sfxEnabled,
		}),
		timestamps = table.freeze({
			createdAt = profileData.timestamps.createdAt,
			lastSeenAt = profileData.timestamps.lastSeenAt,
		}),
	})
end

local function cloneSettings(rawSettings)
	local settingsTable = if type(rawSettings) == "table" then rawSettings else {}

	return {
		musicEnabled = if type(settingsTable.musicEnabled) == "boolean" then settingsTable.musicEnabled else true,
		sfxEnabled = if type(settingsTable.sfxEnabled) == "boolean" then settingsTable.sfxEnabled else true,
	}
end

function ProfileSchema.createDefaultProfile(userId: number)
	local timestamp = os.time()

	return buildFrozenProfile({
		userId = userId,
		currency = {
			coins = 0,
		},
		progression = {
			experience = 0,
			level = 1,
			roundsCompleted = 0,
			bestNight = 0,
			sessionsPlayed = 0,
		},
		mastery = {
			roles = buildDefaultMasteryMap(GameConfig.RoleTuning.Order),
			rites = buildDefaultMasteryMap(GameConfig.RiteTuning.Order),
		},
		settings = {
			musicEnabled = true,
			sfxEnabled = true,
		},
		timestamps = {
			createdAt = timestamp,
			lastSeenAt = timestamp,
		},
	})
end

function ProfileSchema.sanitizeProfile(rawProfile: any, userId: number)
	local profileTable = if type(rawProfile) == "table" then rawProfile else {}
	local currencyTable = if type(profileTable.currency) == "table" then profileTable.currency else {}
	local progressionTable = if type(profileTable.progression) == "table" then profileTable.progression else {}
	local masteryTable = if type(profileTable.mastery) == "table" then profileTable.mastery else {}
	local timestampsTable = if type(profileTable.timestamps) == "table" then profileTable.timestamps else {}

	local createdAt = clampWholeNumber(timestampsTable.createdAt, os.time())
	local experience = clampWholeNumber(progressionTable.experience, 0)

	return buildFrozenProfile({
		userId = userId,
		currency = {
			coins = clampWholeNumber(currencyTable.coins, 0),
		},
		progression = {
			experience = experience,
			level = ProgressionMath.getLevelForExperience(experience),
			roundsCompleted = clampWholeNumber(progressionTable.roundsCompleted, 0),
			bestNight = clampWholeNumber(progressionTable.bestNight, 0),
			sessionsPlayed = clampWholeNumber(progressionTable.sessionsPlayed, 0),
		},
		mastery = {
			roles = sanitizeMasteryMap(masteryTable.roles, GameConfig.RoleTuning.Order),
			rites = sanitizeMasteryMap(masteryTable.rites, GameConfig.RiteTuning.Order),
		},
		settings = cloneSettings(profileTable.settings),
		timestamps = {
			createdAt = createdAt,
			lastSeenAt = clampWholeNumber(timestampsTable.lastSeenAt, createdAt),
		},
	})
end

function ProfileSchema.markSessionStart(profile)
	return buildFrozenProfile({
		userId = profile.userId,
		currency = {
			coins = profile.currency.coins,
		},
		progression = {
			experience = profile.progression.experience,
			level = profile.progression.level,
			roundsCompleted = profile.progression.roundsCompleted,
			bestNight = profile.progression.bestNight,
			sessionsPlayed = profile.progression.sessionsPlayed + 1,
		},
		mastery = {
			roles = cloneMasteryMap(profile.mastery.roles, GameConfig.RoleTuning.Order),
			rites = cloneMasteryMap(profile.mastery.rites, GameConfig.RiteTuning.Order),
		},
		settings = {
			musicEnabled = profile.settings.musicEnabled,
			sfxEnabled = profile.settings.sfxEnabled,
		},
		timestamps = {
			createdAt = profile.timestamps.createdAt,
			lastSeenAt = os.time(),
		},
	})
end

function ProfileSchema.applyRoundRewards(profile, rewards, roundOutcome, masterySummary)
	local nextExperience = profile.progression.experience + rewards.experience
	local nextRoundsCompleted = profile.progression.roundsCompleted + 1
	local nextBestNight = math.max(profile.progression.bestNight, roundOutcome.nightNumber)
	local nextRoleMastery = cloneMasteryMap(profile.mastery.roles, GameConfig.RoleTuning.Order)
	local nextRiteMastery = cloneMasteryMap(profile.mastery.rites, GameConfig.RiteTuning.Order)

	if masterySummary ~= nil and masterySummary.role ~= nil then
		local roleName = masterySummary.role.name

		if nextRoleMastery[roleName] ~= nil then
			nextRoleMastery[roleName] += clampWholeNumber(masterySummary.role.experience, 0)
		end
	end

	if masterySummary ~= nil and masterySummary.rite ~= nil then
		local riteName = masterySummary.rite.name

		if nextRiteMastery[riteName] ~= nil then
			nextRiteMastery[riteName] += clampWholeNumber(masterySummary.rite.experience, 0)
		end
	end

	return buildFrozenProfile({
		userId = profile.userId,
		currency = {
			coins = profile.currency.coins + rewards.coins,
		},
		progression = {
			experience = nextExperience,
			level = ProgressionMath.getLevelForExperience(nextExperience),
			roundsCompleted = nextRoundsCompleted,
			bestNight = nextBestNight,
			sessionsPlayed = profile.progression.sessionsPlayed,
		},
		mastery = {
			roles = nextRoleMastery,
			rites = nextRiteMastery,
		},
		settings = {
			musicEnabled = profile.settings.musicEnabled,
			sfxEnabled = profile.settings.sfxEnabled,
		},
		timestamps = {
			createdAt = profile.timestamps.createdAt,
			lastSeenAt = os.time(),
		},
	})
end

function ProfileSchema.touchProfile(profile)
	return buildFrozenProfile({
		userId = profile.userId,
		currency = {
			coins = profile.currency.coins,
		},
		progression = {
			experience = profile.progression.experience,
			level = profile.progression.level,
			roundsCompleted = profile.progression.roundsCompleted,
			bestNight = profile.progression.bestNight,
			sessionsPlayed = profile.progression.sessionsPlayed,
		},
		mastery = {
			roles = cloneMasteryMap(profile.mastery.roles, GameConfig.RoleTuning.Order),
			rites = cloneMasteryMap(profile.mastery.rites, GameConfig.RiteTuning.Order),
		},
		settings = {
			musicEnabled = profile.settings.musicEnabled,
			sfxEnabled = profile.settings.sfxEnabled,
		},
		timestamps = {
			createdAt = profile.timestamps.createdAt,
			lastSeenAt = os.time(),
		},
	})
end

function ProfileSchema.prepareForSave(profile)
	return {
		version = ProfileSchema.CurrentVersion,
		currency = {
			coins = profile.currency.coins,
		},
		progression = {
			experience = profile.progression.experience,
			level = profile.progression.level,
			roundsCompleted = profile.progression.roundsCompleted,
			bestNight = profile.progression.bestNight,
			sessionsPlayed = profile.progression.sessionsPlayed,
		},
		mastery = {
			roles = cloneMasteryMap(profile.mastery.roles, GameConfig.RoleTuning.Order),
			rites = cloneMasteryMap(profile.mastery.rites, GameConfig.RiteTuning.Order),
		},
		settings = {
			musicEnabled = profile.settings.musicEnabled,
			sfxEnabled = profile.settings.sfxEnabled,
		},
		timestamps = {
			createdAt = profile.timestamps.createdAt,
			lastSeenAt = profile.timestamps.lastSeenAt,
		},
	}
end

function ProfileSchema.buildPublicState(profile)
	local currentLevelExperience = ProgressionMath.getExperienceIntoCurrentLevel(profile.progression.experience)
	local experienceNeeded = ProgressionMath.getExperienceNeededForNextLevel(profile.progression.experience)
	local roleSnapshots = buildMasterySnapshots(
		profile.mastery.roles,
		GameConfig.RoleTuning.Roles,
		GameConfig.RoleTuning.Order,
		GameConfig.MasteryTuning.RoleHonorMilestones
	)
	local riteSnapshots = buildMasterySnapshots(
		profile.mastery.rites,
		GameConfig.RiteTuning.Rites,
		GameConfig.RiteTuning.Order,
		GameConfig.MasteryTuning.RiteHonorMilestones
	)
	local topRoleSnapshot = getTopMasterySnapshot(roleSnapshots)
	local topRiteSnapshot = getTopMasterySnapshot(riteSnapshots)
	local unlockedRoleHonors = flattenUnlockedHonors(roleSnapshots)
	local unlockedRiteHonors = flattenUnlockedHonors(riteSnapshots)

	return table.freeze({
		coins = profile.currency.coins,
		experience = profile.progression.experience,
		level = profile.progression.level,
		bestNight = profile.progression.bestNight,
		roundsCompleted = profile.progression.roundsCompleted,
		sessionsPlayed = profile.progression.sessionsPlayed,
		currentLevelExperience = currentLevelExperience,
		nextLevelExperience = experienceNeeded,
		mastery = table.freeze({
			roles = roleSnapshots,
			rites = riteSnapshots,
		}),
		honors = table.freeze({
			activeRoleHonorTitle = if topRoleSnapshot ~= nil then topRoleSnapshot.highestHonorTitle else "",
			activeRoleBannerTitle = if topRoleSnapshot ~= nil then topRoleSnapshot.highestBannerTitle else "",
			activeRiteHonorTitle = if topRiteSnapshot ~= nil then topRiteSnapshot.highestHonorTitle else "",
			activeRiteBannerTitle = if topRiteSnapshot ~= nil then topRiteSnapshot.highestBannerTitle else "",
			displayTitle = if topRoleSnapshot ~= nil and topRoleSnapshot.highestHonorTitle ~= ""
				then topRoleSnapshot.highestHonorTitle
				elseif
					topRiteSnapshot ~= nil and topRiteSnapshot.highestHonorTitle ~= ""
				then topRiteSnapshot.highestHonorTitle
				else "",
			bannerTitle = if topRoleSnapshot ~= nil and topRoleSnapshot.highestBannerTitle ~= ""
				then topRoleSnapshot.highestBannerTitle
				elseif
					topRiteSnapshot ~= nil and topRiteSnapshot.highestBannerTitle ~= ""
				then topRiteSnapshot.highestBannerTitle
				else "",
			unlockedRoleHonors = unlockedRoleHonors,
			unlockedRiteHonors = unlockedRiteHonors,
			totalUnlockedCount = #unlockedRoleHonors + #unlockedRiteHonors,
		}),
	})
end

return ProfileSchema
