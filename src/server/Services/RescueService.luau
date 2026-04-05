local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))

local RescueService = {}

local objectiveService = nil
local currentNightToken = 0
local refreshLoopToken = 0
local downedEntriesByUserId = {}
local activeSurge = nil
local rescueState = table.freeze({
    phaseName = "Lobby",
    roundNumber = 0,
    activeDownedCount = 0,
    totalRevives = 0,
    totalBleedouts = 0,
    activeSurgeLaneName = "",
    activeSurgeRemainingSeconds = 0,
    activeSurgeReviverName = "",
    activeSurgeRescuedName = "",
    downedPlayers = table.freeze({}),
})
local totalRevives = 0
local totalBleedouts = 0

local EMPTY_LANE_MODIFIERS = table.freeze({
    towerDamageBonus = 0,
    towerRangeBonus = 0,
    barricadeMitigationBonus = 0,
})

local EMPTY_COMBAT_MODIFIERS = table.freeze({
    meleeDamageBonus = 0,
    pulseDamageBonus = 0,
    pulseCooldownDelta = 0,
})

local function getRemoteEvent(): RemoteEvent
    local remoteFolder = ReplicatedStorage:WaitForChild(RemoteNames.Folder)
    return remoteFolder:WaitForChild(RemoteNames.RescueStateChanged) :: RemoteEvent
end

local function getCharacterState(player: Player)
    local character = player.Character

    if character == nil then
        return nil, nil, nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")

    return character, humanoid, rootPart
end

local function getRemainingBleedoutSeconds(entry): number
    return math.max(0, math.ceil(entry.bleedoutEndsAt - os.clock()))
end

local function getActiveSurgeRemainingSeconds(): number
    if activeSurge == nil then
        return 0
    end

    return math.max(0, math.ceil(activeSurge.endsAt - os.clock()))
end

local function buildDownedSnapshots()
    local snapshots = {}

    for userId, entry in pairs(downedEntriesByUserId) do
        local player = Players:GetPlayerByUserId(userId)

        if player ~= nil then
            table.insert(snapshots, {
                userId = userId,
                name = player.Name,
                displayName = player.DisplayName,
                laneName = entry.laneName,
                bleedoutRemainingSeconds = getRemainingBleedoutSeconds(entry),
            })
        end
    end

    table.sort(snapshots, function(left, right)
        if left.bleedoutRemainingSeconds == right.bleedoutRemainingSeconds then
            return left.displayName < right.displayName
        end

        return left.bleedoutRemainingSeconds < right.bleedoutRemainingSeconds
    end)

    local frozenSnapshots = {}

    for _, snapshot in ipairs(snapshots) do
        table.insert(frozenSnapshots, table.freeze(snapshot))
    end

    return table.freeze(frozenSnapshots)
end

local function rebuildState(phaseName: string, roundNumber: number)
    if activeSurge ~= nil and activeSurge.endsAt <= os.clock() then
        activeSurge = nil
    end

    rescueState = table.freeze({
        phaseName = phaseName,
        roundNumber = roundNumber,
        activeDownedCount = #buildDownedSnapshots(),
        totalRevives = totalRevives,
        totalBleedouts = totalBleedouts,
        activeSurgeLaneName = if activeSurge ~= nil then activeSurge.laneName else "",
        activeSurgeRemainingSeconds = getActiveSurgeRemainingSeconds(),
        activeSurgeReviverName = if activeSurge ~= nil then activeSurge.reviverDisplayName else "",
        activeSurgeRescuedName = if activeSurge ~= nil then activeSurge.rescuedDisplayName else "",
        downedPlayers = buildDownedSnapshots(),
    })
end

local function buildPayloadForPlayer(player: Player)
    local entry = downedEntriesByUserId[player.UserId]

    return table.freeze({
        phaseName = rescueState.phaseName,
        roundNumber = rescueState.roundNumber,
        activeDownedCount = rescueState.activeDownedCount,
        totalRevives = rescueState.totalRevives,
        totalBleedouts = rescueState.totalBleedouts,
        activeSurgeLaneName = rescueState.activeSurgeLaneName,
        activeSurgeRemainingSeconds = rescueState.activeSurgeRemainingSeconds,
        activeSurgeReviverName = rescueState.activeSurgeReviverName,
        activeSurgeRescuedName = rescueState.activeSurgeRescuedName,
        downedPlayers = rescueState.downedPlayers,
        localIsDowned = entry ~= nil,
        localDownedLaneName = if entry ~= nil then entry.laneName else "",
        localBleedoutRemainingSeconds = if entry ~= nil
            then getRemainingBleedoutSeconds(entry)
            else 0,
    })
