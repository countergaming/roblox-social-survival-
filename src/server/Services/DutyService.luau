local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))

local DutyService = {}

local roleService = nil
local progressByRoleName = {}
local targetsByRoleName = {}
local activeRolesByName = {}
local dutyState = table.freeze({
    phaseName = "Lobby",
    roundNumber = 0,
    activeDutyCount = 0,
    completedDutyCount = 0,
    fullRosterBonusReady = false,
    duties = table.freeze({}),
})

local function getRemoteEvent(): RemoteEvent
    local remoteFolder = ReplicatedStorage:WaitForChild(RemoteNames.Folder)
    return remoteFolder:WaitForChild(RemoteNames.DutyStateChanged) :: RemoteEvent
end

local function getRoleDutyConfig(roleName: string)
    return GameConfig.DutyTuning.Roles[roleName]
end

local function getTargetForRole(roleName: string, roundNumber: number, playerCount: number): number
    local dutyConfig = getRoleDutyConfig(roleName)

    if dutyConfig == nil then
        return 0
    end

    return dutyConfig.baseTarget
        + (math.max(playerCount, 1) - 1) * dutyConfig.perPlayer
        + math.max(0, roundNumber - 1) * dutyConfig.perRound
end

local function rebuildState(phaseName: string, roundNumber: number)
    local dutySnapshots = {}
    local activeDutyCount = 0
    local completedDutyCount = 0

    for _, roleName in ipairs(GameConfig.RoleTuning.Order) do
        local dutyConfig = getRoleDutyConfig(roleName)
        local isActive = activeRolesByName[roleName] == true
        local currentValue = progressByRoleName[roleName] or 0
        local targetValue = targetsByRoleName[roleName] or 0
        local completed = isActive and targetValue > 0 and currentValue >= targetValue

        if isActive then
            activeDutyCount += 1
        end

        if completed then
            completedDutyCount += 1
        end

        table.insert(
            dutySnapshots,
            table.freeze({
                name = roleName,
                title = dutyConfig.title,
                summary = dutyConfig.summary,
                currentValue = currentValue,
                targetValue = targetValue,
                active = isActive,
                completed = completed,
            })
        )
    end

    dutyState = table.freeze({
        phaseName = phaseName,
        roundNumber = roundNumber,
        activeDutyCount = activeDutyCount,
        completedDutyCount = completedDutyCount,
        fullRosterBonusReady = activeDutyCount > 0 and completedDutyCount >= activeDutyCount,
        duties = table.freeze(dutySnapshots),
    })
end

local function broadcastState()
    getRemoteEvent():FireAllClients(dutyState)
end

local function pushState(player: Player)
    getRemoteEvent():FireClient(player, dutyState)
end

local function applyState(phaseName: string, roundNumber: number)
    rebuildState(phaseName, roundNumber)
    broadcastState()
end

local function resetRound(roundNumber: number, playerCount: number)
    progressByRoleName = {}
    targetsByRoleName = {}
    activeRolesByName = {}

    for _, roleName in ipairs(GameConfig.RoleTuning.Order) do
        progressByRoleName[roleName] = 0
        targetsByRoleName[roleName] = getTargetForRole(roleName, roundNumber, playerCount)
        activeRolesByName[roleName] = false
    end
end

local function syncActiveRoles()
    if roleService == nil then
        return
    end

    local roleState = roleService.getState()

    for _, roleSnapshot in ipairs(roleState.roles or {}) do
        activeRolesByName[roleSnapshot.name] = (roleSnapshot.assignedPlayers or 0) > 0
    end
end

local function incrementRoleDuty(player: Player, expectedRoleName: string, amount: number)
    if dutyState.phaseName ~= "DayPrep" and dutyState.phaseName ~= "NightSurvival" then
        return
    end

    if roleService == nil then
        return
    end

    local selectedRoleName = roleService.getSelectedRoleName(player)

    if selectedRoleName ~= expectedRoleName then
        return
    end

    progressByRoleName[expectedRoleName] =
        math.max(0, (progressByRoleName[expectedRoleName] or 0) + math.max(1, amount))
    syncActiveRoles()
    applyState(dutyState.phaseName, dutyState.roundNumber)
end

function DutyService.initialize(dependencies)
    roleService = dependencies.roleService
    resetRound(0, 1)
    applyState("Lobby", 0)
end

function DutyService.startDayPhase(roundNumber: number, playerCount: number)
    resetRound(roundNumber, playerCount)
    syncActiveRoles()
    applyState("DayPrep", roundNumber)

    return dutyState
end

function DutyService.startNightPhase(roundNumber: number)
    syncActiveRoles()
    applyState("NightSurvival", roundNumber)

    return dutyState
end

function DutyService.finishRound(roundNumber: number)
    syncActiveRoles()
    applyState("Results", roundNumber)

    return dutyState
end

function DutyService.registerResourceCollected(player: Player, amount: number)
    incrementRoleDuty(player, "Scavenger", amount)
end

function DutyService.registerBarricadeAction(player: Player, actionName: string)
    incrementRoleDuty(player, "Warden", if actionName == "Reinforce" then 2 else 1)
end

function DutyService.registerTowerAction(player: Player, actionName: string)
    incrementRoleDuty(player, "Sparkkeeper", if actionName == "Overcharge" then 2 else 1)
end

function DutyService.registerPulse(player: Player?)
    if player == nil then
        return
    end

    incrementRoleDuty(player, "Sparkkeeper", 2)
end

function DutyService.handleRoleAssignmentsChanged()
    syncActiveRoles()
    applyState(dutyState.phaseName, dutyState.roundNumber)

    return dutyState
end

function DutyService.getState()
    return dutyState
end

function DutyService.syncPlayer(player: Player)
    pushState(player)
end

return DutyService
