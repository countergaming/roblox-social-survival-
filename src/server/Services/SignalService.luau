local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))

local SignalService = {}

local objectiveService = nil
local defenseService = nil
local rescueService = nil
local roleService = nil
local signalFolder = nil
local laneBellEntriesByName = {}
local activeSignals = {}
local activeLink = nil
local playerCooldownEndsAtByUserId = {}
local laneCooldownEndsAtByName = {}
local refreshLoopToken = 0
local EMPTY_LANE_MODIFIERS = table.freeze({
	towerDamageBonus = 0,
	towerRangeBonus = 0,
	barricadeMitigationBonus = 0,
})
local signalState = table.freeze({
	phaseName = "Lobby",
	roundNumber = 0,
	primarySignalLaneName = "",
	primarySignalTitle = "",
	primarySignalDetail = "",
	primarySignalCallerName = "",
	primarySignalCallerRoleTitle = "",
	primarySignalRemainingSeconds = 0,
	activeLinkLaneName = "",
	activeLinkRemainingSeconds = 0,
	activeLinkResponderCount = 0,
	signals = table.freeze({}),
})

local function getRemoteEvent(): RemoteEvent
	local remoteFolder = ReplicatedStorage:WaitForChild(RemoteNames.Folder)
	return remoteFolder:WaitForChild(RemoteNames.SignalStateChanged) :: RemoteEvent
end

local function getSignalFolder()
	if signalFolder ~= nil and signalFolder.Parent ~= nil then
		return signalFolder
	end

	local runtimeFolder = objectiveService.getRuntimeFolder()
	local existingFolder = runtimeFolder:FindFirstChild("WatchBells")

	if existingFolder ~= nil then
		signalFolder = existingFolder
		return signalFolder
	end

	signalFolder = Instance.new("Folder")
	signalFolder.Name = "WatchBells"
	signalFolder.Parent = runtimeFolder

	return signalFolder
end

local function getRemainingSeconds(entry): number
	return math.max(0, math.ceil(entry.expiresAt - os.clock()))
end

local function getActiveLinkRemainingSeconds(): number
	if activeLink == nil then
		return 0
	end

	return math.max(0, math.ceil(activeLink.endsAt - os.clock()))
end

local function getRoleTitleForPlayer(player: Player): string
	local selectedRoleName = roleService.getSelectedRoleName(player)

	if selectedRoleName == "" then
		return "Lanternkeeper"
	end

	local roleTitle = roleService.getRoleTitle(selectedRoleName)

	if roleTitle == "" then
		return "Lanternkeeper"
	end

	return roleTitle
end

local function findLaneSnapshot(laneName: string)
	local defenseState = defenseService.getState()

	for _, laneSnapshot in ipairs(defenseState.lanes or {}) do
		if laneSnapshot.name == laneName then
			return laneSnapshot
		end
	end

	return nil
end

local function findDownedPlayerOnLane(laneName: string)
	local rescueState = rescueService.getState()

	for _, downedPlayer in ipairs(rescueState.downedPlayers or {}) do
		if downedPlayer.laneName == laneName then
			return downedPlayer
		end
	end

	return nil
end

local function getLaneBellColor(activeSignal)
	if activeSignal == nil then
		return Color3.fromRGB(238, 208, 132)
	end

	if activeSignal.signalTypeName == "Rescue" then
		return Color3.fromRGB(255, 126, 104)
	end

	if activeSignal.signalTypeName == "Breach" then
		return Color3.fromRGB(255, 96, 96)
	end

	if activeSignal.signalTypeName == "Spark" then
		return Color3.fromRGB(126, 194, 255)
	end

	if activeSignal.signalTypeName == "Build" then
		return Color3.fromRGB(168, 228, 150)
	end

	return Color3.fromRGB(255, 210, 120)
end

