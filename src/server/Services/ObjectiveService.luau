local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))

local ObjectiveService = {}

local runtimeFolder = nil
local lanternPart = nil
local resourceFolder = nil
local guideBoardPart = nil
local controlsBoardPart = nil
local dutyService = nil
local echoService = nil
local roleService = nil
local riteService = nil
local objectiveState = table.freeze({
	phaseName = "Lobby",
	roundNumber = 0,
	resourcesCollected = 0,
	resourcesRequired = 0,
	lanternCharge = 0,
	totalSuppliesCollected = 0,
	spentSupplies = 0,
	availableSupplies = 0,
	completed = false,
})

local function isGuidedRound(roundNumber: number): boolean
	return roundNumber > 0 and roundNumber <= GameConfig.TutorialTuning.GuidedRounds
end

local function setObjectiveState(nextState)
	objectiveState = table.freeze(nextState)
end

local function getRemoteEvent(): RemoteEvent
	local remoteFolder = ReplicatedStorage:WaitForChild(RemoteNames.Folder)
	return remoteFolder:WaitForChild(RemoteNames.ObjectiveStateChanged) :: RemoteEvent
end

local function broadcastObjectiveState()
	getRemoteEvent():FireAllClients(objectiveState)
end

local function pushObjectiveState(player: Player)
	getRemoteEvent():FireClient(player, objectiveState)
end

local function ensureRuntimeFolder()
	if runtimeFolder ~= nil and runtimeFolder.Parent ~= nil then
		return runtimeFolder
	end

	local existingFolder = Workspace:FindFirstChild("LanternKeepRuntime")

	if existingFolder ~= nil then
		runtimeFolder = existingFolder
		return runtimeFolder
	end

	runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = "LanternKeepRuntime"
	runtimeFolder.Parent = Workspace

	return runtimeFolder
end

local function ensurePart(parent: Instance, partName: string, size: Vector3, position: Vector3, color: Color3)
	local existingPart = parent:FindFirstChild(partName)

	if existingPart ~= nil then
		existingPart.Size = size
		existingPart.Position = position
		existingPart.Color = color
		return existingPart
	end

	local part = Instance.new("Part")
	part.Name = partName
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent

	return part
end

local function ensureBoardPart(parent: Instance, partName: string, position: Vector3, color: Color3)
	local board = parent:FindFirstChild(partName)

	if board == nil then
		board = Instance.new("Part")
		board.Name = partName
		board.Anchored = true
		board.CanCollide = false
		board.Parent = parent
	end

	board.Size = Vector3.new(16, 9, 1)
	board.Position = position
	board.CFrame = CFrame.lookAt(position, Vector3.new(0, 4, 0))
	board.Color = color
	board.Material = Enum.Material.WoodPlanks
	board.TopSurface = Enum.SurfaceType.Smooth
	board.BottomSurface = Enum.SurfaceType.Smooth

	local surface = board:FindFirstChild("Display")
	if surface == nil then
		surface = Instance.new("SurfaceGui")
		surface.Name = "Display"
		surface.Face = Enum.NormalId.Front
		surface.AlwaysOnTop = true
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 34
		surface.Parent = board

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromOffset(18, 16)
		title.Size = UDim2.new(1, -36, 0, 38)
		title.Font = Enum.Font.GothamBold
		title.TextScaled = true
		title.TextWrapped = true
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = surface

		local body = Instance.new("TextLabel")
		body.Name = "Body"
		body.BackgroundTransparency = 1
		body.Position = UDim2.fromOffset(18, 64)
		body.Size = UDim2.new(1, -36, 1, -82)
		body.Font = Enum.Font.GothamMedium
		body.TextSize = 20
		body.TextWrapped = true
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.Parent = surface
	end

	return board
end

local function setBoardText(board: BasePart, titleText: string, bodyText: string, titleColor: Color3)
	local surface = board:FindFirstChild("Display")

	if surface == nil then
		return
	end

	local title = surface:FindFirstChild("Title")
	local body = surface:FindFirstChild("Body")

	if title ~= nil then
		title.Text = titleText
		title.TextColor3 = titleColor
	end

	if body ~= nil then
		body.Text = bodyText
		body.TextColor3 = Color3.fromRGB(244, 236, 218)
	end
end

