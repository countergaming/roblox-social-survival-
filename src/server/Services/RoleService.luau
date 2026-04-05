local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))

local RoleService = {}

local EMPTY_MODIFIERS = table.freeze({
	extraSuppliesPerCrate = 0,
	nearbyHelperSupplyBonus = 0,
	repairAmountBonus = 0,
	repairCostReduction = 0,
	reinforceCostReduction = 0,
	chargeAmountBonus = 0,
	chargeCostReduction = 0,
	overchargeCostReduction = 0,
	meleeDamageBonus = 0,
	pulseCooldownDelta = 0,
	pulseDamageBonus = 0,
})

local objectiveService = nil
local dutyService = nil
local roleFolder = nil
local roleEntriesByName = {}
local selectedRolesByUserId = {}
local roleState = table.freeze({
	phaseName = "Lobby",
	roundNumber = 0,
	lockedIn = false,
	teamCoverageCount = 0,
	selectedRoleName = "",
	selectedRoleTitle = "",
	selectedRoleSummary = "",
	roles = table.freeze({}),
})

local function getRemoteEvent(): RemoteEvent
	local remoteFolder = ReplicatedStorage:WaitForChild(RemoteNames.Folder)
	return remoteFolder:WaitForChild(RemoteNames.RoleStateChanged) :: RemoteEvent
end

local function setRoleState(nextState)
	roleState = table.freeze(nextState)
end

local function getRoleOrder()
	return GameConfig.RoleTuning.Order
end

local function getRoleConfig(roleName: string)
	return GameConfig.RoleTuning.Roles[roleName]
end

local function getSelectedRoleNameForUserId(userId: number): string
	local selectedRoleName = selectedRolesByUserId[userId]

	if type(selectedRoleName) ~= "string" then
		return ""
	end

	if getRoleConfig(selectedRoleName) == nil then
		return ""
	end

	return selectedRoleName
end

local function getRoleCounts()
	local roleCounts = {}

	for _, roleName in ipairs(getRoleOrder()) do
		roleCounts[roleName] = 0
	end

	for userId, roleName in pairs(selectedRolesByUserId) do
		if Players:GetPlayerByUserId(userId) ~= nil and roleCounts[roleName] ~= nil then
			roleCounts[roleName] += 1
		end
	end

	return roleCounts
end

local function getTeamCoverageCount(roleCounts)
	local coverageCount = 0

	for _, roleName in ipairs(getRoleOrder()) do
		if (roleCounts[roleName] or 0) > 0 then
			coverageCount += 1
		end
	end

	return coverageCount
end

local function getRoleFolder()
	if roleFolder ~= nil and roleFolder.Parent ~= nil then
		return roleFolder
	end

	local runtimeFolder = objectiveService.getRuntimeFolder()
	local existingFolder = runtimeFolder:FindFirstChild("RoleStations")

	if existingFolder ~= nil then
		roleFolder = existingFolder
		return roleFolder
	end

	roleFolder = Instance.new("Folder")
	roleFolder.Name = "RoleStations"
	roleFolder.Parent = runtimeFolder

	return roleFolder
end

local function buildRolePosition(index: number, totalRoles: number): Vector3
	local angle = (math.pi / 2) + (((index - 1) / math.max(totalRoles, 1)) * math.pi * 2)
	local radius = GameConfig.RoleTuning.StationRadius

	return Vector3.new(math.cos(angle) * radius, 3.5, math.sin(angle) * radius)
end

local function buildRolePayloadForPlayer(player: Player, phaseName: string, roundNumber: number, lockedIn: boolean)
	local roleCounts = getRoleCounts()
	local selectedRoleName = getSelectedRoleNameForUserId(player.UserId)
	local selectedRoleConfig = if selectedRoleName ~= "" then getRoleConfig(selectedRoleName) else nil
	local roleSnapshots = {}

	for _, roleName in ipairs(getRoleOrder()) do
		local roleConfig = getRoleConfig(roleName)
		table.insert(
			roleSnapshots,
			table.freeze({
				name = roleName,
				title = roleConfig.title,
				summary = roleConfig.summary,
				assignedPlayers = roleCounts[roleName] or 0,
				isSelected = roleName == selectedRoleName,
			})
		)
	end

	return table.freeze({
		phaseName = phaseName,
		roundNumber = roundNumber,
		lockedIn = lockedIn,
		teamCoverageCount = getTeamCoverageCount(roleCounts),
		selectedRoleName = selectedRoleName,
		selectedRoleTitle = if selectedRoleConfig ~= nil then selectedRoleConfig.title else "",
		selectedRoleSummary = if selectedRoleConfig ~= nil then selectedRoleConfig.summary else "",
		roles = table.freeze(roleSnapshots),
	})
