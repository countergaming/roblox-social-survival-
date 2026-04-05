local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))

local RoundService = {}

local currentState = table.freeze({
    isRunning = false,
    roundNumber = 0,
    phaseName = "Lobby",
})

local function setState(nextState)
    currentState = table.freeze(nextState)
end

local function getRemoteFolder()
    return ReplicatedStorage:WaitForChild(RemoteNames.Folder)
end

local function getPhaseChangedEvent(): RemoteEvent
    local remoteFolder = getRemoteFolder()
    return remoteFolder:WaitForChild(RemoteNames.PhaseChanged) :: RemoteEvent
end

local function getRewardPreviewEvent(): RemoteEvent
    local remoteFolder = getRemoteFolder()
    return remoteFolder:WaitForChild(RemoteNames.RewardPreview) :: RemoteEvent
end

local function broadcastPhase(
    phaseName: string,
    roundNumber: number,
    durationSeconds: number,
    metadata
)
    local payload = table.freeze({
        name = phaseName,
        roundNumber = roundNumber,
        durationSeconds = durationSeconds,
        startedAtUnix = os.time(),
        metadata = metadata or {},
    })

    setState({
        isRunning = true,
        roundNumber = roundNumber,
        phaseName = phaseName,
        lastPayload = payload,
    })

    getPhaseChangedEvent():FireAllClients(payload)
end

local function waitForNightToResolve(durationSeconds: number, threatService)
    local startedAt = os.clock()

    while (os.clock() - startedAt) < durationSeconds do
        if threatService.hasNightEnded() then
            break
        end

        task.wait(0.5)
    end
end

local function buildRoundPlan(roundNumber: number, playerCount: number, spawnDirector)
    local tutorialMode = spawnDirector.isGuidedRound(roundNumber)
    local tutorialTuning = GameConfig.TutorialTuning
    local nightPlan = spawnDirector.buildNightPlan(roundNumber, playerCount)

    return table.freeze({
        tutorialMode = tutorialMode,
        tutorialTitle = if tutorialMode then tutorialTuning.Title else "",
        tutorialSummary = if tutorialMode then tutorialTuning.Summary else "",
        dayPrepDuration = if tutorialMode
            then tutorialTuning.DayPrepDuration
            else GameConfig.PhaseDurations.DayPrep,
        nightSurvivalDuration = if tutorialMode
            then tutorialTuning.NightSurvivalDuration
            else GameConfig.PhaseDurations.NightSurvival,
        targetBarricadeLaneName = if tutorialMode
            then tutorialTuning.TargetBarricadeLaneName
            else "",
        targetTowerLaneName = if tutorialMode then tutorialTuning.TargetTowerLaneName else "",
        allowedLaneNames = if tutorialMode
            then tutorialTuning.AllowedLaneNames
            else table.freeze({}),
        objectiveOptions = if tutorialMode
            then table.freeze({
                resourceNodeCount = tutorialTuning.ResourceNodes,
            })
            else nil,
        defenseOptions = if tutorialMode
            then table.freeze({
                tutorialMode = true,
            })
            else nil,
        nightPlan = nightPlan,
    })
end

