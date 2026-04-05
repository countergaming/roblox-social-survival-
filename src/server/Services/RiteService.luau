local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))

local RiteService = {}

local EMPTY_MODIFIERS = table.freeze({
    pulseCooldownDelta = 0,
    pulseDamageBonus = 0,
    pulseRadiusBonus = 0,
    towerDamageBonus = 0,
    towerRangeBonus = 0,
    warningLeadBonus = 0,
    globalThreatSpeedMultiplier = 1,
    runnerSpeedMultiplier = 1,
    barricadeMitigationBonus = 0,
    lanternHealthBonus = 0,
    sapperDamageMultiplier = 1,
})

local objectiveService = nil
local shrineFolder = nil
local shrineEntriesByName = {}
local votesByUserId = {}
local riteState = table.freeze({
    phaseName = "Lobby",
    roundNumber = 0,
    lockedIn = false,
    leadingRiteName = "",
    leadingRiteTitle = "",
    leadingRiteSummary = "",
    leadingRiteVotes = 0,
    selectedRiteName = "",
    selectedRiteTitle = "",
    selectedRiteSummary = "",
    votedRiteName = "",
    votedRiteTitle = "",
    votedRiteSummary = "",
    rites = table.freeze({}),
})

local function getRemoteEvent(): RemoteEvent
    local remoteFolder = ReplicatedStorage:WaitForChild(RemoteNames.Folder)
    return remoteFolder:WaitForChild(RemoteNames.RiteStateChanged) :: RemoteEvent
end

local function setRiteState(nextState)
    riteState = table.freeze(nextState)
end

local function getRiteOrder()
    return GameConfig.RiteTuning.Order
end

local function getRiteConfig(riteName: string)
    return GameConfig.RiteTuning.Rites[riteName]
end

local function getVotedRiteNameForUserId(userId: number): string
    local votedRiteName = votesByUserId[userId]

    if type(votedRiteName) ~= "string" then
        return ""
    end

    if getRiteConfig(votedRiteName) == nil then
        return ""
    end

    return votedRiteName
end