end

local function findRoleSnapshot(roleName: string)
	for _, snapshot in ipairs(roleState.roles) do
		if snapshot.name == roleName then
			return snapshot
		end
	end

	return nil
end

local function updateRoleStationVisuals(roleName: string)
	local roleEntry = roleEntriesByName[roleName]

	if roleEntry == nil then
		return
	end

	local roleConfig = getRoleConfig(roleName)
	local snapshot = findRoleSnapshot(roleName)
	local assignedPlayers = if snapshot ~= nil then snapshot.assignedPlayers else 0
	local isPopular = assignedPlayers > 0

	roleEntry.part.Size = Vector3.new(
		3.8 + math.min(assignedPlayers, 2) * 0.25,
		5.5 + math.min(assignedPlayers, 3) * 0.35,
		3.8 + math.min(assignedPlayers, 2) * 0.25
	)
	roleEntry.part.Color = roleConfig.color
	roleEntry.part.Material = if isPopular then Enum.Material.SmoothPlastic else Enum.Material.Slate

	roleEntry.light.Color = roleConfig.color
	roleEntry.light.Brightness = 0.8 + (assignedPlayers * 0.25)
	roleEntry.light.Range = 10 + (assignedPlayers * 2)

	roleEntry.label.Text = string.format(
		"%s\n%s\nHold to choose | %d player%s",
		roleConfig.title,
		roleConfig.summary,
		assignedPlayers,
		if assignedPlayers == 1 then "" else "s"
	)
	roleEntry.label.TextColor3 = roleConfig.color

	roleEntry.prompt.ActionText = string.format("Choose %s", roleConfig.title)
	roleEntry.prompt.ObjectText = string.format(
		"%s | %d player%s on this role",
		roleConfig.summary,
		assignedPlayers,
		if assignedPlayers == 1 then "" else "s"
	)
	roleEntry.prompt.Enabled = roleState.phaseName == "DayPrep" and not roleState.lockedIn
end

local function refreshRoleStationVisuals()
	for _, roleName in ipairs(getRoleOrder()) do
		updateRoleStationVisuals(roleName)
	end
end

local function broadcastRoleState(phaseName: string, roundNumber: number, lockedIn: boolean)
	local firstPlayer = Players:GetPlayers()[1]

	if firstPlayer ~= nil then
		setRoleState(buildRolePayloadForPlayer(firstPlayer, phaseName, roundNumber, lockedIn))
	else
		setRoleState(table.freeze({
			phaseName = phaseName,
			roundNumber = roundNumber,
			lockedIn = lockedIn,
			teamCoverageCount = 0,
			selectedRoleName = "",
			selectedRoleTitle = "",
			selectedRoleSummary = "",
			roles = table.freeze({}),
		}))
	end

	refreshRoleStationVisuals()

	for _, player in ipairs(Players:GetPlayers()) do
		getRemoteEvent():FireClient(player, buildRolePayloadForPlayer(player, phaseName, roundNumber, lockedIn))
	end
end

local function handleRoleSelection(player: Player, roleName: string)
	if roleState.phaseName ~= "DayPrep" or roleState.lockedIn then
		return
	end

	if getRoleConfig(roleName) == nil then
		return
	end

	selectedRolesByUserId[player.UserId] = roleName
	broadcastRoleState("DayPrep", roleState.roundNumber, false)

	if dutyService ~= nil then
		dutyService.handleRoleAssignmentsChanged()
	end
end

