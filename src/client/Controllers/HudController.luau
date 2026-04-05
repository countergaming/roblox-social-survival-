local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))

local HudController = {}

local hudRefs = nil
local latestDutyState = nil
local latestObjectiveState = nil
local latestEchoState = nil
local latestDefenseState = nil
local latestThreatState = nil
local latestRoleState = nil
local latestRiteState = nil
local latestRescueState = nil
local latestPhasePayload = nil
local latestPublicProfile = nil
local renderRescueSurgeSummary

local function ensureRiteLabel(frame)
    local existingRiteLabel = frame:FindFirstChild("RiteLabel")

    if existingRiteLabel ~= nil then
        return existingRiteLabel
    end

    local riteLabel = Instance.new("TextLabel")
    riteLabel.Name = "RiteLabel"
    riteLabel.BackgroundTransparency = 1
    riteLabel.Position = UDim2.fromOffset(16, 76)
    riteLabel.Size = UDim2.fromOffset(508, 22)
    riteLabel.Font = Enum.Font.GothamMedium
    riteLabel.TextSize = 14
    riteLabel.TextColor3 = Color3.fromRGB(232, 196, 122)
    riteLabel.TextXAlignment = Enum.TextXAlignment.Left
    riteLabel.Text = "Rite: waiting"
    riteLabel.Parent = frame

    return riteLabel
end

local function ensureEchoLabel(frame)
    local existingEchoLabel = frame:FindFirstChild("EchoLabel")

    if existingEchoLabel ~= nil then
        return existingEchoLabel
    end

    local echoLabel = Instance.new("TextLabel")
    echoLabel.Name = "EchoLabel"
    echoLabel.BackgroundTransparency = 1
    echoLabel.Position = UDim2.fromOffset(16, 98)
    echoLabel.Size = UDim2.fromOffset(508, 22)
    echoLabel.Font = Enum.Font.GothamMedium
    echoLabel.TextSize = 14
    echoLabel.TextColor3 = Color3.fromRGB(184, 224, 255)
    echoLabel.TextXAlignment = Enum.TextXAlignment.Left
    echoLabel.Text = "Echo: complete directives to awaken camp boons."
    echoLabel.Parent = frame

    return echoLabel
end

local function ensureObjectiveLabel(frame)
    local existingObjectiveLabel = frame:FindFirstChild("ObjectiveLabel")

    if existingObjectiveLabel ~= nil then
        return existingObjectiveLabel
    end

    local objectiveLabel = Instance.new("TextLabel")
    objectiveLabel.Name = "ObjectiveLabel"
    objectiveLabel.BackgroundTransparency = 1
    objectiveLabel.Position = UDim2.fromOffset(16, 142)
    objectiveLabel.Size = UDim2.fromOffset(508, 22)
    objectiveLabel.Font = Enum.Font.GothamMedium
    objectiveLabel.TextSize = 14
    objectiveLabel.TextColor3 = Color3.fromRGB(194, 226, 180)
    objectiveLabel.TextXAlignment = Enum.TextXAlignment.Left
    objectiveLabel.Text = "Objective: waiting"
    objectiveLabel.Parent = frame

    return objectiveLabel
end

local function ensureRoleLabel(frame)
    local existingRoleLabel = frame:FindFirstChild("RoleLabel")

    if existingRoleLabel ~= nil then
        return existingRoleLabel
    end

    local roleLabel = Instance.new("TextLabel")
    roleLabel.Name = "RoleLabel"
    roleLabel.BackgroundTransparency = 1
    roleLabel.Position = UDim2.fromOffset(16, 120)
    roleLabel.Size = UDim2.fromOffset(508, 22)
    roleLabel.Font = Enum.Font.GothamMedium
    roleLabel.TextSize = 14
    roleLabel.TextColor3 = Color3.fromRGB(194, 206, 255)
    roleLabel.TextXAlignment = Enum.TextXAlignment.Left
    roleLabel.Text = "Role: choose one during Day Prep"
    roleLabel.Parent = frame

    return roleLabel
end

local function ensureStatusLabel(frame)
    local existingStatusLabel = frame:FindFirstChild("StatusLabel")

    if existingStatusLabel ~= nil then
        return existingStatusLabel
    end

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.BackgroundTransparency = 1
    statusLabel.Position = UDim2.fromOffset(16, 236)
    statusLabel.Size = UDim2.fromOffset(508, 22)
    statusLabel.Font = Enum.Font.GothamMedium
    statusLabel.TextSize = 14
    statusLabel.TextColor3 = Color3.fromRGB(140, 202, 255)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Text = "Status: waiting"
    statusLabel.Parent = frame

    return statusLabel
end

local function ensureMissionLabel(frame)
    local existingMissionLabel = frame:FindFirstChild("MissionLabel")

    if existingMissionLabel ~= nil then
        return existingMissionLabel
    end

    local missionLabel = Instance.new("TextLabel")
    missionLabel.Name = "MissionLabel"
    missionLabel.BackgroundTransparency = 1
    missionLabel.Position = UDim2.fromOffset(16, 168)
    missionLabel.Size = UDim2.fromOffset(508, 62)
    missionLabel.Font = Enum.Font.GothamBold
    missionLabel.TextSize = 14
    missionLabel.TextColor3 = Color3.fromRGB(255, 224, 146)
    missionLabel.TextWrapped = true
    missionLabel.TextXAlignment = Enum.TextXAlignment.Left
    missionLabel.TextYAlignment = Enum.TextYAlignment.Top
    missionLabel.Text = "Mission: waiting"
    missionLabel.Parent = frame

    return missionLabel
end

local function ensureAlertLabel(frame)
    local existingAlertLabel = frame:FindFirstChild("AlertLabel")

    if existingAlertLabel ~= nil then
        return existingAlertLabel
    end

    local alertLabel = Instance.new("TextLabel")
    alertLabel.Name = "AlertLabel"
    alertLabel.BackgroundTransparency = 1
    alertLabel.Position = UDim2.fromOffset(16, 258)
    alertLabel.Size = UDim2.fromOffset(508, 22)
    alertLabel.Font = Enum.Font.GothamMedium
    alertLabel.TextSize = 14
    alertLabel.TextColor3 = Color3.fromRGB(255, 162, 122)
    alertLabel.TextXAlignment = Enum.TextXAlignment.Left
    alertLabel.Text = "Alert: standing by"
    alertLabel.Parent = frame

    return alertLabel
end

