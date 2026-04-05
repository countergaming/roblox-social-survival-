local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))

local ProfileService = {}

local profilesByUserId = {}
local isStarted = false

local function getDataStore()
	return DataStoreService:GetDataStore(GameConfig.Persistence.DataStoreName)
end

local function getProfileKey(userId: number): string
	return string.format("profile_%d", userId)
end

local function getRemoteEvent(): RemoteEvent
	local remoteFolder = ReplicatedStorage:WaitForChild(RemoteNames.Folder)
	return remoteFolder:WaitForChild(RemoteNames.ProfileStateChanged) :: RemoteEvent
end

local function buildStatusPayload(status: string, message: string, profile)
	return table.freeze({
		status = status,
		message = message,
		profile = profile,
	})
end

local function pushProfileState(player: Player, status: string, message: string, profile)
	player:SetAttribute("ProfileStatus", status)
	getRemoteEvent():FireClient(player, buildStatusPayload(status, message, profile))
end

local function syncHonorAttributes(player: Player, publicProfile)
	local honors = if publicProfile ~= nil then publicProfile.honors else nil

	player:SetAttribute("HonorDisplayTitle", if honors ~= nil then honors.displayTitle else "")
	player:SetAttribute("HonorBannerTitle", if honors ~= nil then honors.bannerTitle else "")
	player:SetAttribute("HonorRoleTitle", if honors ~= nil then honors.activeRoleHonorTitle else "")
	player:SetAttribute("HonorRiteTitle", if honors ~= nil then honors.activeRiteHonorTitle else "")
end

local function collectHonorTitles(publicProfile)
	local titleLookup = {}

	if publicProfile == nil or publicProfile.honors == nil then
		return titleLookup
	end

	for _, honorSnapshot in ipairs(publicProfile.honors.unlockedRoleHonors or {}) do
		titleLookup[honorSnapshot.title] = true
	end

	for _, honorSnapshot in ipairs(publicProfile.honors.unlockedRiteHonors or {}) do
		titleLookup[honorSnapshot.title] = true
	end

	return titleLookup
end

local function buildRewardMessage(previousPublicProfile, nextPublicProfile): string
	local previousTitles = collectHonorTitles(previousPublicProfile)
	local newTitles = {}

	for honorTitle, _ in pairs(collectHonorTitles(nextPublicProfile)) do
		if previousTitles[honorTitle] ~= true then
			table.insert(newTitles, honorTitle)
		end
	end

	table.sort(newTitles)

	if #newTitles == 0 then
		return "Rewards applied."
	end

	return string.format("Rewards applied. New honors: %s.", table.concat(newTitles, ", "))
end

