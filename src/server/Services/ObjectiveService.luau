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

local function ensurePart(
    parent: Instance,
    partName: string,
    size: Vector3,
    position: Vector3,
    color: Color3
)
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

local function setBoardText(
    board: BasePart,
    titleText: string,
    bodyText: string,
    titleColor: Color3
)
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

    guideBoardPart =
        ensureBoardPart(folder, "GuideBoard", Vector3.new(-18, 5, -16), Color3.fromRGB(80, 66, 50))
    controlsBoardPart = ensureBoardPart(
        folder,
        "ControlsBoard",
        Vector3.new(18, 5, -16),
        Color3.fromRGB(58, 72, 84)
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
end

local function ensureCamp()
    local folder = ensureRuntimeFolder()

    local ground = ensurePart(
        folder,
        "Ground",
        Vector3.new(220, 1, 220),
        Vector3.new(0, -0.5, 0),
        Color3.fromRGB(65, 92, 58)
    )
    ground.Material = Enum.Material.Grass

    local campPad = ensurePart(
        folder,
        "CampPad",
        Vector3.new(28, 1, 28),
        Vector3.new(0, 0, 0),
        Color3.fromRGB(90, 76, 54)
    )
    campPad.Material = Enum.Material.Slate

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

    lanternPart = ensurePart(
        folder,
        "LanternCore",
        Vector3.new(4, 6, 4),
        Vector3.new(0, 3.5, 0),
        Color3.fromRGB(255, 194, 92)
    )
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
end

local function getNearbySupportCount(originPosition: Vector3, excludedPlayer: Player): number
    local nearbySupportCount = 0

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= excludedPlayer then
            local character = player.Character
            local rootPart = if character ~= nil
                then character:FindFirstChild("HumanoidRootPart")
                else nil

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

    local nextResourcesCollected =
        math.min(objectiveState.resourcesCollected + 1, objectiveState.resourcesRequired)
    local roleModifiers = if roleService ~= nil
        then roleService.getRoleModifiersForPlayer(player)
        else nil
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
        prompt.ObjectText =
            string.format("Supply Crate | +%d supplies", GameConfig.ObjectiveTuning.SuppliesPerNode)
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
            + (math.max(playerCount, 1) - 1)
                * GameConfig.ObjectiveTuning.AdditionalNodesPerPlayer

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

function ObjectiveService.setEchoService(nextEchoService)
    echoService = nextEchoService
end

function ObjectiveService.setDutyService(nextDutyService)
    dutyService = nextDutyService
end

return ObjectiveService