end

local function pushState(player: Player)
    getRemoteEvent():FireClient(player, buildPayloadForPlayer(player))
end

local function broadcastState()
    for _, player in ipairs(Players:GetPlayers()) do
        pushState(player)
    end
end

local function refreshState(phaseName: string, roundNumber: number)
    rebuildState(phaseName, roundNumber)
    broadcastState()
end

local function ensureRefreshLoop()
    refreshLoopToken += 1

    if rescueState.phaseName ~= "NightSurvival" then
        return
    end

    local loopToken = refreshLoopToken
    task.spawn(function()
        while
            loopToken == refreshLoopToken
            and rescueState.phaseName == "NightSurvival"
            and (rescueState.activeDownedCount > 0 or rescueState.activeSurgeRemainingSeconds > 0)
        do
            rebuildState(rescueState.phaseName, rescueState.roundNumber)
            broadcastState()
            task.wait(0.5)
        end
    end)
end

local function clearEntryArtifacts(entry)
    if entry.promptConnection ~= nil then
        entry.promptConnection:Disconnect()
        entry.promptConnection = nil
    end

    if entry.revivePrompt ~= nil and entry.revivePrompt.Parent ~= nil then
        entry.revivePrompt:Destroy()
    end

    if entry.highlight ~= nil and entry.highlight.Parent ~= nil then
        entry.highlight:Destroy()
    end
end

local function removeDownedEntry(userId: number)
    local entry = downedEntriesByUserId[userId]

    if entry == nil then
        return nil
    end

    downedEntriesByUserId[userId] = nil
    clearEntryArtifacts(entry)

    return entry
end

local function restoreStandingState(player: Player, entry, healthAmount: number)
    player:SetAttribute("IsDowned", false)
    player:SetAttribute("DownedLaneName", "")

    local _, humanoid = getCharacterState(player)

    if humanoid == nil then
        return
    end

    humanoid.WalkSpeed = entry.originalWalkSpeed
    humanoid.AutoRotate = entry.originalAutoRotate

    if humanoid.UseJumpPower then
        humanoid.JumpPower = entry.originalJumpPower
    else
        humanoid.JumpHeight = entry.originalJumpHeight
    end

    if humanoid.Health > 0 then
        humanoid.Health = math.max(humanoid.Health, healthAmount)
    end
end

local function moveCharacterToCamp(player: Player, desiredHealth: number)
    local connection = nil

    connection = player.CharacterAdded:Connect(function(character)
        if connection ~= nil then
            connection:Disconnect()
            connection = nil
        end

        task.defer(function()
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local rootPart = character:FindFirstChild("HumanoidRootPart")

            player:SetAttribute("IsDowned", false)
            player:SetAttribute("DownedLaneName", "")

            if humanoid ~= nil then
                humanoid.Health = math.max(humanoid.Health, desiredHealth)
            end

            if rootPart ~= nil and objectiveService ~= nil then
                rootPart.CFrame =
                    CFrame.new(objectiveService.getCampCenter() + Vector3.new(0, 6, 0))
            end
        end)
    end)

    player:LoadCharacter()
end