local function buildRoundOutcome(
    roundNumber: number,
    playerCount: number,
    objectiveState,
    defenseState,
    threatState,
    roleState,
    rescueState
)
    local lanternCharge = if objectiveState ~= nil then objectiveState.lanternCharge else 0
    local objectiveProgress = 0
    local defenseBonus = 0
    local tacticalBonus = 0
    local lanternHealthRatio = 1
    local barricadesStanding = 0
    local fortificationLevel = 0
    local overchargeLevel = 0
    local suppliesCollected = 0
    local suppliesSpent = 0
    local teamCoverageCount = 0
    local concordLanes = 0
    local revivesCompleted = 0
    local bleedouts = 0
    local alivePlayers = math.max(1, math.floor(playerCount * 0.75))
    local nightFailed = if threatState ~= nil then threatState.nightFailed else false
    local nightCleared = if threatState ~= nil then threatState.nightCleared else false

    if objectiveState ~= nil and objectiveState.resourcesRequired > 0 then
        objectiveProgress = math.clamp(
            math.ceil((objectiveState.resourcesCollected / objectiveState.resourcesRequired) * 2),
            0,
            2
        )
        suppliesCollected = objectiveState.totalSuppliesCollected or 0
        suppliesSpent = objectiveState.spentSupplies or 0
    end

    if defenseState ~= nil and defenseState.totalBarricades > 0 then
        barricadesStanding = defenseState.healthyBarricades
        fortificationLevel = defenseState.totalFortificationLevel or 0
        overchargeLevel = defenseState.totalOverchargeLevel or 0
        concordLanes = defenseState.totalConcordLanes or 0

        if defenseState.healthyBarricades == defenseState.totalBarricades then
            defenseBonus = 2
        elseif defenseState.healthyBarricades >= math.ceil(defenseState.totalBarricades / 2) then
            defenseBonus = 1
        end
    end

    if suppliesCollected > 0 and suppliesSpent >= math.ceil(suppliesCollected * 0.5) then
        tacticalBonus += 1
    end

    if fortificationLevel > 0 and overchargeLevel > 0 then
        tacticalBonus += 1
    end

    if roleState ~= nil then
        teamCoverageCount = roleState.teamCoverageCount or 0
    end

    if concordLanes > 0 then
        tacticalBonus += 1
    end

    if threatState ~= nil and threatState.lanternMaxHealth > 0 then
        lanternHealthRatio = threatState.lanternHealth / threatState.lanternMaxHealth
        if nightFailed then
            alivePlayers = math.max(0, math.floor(playerCount * 0.35))
        else
            alivePlayers =
                math.max(1, math.floor(playerCount * (0.55 + (lanternHealthRatio * 0.35))))
        end
    end

    if rescueState ~= nil then
        revivesCompleted = rescueState.totalRevives or 0
        bleedouts = rescueState.totalBleedouts or 0
    end

    return table.freeze({
        nightNumber = roundNumber,
        alivePlayers = alivePlayers,
        totalPlayers = playerCount,
        lanternCharge = lanternCharge,
        objectivesCompleted = math.clamp(objectiveProgress + defenseBonus + tacticalBonus, 0, 6),
        lanternHealthRatio = lanternHealthRatio,
        barricadesStanding = barricadesStanding,
        fortificationLevel = fortificationLevel,
        overchargeLevel = overchargeLevel,
        suppliesCollected = suppliesCollected,
        suppliesSpent = suppliesSpent,
        teamCoverageCount = teamCoverageCount,
        concordLanes = concordLanes,
        revivesCompleted = revivesCompleted,
        bleedouts = bleedouts,
        nightFailed = nightFailed,
        nightCleared = nightCleared,
    })
end

local function findDutySnapshot(dutyState, roleName: string)
    if dutyState == nil then
        return nil
    end

    for _, dutySnapshot in ipairs(dutyState.duties or {}) do
        if dutySnapshot.name == roleName then
            return dutySnapshot
        end
    end

    return nil
end

local function buildPlayerMasterySummary(player: Player, dependencies, context)
    local masteryTuning = GameConfig.MasteryTuning
    local selectedRoleName = dependencies.roleService.getSelectedRoleName(player)
    local selectedRiteName = dependencies.riteService.getSelectedRiteName()
    local votedRiteName = dependencies.riteService.getPlayerVotedRiteName(player)
    local roleSummary = nil
    local riteSummary = nil

    if selectedRoleName ~= "" then
        local roleExperience = masteryTuning.RoleBaseExperience
        local dutySnapshot = findDutySnapshot(context.dutyState, selectedRoleName)

        if dutySnapshot ~= nil and dutySnapshot.completed then
            roleExperience += masteryTuning.RoleDutyCompletedBonus
        end

        if (context.roleState.teamCoverageCount or 0) >= #GameConfig.RoleTuning.Order then
            roleExperience += masteryTuning.RoleCoverageBonus
        end

        if context.roundOutcome.nightCleared then
            roleExperience += masteryTuning.RoleClearBonus
        end

        if (context.roundOutcome.concordLanes or 0) > 0 then
            roleExperience += masteryTuning.RoleConcordBonus
        end

        roleSummary = table.freeze({
            name = selectedRoleName,
            title = dependencies.roleService.getRoleTitle(selectedRoleName),
            experience = roleExperience,
        })
    end

    local targetRiteName = if votedRiteName ~= "" then votedRiteName else selectedRiteName

    if targetRiteName ~= "" then
        local riteExperience = masteryTuning.RiteBaseExperience

        if votedRiteName ~= "" and votedRiteName == selectedRiteName then
            riteExperience += masteryTuning.RiteAlignedVoteBonus
        end

        if context.roundOutcome.nightCleared then
            riteExperience += masteryTuning.RiteClearBonus
        end

        riteSummary = table.freeze({
            name = targetRiteName,
            title = dependencies.riteService.getRiteTitle(targetRiteName),
            experience = riteExperience,
        })
    end

    return table.freeze({
        role = roleSummary,
        rite = riteSummary,
    })