local function getDefaultRiteName(roundNumber: number): string
    local riteOrder = getRiteOrder()
    local orderIndex = ((math.max(roundNumber, 1) - 1) % #riteOrder) + 1

    return riteOrder[orderIndex]
end

local function getVoteCounts()
    local voteCounts = {}

    for _, riteName in ipairs(getRiteOrder()) do
        voteCounts[riteName] = 0
    end

    for _, riteName in pairs(votesByUserId) do
        if voteCounts[riteName] ~= nil then
            voteCounts[riteName] += 1
        end
    end

    return voteCounts
end

local function getTieBreakOrder(roundNumber: number)
    local riteOrder = getRiteOrder()
    local rotatedOrder = {}
    local defaultIndex = ((math.max(roundNumber, 1) - 1) % #riteOrder) + 1

    for offset = 0, #riteOrder - 1 do
        local orderIndex = ((defaultIndex + offset - 1) % #riteOrder) + 1
        table.insert(rotatedOrder, riteOrder[orderIndex])
    end

    return rotatedOrder
end

local function determineLeadingRiteName(roundNumber: number, voteCounts)
    local bestRiteName = getDefaultRiteName(roundNumber)
    local bestVotes = -1

    for _, riteName in ipairs(getTieBreakOrder(roundNumber)) do
        local voteCount = voteCounts[riteName] or 0

        if voteCount > bestVotes then
            bestVotes = voteCount
            bestRiteName = riteName
        end
    end

    return bestRiteName
end

local function getShrineFolder()
    if shrineFolder ~= nil and shrineFolder.Parent ~= nil then
        return shrineFolder
    end

    local runtimeFolder = objectiveService.getRuntimeFolder()
    local existingFolder = runtimeFolder:FindFirstChild("LanternRites")

    if existingFolder ~= nil then
        shrineFolder = existingFolder
        return shrineFolder
    end

    shrineFolder = Instance.new("Folder")
    shrineFolder.Name = "LanternRites"
    shrineFolder.Parent = runtimeFolder

    return shrineFolder
end

local function buildShrinePosition(index: number, totalShrines: number): Vector3
    local angle = (-math.pi / 2) + (((index - 1) / math.max(totalShrines, 1)) * math.pi * 2)
    local radius = GameConfig.RiteTuning.ShrineRadius

    return Vector3.new(math.cos(angle) * radius, 4, math.sin(angle) * radius)
end

local function buildRiteState(
    phaseName: string,
    roundNumber: number,
    lockedIn: boolean,
    selectedRiteName: string,
    player: Player?
)
    local voteCounts = getVoteCounts()
    local leadingRiteName = determineLeadingRiteName(roundNumber, voteCounts)
    local activeSelectedRiteName = if lockedIn and selectedRiteName == ""
        then leadingRiteName
        else selectedRiteName
    local votedRiteName = if player ~= nil then getVotedRiteNameForUserId(player.UserId) else ""
    local leadingRiteConfig = getRiteConfig(leadingRiteName)
    local selectedRiteConfig = if activeSelectedRiteName ~= ""
        then getRiteConfig(activeSelectedRiteName)
        else nil
    local votedRiteConfig = if votedRiteName ~= "" then getRiteConfig(votedRiteName) else nil
    local riteSnapshots = {}

    for _, riteName in ipairs(getRiteOrder()) do
        local riteConfig = getRiteConfig(riteName)
        table.insert(
            riteSnapshots,
            table.freeze({
                name = riteName,
                title = riteConfig.title,
                summary = riteConfig.summary,
                votes = voteCounts[riteName] or 0,
                isLeading = riteName == leadingRiteName,
                isSelected = lockedIn and riteName == activeSelectedRiteName,
            })
        )
    end

    return table.freeze({
        phaseName = phaseName,
        roundNumber = roundNumber,
        lockedIn = lockedIn,
        leadingRiteName = leadingRiteName,
        leadingRiteTitle = leadingRiteConfig.title,
        leadingRiteSummary = leadingRiteConfig.summary,
        leadingRiteVotes = voteCounts[leadingRiteName] or 0,
        selectedRiteName = activeSelectedRiteName,
        selectedRiteTitle = if selectedRiteConfig ~= nil then selectedRiteConfig.title else "",
        selectedRiteSummary = if selectedRiteConfig ~= nil then selectedRiteConfig.summary else "",
        votedRiteName = votedRiteName,
        votedRiteTitle = if votedRiteConfig ~= nil then votedRiteConfig.title else "",
        votedRiteSummary = if votedRiteConfig ~= nil then votedRiteConfig.summary else "",
        rites = table.freeze(riteSnapshots),
    })
end

local function broadcastRiteState()
    for _, player in ipairs(Players:GetPlayers()) do
        getRemoteEvent():FireClient(
            player,
            buildRiteState(
                riteState.phaseName,
                riteState.roundNumber,
                riteState.lockedIn,
                riteState.selectedRiteName,
                player
            )
        )
    end
end

local function pushRiteState(player: Player)
    getRemoteEvent():FireClient(
        player,
        buildRiteState(
            riteState.phaseName,
            riteState.roundNumber,
            riteState.lockedIn,
            riteState.selectedRiteName,
            player
        )
    )
end

local function findRiteSnapshot(riteName: string)
    for _, snapshot in ipairs(riteState.rites) do
        if snapshot.name == riteName then
            return snapshot
        end
    end

    return nil
end

local function updateShrineVisuals(riteName: string)
    local shrineEntry = shrineEntriesByName[riteName]

    if shrineEntry == nil then
        return
    end

    local riteConfig = getRiteConfig(riteName)
    local snapshot = findRiteSnapshot(riteName)
    local voteCount = if snapshot ~= nil then snapshot.votes else 0
    local isLeading = if snapshot ~= nil then snapshot.isLeading else false
    local isSelected = if snapshot ~= nil then snapshot.isSelected else false
    local brightnessBoost = if isSelected then 1.5 elseif isLeading then 0.8 else 0

    shrineEntry.part.Size = Vector3.new(
        3.6 + (if isLeading then 0.35 else 0) + (if isSelected then 0.55 else 0),
        7 + math.min(voteCount, 4) * 0.4 + (if isSelected then 0.8 else 0),
        3.6 + (if isLeading then 0.35 else 0) + (if isSelected then 0.55 else 0)
    )
    shrineEntry.part.Color = riteConfig.color
    shrineEntry.part.Material = if isSelected
        then Enum.Material.Neon
        elseif isLeading then Enum.Material.SmoothPlastic
        else Enum.Material.Slate

    shrineEntry.light.Color = riteConfig.color
    shrineEntry.light.Brightness = 1 + brightnessBoost + (voteCount * 0.2)
    shrineEntry.light.Range = 10 + (voteCount * 2) + (if isSelected then 6 else 0)

    shrineEntry.label.Text = string.format(
        "%s\n%s\nHold to vote | %d vote%s",
        riteConfig.title,
        riteConfig.summary,
        voteCount,
        if voteCount == 1 then "" else "s"
    )
    shrineEntry.label.TextColor3 = if isSelected
        then Color3.fromRGB(255, 248, 232)
        else riteConfig.color

    shrineEntry.prompt.ActionText = string.format("Bind %s", riteConfig.title)
    shrineEntry.prompt.ObjectText = string.format(
        "%s | Hold to vote | %d vote%s",
        riteConfig.summary,
        voteCount,
        if voteCount == 1 then "" else "s"
    )
    shrineEntry.prompt.Enabled = riteState.phaseName == "DayPrep" and not riteState.lockedIn
end

local function refreshShrineVisuals()
    for _, riteName in ipairs(getRiteOrder()) do
        updateShrineVisuals(riteName)
    end
end

local function applyRiteState(nextState)
    setRiteState(nextState)
    refreshShrineVisuals()
    broadcastRiteState()
end

local function handleVote(player: Player, riteName: string)
    if riteState.phaseName ~= "DayPrep" or riteState.lockedIn then
        return
    end

    if getRiteConfig(riteName) == nil then
        return
    end

    votesByUserId[player.UserId] = riteName
    applyRiteState(buildRiteState("DayPrep", riteState.roundNumber, false, "", nil))
end

local function buildShrine(riteName: string, index: number, totalShrines: number)
    local folder = getShrineFolder()
    local riteConfig = getRiteConfig(riteName)
    local existingShrine = folder:FindFirstChild(riteName)
    local shrinePart = existingShrine

    if shrinePart == nil then
        shrinePart = Instance.new("Part")
        shrinePart.Name = riteName
        shrinePart.Anchored = true
        shrinePart.Parent = folder
    end

    shrinePart.Size = Vector3.new(3.6, 7, 3.6)
    shrinePart.Position = buildShrinePosition(index, totalShrines)
    shrinePart.CFrame = CFrame.lookAt(shrinePart.Position, objectiveService.getCampCenter())
    shrinePart.TopSurface = Enum.SurfaceType.Smooth
    shrinePart.BottomSurface = Enum.SurfaceType.Smooth

    local prompt = shrinePart:FindFirstChild("VotePrompt")
    if prompt == nil then
        prompt = Instance.new("ProximityPrompt")
        prompt.Name = "VotePrompt"
        prompt.HoldDuration = 0.55
        prompt.MaxActivationDistance = 12
        prompt.Parent = shrinePart

        prompt.Triggered:Connect(function(player)
            handleVote(player, riteName)
        end)
    end

    local light = shrinePart:FindFirstChild("ShrineLight")
    if light == nil then
        light = Instance.new("PointLight")
        light.Name = "ShrineLight"
        light.Parent = shrinePart
    end

    local billboard = shrinePart:FindFirstChild("RiteBillboard")
    if billboard == nil then
        billboard = Instance.new("BillboardGui")
        billboard.Name = "RiteBillboard"
        billboard.Size = UDim2.fromOffset(188, 86)
        billboard.StudsOffset = Vector3.new(0, 6.2, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = shrinePart
    end

    local label = billboard:FindFirstChild("RiteLabel")
    if label == nil then
        label = Instance.new("TextLabel")
        label.Name = "RiteLabel"
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.TextWrapped = true
        label.Parent = billboard
    end

    label.TextStrokeTransparency = 0.4
    label.Text =
        string.format("%s\n%s\nHold to vote | 0 votes", riteConfig.title, riteConfig.summary)

    shrineEntriesByName[riteName] = {
        part = shrinePart,
        prompt = prompt,
        light = light,
        label = label,
    }

    updateShrineVisuals(riteName)
end

function RiteService.initialize(dependencies)
    objectiveService = dependencies.objectiveService

    for index, riteName in ipairs(getRiteOrder()) do
        buildShrine(riteName, index, #getRiteOrder())
    end

    Players.PlayerRemoving:Connect(function(player)
        if votesByUserId[player.UserId] == nil then
            return
        end

        votesByUserId[player.UserId] = nil

        if riteState.phaseName == "DayPrep" and not riteState.lockedIn then
            applyRiteState(buildRiteState("DayPrep", riteState.roundNumber, false, "", nil))
        end
    end)

    applyRiteState(buildRiteState("Lobby", 0, false, "", nil))
end

function RiteService.startDayPhase(roundNumber: number)
    votesByUserId = {}
    applyRiteState(buildRiteState("DayPrep", roundNumber, false, "", nil))

    return riteState
end

function RiteService.startNightPhase(roundNumber: number)
    local selectedRiteName = determineLeadingRiteName(roundNumber, getVoteCounts())
    applyRiteState(buildRiteState("NightSurvival", roundNumber, true, selectedRiteName, nil))

    return riteState
end

function RiteService.finishRound(roundNumber: number)
    local selectedRiteName = riteState.selectedRiteName

    if selectedRiteName == "" then
        selectedRiteName = determineLeadingRiteName(roundNumber, getVoteCounts())
    end

    applyRiteState(buildRiteState("Results", roundNumber, true, selectedRiteName, nil))

    return riteState
end

function RiteService.getNightModifiers()
    local selectedRiteName = riteState.selectedRiteName

    if selectedRiteName == "" then
        return EMPTY_MODIFIERS
    end

    local riteConfig = getRiteConfig(selectedRiteName)

    if riteConfig == nil then
        return EMPTY_MODIFIERS
    end

    return riteConfig.modifiers
end

function RiteService.getSelectedRiteName(): string
    return riteState.selectedRiteName
end

function RiteService.getPlayerVotedRiteName(player: Player): string
    return getVotedRiteNameForUserId(player.UserId)
end

function RiteService.getRiteTitle(riteName: string): string
    local riteConfig = getRiteConfig(riteName)

    if riteConfig == nil then
        return ""
    end

    return riteConfig.title
end

function RiteService.getState()
    return riteState
end

function RiteService.syncPlayer(player: Player)
    pushRiteState(player)
end

return RiteService
