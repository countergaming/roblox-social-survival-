local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))

local RiteFocusService = {}

local EMPTY_LANE_MODIFIERS = table.freeze({
	towerDamageBonus = 0,
	towerRangeBonus = 0,
	barricadeMitigationBonus = 0,
})

local EMPTY_THREAT_MODIFIERS = table.freeze({
	speedMultiplier = 1,
})

local EMPTY_COMBAT_MODIFIERS = table.freeze({
	pulseDamageBonus = 0,
	pulseCooldownDelta = 0,
	pulseRadiusBonus = 0,
})

local objectiveService = nil
local defenseService = nil
local riteService = nil
local focusFolder = nil
local focusEntriesByLaneName = {}
local laneCooldownEndsAtByName = {}
local refreshLoopToken = 0
local activeFocus = nil
local focusState = table.freeze({
	phaseName = "Lobby",
	roundNumber = 0,
	selectedRiteName = "",
	selectedRiteTitle = "",
	selectedRiteSummary = "",
	activeLaneName = "",
	activeTitle = "",
	activeSummary = "",
	activeRemainingSeconds = 0,
	lanes = table.freeze({}),
})

local function getRemoteEvent(): RemoteEvent
	local remoteFolder = ReplicatedStorage:WaitForChild(RemoteNames.Folder)
	return remoteFolder:WaitForChild(RemoteNames.RiteFocusStateChanged) :: RemoteEvent
end

local function getFocusFolder()
	if focusFolder ~= nil and focusFolder.Parent ~= nil then
		return focusFolder
	end

	local runtimeFolder = objectiveService.getRuntimeFolder()
	local existingFolder = runtimeFolder:FindFirstChild("RiteFoci")

	if existingFolder ~= nil then
		focusFolder = existingFolder
		return focusFolder
	end

	focusFolder = Instance.new("Folder")
	focusFolder.Name = "RiteFoci"
	focusFolder.Parent = runtimeFolder

	return focusFolder
end

local function getSelectedRiteConfig()
	if focusState.selectedRiteName == "" then
		return nil
	end

	return GameConfig.RiteFocusTuning.Rites[focusState.selectedRiteName]
end

local function getActiveRemainingSeconds(): number
	if activeFocus == nil then
		return 0
	end

	return math.max(0, math.ceil(activeFocus.endsAt - os.clock()))
end

local function getLaneCooldownRemainingSeconds(laneName: string): number
	return math.max(0, math.ceil((laneCooldownEndsAtByName[laneName] or 0) - os.clock()))
end

local function pruneExpiredFocus()
	if activeFocus ~= nil and getActiveRemainingSeconds() <= 0 then
		activeFocus = nil
	end
end

local function hasAnyCooldowns(): boolean
	local expiredLaneNames = {}

	for laneName, endsAt in pairs(laneCooldownEndsAtByName) do
		if endsAt > os.clock() then
			return true
		end

		table.insert(expiredLaneNames, laneName)
	end

	for _, laneName in ipairs(expiredLaneNames) do
		laneCooldownEndsAtByName[laneName] = nil
	end

	return false
end

local function buildFocusPosition(laneName: string): Vector3
	local beaconPosition = defenseService.getLaneBeaconPosition(laneName)
	local campCenter = objectiveService.getCampCenter()
	local outwardDirection = beaconPosition - campCenter
	local flatDirection = Vector3.new(outwardDirection.X, 0, outwardDirection.Z)

	if flatDirection.Magnitude < 0.001 then
		flatDirection = Vector3.new(0, 0, -1)
	else
		flatDirection = flatDirection.Unit
	end

	return beaconPosition + (flatDirection * GameConfig.RiteFocusTuning.FocusOffset) + Vector3.new(0, -3, 0)
end

local function updateFocusVisuals(laneName: string)
	local focusEntry = focusEntriesByLaneName[laneName]

	if focusEntry == nil then
		return
	end

	pruneExpiredFocus()

	local isNight = focusState.phaseName == "NightSurvival"
	local riteConfig = getSelectedRiteConfig()
	local isActive = activeFocus ~= nil and activeFocus.laneName == laneName
	local cooldownRemainingSeconds = getLaneCooldownRemainingSeconds(laneName)
	local baseColor = if riteConfig ~= nil
		then GameConfig.RiteTuning.Rites[focusState.selectedRiteName].color
		else Color3.fromRGB(205, 189, 142)

	focusEntry.focus.Color = if isActive then Color3.fromRGB(255, 244, 176) else baseColor
	focusEntry.light.Color = if isActive then Color3.fromRGB(255, 236, 162) else baseColor
	focusEntry.light.Brightness = if isActive then 4.2 else if isNight and riteConfig ~= nil then 1.8 else 0.8
	focusEntry.light.Range = if isActive then 20 else if isNight and riteConfig ~= nil then 12 else 8
	focusEntry.prompt.Enabled = isNight and riteConfig ~= nil and not isActive and cooldownRemainingSeconds <= 0

	if isActive and activeFocus ~= nil then
		focusEntry.titleLabel.Text = string.format("%s Active", activeFocus.title)
		focusEntry.bodyLabel.Text = string.format("%s\n%ss remaining", activeFocus.summary, getActiveRemainingSeconds())
		focusEntry.prompt.ActionText = activeFocus.actionText
		focusEntry.prompt.ObjectText = string.format("%s lane active", laneName)
		return
	end

	if riteConfig ~= nil and isNight then
		focusEntry.titleLabel.Text = string.format("%s Focus", focusState.selectedRiteTitle)

		if cooldownRemainingSeconds > 0 then
			focusEntry.bodyLabel.Text =
				string.format("%s\nCooldown %ss", riteConfig.focusSummary, cooldownRemainingSeconds)
		else
			focusEntry.bodyLabel.Text =
				string.format("%s\nHold to invoke on %s lane.", riteConfig.focusSummary, laneName)
		end

		focusEntry.prompt.ActionText = riteConfig.actionText
		focusEntry.prompt.ObjectText = string.format("%s lane focus", laneName)
		return
	end

	focusEntry.titleLabel.Text = string.format("%s Font", laneName)
	focusEntry.bodyLabel.Text = "The active rite can be channeled here once night begins."
	focusEntry.prompt.ActionText = "Await Rite"
	focusEntry.prompt.ObjectText = string.format("%s lane", laneName)