local function ensureProfileLabel(frame)
    local existingProfileLabel = frame:FindFirstChild("ProfileLabel")

    if existingProfileLabel ~= nil then
        return existingProfileLabel
    end

    local profileLabel = Instance.new("TextLabel")
    profileLabel.Name = "ProfileLabel"
    profileLabel.BackgroundTransparency = 1
    profileLabel.Position = UDim2.fromOffset(16, 404)
    profileLabel.Size = UDim2.fromOffset(508, 22)
    profileLabel.Font = Enum.Font.GothamMedium
    profileLabel.TextSize = 14
    profileLabel.TextColor3 = Color3.fromRGB(255, 210, 112)
    profileLabel.TextXAlignment = Enum.TextXAlignment.Left
    profileLabel.Text = "Profile: waiting"
    profileLabel.Parent = frame

    return profileLabel
end

local function ensureGuideLabel(frame)
    local existingGuideLabel = frame:FindFirstChild("GuideLabel")

    if existingGuideLabel ~= nil then
        return existingGuideLabel
    end

    local guideLabel = Instance.new("TextLabel")
    guideLabel.Name = "GuideLabel"
    guideLabel.BackgroundTransparency = 1
    guideLabel.Position = UDim2.fromOffset(16, 300)
    guideLabel.Size = UDim2.fromOffset(508, 74)
    guideLabel.Font = Enum.Font.Gotham
    guideLabel.TextSize = 15
    guideLabel.TextColor3 = Color3.fromRGB(238, 233, 220)
    guideLabel.TextWrapped = true
    guideLabel.TextXAlignment = Enum.TextXAlignment.Left
    guideLabel.TextYAlignment = Enum.TextYAlignment.Top
    guideLabel.Text = "Guide: waiting for the first round instructions."
    guideLabel.Parent = frame

    return guideLabel
end

local function ensureControlsLabel(frame)
    local existingControlsLabel = frame:FindFirstChild("ControlsLabel")

    if existingControlsLabel ~= nil then
        return existingControlsLabel
    end

    local controlsLabel = Instance.new("TextLabel")
    controlsLabel.Name = "ControlsLabel"
    controlsLabel.BackgroundTransparency = 1
    controlsLabel.Position = UDim2.fromOffset(16, 378)
    controlsLabel.Size = UDim2.fromOffset(508, 30)
    controlsLabel.Font = Enum.Font.GothamMedium
    controlsLabel.TextSize = 13
    controlsLabel.TextColor3 = Color3.fromRGB(174, 198, 216)
    controlsLabel.TextWrapped = true
    controlsLabel.TextXAlignment = Enum.TextXAlignment.Left
    controlsLabel.TextYAlignment = Enum.TextYAlignment.Top
    controlsLabel.Text =
        "Controls: move to objects, hold prompts to interact, click or tap with the Lantern Pike to attack."
    controlsLabel.Parent = frame

    return controlsLabel
end

local function buildHud()
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local existingGui = playerGui:FindFirstChild("LanternKeepHud")

    if existingGui ~= nil then
        existingGui:Destroy()
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "LanternKeepHud"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Name = "Frame"
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.Position = UDim2.fromScale(0.5, 0.03)
    frame.Size = UDim2.fromOffset(540, 432)
    frame.BackgroundColor3 = Color3.fromRGB(22, 29, 34)
    frame.BackgroundTransparency = 0.15
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 16)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 210, 112)
    stroke.Transparency = 0.25
    stroke.Parent = frame

    local phaseLabel = Instance.new("TextLabel")
    phaseLabel.Name = "PhaseLabel"
    phaseLabel.BackgroundTransparency = 1
    phaseLabel.Position = UDim2.fromOffset(16, 10)
    phaseLabel.Size = UDim2.fromOffset(508, 28)
    phaseLabel.Font = Enum.Font.GothamBold
    phaseLabel.TextSize = 24
    phaseLabel.TextColor3 = Color3.fromRGB(255, 244, 214)
    phaseLabel.TextXAlignment = Enum.TextXAlignment.Left
    phaseLabel.Text = "Lantern Keep"
    phaseLabel.Parent = frame

    local detailLabel = Instance.new("TextLabel")
    detailLabel.Name = "DetailLabel"
    detailLabel.BackgroundTransparency = 1
    detailLabel.Position = UDim2.fromOffset(16, 42)
    detailLabel.Size = UDim2.fromOffset(508, 34)
    detailLabel.Font = Enum.Font.Gotham
    detailLabel.TextSize = 16
    detailLabel.TextColor3 = Color3.fromRGB(211, 220, 228)
    detailLabel.TextWrapped = true
    detailLabel.TextXAlignment = Enum.TextXAlignment.Left
    detailLabel.Text = "Waiting for the first phase update."
    detailLabel.Parent = frame

    local riteLabel = ensureRiteLabel(frame)
    local echoLabel = ensureEchoLabel(frame)
    local roleLabel = ensureRoleLabel(frame)
    local objectiveLabel = ensureObjectiveLabel(frame)
    local missionLabel = ensureMissionLabel(frame)
    local statusLabel = ensureStatusLabel(frame)
    local alertLabel = ensureAlertLabel(frame)
    local guideLabel = ensureGuideLabel(frame)
    local controlsLabel = ensureControlsLabel(frame)
    local profileLabel = ensureProfileLabel(frame)

    return {
        screenGui = screenGui,
        phaseLabel = phaseLabel,
        detailLabel = detailLabel,
        riteLabel = riteLabel,
        echoLabel = echoLabel,
        roleLabel = roleLabel,
        objectiveLabel = objectiveLabel,
        missionLabel = missionLabel,
        statusLabel = statusLabel,
        alertLabel = alertLabel,
        guideLabel = guideLabel,
        controlsLabel = controlsLabel,
        profileLabel = profileLabel,
    }
end