local function buildSignalDefinition(player: Player, laneName: string)
	local laneSnapshot = findLaneSnapshot(laneName)
	local downedPlayer = findDownedPlayerOnLane(laneName)
	local roleTitle = getRoleTitleForPlayer(player)
	local phaseName = signalState.phaseName

	if phaseName == "DayPrep" then
		if laneSnapshot ~= nil and laneSnapshot.barricadeIntegrity < 100 then
			return table.freeze({
				signalTypeName = "Repair",
				title = string.format("Repair %s", laneName),
				detail = string.format(
					"%s is calling builders to restore %s lane before dusk.",
					player.DisplayName,
					laneName
				),
			})
		end

		if laneSnapshot ~= nil and laneSnapshot.towerEnergy < 100 then
			return table.freeze({
				signalTypeName = "Spark",
				title = string.format("Charge %s", laneName),
				detail = string.format("%s wants the %s tower charged before nightfall.", player.DisplayName, laneName),
			})
		end

		if laneSnapshot ~= nil and (laneSnapshot.concordCount or 0) < 2 then
			return table.freeze({
				signalTypeName = "Build",
				title = string.format("Build %s", laneName),
				detail = string.format("%s wants mixed roles on %s lane to awaken Concord.", roleTitle, laneName),
			})
		end

		return table.freeze({
			signalTypeName = "Gather",
			title = string.format("Gather %s", laneName),
			detail = string.format(
				"%s is rallying the team to finish %s lane before dusk.",
				player.DisplayName,
				laneName
			),
		})
	end

	if downedPlayer ~= nil then
		return table.freeze({
			signalTypeName = "Rescue",
			title = string.format("Revive %s", laneName),
			detail = string.format(
				"%s is calling a rescue for %s on %s lane.",
				player.DisplayName,
				downedPlayer.displayName or "a teammate",
				laneName
			),
		})
	end

	if laneSnapshot ~= nil and laneSnapshot.breached then
		return table.freeze({
			signalTypeName = "Breach",
			title = string.format("Seal %s", laneName),
			detail = string.format("%s lane is breached. Wardens and Sparkkeepers rotate now.", laneName),
		})
	end

	if laneSnapshot ~= nil and (laneSnapshot.warningLevel or 0) >= GameConfig.SignalTuning.HeavyWarningLevel then
		return table.freeze({
			signalTypeName = "Hold",
			title = string.format("Hold %s", laneName),
			detail = string.format("%s called heavy pressure on %s lane. Hold together.", player.DisplayName, laneName),
		})
	end

	if laneSnapshot ~= nil and (laneSnapshot.towerEnergy or 0) <= GameConfig.SignalTuning.LowTowerEnergyThreshold then
		return table.freeze({
			signalTypeName = "Spark",
			title = string.format("Spark %s", laneName),
			detail = string.format(
				"%s says the %s tower is fading and needs charge now.",
				player.DisplayName,
				laneName
			),
		})
	end

	if
		laneSnapshot ~= nil
		and (laneSnapshot.barricadeIntegrity or 0) <= GameConfig.SignalTuning.LowBarricadeIntegrityThreshold
	then
		return table.freeze({
			signalTypeName = "Brace",
			title = string.format("Brace %s", laneName),
			detail = string.format(
				"%s says %s lane is cracking. Wardens and melee rotate in.",
				player.DisplayName,
				laneName
			),
		})
	end

	return table.freeze({
		signalTypeName = "Rotate",
		title = string.format("Rotate %s", laneName),
		detail = string.format("%s is rallying teammates to stabilize %s lane.", player.DisplayName, laneName),
	})
end

local function findActiveSignalForLane(laneName: string)
	for _, entry in ipairs(activeSignals) do
		if entry.laneName == laneName and getRemainingSeconds(entry) > 0 then
			return entry
		end
	end

	return nil
end

local function isLinkActiveOnLane(laneName: string): boolean
	return activeLink ~= nil and activeLink.laneName == laneName and getActiveLinkRemainingSeconds() > 0
end