local function ensureGuideBoards()
	local folder = ensureRuntimeFolder()

	guideBoardPart = ensureBoardPart(folder, "GuideBoard", Vector3.new(-18, 5, -16), Color3.fromRGB(80, 66, 50))
	controlsBoardPart = ensureBoardPart(folder, "ControlsBoard", Vector3.new(18, 5, -16), Color3.fromRGB(58, 72, 84))
end

local function ensureObjectiveMarker()
	local folder = ensureRuntimeFolder()
	local marker = folder:FindFirstChild("PrimaryObjectiveMarker")

	if marker == nil then
		marker = Instance.new("Part")
		marker.Name = "PrimaryObjectiveMarker"
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.Shape = Enum.PartType.Ball
		marker.Material = Enum.Material.Neon
		marker.Parent = folder

		local light = Instance.new("PointLight")
		light.Name = "MarkerLight"
		light.Parent = marker

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "MarkerBillboard"
		billboard.Size = UDim2.fromOffset(240, 76)
		billboard.StudsOffset = Vector3.new(0, 3.8, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 140
		billboard.Parent = marker

		local container = Instance.new("Frame")
		container.Name = "Container"
		container.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
		container.BackgroundTransparency = 0.1
		container.Size = UDim2.fromScale(1, 1)
		container.Parent = billboard

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = container

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 210, 112)
		stroke.Transparency = 0.25
		stroke.Parent = container

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromOffset(10, 8)
		title.Size = UDim2.new(1, -20, 0, 20)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 15
		title.TextColor3 = Color3.fromRGB(255, 232, 174)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = container

		local body = Instance.new("TextLabel")
		body.Name = "Body"
		body.BackgroundTransparency = 1
		body.Position = UDim2.fromOffset(10, 30)
		body.Size = UDim2.new(1, -20, 1, -36)
		body.Font = Enum.Font.GothamMedium
		body.TextSize = 13
		body.TextWrapped = true
		body.TextColor3 = Color3.fromRGB(240, 233, 220)
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.Parent = container
	end

	marker.Size = Vector3.new(1.7, 1.7, 1.7)
	return marker
end

local function ensureObjectiveGuideParts()
	local folder = ensureRuntimeFolder()
	local beam = folder:FindFirstChild("PrimaryObjectiveBeam")

	if beam == nil then
		beam = Instance.new("Part")
		beam.Name = "PrimaryObjectiveBeam"
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.Material = Enum.Material.Neon
		beam.Parent = folder
	end

	local ring = folder:FindFirstChild("PrimaryObjectiveRing")

	if ring == nil then
		ring = Instance.new("Part")
		ring.Name = "PrimaryObjectiveRing"
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Parent = folder
	end

	local routeFolder = folder:FindFirstChild("ObjectiveRoute")

	if routeFolder == nil then
		routeFolder = Instance.new("Folder")
		routeFolder.Name = "ObjectiveRoute"
		routeFolder.Parent = folder
	end

	for index = 1, 5 do
		local partName = string.format("Waypoint%02d", index)
		local waypoint = routeFolder:FindFirstChild(partName)

		if waypoint == nil then
			waypoint = Instance.new("Part")
			waypoint.Name = partName
			waypoint.Anchored = true
			waypoint.CanCollide = false
			waypoint.CanQuery = false
			waypoint.CanTouch = false
			waypoint.Material = Enum.Material.Neon
			waypoint.Parent = routeFolder
		end
	end

	return beam, ring, routeFolder
end

