local Players = game:GetService("Players")

local servicesFolder = script.Parent:WaitForChild("Services")

local CombatService = require(servicesFolder:WaitForChild("CombatService"))
local DefenseService = require(servicesFolder:WaitForChild("DefenseService"))
local DutyService = require(servicesFolder:WaitForChild("DutyService"))
local EchoService = require(servicesFolder:WaitForChild("EchoService"))
local ObjectiveService = require(servicesFolder:WaitForChild("ObjectiveService"))
local RoleService = require(servicesFolder:WaitForChild("RoleService"))
local RiteService = require(servicesFolder:WaitForChild("RiteService"))
local RemoteSetup = require(servicesFolder:WaitForChild("RemoteSetup"))
local ProfileService = require(servicesFolder:WaitForChild("ProfileService"))
local RescueService = require(servicesFolder:WaitForChild("RescueService"))
local RewardService = require(servicesFolder:WaitForChild("RewardService"))
local RoundService = require(servicesFolder:WaitForChild("RoundService"))
local SpawnDirector = require(servicesFolder:WaitForChild("SpawnDirector"))
local ThreatService = require(servicesFolder:WaitForChild("ThreatService"))

RemoteSetup.ensureRemotes()
EchoService.initialize()
DutyService.initialize({
    roleService = RoleService,
})
ObjectiveService.initialize()
RescueService.initialize({
    objectiveService = ObjectiveService,
})
RiteService.initialize({
    objectiveService = ObjectiveService,
})
RoleService.initialize({
    dutyService = DutyService,
    objectiveService = ObjectiveService,
})
ObjectiveService.setRoleService(RoleService)
ObjectiveService.setEchoService(EchoService)
ObjectiveService.setDutyService(DutyService)
DefenseService.initialize({
    dutyService = DutyService,
    echoService = EchoService,
    objectiveService = ObjectiveService,
    rescueService = RescueService,
    riteService = RiteService,
    roleService = RoleService,
})
ThreatService.initialize({
    dutyService = DutyService,
    echoService = EchoService,
    objectiveService = ObjectiveService,
    defenseService = DefenseService,
    rescueService = RescueService,
    riteService = RiteService,
    roleService = RoleService,
})
CombatService.start({
    threatService = ThreatService,
    roleService = RoleService,
})
ProfileService.start()

RoundService.start({
    defenseService = DefenseService,
    dutyService = DutyService,
    echoService = EchoService,
    objectiveService = ObjectiveService,
    profileService = ProfileService,
    rescueService = RescueService,
    rewardService = RewardService,
    roleService = RoleService,
    riteService = RiteService,
    spawnDirector = SpawnDirector,
    threatService = ThreatService,
})

Players.PlayerAdded:Connect(function(player)
    task.delay(1, function()
        if player.Parent == nil then
            return
        end

        RoundService.syncPlayer(player)
        ObjectiveService.syncPlayer(player)
        DutyService.syncPlayer(player)
        EchoService.syncPlayer(player)
        RoleService.syncPlayer(player)
        RiteService.syncPlayer(player)
        DefenseService.syncPlayer(player)
        ThreatService.syncPlayer(player)
        RescueService.syncPlayer(player)
    end)
end)