local function updateBellVisuals(laneName: string)
	local bellEntry = laneBellEntriesByName[laneName]

	if bellEntry == nil then
		return
	end

	local activeSignal = findActiveSignalForLane(laneName)
	local linkActive = isLinkActiveOnLane(laneName)
	local bellColor = if linkActive then Color3.fromRGB(132, 255, 172) else getLaneBellColor(activeSignal)

	bellEntry.bell.Color = bellColor
	bellEntry.light.Color = bellColor
	bellEntry.light.Brightness = if linkActive then 4.2 else if activeSignal ~= nil then 3.4 else 1.2
	bellEntry.light.Range = if linkActive then 20 else if activeSignal ~= nil then 18 else 10
	bellEntry.prompt.Enabled = signalState.phaseName == "DayPrep" or signalState.phaseName == "NightSurvival"

	if linkActive and activeLink ~= nil then
		bellEntry.titleLabel.Text = string.format("%s Watch Link", laneName)
		bellEntry.bodyLabel.Text = string.format(
			"%d responder%s answered the bell.\nLane buff %ss",
			activeLink.responderCount,
			if activeLink.responderCount == 1 then "" else "s",
			getActiveLinkRemainingSeconds()
		)
		bellEntry.prompt.ObjectText = string.format("%s lane linked", laneName)
	elseif activeSignal ~= nil then
		bellEntry.titleLabel.Text = activeSignal.title
		bellEntry.bodyLabel.Text = string.format("%s\n%ss left", activeSignal.detail, getRemainingSeconds(activeSignal))
		bellEntry.prompt.ObjectText = string.format("%s lane rally", laneName)
	elseif signalState.phaseName == "DayPrep" then
		bellEntry.titleLabel.Text = string.format("%s Watch Bell", laneName)
		bellEntry.bodyLabel.Text = "Ring to rally builders, charge towers, or stack Concord."
		bellEntry.prompt.ObjectText = string.format("%s lane prep", laneName)
	elseif signalState.phaseName == "NightSurvival" then
		bellEntry.titleLabel.Text = string.format("%s Watch Bell", laneName)
		bellEntry.bodyLabel.Text = "Ring to call help, a revive, or a rotation without chat."
		bellEntry.prompt.ObjectText = string.format("%s lane defense", laneName)
	else
		bellEntry.titleLabel.Text = string.format("%s Watch Bell", laneName)
		bellEntry.bodyLabel.Text = "Bells ring again when the next watch begins."
		bellEntry.prompt.ObjectText = string.format("%s lane", laneName)
	end
end

local function refreshBellVisuals()
	for laneName, _ in pairs(laneBellEntriesByName) do
		updateBellVisuals(laneName)
	end
end

local function pruneExpiredSignals()
	local nextSignals = {}

	for _, entry in ipairs(activeSignals) do
		if getRemainingSeconds(entry) > 0 then
			table.insert(nextSignals, entry)
		end
	end

	activeSignals = nextSignals
end

local function pruneExpiredLink()
	if activeLink ~= nil and getActiveLinkRemainingSeconds() <= 0 then
		activeLink = nil
	end
end

local function getResponderCountForLane(laneName: string): number
	local responderCount = 0
	local beaconPosition = defenseService.getLaneBeaconPosition(laneName)

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil

		if rootPart ~= nil then
			local distanceToLane = (rootPart.Position - beaconPosition).Magnitude

			if distanceToLane <= GameConfig.SignalTuning.ResponderRadius then
				responderCount += 1
			end
		end
	end

	return responderCount
end

local function resolveAnsweredSignals()
	pruneExpiredLink()

	if activeLink ~= nil then
		return
	end

	for index, entry in ipairs(activeSignals) do
		local responderCount = getResponderCountForLane(entry.laneName)

		if responderCount >= GameConfig.SignalTuning.RequiredResponders then
			activeLink = {
				laneName = entry.laneName,
				responderCount = responderCount,
				endsAt = os.clock() + GameConfig.SignalTuning.LinkDurationSeconds,
			}
			table.remove(activeSignals, index)
			return
		end
	end
end

local function rebuildSignalState()
	pruneExpiredSignals()
	resolveAnsweredSignals()
	pruneExpiredLink()

	local signalSnapshots = {}

	for _, entry in ipairs(activeSignals) do
		table.insert(
			signalSnapshots,
			table.freeze({
				laneName = entry.laneName,
				title = entry.title,
				detail = entry.detail,
				callerName = entry.callerName,
				callerRoleTitle = entry.callerRoleTitle,
				remainingSeconds = getRemainingSeconds(entry),
			})
		)
	end

	local primarySignal = signalSnapshots[1]

	signalState = table.freeze({
		phaseName = signalState.phaseName,
		roundNumber = signalState.roundNumber,
		primarySignalLaneName = if primarySignal ~= nil then primarySignal.laneName else "",
		primarySignalTitle = if primarySignal ~= nil then primarySignal.title else "",
		primarySignalDetail = if primarySignal ~= nil then primarySignal.detail else "",
		primarySignalCallerName = if primarySignal ~= nil then primarySignal.callerName else "",
		primarySignalCallerRoleTitle = if primarySignal ~= nil then primarySignal.callerRoleTitle else "",
		primarySignalRemainingSeconds = if primarySignal ~= nil then primarySignal.remainingSeconds else 0,
		activeLinkLaneName = if activeLink ~= nil then activeLink.laneName else "",
		activeLinkRemainingSeconds = getActiveLinkRemainingSeconds(),
		activeLinkResponderCount = if activeLink ~= nil then activeLink.responderCount else 0,
		signals = table.freeze(signalSnapshots),
	})
end

local function pushSignalState(player: Player)
	getRemoteEvent():FireClient(player, signalState)
end