local function getRemotes()
    local remoteFolder = ReplicatedStorage:WaitForChild(RemoteNames.Folder)
    local phaseChanged = remoteFolder:WaitForChild(RemoteNames.PhaseChanged) :: RemoteEvent
    local rewardPreview = remoteFolder:WaitForChild(RemoteNames.RewardPreview) :: RemoteEvent
    local profileStateChanged =
        remoteFolder:WaitForChild(RemoteNames.ProfileStateChanged) :: RemoteEvent
    local objectiveStateChanged =
        remoteFolder:WaitForChild(RemoteNames.ObjectiveStateChanged) :: RemoteEvent
    local echoStateChanged = remoteFolder:WaitForChild(RemoteNames.EchoStateChanged) :: RemoteEvent
    local dutyStateChanged = remoteFolder:WaitForChild(RemoteNames.DutyStateChanged) :: RemoteEvent
    local roleStateChanged = remoteFolder:WaitForChild(RemoteNames.RoleStateChanged) :: RemoteEvent
    local riteStateChanged = remoteFolder:WaitForChild(RemoteNames.RiteStateChanged) :: RemoteEvent
    local defenseStateChanged =
        remoteFolder:WaitForChild(RemoteNames.DefenseStateChanged) :: RemoteEvent
    local threatStateChanged =
        remoteFolder:WaitForChild(RemoteNames.ThreatStateChanged) :: RemoteEvent
    local rescueStateChanged =
        remoteFolder:WaitForChild(RemoteNames.RescueStateChanged) :: RemoteEvent

    return phaseChanged,
        rewardPreview,
        profileStateChanged,
        objectiveStateChanged,
        echoStateChanged,
        dutyStateChanged,
        roleStateChanged,
        riteStateChanged,
        defenseStateChanged,
        threatStateChanged,
        rescueStateChanged
end

local function describePhase(payload)
    if payload.name == "Lobby" then
        if payload.metadata.waitingForPlayers then
            return string.format("Waiting for %d more player(s).", payload.metadata.playersNeeded)
        end

        if payload.metadata.tutorialMode then
            return string.format(
                "%s is about to begin.",
                payload.metadata.tutorialTitle or "First Watch"
            )
        end

        return "Round starts soon. Stay near the campfire."
    end

    if payload.name == "DayPrep" then
        if payload.metadata.tutorialMode then
            return string.format(
                "%s: a guided day phase. Fuel the lantern, pick a role, fix %s, charge %s, and vote.",
                payload.metadata.tutorialTitle or "First Watch",
                payload.metadata.targetBarricadeLaneName or "East",
                payload.metadata.targetTowerLaneName or "North"
            )
        end

        return string.format(
            "Collect fuel, choose a role, build mixed-role Concord lanes, and vote on the night rite. Team coverage: %d/3. %s leads right now. Duties: %d/%d complete. Echo boons active: %d.",
            payload.metadata.teamCoverageCount or 0,
            payload.metadata.leadingRiteTitle or "Emberwake",
            payload.metadata.completedDutyCount or 0,
            payload.metadata.activeDutyCount or 0,
            payload.metadata.unlockedBoonCount or 0
        )
    end

    if payload.name == "NightSurvival" then
        if payload.metadata.tutorialMode then
            return string.format(
                "%s: defend %s while you learn the first night rhythm.",
                payload.metadata.tutorialTitle or "First Watch",
                table.concat(payload.metadata.allowedLaneNames or {}, " and ")
            )
        end

        return string.format(
            "Defend the lantern under %s. Threat rate: %.2f | Elite chance: %.0f%% | Duties: %d/%d | Echo boons: %d | Downed: %d",
            payload.metadata.riteTitle or "the current rite",
            payload.metadata.threatRate or 0,
            (payload.metadata.eliteChance or 0) * 100,
            payload.metadata.completedDutyCount or 0,
            payload.metadata.activeDutyCount or 0,
            payload.metadata.unlockedBoonCount or 0,
            payload.metadata.activeDownedCount or 0
        )
    end

    if payload.name == "Results" then
        if payload.metadata.outcome ~= nil then
            local outcome = payload.metadata.outcome

            return string.format(
                "%s | Lantern %.0f%% | Barricades %d/%d | Concord %d | Revives %d | Bleedouts %d",
                if outcome.nightFailed then "Dawn lost" else "Dawn held",
                (outcome.lanternHealthRatio or 0) * 100,
                outcome.barricadesStanding or 0,
                GameConfig.DefenseTuning.BarricadeCount,
                outcome.concordLanes or 0,
                outcome.revivesCompleted or 0,
                outcome.bleedouts or 0
            )
        end

        return "Dawn reached. Rewards granted and the next rite will soon be chosen."
    end

    return "Stay with the team and protect the lantern."
end

local function renderStatus()
    if latestThreatState ~= nil and latestThreatState.phaseName == "NightSurvival" then
        local baseStatus = string.format(
            "%s | Lantern %d/%d | Threats %d | Pulse %ss",
            latestThreatState.waveLabel,
            latestThreatState.lanternHealth,
            latestThreatState.lanternMaxHealth,
            latestThreatState.activeThreats,
            latestThreatState.pulseReadyInSeconds
        )

        if latestRescueState ~= nil then
            local rescueStatus = string.format(
                "%s | Downed %d | Revives %d",
                baseStatus,
                latestRescueState.activeDownedCount or 0,
                latestRescueState.totalRevives or 0
            )
            local rescueSurgeSummary = renderRescueSurgeSummary()

            if rescueSurgeSummary ~= "" then
                return string.format("%s | %s", rescueStatus, rescueSurgeSummary)
            end

            return rescueStatus
        end

        return baseStatus
    end

    if latestDefenseState ~= nil then
        return string.format(
            "Barricades %d/%d | Tower %d%% | Fort %d | Boost %d | Concord %d",
            latestDefenseState.healthyBarricades,
            latestDefenseState.totalBarricades,
            latestDefenseState.averageTowerEnergy,
            latestDefenseState.totalFortificationLevel or 0,
            latestDefenseState.totalOverchargeLevel or 0,
            latestDefenseState.totalConcordLanes or 0
        )
    end

    return "Status: waiting for the next defense phase."
end

local function findDutySnapshot(roleName: string)
    if latestDutyState == nil then
        return nil
    end

    for _, dutySnapshot in ipairs(latestDutyState.duties or {}) do
        if dutySnapshot.name == roleName then
            return dutySnapshot
        end
    end

    return nil
end

local function findMasterySnapshot(categoryName: string, masteryName: string)
    if latestPublicProfile == nil or latestPublicProfile.mastery == nil then
        return nil
    end

    for _, masterySnapshot in ipairs(latestPublicProfile.mastery[categoryName] or {}) do
        if masterySnapshot.name == masteryName then
            return masterySnapshot
        end
    end

    return nil
end