end

local function refreshFocusVisuals()
	for laneName, _ in pairs(focusEntriesByLaneName) do
		updateFocusVisuals(laneName)
	end
end

local function rebuildState()
	pruneExpiredFocus()

	local laneSnapshots = {}

	for _, laneName in ipairs(defenseService.getLaneNames()) do
		table.insert(
			laneSnapshots,
			table.freeze({
				name = laneName,
				cooldownRemainingSeconds = getLaneCooldownRemainingSeconds(laneName),
				isActive = activeFocus ~= nil and activeFocus.laneName == laneName,
			})
		)
	end

	focusState = table.freeze({
		phaseName = focusState.phaseName,
		roundNumber = focusState.roundNumber,
		selectedRiteName = focusState.selectedRiteName,
		selectedRiteTitle = focusState.selectedRiteTitle,
		selectedRiteSummary = focusState.selectedRiteSummary,
		activeLaneName = if activeFocus ~= nil then activeFocus.laneName else "",
		activeTitle = if activeFocus ~= nil then activeFocus.title else "",
		activeSummary = if activeFocus ~= nil then activeFocus.summary else "",
		activeRemainingSeconds = getActiveRemainingSeconds(),
		lanes = table.freeze(laneSnapshots),
	})
end

local function broadcastState()
	rebuildState()
	refreshFocusVisuals()
	getRemoteEvent():FireAllClients(focusState)
end

local function pushState(player: Player)
	rebuildState()
	getRemoteEvent():FireClient(player, focusState)
end

local function startRefreshLoop()
	refreshLoopToken += 1

	if activeFocus == nil and not hasAnyCooldowns() then
		return
	end

	local loopToken = refreshLoopToken

	task.spawn(function()
		while loopToken == refreshLoopToken do
			pruneExpiredFocus()

			if activeFocus == nil and not hasAnyCooldowns() then
				broadcastState()
				break
			end

			broadcastState()
			task.wait(0.5)
		end
	end)
end

local function createPrompt(parent: Instance, laneName: string)
	local prompt = parent:FindFirstChild("InvokePrompt")

	if prompt ~= nil and prompt:IsA("ProximityPrompt") then
		return prompt
	end

	prompt = Instance.new("ProximityPrompt")
	prompt.Name = "InvokePrompt"
	prompt.ActionText = "Await Rite"
	prompt.ObjectText = string.format("%s lane", laneName)
	prompt.HoldDuration = GameConfig.RiteFocusTuning.PromptHoldDuration
	prompt.MaxActivationDistance = GameConfig.RiteFocusTuning.PromptDistance
	prompt.Parent = parent

	return prompt
end