end

function RoundService.getState()
    return currentState
end

function RoundService.syncPlayer(player: Player)
    if currentState.lastPayload == nil then
        return
    end

    getPhaseChangedEvent():FireClient(player, currentState.lastPayload)
end

function RoundService.start(dependencies)
    if currentState.isRunning then
        return
    end

    setState({
        isRunning = true,
        roundNumber = 0,
        phaseName = "Lobby",
    })

    task.spawn(function()
        local roundNumber = 0

        while true do
            local playerCount = #Players:GetPlayers()

            if playerCount < GameConfig.MinimumPlayers then
                broadcastPhase("Lobby", roundNumber, GameConfig.PhaseDurations.Lobby, {
                    waitingForPlayers = true,
                    playersNeeded = GameConfig.MinimumPlayers - playerCount,
                })
                task.wait(5)
            else
                roundNumber = roundNumber + 1
                local roundPlan =
                    buildRoundPlan(roundNumber, playerCount, dependencies.spawnDirector)

                broadcastPhase("Lobby", roundNumber, GameConfig.PhaseDurations.Lobby, {
                    waitingForPlayers = false,
                    tutorialMode = roundPlan.tutorialMode,
                    tutorialTitle = roundPlan.tutorialTitle,
                })
                task.wait(GameConfig.PhaseDurations.Lobby)

                local dayDefenseState =
                    dependencies.defenseService.startDayPhase(roundNumber, roundPlan.defenseOptions)
                local dayObjectiveState = dependencies.objectiveService.startDayPhase(
                    roundNumber,
                    playerCount,
                    roundPlan.objectiveOptions
                )
                local dayDutyState =
                    dependencies.dutyService.startDayPhase(roundNumber, playerCount)
                local dayEchoState =
                    dependencies.echoService.startDayPhase(roundNumber, playerCount)
                local dayRoleState = dependencies.roleService.startDayPhase(roundNumber)
                local dayRiteState = dependencies.riteService.startDayPhase(roundNumber)
                broadcastPhase("DayPrep", roundNumber, roundPlan.dayPrepDuration, {
                    resourceNodes = dayObjectiveState.resourcesRequired,
                    interactionPrompt = if roundPlan.tutorialMode
                        then string.format(
                            "Guided %s: collect fuel, choose a role, repair %s, charge %s, and vote.",
                            roundPlan.tutorialTitle,
                            roundPlan.targetBarricadeLaneName,
                            roundPlan.targetTowerLaneName
                        )
                        else "Collect fuel, choose roles, shore up lanes, and choose a lantern rite.",
                    activeBarricades = dayDefenseState.healthyBarricades,
                    averageTowerEnergy = dayDefenseState.averageTowerEnergy,
                    teamCoverageCount = dayRoleState.teamCoverageCount,
                    leadingRiteTitle = dayRiteState.leadingRiteTitle,
                    leadingRiteSummary = dayRiteState.leadingRiteSummary,
                    tutorialMode = roundPlan.tutorialMode,
                    tutorialTitle = roundPlan.tutorialTitle,
                    tutorialSummary = roundPlan.tutorialSummary,
                    targetBarricadeLaneName = roundPlan.targetBarricadeLaneName,
                    targetTowerLaneName = roundPlan.targetTowerLaneName,
                    completedDutyCount = dayDutyState.completedDutyCount,
                    activeDutyCount = dayDutyState.activeDutyCount,
                    unlockedBoonCount = dayEchoState.unlockedBoonCount,
                })
                task.wait(roundPlan.dayPrepDuration)

                local nightDutyState = dependencies.dutyService.startNightPhase(roundNumber)
                local nightEchoState = dependencies.echoService.startNightPhase(roundNumber)
                local nightRoleState = dependencies.roleService.startNightPhase(roundNumber)
                local nightRiteState = dependencies.riteService.startNightPhase(roundNumber)
                local nightRescueState = dependencies.rescueService.startNightPhase(roundNumber)
                local nightDefenseState = dependencies.defenseService.startNightPhase(roundNumber)
                local nightObjectiveState =
                    dependencies.objectiveService.startNightPhase(roundNumber)
                local nightPlan = roundPlan.nightPlan
                local enrichedNightPlan = table.freeze({
                    tutorialMode = nightPlan.tutorialMode == true,
                    tutorialTitle = nightPlan.tutorialTitle,
                    tutorialSummary = nightPlan.tutorialSummary,
                    threatRate = nightPlan.threatRate,
                    spawnIntervalSeconds = nightPlan.spawnIntervalSeconds,
                    maxSimultaneousThreats = nightPlan.maxSimultaneousThreats,
                    eliteChance = nightPlan.eliteChance,
                    warningLeadSeconds = nightPlan.warningLeadSeconds,
                    allowedLaneNames = nightPlan.allowedLaneNames,
                    forcedLaneSequence = nightPlan.forcedLaneSequence,
                    threatSequence = nightPlan.threatSequence,
                    desiredSpawnCount = nightPlan.desiredSpawnCount,
                    waveLabelOverride = nightPlan.waveLabelOverride,
                    lanternCharge = nightObjectiveState.lanternCharge,
                    healthyBarricades = nightDefenseState.healthyBarricades,
                })
                local initialThreatState = dependencies.threatService.startNightPhase(
                    roundNumber,
                    roundPlan.nightSurvivalDuration,
                    enrichedNightPlan,
                    nightObjectiveState
                )
                broadcastPhase("NightSurvival", roundNumber, roundPlan.nightSurvivalDuration, {
                    threatRate = enrichedNightPlan.threatRate,
                    spawnIntervalSeconds = enrichedNightPlan.spawnIntervalSeconds,
                    maxSimultaneousThreats = enrichedNightPlan.maxSimultaneousThreats,
                    eliteChance = enrichedNightPlan.eliteChance,
                    lanternCharge = nightObjectiveState.lanternCharge,
                    lanternHealth = initialThreatState.lanternHealth,
                    healthyBarricades = nightDefenseState.healthyBarricades,
                    teamCoverageCount = nightRoleState.teamCoverageCount,
                    riteTitle = nightRiteState.selectedRiteTitle,
                    riteSummary = nightRiteState.selectedRiteSummary,
                    activeDownedCount = nightRescueState.activeDownedCount,
                    tutorialMode = roundPlan.tutorialMode,
                    tutorialTitle = roundPlan.tutorialTitle,
                    tutorialSummary = roundPlan.tutorialSummary,
                    allowedLaneNames = roundPlan.allowedLaneNames,
                    targetBarricadeLaneName = roundPlan.targetBarricadeLaneName,
                    targetTowerLaneName = roundPlan.targetTowerLaneName,
                    completedDutyCount = nightDutyState.completedDutyCount,
                    activeDutyCount = nightDutyState.activeDutyCount,
                    unlockedBoonCount = nightEchoState.unlockedBoonCount,
                })
                waitForNightToResolve(roundPlan.nightSurvivalDuration, dependencies.threatService)

                local finishedThreatState = dependencies.threatService.finishNightPhase(roundNumber)
                local finishedRescueState = dependencies.rescueService.finishRound(roundNumber)
                local finishedDutyState = dependencies.dutyService.finishRound(roundNumber)
                local finishedRoleState = dependencies.roleService.finishRound(roundNumber)
                local finishedRiteState = dependencies.riteService.finishRound(roundNumber)
                local finishedDefenseState = dependencies.defenseService.finishRound(roundNumber)
                local finishedObjectiveState = dependencies.objectiveService.finishRound()
                local roundOutcome = buildRoundOutcome(
                    roundNumber,
                    playerCount,
                    finishedObjectiveState,
                    finishedDefenseState,
                    finishedThreatState,
                    finishedRoleState,
                    finishedRescueState
                )
                local finishedEchoState = dependencies.echoService.finishRound(
                    roundNumber,
                    roundOutcome,
                    finishedRoleState,
                    finishedDefenseState
                )
                local rewards = dependencies.rewardService.calculateRewards(
                    roundOutcome,
                    finishedEchoState,
                    finishedDutyState
                )

                for _, player in ipairs(Players:GetPlayers()) do
                    local masterySummary = buildPlayerMasterySummary(player, dependencies, {
                        dutyState = finishedDutyState,
                        roleState = finishedRoleState,
                        roundOutcome = roundOutcome,
                    })
                    dependencies.profileService.applyRoundRewards(
                        player,
                        rewards,
                        roundOutcome,
                        masterySummary
                    )
                end

                getRewardPreviewEvent():FireAllClients(rewards)

                broadcastPhase("Results", roundNumber, GameConfig.PhaseDurations.Results, {
                    outcome = roundOutcome,
                    rewards = rewards,
                    dutyState = finishedDutyState,
                    echoState = finishedEchoState,
                    roleState = finishedRoleState,
                    riteState = finishedRiteState,
                    threatState = finishedThreatState,
                    rescueState = finishedRescueState,
                    defenseState = finishedDefenseState,
                })
                task.wait(GameConfig.PhaseDurations.Results)
            end
        end
    end)
end

return RoundService