local function getTopMasterySnapshot(categoryName: string)
    if latestPublicProfile == nil or latestPublicProfile.mastery == nil then
        return nil
    end

    local bestSnapshot = nil

    for _, masterySnapshot in ipairs(latestPublicProfile.mastery[categoryName] or {}) do
        if
            bestSnapshot == nil
            or masterySnapshot.level > bestSnapshot.level
            or (
                masterySnapshot.level == bestSnapshot.level
                and masterySnapshot.experience > bestSnapshot.experience
            )
        then
            bestSnapshot = masterySnapshot
        end
    end

    return bestSnapshot
end

local function renderRole()
    if latestRoleState == nil then
        return "Role: choose one during Day Prep"
    end

    if latestRoleState.selectedRoleTitle == "" then
        return string.format(
            "Role: unassigned | Team coverage %d/3 | Choose a role to activate a duty",
            latestRoleState.teamCoverageCount or 0
        )
    end

    local dutySnapshot = findDutySnapshot(latestRoleState.selectedRoleName)
    local dutyText = ""

    if dutySnapshot ~= nil and dutySnapshot.active then
        dutyText = string.format(
            " | Duty %d/%d%s",
            dutySnapshot.currentValue,
            dutySnapshot.targetValue,
            if dutySnapshot.completed then " complete" else ""
        )
    end

    local masteryText = ""
    local masterySnapshot = findMasterySnapshot("roles", latestRoleState.selectedRoleName)

    if masterySnapshot ~= nil then
        masteryText = string.format(
            " | Mastery Lv %d (%d/%d)",
            masterySnapshot.level,
            masterySnapshot.currentLevelExperience,
            masterySnapshot.nextLevelExperience
        )
    end

    return string.format(
        "Role: %s | Team coverage %d/3 | %s%s%s",
        latestRoleState.selectedRoleTitle,
        latestRoleState.teamCoverageCount or 0,
        latestRoleState.selectedRoleSummary,
        dutyText,
        masteryText
    )
end

local function renderRite()
    if latestRiteState == nil then
        return "Rite: waiting for the first vote."
    end

    if latestRiteState.lockedIn and latestRiteState.selectedRiteTitle ~= "" then
        local masterySnapshot = findMasterySnapshot("rites", latestRiteState.selectedRiteName)
        local masteryText = ""

        if masterySnapshot ~= nil then
            masteryText = string.format(
                " | Affinity Lv %d (%d/%d)",
                masterySnapshot.level,
                masterySnapshot.currentLevelExperience,
                masterySnapshot.nextLevelExperience
            )
        end

        return string.format(
            "Rite: %s | %s%s",
            latestRiteState.selectedRiteTitle,
            latestRiteState.selectedRiteSummary,
            masteryText
        )
    end

    local votedMasterySnapshot = nil

    if latestRiteState.votedRiteName ~= "" then
        votedMasterySnapshot = findMasterySnapshot("rites", latestRiteState.votedRiteName)
    end

    local masteryText = ""
    if votedMasterySnapshot ~= nil then
        masteryText = string.format(" | Your affinity Lv %d", votedMasterySnapshot.level)
    end

    return string.format(
        "Rite Vote: %s leading with %d vote%s%s",
        latestRiteState.leadingRiteTitle,
        latestRiteState.leadingRiteVotes or 0,
        if (latestRiteState.leadingRiteVotes or 0) == 1 then "" else "s",
        masteryText
    )
end

local function checkbox(isComplete: boolean): string
    if isComplete then
        return "[x]"
    end

    return "[ ]"
end

local function renderEcho()
    if latestEchoState == nil then
        return "Echo: complete directives to awaken camp boons."
    end

    if latestEchoState.unlockedBoonCount == 0 then
        return "Echo: no boons awakened yet. Clear nights after finishing directives."
    end

    local boonTitles = {}

    for _, boonSnapshot in ipairs(latestEchoState.unlockedBoons or {}) do
        table.insert(boonTitles, boonSnapshot.title)
    end

    local latestUnlockText = ""
    if latestEchoState.latestUnlockedBoonTitle ~= "" then
        latestUnlockText = string.format(" | New: %s", latestEchoState.latestUnlockedBoonTitle)
    end

    return string.format(
        "Echo Boons (%d): %s%s",
        latestEchoState.unlockedBoonCount,
        table.concat(boonTitles, ", "),
        latestUnlockText
    )
end

local function renderDutySummary()
    if latestDutyState == nil or #latestDutyState.duties == 0 then
        return ""
    end

    local dutySegments = {}

    for _, dutySnapshot in ipairs(latestDutyState.duties) do
        if dutySnapshot.active then
            table.insert(
                dutySegments,
                string.format(
                    "%s %s %d/%d",
                    checkbox(dutySnapshot.completed),
                    dutySnapshot.name,
                    dutySnapshot.currentValue,
                    dutySnapshot.targetValue
                )
            )
        end
    end

    if #dutySegments == 0 then
        return "No active duties yet. Choose roles first."
    end

    return table.concat(dutySegments, " | ")
end

local function renderDirectiveSummary()
    if latestEchoState == nil or #latestEchoState.directives == 0 then
        return ""
    end

    local directiveSegments = {}

    for _, directiveSnapshot in ipairs(latestEchoState.directives) do
        table.insert(
            directiveSegments,
            string.format(
                "%s %s %d/%d",
                checkbox(directiveSnapshot.completed),
                directiveSnapshot.shortTitle,
                directiveSnapshot.currentValue,
                directiveSnapshot.targetValue
            )
        )
    end

    return table.concat(directiveSegments, " | ")
end

local function findLaneState(laneName: string)
    if latestDefenseState == nil then
        return nil
    end

    for _, laneState in ipairs(latestDefenseState.lanes or {}) do
        if laneState.name == laneName then
            return laneState
        end
    end

    return nil
end

local function isTutorialMode(): boolean
    return latestPhasePayload ~= nil and latestPhasePayload.metadata.tutorialMode == true
end

function renderRescueSurgeSummary(): string
    if latestRescueState == nil then
        return ""
    end

    if
        (latestRescueState.activeSurgeRemainingSeconds or 0) <= 0
        or latestRescueState.activeSurgeLaneName == ""
    then
        return ""
    end

    return string.format(
        "Rally %s %ss",
        latestRescueState.activeSurgeLaneName,
        latestRescueState.activeSurgeRemainingSeconds or 0
    )
end

local function renderThreatCounterplayHint(threatTypeName: string): string
    if threatTypeName == "Runner" then
        return "Runners rush downed lanes, so peel fast when a revive starts."
    end

    if threatTypeName == "Brute" then
        return "Brutes slam in an area, so do not stack on a barricade or revive."
    end

    if threatTypeName == "Sapper" then
        return "Sappers drain tower charge and break overcharge, so shut them down early."
    end

    return "Watch lane beacons and rotate before pressure snowballs."