local function updateObjectiveRoute(targetPosition: Vector3?, color: Color3, visible: boolean)
	local _, _, routeFolder = ensureObjectiveGuideParts()

	if targetPosition == nil or not visible then
		for _, child in ipairs(routeFolder:GetChildren()) do
			if child:IsA("BasePart") then
				child.Transparency = 1
			end
		end

		return
	end

	local startPosition = ObjectiveService.getCampCenter()
	local startGround = Vector3.new(startPosition.X, 0.35, startPosition.Z)
	local endGround = Vector3.new(targetPosition.X, 0.35, targetPosition.Z)
	local waypoints = routeFolder:GetChildren()

	table.sort(waypoints, function(left, right)
		return left.Name < right.Name
	end)

	for index, child in ipairs(waypoints) do
		if child:IsA("BasePart") then
			local alpha = index / (#waypoints + 1)
			local waypointPosition = startGround:Lerp(endGround, alpha)
			local remaining = (endGround - waypointPosition).Magnitude

			child.Size = Vector3.new(3.2, 0.35, 3.2)
			child.Position = waypointPosition
			child.Color = color
			child.Transparency = 0.16 + (alpha * 0.38)
			child.CFrame = CFrame.lookAt(waypointPosition, endGround)

			if remaining < 6 then
				child.Size = Vector3.new(4.2, 0.35, 4.2)
				child.Transparency = 0.08
			end
		end
	end
end

local function setObjectiveMarker(
	position: Vector3?,
	titleText: string,
	bodyText: string,
	color: Color3,
	visible: boolean
)
	local marker = ensureObjectiveMarker()
	local beam, ring = ensureObjectiveGuideParts()
	local light = marker:FindFirstChild("MarkerLight")
	local billboard = marker:FindFirstChild("MarkerBillboard")
	local container = if billboard ~= nil then billboard:FindFirstChild("Container") else nil
	local title = if container ~= nil then container:FindFirstChild("Title") else nil
	local body = if container ~= nil then container:FindFirstChild("Body") else nil

	marker.Color = color
	marker.Transparency = if visible then 0.08 else 1
	marker:SetAttribute("GuidanceTitle", titleText)
	marker:SetAttribute("GuidanceBody", bodyText)

	if position ~= nil then
		marker.Position = position + Vector3.new(0, 6.5, 0)
		marker:SetAttribute("TargetPosition", position)
	else
		marker:SetAttribute("TargetPosition", nil)
	end

	if light ~= nil then
		light.Color = color
		light.Brightness = if visible then 3.4 else 0
		light.Range = if visible then 18 else 0
	end

	if billboard ~= nil then
		billboard.Enabled = visible
	end

	if title ~= nil then
		title.Text = titleText
	end

	if body ~= nil then
		body.Text = bodyText
	end

	if position ~= nil then
		beam.Color = color
		beam.Size = Vector3.new(1.2, 7.4, 1.2)
		beam.Position = Vector3.new(position.X, 3.7, position.Z)
		beam.Transparency = if visible then 0.34 else 1

		ring.Color = color
		ring.Size = Vector3.new(0.45, 11, 11)
		ring.CFrame = CFrame.new(position.X, 0.22, position.Z) * CFrame.Angles(0, 0, math.rad(90))
		ring.Transparency = if visible then 0.18 else 1
	else
		beam.Transparency = 1
		ring.Transparency = 1
	end

	updateObjectiveRoute(position, color, visible)
end

local function findPrimaryResourceNode()
	if resourceFolder == nil then
		return nil
	end

	for _, child in ipairs(resourceFolder:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("Collected") ~= true then
			return child
		end
	end

	return nil
end

local function updateResourceNodeVisuals()
	if resourceFolder == nil then
		return
	end

	local primaryNode = findPrimaryResourceNode()

	for _, child in ipairs(resourceFolder:GetChildren()) do
		if child:IsA("BasePart") then
			local prompt = child:FindFirstChild("CollectPrompt")
			local light = child:FindFirstChild("NodeLight")
			local billboard = child:FindFirstChild("NodeBillboard")
			local label = if billboard ~= nil then billboard:FindFirstChild("NodeLabel") else nil
			local isCollected = child:GetAttribute("Collected") == true
			local isPrimary = child == primaryNode and objectiveState.phaseName == "DayPrep"

			if light == nil then
				light = Instance.new("PointLight")
				light.Name = "NodeLight"
				light.Parent = child
			end

			if billboard == nil then
				billboard = Instance.new("BillboardGui")
				billboard.Name = "NodeBillboard"
				billboard.Size = UDim2.fromOffset(150, 50)
				billboard.StudsOffset = Vector3.new(0, 4.4, 0)
				billboard.AlwaysOnTop = true
				billboard.MaxDistance = 90
				billboard.Parent = child

				label = Instance.new("TextLabel")
				label.Name = "NodeLabel"
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.GothamBold
				label.TextSize = 13
				label.TextWrapped = true
				label.Parent = billboard
			end

			if label == nil then
				label = billboard:FindFirstChild("NodeLabel")
			end

			if isCollected then
				child.Color = Color3.fromRGB(80, 93, 109)
				light.Brightness = 0
				light.Range = 0
				billboard.Enabled = false
				if prompt ~= nil then
					prompt.ActionText = "Collected"
				end
			else
				child.Color = if isPrimary then Color3.fromRGB(232, 182, 102) else Color3.fromRGB(164, 118, 78)
				light.Color = if isPrimary then Color3.fromRGB(255, 218, 126) else Color3.fromRGB(204, 156, 106)
				light.Brightness = if isPrimary then 4 else 1.4
				light.Range = if isPrimary then 18 else 10
				billboard.Enabled = objectiveState.phaseName == "DayPrep"
				if label ~= nil then
					label.Text = if isPrimary then "START HERE\nCollect Fuel" else "Fuel Crate"
					label.TextColor3 = if isPrimary
						then Color3.fromRGB(255, 238, 188)
						else Color3.fromRGB(232, 214, 176)
				end
				if prompt ~= nil then
					prompt.ActionText = if isPrimary then "Start: Collect Fuel" else "Collect Fuel"
				end
			end
		end
	end
end

local function updatePrimaryObjectiveMarker()
	if objectiveState.phaseName == "Lobby" then
		setObjectiveMarker(
			lanternPart.Position,
			"WAIT HERE",
			"Stay by the lantern. Day Prep begins soon.",
			Color3.fromRGB(255, 210, 112),
			true
		)
		return
	end

	if objectiveState.phaseName == "DayPrep" then
		local primaryNode = findPrimaryResourceNode()

		if primaryNode ~= nil then
			setObjectiveMarker(
				primaryNode.Position,
				"START HERE",
				string.format(
					"Walk here, then hold the prompt to collect fuel. %d/%d crates gathered.",
					objectiveState.resourcesCollected,
					objectiveState.resourcesRequired
				),
				Color3.fromRGB(255, 210, 112),
				true
			)
			return
		end

		if roleService ~= nil and roleService.getTeamCoverageCount() == 0 then
			setObjectiveMarker(
				roleService.getSuggestedStationPosition(),
				"CHOOSE A ROLE",
				"Follow the route to a role station and hold the prompt to choose your job.",
				Color3.fromRGB(160, 226, 176),
				true
			)
			return
		end

		if riteService ~= nil and (riteService.getState().leadingRiteVotes or 0) == 0 then
			setObjectiveMarker(
				riteService.getSuggestedShrinePosition(),
				"VOTE ON A RITE",
				"Walk to a shrine and hold the prompt to bind tonight's rite.",
				Color3.fromRGB(150, 208, 255),
				true
			)
			return
		end

		setObjectiveMarker(
			lanternPart.Position,
			"NEXT STEP",
			"Follow the route to a lane. Spend supplies on a barricade or tower before night falls.",
			Color3.fromRGB(176, 224, 255),
			true
		)
		return
	end

	if objectiveState.phaseName == "NightSurvival" then
		setObjectiveMarker(
			lanternPart.Position,
			"DEFEND HERE",
			"Hold the lanes and fall back to the lantern when the swarm reaches camp.",
			Color3.fromRGB(255, 182, 128),
			true
		)
		return
	end

	setObjectiveMarker(
		lanternPart.Position,
		"REGROUP",
		"Review the debrief, then get ready for the next watch.",
		Color3.fromRGB(194, 206, 255),
		true
	)
end

local function updateGuideBoards()
	ensureGuideBoards()

	local guideTitle = "Lantern Keep Orders"
	local guideBody = "Stay near the camp and wait for the next round to begin."

	if objectiveState.phaseName == "Lobby" then
		if isGuidedRound(objectiveState.roundNumber + 1) then
			guideTitle = GameConfig.TutorialTuning.Title
			guideBody = table.concat({
				"1. Stay near the campfire while the guided round starts.",
				"2. Follow the mission tracker instead of trying to optimize everything at once.",
				"3. Tonight only uses a smaller lane set so you can learn the loop cleanly.",
			}, "\n")
		else
			guideTitle = "Round Briefing"
			guideBody = table.concat({
				"1. Stay near the campfire while the round starts.",
				"2. Watch the top HUD for phase changes and lane alerts.",
				"3. Read the shrine and defense prompts before moving out.",
			}, "\n")
		end
	elseif objectiveState.phaseName == "DayPrep" then
		if isGuidedRound(objectiveState.roundNumber) then
			guideTitle = GameConfig.TutorialTuning.Title
			guideBody = table.concat({
				string.format(
					"1. Collect %d fuel crates. Progress: %d/%d.",
					objectiveState.resourcesRequired,
					objectiveState.resourcesCollected,
					objectiveState.resourcesRequired
				),
				"2. Choose a role station before spending supplies.",
				string.format(
					"3. Repair %s lane and charge %s tower. Supplies ready: %d.",
					GameConfig.TutorialTuning.TargetBarricadeLaneName,
					GameConfig.TutorialTuning.TargetTowerLaneName,
					objectiveState.availableSupplies
				),
				"4. Vote at a rite shrine so the team learns tonight's blessing.",
			}, "\n")
		else
			guideTitle = "Day Prep Orders"
			guideBody = table.concat({
				string.format(
					"1. Collect %d fuel crates around camp. Progress: %d/%d.",
					objectiveState.resourcesRequired,
					objectiveState.resourcesCollected,
					objectiveState.resourcesRequired
				),
				string.format(
					"2. Spend shared supplies on repairs, reinforcement, charge, or overcharge. Supplies ready: %d.",
					objectiveState.availableSupplies
				),
				"3. Choose a role station, then build the same lane with different roles to create Concord.",
				"4. Visit a Lantern Rite shrine and vote for the night's blessing.",
			}, "\n")
		end
	elseif objectiveState.phaseName == "NightSurvival" then
		if isGuidedRound(objectiveState.roundNumber) then
			guideTitle = "First Watch"
			guideBody = table.concat({
				string.format(
					"1. Hold %s and %s lanes during the guided watch.",
					GameConfig.TutorialTuning.AllowedLaneNames[1],
					GameConfig.TutorialTuning.AllowedLaneNames[2]
				),
				"2. Move to the flashing beacon and strike enemies before they touch the barricade.",
				"3. If the swarm reaches camp, retreat to the lantern and trigger Pulse.",
			}, "\n")
		else
			guideTitle = "Night Orders"
			guideBody = table.concat({
				"1. Follow the warning beacon and move to the pressured lane.",
				"2. Use the Lantern Pike on enemies near barricades before they break through.",
				"3. Fall back to the lantern and use the Pulse prompt when the swarm closes in.",
			}, "\n")
		end
	elseif objectiveState.phaseName == "Results" then
		guideTitle = "Dawn Debrief"
		guideBody = table.concat({
			"1. Review the result and reward popup.",
			"2. Reposition near camp for the next day phase.",
			"3. A new rite vote begins when the next round starts.",
		}, "\n")
	end

	setBoardText(guideBoardPart, guideTitle, guideBody, Color3.fromRGB(255, 214, 146))
	setBoardText(
		controlsBoardPart,
		"Controls",
		table.concat({
			"Move: walk to crates, shrines, towers, and barricades.",
			"Interact: hold the on-screen prompt when close to an object or role station.",
			"Fight: equip the Lantern Pike and click or tap to strike.",
			"Emergency: use the lantern Pulse prompt when threats mass at camp.",
		}, "\n"),
		Color3.fromRGB(152, 216, 255)
	)
	updatePrimaryObjectiveMarker()
	updateResourceNodeVisuals()
end

local function ensureCamp()
	local folder = ensureRuntimeFolder()

	local ground =
		ensurePart(folder, "Ground", Vector3.new(220, 1, 220), Vector3.new(0, -0.5, 0), Color3.fromRGB(65, 92, 58))
	ground.Material = Enum.Material.Grass

	local campPad =
		ensurePart(folder, "CampPad", Vector3.new(28, 1, 28), Vector3.new(0, 0, 0), Color3.fromRGB(90, 76, 54))
	campPad.Material = Enum.Material.Slate

	local lanternPedestal =
		ensurePart(folder, "LanternPedestal", Vector3.new(8, 2, 8), Vector3.new(0, 1, 0), Color3.fromRGB(106, 92, 70))
	lanternPedestal.Material = Enum.Material.Slate

	local campfireBase =
		ensurePart(folder, "CampfireBase", Vector3.new(6, 1, 6), Vector3.new(0, 0.55, 6), Color3.fromRGB(74, 68, 62))
	campfireBase.Material = Enum.Material.Slate

	local campfireFlame = ensurePart(
		folder,
		"CampfireFlame",
		Vector3.new(2.4, 3.4, 2.4),
		Vector3.new(0, 2.4, 6),
		Color3.fromRGB(255, 166, 84)
	)
	campfireFlame.Material = Enum.Material.Neon
	campfireFlame.Shape = Enum.PartType.Ball

	local campfireLight = campfireFlame:FindFirstChild("FireLight")
	if campfireLight == nil then
		campfireLight = Instance.new("PointLight")
		campfireLight.Name = "FireLight"
		campfireLight.Range = 20
		campfireLight.Brightness = 2.2
		campfireLight.Color = Color3.fromRGB(255, 194, 108)
		campfireLight.Parent = campfireFlame
	end

	local supplyStackA =
		ensurePart(folder, "SupplyStackA", Vector3.new(6, 3, 4), Vector3.new(-10, 1.6, 5), Color3.fromRGB(132, 98, 68))
	supplyStackA.Material = Enum.Material.WoodPlanks

	local supplyStackB =
		ensurePart(folder, "SupplyStackB", Vector3.new(6, 3, 4), Vector3.new(10, 1.6, 5), Color3.fromRGB(132, 98, 68))
	supplyStackB.Material = Enum.Material.WoodPlanks

	local markerPath = ensurePart(
		folder,
		"MarkerPath",
		Vector3.new(12, 0.4, 18),
		Vector3.new(0, 0.25, -10),
		Color3.fromRGB(118, 102, 76)
	)
	markerPath.Material = Enum.Material.Slate

	local spawnLocation = folder:FindFirstChild("Spawn")
	if spawnLocation == nil then
		spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = "Spawn"
		spawnLocation.Anchored = true
		spawnLocation.Neutral = true
		spawnLocation.Size = Vector3.new(8, 1, 8)
		spawnLocation.Position = Vector3.new(0, 1, -6)
		spawnLocation.Color = Color3.fromRGB(217, 192, 104)
		spawnLocation.Parent = folder
	end

	lanternPart =
		ensurePart(folder, "LanternCore", Vector3.new(4, 6, 4), Vector3.new(0, 3.5, 0), Color3.fromRGB(255, 194, 92))
	lanternPart.Material = Enum.Material.Neon

	local pointLight = lanternPart:FindFirstChild("LanternLight")
	if pointLight == nil then
		pointLight = Instance.new("PointLight")
		pointLight.Name = "LanternLight"
		pointLight.Range = 32
		pointLight.Brightness = 2
		pointLight.Color = Color3.fromRGB(255, 209, 126)
		pointLight.Parent = lanternPart
	end

	resourceFolder = folder:FindFirstChild("ResourceNodes")
	if resourceFolder == nil then
		resourceFolder = Instance.new("Folder")
		resourceFolder.Name = "ResourceNodes"
		resourceFolder.Parent = folder
	end

	ensureGuideBoards()
	ensureObjectiveMarker()
end

local function updateLanternVisuals(chargeRatio: number)
	if lanternPart == nil then
		return
	end

	local clampedCharge = math.clamp(chargeRatio, 0, 1)
	local brightness = 1 + (clampedCharge * 4)
	local pointLight = lanternPart:FindFirstChild("LanternLight")

	lanternPart.Color = Color3.fromRGB(
		175 + math.floor(80 * clampedCharge),
		114 + math.floor(95 * clampedCharge),
		60 + math.floor(40 * clampedCharge)
	)

	if pointLight ~= nil then
		pointLight.Brightness = brightness
		pointLight.Range = 20 + math.floor(24 * clampedCharge)
	end
end

local function buildObjectivePayload(
	phaseName: string,
	roundNumber: number,
	resourcesCollected: number,
	resourcesRequired: number,
	totalSuppliesCollected: number,
	spentSupplies: number
)
	local lanternCharge = 0
	local completed = false
	local collectedSupplyCount = math.max(0, math.floor(totalSuppliesCollected))
	local spentSupplyCount = math.clamp(math.floor(spentSupplies), 0, collectedSupplyCount)
	local availableSupplies = collectedSupplyCount - spentSupplyCount

	if resourcesRequired > 0 then
		lanternCharge = math.clamp(
			resourcesCollected * GameConfig.ObjectiveTuning.LanternChargePerNode,
			0,
			GameConfig.ObjectiveTuning.MaxLanternCharge
		)
		completed = resourcesCollected >= resourcesRequired
	end

	return table.freeze({
		phaseName = phaseName,
		roundNumber = roundNumber,
		resourcesCollected = resourcesCollected,
		resourcesRequired = resourcesRequired,
		lanternCharge = lanternCharge,
		totalSuppliesCollected = collectedSupplyCount,
		spentSupplies = spentSupplyCount,
		availableSupplies = availableSupplies,
		completed = completed,
	})
end

local function setNodeCollected(nodePart: BasePart)
	nodePart.Transparency = 0.65
	nodePart.CanCollide = false
	nodePart.Color = Color3.fromRGB(80, 93, 109)

	local prompt = nodePart:FindFirstChild("CollectPrompt")
	if prompt ~= nil then
		prompt.Enabled = false
	end

	updateResourceNodeVisuals()
end

local function getNearbySupportCount(originPosition: Vector3, excludedPlayer: Player): number
	local nearbySupportCount = 0

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= excludedPlayer then
			local character = player.Character
			local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil

			if rootPart ~= nil and (rootPart.Position - originPosition).Magnitude <= 18 then
				nearbySupportCount += 1
			end
		end
	end

	return nearbySupportCount
end

local function handleResourceCollected(player: Player, nodePart: BasePart)
	if nodePart:GetAttribute("Collected") == true then
		return
	end

	if objectiveState.phaseName ~= "DayPrep" then
		return
	end

	nodePart:SetAttribute("Collected", true)
	setNodeCollected(nodePart)

	local nextResourcesCollected = math.min(objectiveState.resourcesCollected + 1, objectiveState.resourcesRequired)
	local roleModifiers = if roleService ~= nil then roleService.getRoleModifiersForPlayer(player) else nil
	local echoModifiers = if echoService ~= nil then echoService.getCombinedModifiers() else nil
	local supportCount = getNearbySupportCount(nodePart.Position, player)
	local supplyGain = GameConfig.ObjectiveTuning.SuppliesPerNode
		+ (if roleModifiers ~= nil then roleModifiers.extraSuppliesPerCrate else 0)
		+ (if echoModifiers ~= nil then echoModifiers.extraSuppliesPerCrate else 0)

	if supportCount > 0 and roleModifiers ~= nil then
		supplyGain += roleModifiers.nearbyHelperSupplyBonus
	end

	local nextTotalSuppliesCollected = objectiveState.totalSuppliesCollected + supplyGain

	setObjectiveState(
		buildObjectivePayload(
			objectiveState.phaseName,
			objectiveState.roundNumber,
			nextResourcesCollected,
			objectiveState.resourcesRequired,
			nextTotalSuppliesCollected,
			objectiveState.spentSupplies
		)
	)
	updateLanternVisuals(objectiveState.lanternCharge)
	updateGuideBoards()
	broadcastObjectiveState()

	if echoService ~= nil then
		echoService.registerResourceCollected(player, 1)
	end

	if dutyService ~= nil then
		dutyService.registerResourceCollected(player, 1)
	end
end

local function buildResourceNode(nodeIndex: number, totalNodes: number)
	local nodeName = string.format("ResourceNode_%d", nodeIndex)
	local nodeAngle = ((nodeIndex - 1) / math.max(totalNodes, 1)) * (math.pi * 2)
	local nodePosition = Vector3.new(
		math.cos(nodeAngle) * GameConfig.ObjectiveTuning.ResourceRingRadius,
		2.5,
		math.sin(nodeAngle) * GameConfig.ObjectiveTuning.ResourceRingRadius
	)

	local nodePart = resourceFolder:FindFirstChild(nodeName)

	if nodePart == nil then
		nodePart = Instance.new("Part")
		nodePart.Name = nodeName
		nodePart.Anchored = true
		nodePart.Size = Vector3.new(4, 5, 4)
		nodePart.Material = Enum.Material.Wood
		nodePart.Parent = resourceFolder

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CollectPrompt"
		prompt.ActionText = "Collect Fuel"
		prompt.ObjectText = string.format("Supply Crate | +%d supplies", GameConfig.ObjectiveTuning.SuppliesPerNode)
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 12
		prompt.Parent = nodePart

		prompt.Triggered:Connect(function(player)
			handleResourceCollected(player, nodePart)
		end)
	end

	nodePart.Position = nodePosition
	nodePart.Color = Color3.fromRGB(164, 118, 78)
	nodePart.Transparency = 0
	nodePart.CanCollide = true
	nodePart:SetAttribute("Collected", false)

	local prompt = nodePart:FindFirstChild("CollectPrompt")
	if prompt ~= nil then
		prompt.Enabled = true
	end

	updateResourceNodeVisuals()

	return nodePart
end

local function refreshResourceNodes(totalNodes: number)
	for _, child in ipairs(resourceFolder:GetChildren()) do
		if child:IsA("BasePart") then
			local prompt = child:FindFirstChild("CollectPrompt")
			if prompt ~= nil then
				prompt.Enabled = false
			end
			child:Destroy()
		end
	end

	for nodeIndex = 1, totalNodes do
		buildResourceNode(nodeIndex, totalNodes)
	end
end

function ObjectiveService.initialize()
	ensureCamp()
	setObjectiveState(buildObjectivePayload("Lobby", 0, 0, 0, 0, 0))
	updateLanternVisuals(0)
	updateGuideBoards()
end

function ObjectiveService.startDayPhase(roundNumber: number, playerCount: number, options)
	ensureCamp()

	local requiredNodes = if options ~= nil and options.resourceNodeCount ~= nil
		then math.max(1, math.floor(options.resourceNodeCount))
		else GameConfig.ObjectiveTuning.BaseResourceNodes
			+ (math.max(playerCount, 1) - 1) * GameConfig.ObjectiveTuning.AdditionalNodesPerPlayer

	refreshResourceNodes(requiredNodes)

	setObjectiveState(buildObjectivePayload("DayPrep", roundNumber, 0, requiredNodes, 0, 0))
	updateLanternVisuals(objectiveState.lanternCharge)
	updateGuideBoards()
	broadcastObjectiveState()

	return objectiveState
end

function ObjectiveService.startNightPhase(roundNumber: number)
	setObjectiveState(
		buildObjectivePayload(
			"NightSurvival",
			roundNumber,
			objectiveState.resourcesCollected,
			objectiveState.resourcesRequired,
			objectiveState.totalSuppliesCollected,
			objectiveState.spentSupplies
		)
	)
	updateLanternVisuals(objectiveState.lanternCharge)
	updateGuideBoards()
	broadcastObjectiveState()

	for _, child in ipairs(resourceFolder:GetChildren()) do
		local prompt = child:FindFirstChild("CollectPrompt")
		if prompt ~= nil then
			prompt.Enabled = false
		end
	end

	return objectiveState
end

function ObjectiveService.finishRound()
	setObjectiveState(
		buildObjectivePayload(
			"Results",
			objectiveState.roundNumber,
			objectiveState.resourcesCollected,
			objectiveState.resourcesRequired,
			objectiveState.totalSuppliesCollected,
			objectiveState.spentSupplies
		)
	)
	updateGuideBoards()
	broadcastObjectiveState()

	return objectiveState
end

function ObjectiveService.consumeSupplies(amount: number): boolean
	local spendAmount = math.max(0, math.floor(amount))

	if spendAmount == 0 then
		return true
	end

	if objectiveState.phaseName ~= "DayPrep" or objectiveState.availableSupplies < spendAmount then
		return false
	end

	setObjectiveState(
		buildObjectivePayload(
			objectiveState.phaseName,
			objectiveState.roundNumber,
			objectiveState.resourcesCollected,
			objectiveState.resourcesRequired,
			objectiveState.totalSuppliesCollected,
			objectiveState.spentSupplies + spendAmount
		)
	)
	updateGuideBoards()
	broadcastObjectiveState()

	return true
end

function ObjectiveService.getState()
	return objectiveState
end

function ObjectiveService.syncPlayer(player: Player)
	pushObjectiveState(player)
end

function ObjectiveService.getRuntimeFolder()
	return ensureRuntimeFolder()
end

function ObjectiveService.getLanternPart()
	ensureCamp()
	return lanternPart
end

function ObjectiveService.getCampCenter()
	return Vector3.new(0, 0, 0)
end

function ObjectiveService.setRoleService(nextRoleService)
	roleService = nextRoleService
	updateGuideBoards()
end

function ObjectiveService.setRiteService(nextRiteService)
	riteService = nextRiteService
	updateGuideBoards()
end

function ObjectiveService.setEchoService(nextEchoService)
	echoService = nextEchoService
end

function ObjectiveService.setDutyService(nextDutyService)
	dutyService = nextDutyService
end

return ObjectiveService