local function applyDownedState(player: Player, laneName: string)
    if rescueState.phaseName ~= "NightSurvival" then
        return false
    end

    if downedEntriesByUserId[player.UserId] ~= nil then
        return false
    end

    local character, humanoid, rootPart = getCharacterState(player)

    if character == nil or humanoid == nil or rootPart == nil or humanoid.Health <= 0 then
        return false
    end

    local revivePrompt = Instance.new("ProximityPrompt")
    revivePrompt.Name = "RevivePrompt"
    revivePrompt.ActionText = "Revive"
    revivePrompt.ObjectText = string.format("%s | %s lane", player.DisplayName, laneName)
    revivePrompt.HoldDuration = GameConfig.RescueTuning.ReviveHoldSeconds
    revivePrompt.MaxActivationDistance = 12
    revivePrompt.RequiresLineOfSight = false
    revivePrompt.Parent = rootPart

    local highlight = Instance.new("Highlight")
    highlight.Name = "DownedHighlight"
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.55
    highlight.OutlineTransparency = 0.05
    highlight.FillColor = Color3.fromRGB(255, 170, 110)
    highlight.OutlineColor = Color3.fromRGB(255, 238, 198)
    highlight.Parent = character

    local entry = {
        laneName = laneName,
        bleedoutEndsAt = os.clock() + GameConfig.RescueTuning.BleedoutSeconds,
        revivePrompt = revivePrompt,
        highlight = highlight,
        originalWalkSpeed = humanoid.WalkSpeed,
        originalJumpPower = humanoid.JumpPower,
        originalJumpHeight = humanoid.JumpHeight,
        originalAutoRotate = humanoid.AutoRotate,
        promptConnection = nil,
    }

    player:SetAttribute("IsDowned", true)
    player:SetAttribute("DownedLaneName", laneName)
    humanoid:UnequipTools()
    humanoid.WalkSpeed = GameConfig.RescueTuning.DownedWalkSpeed
    humanoid.AutoRotate = false

    if humanoid.UseJumpPower then
        humanoid.JumpPower = GameConfig.RescueTuning.DownedJumpPower
    else
        humanoid.JumpHeight = 0
    end

    humanoid.Health =
        math.max(1, math.min(humanoid.MaxHealth, GameConfig.RescueTuning.DownedHealth))

    entry.promptConnection = revivePrompt.Triggered:Connect(function(reviver)
        if reviver == nil or reviver.UserId == player.UserId then
            return
        end

        if RescueService.isPlayerDowned(reviver) then
            return
        end

        local _, reviverHumanoid, reviverRootPart = getCharacterState(reviver)

        if reviverHumanoid == nil or reviverHumanoid.Health <= 0 or reviverRootPart == nil then
            return
        end

        local _, _, targetRootPart = getCharacterState(player)

        if targetRootPart == nil then
            return
        end

        if (reviverRootPart.Position - targetRootPart.Position).Magnitude > 14 then
            return
        end

        local removedEntry = removeDownedEntry(player.UserId)

        if removedEntry == nil then
            return
        end

        totalRevives += 1
        activeSurge = {
            laneName = removedEntry.laneName,
            endsAt = os.clock() + GameConfig.RescueTuning.SurgeDurationSeconds,
            reviverDisplayName = reviver.DisplayName,
            rescuedDisplayName = player.DisplayName,
        }
        restoreStandingState(player, removedEntry, GameConfig.RescueTuning.ReviveHealth)
        reviver:SetAttribute("LastRescueAt", os.time())
        refreshState(rescueState.phaseName, rescueState.roundNumber)
        ensureRefreshLoop()
    end)

    downedEntriesByUserId[player.UserId] = entry
    refreshState(rescueState.phaseName, rescueState.roundNumber)
    ensureRefreshLoop()

    local nightToken = currentNightToken
    task.spawn(function()
        task.wait(GameConfig.RescueTuning.BleedoutSeconds)

        if rescueState.phaseName ~= "NightSurvival" or nightToken ~= currentNightToken then
            return
        end

        local removedEntry = removeDownedEntry(player.UserId)

        if removedEntry == nil then
            return
        end

        totalBleedouts += 1
        player:SetAttribute("IsDowned", false)
        player:SetAttribute("DownedLaneName", "")
        refreshState(rescueState.phaseName, rescueState.roundNumber)
        ensureRefreshLoop()
        moveCharacterToCamp(player, GameConfig.RescueTuning.RespawnHealth)
    end)

    return true
end

local function clearAllDownedEntries(healthAmount: number)
    for userId, _ in pairs(downedEntriesByUserId) do
        local removedEntry = removeDownedEntry(userId)
        local player = Players:GetPlayerByUserId(userId)

        if removedEntry ~= nil and player ~= nil then
            restoreStandingState(player, removedEntry, healthAmount)
        end
    end
end