end

local function renderMission()
    local phaseName = if latestPhasePayload ~= nil then latestPhasePayload.name else "Lobby"

    if phaseName == "Lobby" then
        if isTutorialMode() then
            return "Mission: briefing for the guided First Watch."
        end

        return "Mission: regroup in camp and wait for the next cycle."
    end

    if phaseName == "DayPrep" then
        if isTutorialMode() then
            local targetBarricadeLaneName = latestPhasePayload.metadata.targetBarricadeLaneName
                or "East"
            local targetTowerLaneName = latestPhasePayload.metadata.targetTowerLaneName or "North"
            local targetBarricadeLaneState = findLaneState(targetBarricadeLaneName)
            local targetTowerLaneState = findLaneState(targetTowerLaneName)
            local cratesDone = latestObjectiveState ~= nil
                and latestObjectiveState.resourcesCollected
                    >= latestObjectiveState.resourcesRequired
            local roleDone = latestRoleState ~= nil and latestRoleState.selectedRoleName ~= ""
            local repairDone = targetBarricadeLaneState ~= nil
                and targetBarricadeLaneState.barricadeIntegrity >= 98
            local chargeDone = targetTowerLaneState ~= nil
                and targetTowerLaneState.towerEnergy >= 80
            local voteDone = latestRiteState ~= nil and latestRiteState.votedRiteName ~= ""

            return table.concat({
                "Mission: First Watch checklist",
                string.format("  %s Gather fuel", checkbox(cratesDone)),
                string.format("  %s Choose a role", checkbox(roleDone)),
                string.format("  %s Repair %s lane", checkbox(repairDone), targetBarricadeLaneName),
                string.format("  %s Charge %s tower", checkbox(chargeDone), targetTowerLaneName),
                string.format("  %s Bind a rite vote", checkbox(voteDone)),
            }, " | ")
        end

        local fuelDone = latestObjectiveState ~= nil
            and latestObjectiveState.resourcesCollected
                >= latestObjectiveState.resourcesRequired
        local roleDone = latestRoleState ~= nil and latestRoleState.selectedRoleName ~= ""
        local voteDone = latestRiteState ~= nil and latestRiteState.votedRiteName ~= ""
        local directiveSummary = renderDirectiveSummary()
        local missionSegments = {
            "Mission:",
            string.format("%s fuel", checkbox(fuelDone)),
            string.format("%s role", checkbox(roleDone)),
            string.format("%s shrine vote", checkbox(voteDone)),
            "invest supplies into one or two lanes",
        }
        local dutySummary = renderDutySummary()

        if directiveSummary ~= "" then
            table.insert(missionSegments, "| Directives: " .. directiveSummary)
        end

        if dutySummary ~= "" then
            table.insert(missionSegments, "| Duties: " .. dutySummary)
        end

        return table.concat(missionSegments, " ")
    end

    if phaseName == "NightSurvival" then
        if latestRescueState ~= nil and latestRescueState.localIsDowned then
            return string.format(
                "Mission: stay alive for rescue on %s lane | bleedout in %ss | watch teammates clear space around you",
                latestRescueState.localDownedLaneName or "the active",
                latestRescueState.localBleedoutRemainingSeconds or 0
            )
        end

        local tutorialPrefix = if isTutorialMode()
            then "Mission: Guided watch"
            else "Mission: Hold until dawn"
        local allowedLaneNames = if latestPhasePayload ~= nil
            then latestPhasePayload.metadata.allowedLaneNames
            else nil
        local laneText = if type(allowedLaneNames) == "table" and #allowedLaneNames > 0
            then table.concat(allowedLaneNames, " / ")
            else "all lanes"
        local directiveSummary = renderDirectiveSummary()
        local dutySummary = renderDutySummary()
        local rescueSurgeSummary = renderRescueSurgeSummary()
        local rescueSummary = if latestRescueState ~= nil
            then string.format(
                " | Downed %d | Revives %d",
                latestRescueState.activeDownedCount or 0,
                latestRescueState.totalRevives or 0
            )
            else ""
        local baseMission = string.format(
            "%s | defend %s | Defeated %d | Live threats %d | Pulse in %ss%s",
            tutorialPrefix,
            laneText,
            if latestThreatState ~= nil then latestThreatState.defeatedThreats else 0,
            if latestThreatState ~= nil then latestThreatState.activeThreats else 0,
            if latestThreatState ~= nil then latestThreatState.pulseReadyInSeconds else 0,
            rescueSummary
        )

        if rescueSurgeSummary ~= "" then
            baseMission = string.format("%s | %s", baseMission, rescueSurgeSummary)
        end

        if directiveSummary == "" and dutySummary == "" then
            return baseMission
        end

        local suffixSegments = {}

        if directiveSummary ~= "" then
            table.insert(suffixSegments, "Directives: " .. directiveSummary)
        end

        if dutySummary ~= "" then
            table.insert(suffixSegments, "Duties: " .. dutySummary)
        end

        return string.format("%s | %s", baseMission, table.concat(suffixSegments, " | "))
    end

    if latestThreatState ~= nil and latestThreatState.nightFailed then
        return "Mission: review the collapse, rebuild weak lanes, and try the next watch."
    end

    if latestPhasePayload ~= nil and latestPhasePayload.metadata.outcome ~= nil then
        local outcome = latestPhasePayload.metadata.outcome

        return string.format(
            "Mission: %s | lantern %.0f%% | supplies spent %d | team coverage %d/3 | concord lanes %d | revives %d | bleedouts %d%s",
            if outcome.nightFailed then "learn from the collapse" else "bank the win and scale up",
            (outcome.lanternHealthRatio or 0) * 100,
            outcome.suppliesSpent or 0,
            outcome.teamCoverageCount or 0,
            outcome.concordLanes or 0,
            outcome.revivesCompleted or 0,
            outcome.bleedouts or 0,
            if latestEchoState ~= nil and latestEchoState.latestUnlockedBoonTitle ~= ""
                then string.format(" | Echo unlocked: %s", latestEchoState.latestUnlockedBoonTitle)
                else ""
        )
    end

    return "Mission: cash out rewards, regroup, and prepare the next rite."
end