local function broadcastSignalState()
	rebuildSignalState()
	refreshBellVisuals()
	getRemoteEvent():FireAllClients(signalState)
end

local function startRefreshLoop()
	refreshLoopToken += 1

	if #activeSignals == 0 and activeLink == nil then
		return
	end

	local loopToken = refreshLoopToken

	task.spawn(function()
		while loopToken == refreshLoopToken do
			pruneExpiredSignals()
			resolveAnsweredSignals()
			pruneExpiredLink()

			if #activeSignals == 0 and activeLink == nil then
				broadcastSignalState()
				break
			end

			broadcastSignalState()
			task.wait(0.5)
		end
	end)
end

local function buildBellPosition(laneName: string): Vector3
	local beaconPosition = defenseService.getLaneBeaconPosition(laneName)
	local campCenter = objectiveService.getCampCenter()
	local outwardDirection = beaconPosition - campCenter
	local flatDirection = Vector3.new(outwardDirection.X, 0, outwardDirection.Z)

	if flatDirection.Magnitude < 0.001 then
		flatDirection = Vector3.new(0, 0, -1)
	else
		flatDirection = flatDirection.Unit
	end

	return beaconPosition + (flatDirection * GameConfig.SignalTuning.BellRadiusOffset) + Vector3.new(0, -3.1, 0)
end

local function createBellPrompt(parent: Instance, laneName: string)
	local prompt = parent:FindFirstChild("RingPrompt")

	if prompt ~= nil and prompt:IsA("ProximityPrompt") then
		return prompt
	end

	prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RingPrompt"
	prompt.ActionText = "Ring Watch Bell"
	prompt.ObjectText = string.format("%s lane", laneName)
	prompt.HoldDuration = GameConfig.SignalTuning.BellPromptHoldDuration
	prompt.MaxActivationDistance = GameConfig.SignalTuning.BellPromptDistance
	prompt.Parent = parent

	return prompt
end

local function buildLaneBell(laneName: string)
	local folder = getSignalFolder()
	local laneFolder = folder:FindFirstChild(laneName)

	if laneFolder == nil then
		laneFolder = Instance.new("Folder")
		laneFolder.Name = laneName
		laneFolder.Parent = folder
	end

	local bellPosition = buildBellPosition(laneName)

	local post = laneFolder:FindFirstChild("Post")
	if post == nil then
		post = Instance.new("Part")
		post.Name = "Post"
		post.Anchored = true
		post.CanCollide = false
		post.Material = Enum.Material.WoodPlanks
		post.Color = Color3.fromRGB(87, 63, 45)
		post.Parent = laneFolder
	end

	post.Size = Vector3.new(0.9, 4.2, 0.9)
	post.Position = bellPosition + Vector3.new(0, 2.1, 0)

	local bell = laneFolder:FindFirstChild("Bell")
	if bell == nil then
		bell = Instance.new("Part")
		bell.Name = "Bell"
		bell.Anchored = true
		bell.CanCollide = false
		bell.Shape = Enum.PartType.Ball
		bell.Material = Enum.Material.Metal
		bell.Parent = laneFolder

		local light = Instance.new("PointLight")
		light.Name = "BellLight"
		light.Parent = bell

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Label"
		billboard.Size = UDim2.fromOffset(220, 74)
		billboard.StudsOffset = Vector3.new(0, 2.8, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 90
		billboard.Parent = bell

		local container = Instance.new("Frame")
		container.Name = "Container"
		container.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
		container.BackgroundTransparency = 0.14
		container.Size = UDim2.fromScale(1, 1)
		container.Parent = billboard

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = container

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 210, 112)
		stroke.Transparency = 0.32
		stroke.Parent = container

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "TitleLabel"
		titleLabel.BackgroundTransparency = 1
		titleLabel.Position = UDim2.fromOffset(8, 6)
		titleLabel.Size = UDim2.new(1, -16, 0, 18)
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.TextSize = 14
		titleLabel.TextColor3 = Color3.fromRGB(255, 232, 174)
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.Parent = container

		local bodyLabel = Instance.new("TextLabel")
		bodyLabel.Name = "BodyLabel"
		bodyLabel.BackgroundTransparency = 1
		bodyLabel.Position = UDim2.fromOffset(8, 26)
		bodyLabel.Size = UDim2.new(1, -16, 1, -32)
		bodyLabel.Font = Enum.Font.Gotham
		bodyLabel.TextSize = 12
		bodyLabel.TextWrapped = true
		bodyLabel.TextColor3 = Color3.fromRGB(233, 232, 226)
		bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
		bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
		bodyLabel.Parent = container
	end

	bell.Size = Vector3.new(1.8, 1.8, 1.8)
	bell.Position = bellPosition + Vector3.new(0, 4.4, 0)

	local light = bell:FindFirstChild("BellLight") :: PointLight
	local label = bell:FindFirstChild("Label")
	local container = if label ~= nil then label:FindFirstChild("Container") else nil
	local titleLabel = if container ~= nil then container:FindFirstChild("TitleLabel") else nil
	local bodyLabel = if container ~= nil then container:FindFirstChild("BodyLabel") else nil
	local prompt = createBellPrompt(bell, laneName)

	prompt.Triggered:Connect(function(player)
		local nowTime = os.clock()

		if signalState.phaseName ~= "DayPrep" and signalState.phaseName ~= "NightSurvival" then
			return
		end

		if (playerCooldownEndsAtByUserId[player.UserId] or 0) > nowTime then
			return
		end

		if (laneCooldownEndsAtByName[laneName] or 0) > nowTime then
			return
		end

		local signalDefinition = buildSignalDefinition(player, laneName)
		local nextSignals = {}

		for _, entry in ipairs(activeSignals) do
			if entry.laneName ~= laneName and getRemainingSeconds(entry) > 0 then
				table.insert(nextSignals, entry)
			end
		end

		table.insert(nextSignals, 1, {
			laneName = laneName,
			title = signalDefinition.title,
			detail = signalDefinition.detail,
			signalTypeName = signalDefinition.signalTypeName,
			callerName = player.DisplayName,
			callerRoleTitle = getRoleTitleForPlayer(player),
			createdAt = nowTime,
			expiresAt = nowTime + GameConfig.SignalTuning.SignalDurationSeconds,
		})

		while #nextSignals > GameConfig.SignalTuning.MaxActiveSignals do
			table.remove(nextSignals)
		end

		activeSignals = nextSignals
		playerCooldownEndsAtByUserId[player.UserId] = nowTime + GameConfig.SignalTuning.PlayerCooldownSeconds
		laneCooldownEndsAtByName[laneName] = nowTime + GameConfig.SignalTuning.LaneCooldownSeconds
		broadcastSignalState()
		startRefreshLoop()
	end)

	laneBellEntriesByName[laneName] = {
		bell = bell,
		light = light,
		prompt = prompt,
		titleLabel = titleLabel,
		bodyLabel = bodyLabel,
	}