function RescueService.initialize(dependencies)
    objectiveService = dependencies.objectiveService

    local function attachCharacterReset(player: Player)
        player:SetAttribute("IsDowned", false)
        player:SetAttribute("DownedLaneName", "")

        player.CharacterAdded:Connect(function()
            local removedEntry = removeDownedEntry(player.UserId)

            if removedEntry ~= nil then
                refreshState(rescueState.phaseName, rescueState.roundNumber)
                ensureRefreshLoop()
            end

            player:SetAttribute("IsDowned", false)
            player:SetAttribute("DownedLaneName", "")
        end)
    end

    Players.PlayerAdded:Connect(attachCharacterReset)
    Players.PlayerRemoving:Connect(function(player)
        local removedEntry = removeDownedEntry(player.UserId)

        if removedEntry ~= nil then
            refreshState(rescueState.phaseName, rescueState.roundNumber)
            ensureRefreshLoop()
        end
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        attachCharacterReset(player)
    end

    rebuildState("Lobby", 0)
    broadcastState()
end

function RescueService.startNightPhase(roundNumber: number)
    currentNightToken += 1
    totalRevives = 0
    totalBleedouts = 0
    activeSurge = nil
    clearAllDownedEntries(GameConfig.RescueTuning.RespawnHealth)
    refreshState("NightSurvival", roundNumber)

    return rescueState
end

function RescueService.finishRound(roundNumber: number)
    currentNightToken += 1
    activeSurge = nil
    clearAllDownedEntries(GameConfig.RescueTuning.RespawnHealth)
    refreshState("Results", roundNumber)

    return rescueState
end

function RescueService.findInterceptTarget(threatPosition: Vector3)
    if rescueState.phaseName ~= "NightSurvival" then
        return nil
    end

    local nearestTarget = nil
    local nearestDistance = GameConfig.RescueTuning.PlayerInterceptDistance

    for _, player in ipairs(Players:GetPlayers()) do
        if not RescueService.isPlayerDowned(player) then
            local _, humanoid, rootPart = getCharacterState(player)

            if humanoid ~= nil and humanoid.Health > 0 and rootPart ~= nil then
                local distance = (rootPart.Position - threatPosition).Magnitude

                if distance <= nearestDistance then
                    nearestTarget = {
                        player = player,
                        position = rootPart.Position,
                        distance = distance,
                    }
                    nearestDistance = distance
                end
            end
        end
    end

    return nearestTarget
end

function RescueService.getDownedCountForLane(laneName: string): number
    local downedCount = 0

    for _, entry in pairs(downedEntriesByUserId) do
        if entry.laneName == laneName then
            downedCount += 1
        end
    end

    return downedCount
end

function RescueService.getPriorityLaneName(threatTypeName: string, allowedLaneNames)
    if rescueState.phaseName ~= "NightSurvival" then
        return nil
    end

    local allowedLookup = {}

    if type(allowedLaneNames) == "table" and #allowedLaneNames > 0 then
        for _, laneName in ipairs(allowedLaneNames) do
            allowedLookup[laneName] = true
        end
    end

    local function laneAllowed(laneName: string): boolean
        if next(allowedLookup) == nil then
            return true
        end

        return allowedLookup[laneName] == true
    end

    if threatTypeName == "Runner" then
        local bestLaneName = nil
        local shortestBleedout = math.huge

        for _, entry in pairs(downedEntriesByUserId) do
            local remainingSeconds = getRemainingBleedoutSeconds(entry)

            if laneAllowed(entry.laneName) and remainingSeconds < shortestBleedout then
                bestLaneName = entry.laneName
                shortestBleedout = remainingSeconds
            end
        end

        return bestLaneName
    end

    if
        threatTypeName == "Sapper"
        and activeSurge ~= nil
        and activeSurge.endsAt > os.clock()
        and laneAllowed(activeSurge.laneName)
    then
        return activeSurge.laneName
    end

    return nil
end

function RescueService.applyThreatHit(player: Player, damageAmount: number, laneName: string)
    if rescueState.phaseName ~= "NightSurvival" or RescueService.isPlayerDowned(player) then
        return false
    end

    local _, humanoid = getCharacterState(player)

    if humanoid == nil or humanoid.Health <= 0 then
        return false
    end

    local postHitHealth = humanoid.Health - damageAmount

    if postHitHealth > GameConfig.RescueTuning.DownedHealth then
        humanoid.Health = postHitHealth
        return true
    end

    return applyDownedState(player, laneName)
end

function RescueService.isPlayerDowned(player: Player): boolean
    return downedEntriesByUserId[player.UserId] ~= nil or player:GetAttribute("IsDowned") == true
end

function RescueService.getLaneModifiers(laneName: string)
    if
        rescueState.phaseName ~= "NightSurvival"
        or activeSurge == nil
        or activeSurge.laneName ~= laneName
        or activeSurge.endsAt <= os.clock()
    then
        return EMPTY_LANE_MODIFIERS
    end

    return table.freeze({
        towerDamageBonus = GameConfig.RescueTuning.SurgeTowerDamageBonus,
        towerRangeBonus = GameConfig.RescueTuning.SurgeTowerRangeBonus,
        barricadeMitigationBonus = GameConfig.RescueTuning.SurgeBarricadeMitigationBonus,
    })
end

function RescueService.getCombatModifiers()
    if
        rescueState.phaseName ~= "NightSurvival"
        or activeSurge == nil
        or activeSurge.endsAt <= os.clock()
    then
        return EMPTY_COMBAT_MODIFIERS
    end

    return table.freeze({
        meleeDamageBonus = GameConfig.RescueTuning.SurgeMeleeDamageBonus,
        pulseDamageBonus = GameConfig.RescueTuning.SurgePulseDamageBonus,
        pulseCooldownDelta = GameConfig.RescueTuning.SurgePulseCooldownDelta,
    })
end

function RescueService.getState()
    return rescueState
end

function RescueService.syncPlayer(player: Player)
    pushState(player)
end

return RescueService