local function renderGuide()
    local phaseName = if latestPhasePayload ~= nil then latestPhasePayload.name else "Lobby"

    if phaseName == "Lobby" then
        if isTutorialMode() then
            return table.concat({
                "What to do now:",
                "1. Read the two camp boards and stay close to the lantern.",
                "2. The first round is guided, so use it to learn the loop instead of rushing.",
                "3. When Day Prep opens, follow the mission checklist from left to right.",
            }, "\n")
        end

        return table.concat({
            "What to do now:",
            "1. Stay near the camp until the lobby countdown ends.",
            "2. Read the boards beside spawn so you know the round loop.",
            "3. Get ready to choose a role as soon as Day Prep begins.",
        }, "\n")
    end

    if phaseName == "DayPrep" then
        if isTutorialMode() then
            local targetBarricadeLaneName = latestPhasePayload.metadata.targetBarricadeLaneName
                or "East"
            local targetTowerLaneName = latestPhasePayload.metadata.targetTowerLaneName or "North"

            return table.concat({
                string.format(
                    "What to do now in %s:",
                    latestPhasePayload.metadata.tutorialTitle or "First Watch"
                ),
                "1. Collect the nearby fuel crates until the lantern is charged enough to survive.",
                "2. Choose any role, then coordinate so different roles touch the same lane later.",
                string.format(
                    "3. Repair %s lane first, then charge %s tower so players learn both prompts.",
                    targetBarricadeLaneName,
                    targetTowerLaneName
                ),
                "4. Vote at any shrine before night starts so you feel the rite system immediately.",
            }, "\n")
        end

        local leadingRiteTitle = if latestRiteState ~= nil
                and latestRiteState.leadingRiteTitle ~= ""
            then latestRiteState.leadingRiteTitle
            else "the default rite"
        local roleLine = "Choose a role station before investing heavily in one lane."
        local fuelProgressText = "collect fuel crates"
        local supplyText = "shared supplies are empty"

        if latestObjectiveState ~= nil and latestObjectiveState.resourcesRequired > 0 then
            fuelProgressText = string.format(
                "collect fuel crates (%d/%d)",
                latestObjectiveState.resourcesCollected,
                latestObjectiveState.resourcesRequired
            )
            supplyText = string.format(
                "shared supplies available: %d",
                latestObjectiveState.availableSupplies or 0
            )
        end

        if latestRoleState ~= nil and latestRoleState.selectedRoleTitle ~= "" then
            roleLine = string.format(
                "You are %s. Pair with other roles on one lane to create Concord.",
                latestRoleState.selectedRoleTitle
            )
        end

        return table.concat({
            "What to do now:",
            string.format("1. Walk the outer ring and %s.", fuelProgressText),
            string.format(
                "2. Spend supplies on damaged barricades and low towers. %s.",
                supplyText
            ),
            string.format("3. %s", roleLine),
            "4. Push your role duty as you build, because covered roles add a round bonus together.",
            "5. If a barricade or tower is already full, interact again to reinforce or overcharge it.",
            string.format("6. Vote at a shrine so %s does not win by default.", leadingRiteTitle),
            "7. Watch the Echo line and finish directives to awaken permanent run boons.",
        }, "\n")
    end

    if phaseName == "NightSurvival" then
        if latestRescueState ~= nil and latestRescueState.localIsDowned then
            return table.concat({
                "What to do now while downed:",
                "1. Stay visible and avoid crawling away from teammates unless the lane is collapsing.",
                "2. A teammate must hold the Revive prompt on you before the bleedout timer ends.",
                "3. Watch the lane callout so you can tell rescuers where the pressure is coming from.",
                "4. If the timer runs out, you will respawn at camp and the team loses tempo.",
            }, "\n")
        end

        if isTutorialMode() then
            local laneText =
                table.concat(latestPhasePayload.metadata.allowedLaneNames or {}, " and ")

            return table.concat({
                string.format(
                    "What to do now in %s:",
                    latestPhasePayload.metadata.tutorialTitle or "First Watch"
                ),
                string.format("1. Stay on %s and follow the beacon callouts.", laneText),
                "2. Let the barricade hold briefly, then strike enemies before they wind up again.",
                "3. If a teammate drops, peel off and hold Revive before going back to the lane.",
                "4. Save Pulse for the moment several threats reach camp together.",
                "5. Watch how your role and rite change the defense loop before the harder nights start.",
            }, "\n")
        end

        local activeRiteTitle = if latestRiteState ~= nil
                and latestRiteState.selectedRiteTitle ~= ""
            then latestRiteState.selectedRiteTitle
            else "the active rite"
        local concordLine = "Protect the strongest lane and rotate when alerts spike."
        local rescueSurgeSummary = renderRescueSurgeSummary()
        local threatHint = if latestThreatState ~= nil
                and latestThreatState.incomingThreatTypeName ~= ""
            then renderThreatCounterplayHint(latestThreatState.incomingThreatTypeName)
            else "Runners collapse on rescues, Brutes punish stacking, and Sappers drain towers."

        if latestDefenseState ~= nil and (latestDefenseState.totalConcordLanes or 0) > 0 then
            concordLine = string.format(
                "Protect your %d Concord lane%s first because they are stronger and more valuable.",
                latestDefenseState.totalConcordLanes,
                if latestDefenseState.totalConcordLanes == 1 then "" else "s"
            )
        end

        local guideLines = {
            string.format("What to do now under %s:", activeRiteTitle),
            "1. Move to the flashing lane beacon when an alert appears.",
            string.format("2. %s", concordLine),
            "3. Keep your role duty moving while you defend, especially Sparkkeeper pulses and Warden holds.",
            "4. Swing the Lantern Pike on enemies before they chew through the barricade.",
            "5. If a teammate is downed, one player peels to revive while the others hold the lane.",
            "6. If several threats reach camp, retreat to the lantern and use the Pulse prompt.",
            "7. Keep an eye on the Echo directives because clearing them unlocks stronger run boons.",
            string.format("8. %s", threatHint),
        }

        if rescueSurgeSummary ~= "" then
            table.insert(
                guideLines,
                string.format(
                    "9. %s is active, so swing the fight back through that lane while the rescue momentum lasts.",
                    rescueSurgeSummary
                )
            )
        end

        return table.concat(guideLines, "\n")
    end

    if latestPhasePayload ~= nil and latestPhasePayload.metadata.outcome ~= nil then
        local outcome = latestPhasePayload.metadata.outcome
        local suggestions = {
            "What to do now:",
            "1. Review the reward popup and compare it to the debrief below.",
        }

        if outcome.nightFailed then
            if (outcome.teamCoverageCount or 0) < 3 then
                table.insert(
                    suggestions,
                    "2. Cover all three roles next round so the team is not missing a lane job."
                )
            elseif (outcome.concordLanes or 0) == 0 then
                table.insert(
                    suggestions,
                    "2. Build one mixed-role Concord lane next round for a safer anchor."
                )
            elseif
                (outcome.suppliesSpent or 0) < math.ceil((outcome.suppliesCollected or 0) * 0.5)
            then
                table.insert(
                    suggestions,
                    "2. Spend more of the collected supplies before night begins."
                )
            else
                table.insert(
                    suggestions,
                    "2. Reinforce earlier and rotate faster toward the pressure lane."
                )
            end
        else
            table.insert(
                suggestions,
                "2. Keep the role coverage, then push for a second Concord lane next round."
            )
        end

        table.insert(suggestions, "3. Return to camp and prepare for the next rite vote.")

        return table.concat(suggestions, "\n")
    end

    return table.concat({
        "What to do now:",
        "1. Review the reward popup and your current coins and XP.",
        "2. Return to camp and get ready to collect fuel again.",
        "3. The next day phase starts a new vote and defense cycle.",
    }, "\n")