end

local function setPhase(phaseName: string, roundNumber: number)
	activeSignals = {}
	activeLink = nil
	signalState = table.freeze({
		phaseName = phaseName,
		roundNumber = roundNumber,
		primarySignalLaneName = "",
		primarySignalTitle = "",
		primarySignalDetail = "",
		primarySignalCallerName = "",
		primarySignalCallerRoleTitle = "",
		primarySignalRemainingSeconds = 0,
		activeLinkLaneName = "",
		activeLinkRemainingSeconds = 0,
		activeLinkResponderCount = 0,
		signals = table.freeze({}),
	})
	refreshLoopToken += 1
	broadcastSignalState()
end

function SignalService.initialize(dependencies)
	objectiveService = dependencies.objectiveService
	defenseService = dependencies.defenseService
	rescueService = dependencies.rescueService
	roleService = dependencies.roleService

	for _, laneName in ipairs(defenseService.getLaneNames()) do
		buildLaneBell(laneName)
	end

	setPhase("Lobby", 0)
end

function SignalService.startDayPhase(roundNumber: number)
	setPhase("DayPrep", roundNumber)
	return signalState
end

function SignalService.startNightPhase(roundNumber: number)
	setPhase("NightSurvival", roundNumber)
	return signalState
end

function SignalService.finishRound(roundNumber: number)
	setPhase("Results", roundNumber)
	return signalState
end

function SignalService.getState()
	return signalState
end

function SignalService.getLaneModifiers(laneName: string)
	pruneExpiredLink()

	if not isLinkActiveOnLane(laneName) then
		return EMPTY_LANE_MODIFIERS
	end

	return table.freeze({
		towerDamageBonus = GameConfig.SignalTuning.LinkTowerDamageBonus,
		towerRangeBonus = GameConfig.SignalTuning.LinkTowerRangeBonus,
		barricadeMitigationBonus = GameConfig.SignalTuning.LinkBarricadeMitigationBonus,
	})
end

function SignalService.syncPlayer(player: Player)
	pushSignalState(player)
end

return SignalService