local function buildRoleStation(roleName: string, index: number, totalRoles: number)
	local folder = getRoleFolder()
	local roleConfig = getRoleConfig(roleName)
	local existingStation = folder:FindFirstChild(roleName)
	local stationPart = existingStation

	if stationPart == nil then
		stationPart = Instance.new("Part")
		stationPart.Name = roleName
		stationPart.Anchored = true
		stationPart.Parent = folder
	end

	stationPart.Size = Vector3.new(3.8, 5.5, 3.8)
	stationPart.Position = buildRolePosition(index, totalRoles)
	stationPart.CFrame = CFrame.lookAt(stationPart.Position, objectiveService.getCampCenter())
	stationPart.TopSurface = Enum.SurfaceType.Smooth
	stationPart.BottomSurface = Enum.SurfaceType.Smooth

	local prompt = stationPart:FindFirstChild("RolePrompt")
	if prompt == nil then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RolePrompt"
		prompt.HoldDuration = 0.45
		prompt.MaxActivationDistance = 12
		prompt.Parent = stationPart

		prompt.Triggered:Connect(function(player)
			handleRoleSelection(player, roleName)
		end)
	end

	local light = stationPart:FindFirstChild("RoleLight")
	if light == nil then
		light = Instance.new("PointLight")
		light.Name = "RoleLight"
		light.Parent = stationPart
	end

	local billboard = stationPart:FindFirstChild("RoleBillboard")
	if billboard == nil then
		billboard = Instance.new("BillboardGui")
		billboard.Name = "RoleBillboard"
		billboard.Size = UDim2.fromOffset(188, 82)
		billboard.StudsOffset = Vector3.new(0, 5.6, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = stationPart
	end

	local label = billboard:FindFirstChild("RoleLabel")
	if label == nil then
		label = Instance.new("TextLabel")
		label.Name = "RoleLabel"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextWrapped = true
		label.Parent = billboard
	end

	label.TextStrokeTransparency = 0.4
	label.Text = string.format("%s\n%s\nHold to choose | 0 players", roleConfig.title, roleConfig.summary)

	roleEntriesByName[roleName] = {
		part = stationPart,
		prompt = prompt,
		light = light,
		label = label,
	}

	updateRoleStationVisuals(roleName)
end

function RoleService.initialize(dependencies)
	objectiveService = dependencies.objectiveService
	dutyService = dependencies.dutyService

	for index, roleName in ipairs(getRoleOrder()) do
		buildRoleStation(roleName, index, #getRoleOrder())
	end

	Players.PlayerRemoving:Connect(function(player)
		if selectedRolesByUserId[player.UserId] == nil then
			return
		end

		selectedRolesByUserId[player.UserId] = nil
		broadcastRoleState(roleState.phaseName, roleState.roundNumber, roleState.lockedIn)

		if dutyService ~= nil then
			dutyService.handleRoleAssignmentsChanged()
		end
	end)

	broadcastRoleState("Lobby", 0, false)
end

function RoleService.startDayPhase(roundNumber: number)
	broadcastRoleState("DayPrep", roundNumber, false)

	return roleState
end

function RoleService.startNightPhase(roundNumber: number)
	broadcastRoleState("NightSurvival", roundNumber, true)

	return roleState
end

function RoleService.finishRound(roundNumber: number)
	broadcastRoleState("Results", roundNumber, true)

	return roleState
end

function RoleService.getSelectedRoleName(player: Player): string
	return getSelectedRoleNameForUserId(player.UserId)
end

function RoleService.getRoleModifiersForPlayer(player: Player)
	local selectedRoleName = RoleService.getSelectedRoleName(player)

	if selectedRoleName == "" then
		return EMPTY_MODIFIERS
	end

	local roleConfig = getRoleConfig(selectedRoleName)

	if roleConfig == nil then
		return EMPTY_MODIFIERS
	end

	return roleConfig.modifiers
end

function RoleService.getRoleTitle(roleName: string): string
	local roleConfig = getRoleConfig(roleName)

	if roleConfig == nil then
		return ""
	end

	return roleConfig.title
end

function RoleService.getTeamCoverageCount(): number
	return getTeamCoverageCount(getRoleCounts())
end

function RoleService.getSuggestedStationPosition(): Vector3
	local roleCounts = getRoleCounts()

	for _, roleName in ipairs(getRoleOrder()) do
		if (roleCounts[roleName] or 0) == 0 then
			local roleEntry = roleEntriesByName[roleName]

			if roleEntry ~= nil then
				return roleEntry.part.Position
			end
		end
	end

	local firstRoleName = getRoleOrder()[1]
	local firstRoleEntry = if firstRoleName ~= nil then roleEntriesByName[firstRoleName] else nil

	if firstRoleEntry ~= nil then
		return firstRoleEntry.part.Position
	end

	return objectiveService.getCampCenter()
end

function RoleService.getState()
	return roleState
end

function RoleService.syncPlayer(player: Player)
	getRemoteEvent():FireClient(
		player,
		buildRolePayloadForPlayer(player, roleState.phaseName, roleState.roundNumber, roleState.lockedIn)
	)
end

return RoleService