end

local function renderControls()
    local phaseName = if latestPhasePayload ~= nil then latestPhasePayload.name else "Lobby"

    if phaseName == "NightSurvival" then
        if latestRescueState ~= nil and latestRescueState.localIsDowned then
            return "Controls: you are downed. Crawl slowly with movement keys or stick input and wait for a teammate to hold Revive on you."
        end

        if isTutorialMode() then
            return "Controls: keep the Lantern Pike equipped, swing with click or tap, revive teammates with their prompt, and retreat to the lantern to trigger Pulse when the wave stacks up."
        end

        return "Controls: click or tap with the Lantern Pike to attack. Hold Revive on downed teammates and use the lantern Pulse when the swarm closes in."
    end

    if phaseName == "DayPrep" and isTutorialMode() then
        return "Controls: hold prompts at crates, role stations, the East barricade, the North tower, and any shrine to complete the guided checklist."
    end

    return "Controls: walk close to an object and hold its prompt to choose a role, collect fuel, vote, repair, reinforce, charge, or overcharge."
end

local function renderAlert()
    if latestRescueState ~= nil and latestRescueState.localIsDowned then
        return string.format(
            "Alert: you are downed on %s lane, bleedout in %ss",
            latestRescueState.localDownedLaneName or "the active",
            latestRescueState.localBleedoutRemainingSeconds or 0
        )
    end

    if latestRescueState ~= nil and #(latestRescueState.downedPlayers or {}) > 0 then
        local downedPlayer = latestRescueState.downedPlayers[1]
        return string.format(
            "Alert: %s is down on %s lane (%ss)",
            downedPlayer.displayName or downedPlayer.name or "A teammate",
            downedPlayer.laneName or "the active",
            downedPlayer.bleedoutRemainingSeconds or 0
        )
    end

    if latestThreatState ~= nil then
        if latestThreatState.incomingLaneName ~= "" then
            return string.format(
                "Alert: %s incoming at %s lane | %s",
                latestThreatState.incomingThreatTypeName,
                latestThreatState.incomingLaneName,
                renderThreatCounterplayHint(latestThreatState.incomingThreatTypeName or "")
            )
        end

        if
            latestThreatState.phaseName == "NightSurvival"
            and latestThreatState.pressureLaneName ~= ""
        then
            return string.format(
                "Alert: highest pressure on %s lane",
                latestThreatState.pressureLaneName
            )
        end

        if latestThreatState.phaseName == "Results" and latestThreatState.nightFailed then
            return "Alert: the lantern was overrun before dawn"
        end

        if latestThreatState.phaseName == "Results" and latestThreatState.nightCleared then
            return "Alert: night cleared, regroup and rebuild"
        end
    end

    if
        latestRescueState ~= nil
        and (latestRescueState.activeSurgeRemainingSeconds or 0) > 0
        and latestRescueState.activeSurgeLaneName ~= ""
    then
        return string.format(
            "Alert: Rally active on %s lane for %ss after %s saved %s",
            latestRescueState.activeSurgeLaneName,
            latestRescueState.activeSurgeRemainingSeconds or 0,
            latestRescueState.activeSurgeReviverName or "a teammate",
            latestRescueState.activeSurgeRescuedName or "an ally"
        )
    end

    if latestDefenseState ~= nil then
        for _, laneState in ipairs(latestDefenseState.lanes or {}) do
            if laneState.breached then
                return string.format("Alert: %s lane is breached", laneState.name)
            end
        end
    end

    return "Alert: standing by"
end