local function buildLaneFocus(laneName: string)
	local folder = getFocusFolder()
	local laneFolder = folder:FindFirstChild(laneName)

	if laneFolder == nil then
		laneFolder = Instance.new("Folder")
		laneFolder.Name = laneName
		laneFolder.Parent = folder
	end

	local focusPosition = buildFocusPosition(laneName)

	local pedestal = laneFolder:FindFirstChild("Pedestal")
	if pedestal == nil then
		pedestal = Instance.new("Part")
		pedestal.Name = "Pedestal"
		pedestal.Anchored = true
		pedestal.CanCollide = false
		pedestal.Material = Enum.Material.Slate
		pedestal.Color = Color3.fromRGB(86, 88, 98)
		pedestal.Parent = laneFolder
	end

	pedestal.Size = Vector3.new(3.2, 1.4, 3.2)
	pedestal.Position = focusPosition + Vector3.new(0, 0.7, 0)

	local focus = laneFolder:FindFirstChild("Focus")
	if focus == nil then
		focus = Instance.new("Part")
		focus.Name = "Focus"
		focus.Anchored = true
		focus.CanCollide = false
		focus.Shape = Enum.PartType.Ball
		focus.Material = Enum.Material.Neon
		focus.Parent = laneFolder

		local light = Instance.new("PointLight")
		light.Name = "FocusLight"
		light.Parent = focus

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Label"
		billboard.Size = UDim2.fromOffset(220, 82)
		billboard.StudsOffset = Vector3.new(0, 3.2, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 90
		billboard.Parent = focus

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

	focus.Size = Vector3.new(2.2, 2.2, 2.2)
	focus.Position = focusPosition + Vector3.new(0, 2.6, 0)

	local light = focus:FindFirstChild("FocusLight") :: PointLight
	local label = focus:FindFirstChild("Label")
	local container = if label ~= nil then label:FindFirstChild("Container") else nil
	local titleLabel = if container ~= nil then container:FindFirstChild("TitleLabel") else nil
	local bodyLabel = if container ~= nil then container:FindFirstChild("BodyLabel") else nil
	local prompt = createPrompt(focus, laneName)

	prompt.Triggered:Connect(function()
		if focusState.phaseName ~= "NightSurvival" or activeFocus ~= nil then
			return
		end

		local riteConfig = getSelectedRiteConfig()

		if riteConfig == nil or getLaneCooldownRemainingSeconds(laneName) > 0 then
			return
		end

		local nowTime = os.clock()
		local immediate = riteConfig.immediate

		activeFocus = {
			laneName = laneName,
			title = riteConfig.focusTitle,
			summary = riteConfig.focusSummary,
			actionText = riteConfig.actionText,
			endsAt = nowTime + GameConfig.RiteFocusTuning.FocusDurationSeconds,
		}
		laneCooldownEndsAtByName[laneName] = nowTime + GameConfig.RiteFocusTuning.LaneCooldownSeconds
		defenseService.applyLaneRestoration(
			laneName,
			immediate.barricadeRestore or 0,
			immediate.towerEnergyRestore or 0
		)
		broadcastState()
		startRefreshLoop()
	end)

	focusEntriesByLaneName[laneName] = {
		focus = focus,
		light = light,
		prompt = prompt,
		titleLabel = titleLabel,
		bodyLabel = bodyLabel,
	}
end

local function setPhase(
	phaseName: string,
	roundNumber: number,
	selectedRiteName: string,
	selectedRiteTitle: string,
	selectedRiteSummary: string
)
	activeFocus = nil
	laneCooldownEndsAtByName = {}
	focusState = table.freeze({
		phaseName = phaseName,
		roundNumber = roundNumber,
		selectedRiteName = selectedRiteName,
		selectedRiteTitle = selectedRiteTitle,
		selectedRiteSummary = selectedRiteSummary,
		activeLaneName = "",
		activeTitle = "",
		activeSummary = "",
		activeRemainingSeconds = 0,
		lanes = table.freeze({}),
	})
	refreshLoopToken += 1
	broadcastState()
end

function RiteFocusService.initialize(dependencies)
	objectiveService = dependencies.objectiveService
	defenseService = dependencies.defenseService
	riteService = dependencies.riteService

	for _, laneName in ipairs(defenseService.getLaneNames()) do
		buildLaneFocus(laneName)
	end

	setPhase("Lobby", 0, "", "", "")
end

function RiteFocusService.startDayPhase(roundNumber: number)
	setPhase("DayPrep", roundNumber, "", "", "")
	return focusState
end

function RiteFocusService.startNightPhase(roundNumber: number)
	local riteState = riteService.getState()
	setPhase(
		"NightSurvival",
		roundNumber,
		riteState.selectedRiteName or "",
		riteState.selectedRiteTitle or "",
		riteState.selectedRiteSummary or ""
	)
	return focusState
end

function RiteFocusService.finishRound(roundNumber: number)
	setPhase(
		"Results",
		roundNumber,
		focusState.selectedRiteName,
		focusState.selectedRiteTitle,
		focusState.selectedRiteSummary
	)
	return focusState
end

function RiteFocusService.getLaneModifiers(laneName: string)
	pruneExpiredFocus()
	local riteConfig = getSelectedRiteConfig()

	if activeFocus == nil or activeFocus.laneName ~= laneName or riteConfig == nil then
		return EMPTY_LANE_MODIFIERS
	end

	return riteConfig.laneModifiers or EMPTY_LANE_MODIFIERS
end

function RiteFocusService.getThreatModifiers(laneName: string)
	pruneExpiredFocus()
	local riteConfig = getSelectedRiteConfig()

	if activeFocus == nil or activeFocus.laneName ~= laneName or riteConfig == nil then
		return EMPTY_THREAT_MODIFIERS
	end

	return riteConfig.threatModifiers or EMPTY_THREAT_MODIFIERS
end

function RiteFocusService.getCombatModifiers()
	pruneExpiredFocus()
	local riteConfig = getSelectedRiteConfig()

	if activeFocus == nil or riteConfig == nil then
		return EMPTY_COMBAT_MODIFIERS
	end

	return riteConfig.combatModifiers or EMPTY_COMBAT_MODIFIERS
end

function RiteFocusService.getState()
	rebuildState()
	return focusState
end

function RiteFocusService.syncPlayer(player: Player)
	pushState(player)
end

return RiteFocusService