local function ensureLeaderstats(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")

	if leaderstats == nil then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local statNames = { "Coins", "Level", "XP" }

	for _, statName in ipairs(statNames) do
		if leaderstats:FindFirstChild(statName) == nil then
			local statValue = Instance.new("IntValue")
			statValue.Name = statName
			statValue.Parent = leaderstats
		end
	end

	return leaderstats
end

local function syncLeaderstats(player: Player, publicProfile)
	local leaderstats = ensureLeaderstats(player)

	leaderstats.Coins.Value = publicProfile.coins
	leaderstats.Level.Value = publicProfile.level
	leaderstats.XP.Value = publicProfile.experience
end

local function getOrCreateSessionProfile(player: Player)
	local existingProfile = profilesByUserId[player.UserId]

	if existingProfile ~= nil then
		return existingProfile
	end

	local fallbackProfile = ProfileSchema.markSessionStart(ProfileSchema.createDefaultProfile(player.UserId))
	profilesByUserId[player.UserId] = fallbackProfile

	return fallbackProfile
end

local function fetchStoredProfile(userId: number)
	local persistenceConfig = GameConfig.Persistence
	local profileKey = getProfileKey(userId)

	for attempt = 1, persistenceConfig.SaveRetryCount do
		local success, storedProfile = pcall(function()
			return getDataStore():GetAsync(profileKey)
		end)

		if success then
			return true, storedProfile
		end

		warn(string.format("Profile load failed for %s on attempt %d.", profileKey, attempt))
		task.wait(persistenceConfig.SaveRetryDelaySeconds * attempt)
	end

	return false, nil
end

function ProfileService.loadProfileAsync(player: Player)
	pushProfileState(player, "Loading", "Loading progression...", nil)

	local loadSucceeded, storedProfile = fetchStoredProfile(player.UserId)

	if player.Parent == nil then
		return
	end

	local sessionProfile = ProfileSchema.markSessionStart(ProfileSchema.sanitizeProfile(storedProfile, player.UserId))

	profilesByUserId[player.UserId] = sessionProfile

	local publicProfile = ProfileSchema.buildPublicState(sessionProfile)
	syncLeaderstats(player, publicProfile)
	syncHonorAttributes(player, publicProfile)

	if loadSucceeded then
		pushProfileState(player, "Ready", "Profile loaded.", publicProfile)
	else
		pushProfileState(player, "Error", "Cloud data unavailable. Progress may not save.", publicProfile)
	end
end

function ProfileService.saveProfileAsync(player: Player, reason: string?)
	local existingProfile = profilesByUserId[player.UserId]

	if existingProfile == nil then
		return true
	end

	local persistenceConfig = GameConfig.Persistence
	local profileKey = getProfileKey(player.UserId)
	local preparedProfile = ProfileSchema.touchProfile(existingProfile)

	for attempt = 1, persistenceConfig.SaveRetryCount do
		local success = pcall(function()
			getDataStore():UpdateAsync(profileKey, function()
				return ProfileSchema.prepareForSave(preparedProfile)
			end)
		end)

		if success then
			profilesByUserId[player.UserId] = preparedProfile

			local publicProfile = ProfileSchema.buildPublicState(preparedProfile)
			syncLeaderstats(player, publicProfile)
			syncHonorAttributes(player, publicProfile)

			if reason ~= "autosave" and player.Parent ~= nil then
				pushProfileState(player, "Ready", "Progress saved.", publicProfile)
			end

			return true
		end

		warn(string.format("Profile save failed for %s on attempt %d.", profileKey, attempt))
		task.wait(persistenceConfig.SaveRetryDelaySeconds * attempt)
	end

	pushProfileState(
		player,
		"Error",
		"Saving failed. Progress may be delayed.",
		ProfileSchema.buildPublicState(existingProfile)
	)
	syncHonorAttributes(player, ProfileSchema.buildPublicState(existingProfile))

	return false
end

function ProfileService.applyRoundRewards(player: Player, rewards, roundOutcome, masterySummary)
	local currentProfile = getOrCreateSessionProfile(player)
	local previousPublicProfile = ProfileSchema.buildPublicState(currentProfile)
	local updatedProfile = ProfileSchema.applyRoundRewards(currentProfile, rewards, roundOutcome, masterySummary)

	profilesByUserId[player.UserId] = updatedProfile

	local publicProfile = ProfileSchema.buildPublicState(updatedProfile)
	syncLeaderstats(player, publicProfile)
	syncHonorAttributes(player, publicProfile)
	pushProfileState(player, "Ready", buildRewardMessage(previousPublicProfile, publicProfile), publicProfile)

	return updatedProfile
end

function ProfileService.getPublicProfile(player: Player)
	local existingProfile = profilesByUserId[player.UserId]

	if existingProfile == nil then
		return nil
	end

	return ProfileSchema.buildPublicState(existingProfile)
end

local function startAutoSaveLoop()
	task.spawn(function()
		while true do
			task.wait(GameConfig.Persistence.AutoSaveIntervalSeconds)

			for _, player in ipairs(Players:GetPlayers()) do
				ProfileService.saveProfileAsync(player, "autosave")
			end
		end
	end)
end

function ProfileService.start()
	if isStarted then
		return
	end

	isStarted = true

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			ProfileService.loadProfileAsync(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		ProfileService.saveProfileAsync(player, "leave")
		profilesByUserId[player.UserId] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			ProfileService.loadProfileAsync(player)
		end)
	end

	startAutoSaveLoop()

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			ProfileService.saveProfileAsync(player, "shutdown")
		end
	end)
end

return ProfileService