function HudController.start()
    hudRefs = buildHud()
    hudRefs.echoLabel.Text = renderEcho()
    hudRefs.roleLabel.Text = renderRole()
    hudRefs.missionLabel.Text = renderMission()
    hudRefs.statusLabel.Text = renderStatus()
    hudRefs.alertLabel.Text = renderAlert()
    hudRefs.guideLabel.Text = renderGuide()
    hudRefs.controlsLabel.Text = renderControls()

    local phaseChanged, rewardPreview, profileStateChanged, objectiveStateChanged, echoStateChanged, dutyStateChanged, roleStateChanged, riteStateChanged, defenseStateChanged, threatStateChanged, rescueStateChanged =
        getRemotes()

    phaseChanged.OnClientEvent:Connect(function(payload)
        latestPhasePayload = payload
        hudRefs.phaseLabel.Text = string.format("Round %d | %s", payload.roundNumber, payload.name)
        hudRefs.detailLabel.Text = describePhase(payload)
        hudRefs.missionLabel.Text = renderMission()
        hudRefs.guideLabel.Text = renderGuide()
        hudRefs.controlsLabel.Text = renderControls()
    end)

    rewardPreview.OnClientEvent:Connect(function(rewards)
        hudRefs.detailLabel.Text = string.format(
            "Rewarded %d coins and %d XP. Co-op bonus: %d | Duty bonus: %d | Echo bonus: %d.",
            rewards.coins,
            rewards.experience,
            rewards.socialBonus or 0,
            rewards.dutyBonus or 0,
            rewards.echoBonus or 0
        )
    end)

    objectiveStateChanged.OnClientEvent:Connect(function(payload)
        latestObjectiveState = payload
        if payload.resourcesRequired == 0 then
            hudRefs.objectiveLabel.Text = "Objective: waiting for the next round."
            hudRefs.missionLabel.Text = renderMission()
            hudRefs.guideLabel.Text = renderGuide()
            return
        end

        hudRefs.objectiveLabel.Text = string.format(
            "Objective: %d/%d fuel | Supplies %d | Lantern %.0f%%",
            payload.resourcesCollected,
            payload.resourcesRequired,
            payload.availableSupplies or 0,
            payload.lanternCharge * 100
        )
        hudRefs.missionLabel.Text = renderMission()
        hudRefs.guideLabel.Text = renderGuide()
    end)

    echoStateChanged.OnClientEvent:Connect(function(payload)
        latestEchoState = payload
        hudRefs.echoLabel.Text = renderEcho()
        hudRefs.missionLabel.Text = renderMission()
        hudRefs.guideLabel.Text = renderGuide()
    end)

    dutyStateChanged.OnClientEvent:Connect(function(payload)
        latestDutyState = payload
        hudRefs.roleLabel.Text = renderRole()
        hudRefs.missionLabel.Text = renderMission()
        hudRefs.guideLabel.Text = renderGuide()
    end)

    roleStateChanged.OnClientEvent:Connect(function(payload)
        latestRoleState = payload
        hudRefs.roleLabel.Text = renderRole()
        hudRefs.missionLabel.Text = renderMission()

        local roleName = payload.selectedRoleName
        if roleName ~= "" and GameConfig.RoleTuning.Roles[roleName] ~= nil then
            hudRefs.roleLabel.TextColor3 = GameConfig.RoleTuning.Roles[roleName].color
        else
            hudRefs.roleLabel.TextColor3 = Color3.fromRGB(194, 206, 255)
        end

        hudRefs.guideLabel.Text = renderGuide()
    end)

    riteStateChanged.OnClientEvent:Connect(function(payload)
        latestRiteState = payload
        hudRefs.riteLabel.Text = renderRite()
        hudRefs.missionLabel.Text = renderMission()
        hudRefs.guideLabel.Text = renderGuide()

        local riteName = payload.selectedRiteName
        if riteName == "" then
            riteName = payload.leadingRiteName
        end

        if riteName ~= "" and GameConfig.RiteTuning.Rites[riteName] ~= nil then
            hudRefs.riteLabel.TextColor3 = GameConfig.RiteTuning.Rites[riteName].color
        else
            hudRefs.riteLabel.TextColor3 = Color3.fromRGB(232, 196, 122)
        end
    end)

    defenseStateChanged.OnClientEvent:Connect(function(payload)
        latestDefenseState = payload
        hudRefs.missionLabel.Text = renderMission()
        hudRefs.statusLabel.Text = renderStatus()
        hudRefs.alertLabel.Text = renderAlert()
        hudRefs.guideLabel.Text = renderGuide()
    end)

    threatStateChanged.OnClientEvent:Connect(function(payload)
        latestThreatState = payload
        hudRefs.missionLabel.Text = renderMission()
        hudRefs.statusLabel.Text = renderStatus()
        hudRefs.alertLabel.Text = renderAlert()
        hudRefs.guideLabel.Text = renderGuide()
        hudRefs.controlsLabel.Text = renderControls()

        if payload.phaseName == "Results" and payload.nightFailed then
            hudRefs.detailLabel.Text = "The lantern collapsed before dawn."
        end
    end)

    rescueStateChanged.OnClientEvent:Connect(function(payload)
        latestRescueState = payload
        hudRefs.missionLabel.Text = renderMission()
        hudRefs.statusLabel.Text = renderStatus()
        hudRefs.alertLabel.Text = renderAlert()
        hudRefs.guideLabel.Text = renderGuide()
        hudRefs.controlsLabel.Text = renderControls()

        if payload.localIsDowned then
            hudRefs.detailLabel.Text = string.format(
                "You are downed on %s lane. Bleedout in %ss unless a teammate revives you.",
                payload.localDownedLaneName or "the active",
                payload.localBleedoutRemainingSeconds or 0
            )
        end
    end)

    profileStateChanged.OnClientEvent:Connect(function(payload)
        if payload.status == "Error" then
            latestPublicProfile = payload.profile

            if payload.profile ~= nil then
                local topRoleMastery = getTopMasterySnapshot("roles")
                local topRiteMastery = getTopMasterySnapshot("rites")
                local masteryText = ""

                if topRoleMastery ~= nil and topRiteMastery ~= nil then
                    masteryText = string.format(
                        " | %s Lv %d | %s Lv %d",
                        topRoleMastery.title,
                        topRoleMastery.level,
                        topRiteMastery.title,
                        topRiteMastery.level
                    )
                end

                hudRefs.profileLabel.Text = string.format(
                    "Sync issue | Lv %d | Coins %d | Best Night %d%s",
                    payload.profile.level,
                    payload.profile.coins,
                    payload.profile.bestNight,
                    masteryText
                )
            else
                hudRefs.profileLabel.Text = string.format("Profile: %s", payload.message)
            end

            hudRefs.detailLabel.Text = payload.message
            hudRefs.roleLabel.Text = renderRole()
            hudRefs.riteLabel.Text = renderRite()
            return
        end

        if payload.status == "Loading" then
            hudRefs.profileLabel.Text = "Profile: loading..."
            return
        end

        if payload.profile ~= nil then
            latestPublicProfile = payload.profile
            local topRoleMastery = getTopMasterySnapshot("roles")
            local topRiteMastery = getTopMasterySnapshot("rites")
            local masteryText = ""

            if topRoleMastery ~= nil and topRiteMastery ~= nil then
                masteryText = string.format(
                    " | %s Lv %d | %s Lv %d",
                    topRoleMastery.title,
                    topRoleMastery.level,
                    topRiteMastery.title,
                    topRiteMastery.level
                )
            end

            hudRefs.profileLabel.Text = string.format(
                "Lv %d | Coins %d | XP %d | Best Night %d%s",
                payload.profile.level,
                payload.profile.coins,
                payload.profile.experience,
                payload.profile.bestNight,
                masteryText
            )
            hudRefs.roleLabel.Text = renderRole()
            hudRefs.riteLabel.Text = renderRite()
            return
        end

        latestPublicProfile = nil
        hudRefs.profileLabel.Text = string.format("Profile: %s", payload.message)
    end)
end

return HudController
