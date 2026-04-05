local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))

local DefenseService = {}

local LANE_ORDER = { "North", "East", "South", "West" }

local defenseFolder = nil
local dutyService = nil
local echoService = nil
local objectiveService = nil
local rescueService = nil
local riteService = nil
local roleService = nil
local laneEntriesByName = {}
local defenseState = table.freeze({
    phaseName = "Lobby",
    roundNumber = 0,
    totalBarricades = 0,
    healthyBarricades = 0,
    averageBarricadeIntegrity = 0,
    averageTowerEnergy = 0,
    totalFortificationLevel = 0,
    totalOverchargeLevel = 0,
    totalConcordLanes = 0,
    lanes = {},
})

local function getRemoteEvent(): RemoteEvent
    local remoteFolder = ReplicatedStorage:WaitForChild(RemoteNames.Folder)
    return remoteFolder:WaitForChild(RemoteNames.DefenseStateChanged) :: RemoteEvent
end

local function setDefenseState(nextState)
    defenseState = table.freeze(nextState)
end

local function buildLanePosition(laneName: string, radius: number): Vector3
    if laneName == "North" then
        return Vector3.new(0, 3, -radius)
    end

    if laneName == "East" then
        return Vector3.new(radius, 3, 0)
    end

    if laneName == "South" then
        return Vector3.new(0, 3, radius)
    end

    return Vector3.new(-radius, 3, 0)
end

local function getLanePartsFolder()
    if defenseFolder ~= nil and defenseFolder.Parent ~= nil then
        return defenseFolder
    end

    local runtimeFolder = objectiveService.getRuntimeFolder()
    local existingFolder = runtimeFolder:FindFirstChild("Defense")

    if existingFolder ~= nil then
        defenseFolder = existingFolder
        return defenseFolder
    end

    defenseFolder = Instance.new("Folder")
    defenseFolder.Name = "Defense"
    defenseFolder.Parent = runtimeFolder

    return defenseFolder
end

local function getBarricadeHealthRatio(laneEntry)
    return laneEntry.barricadeHealth / GameConfig.DefenseTuning.BarricadeMaxHealth
end

local function getTowerEnergyRatio(laneEntry)
    return laneEntry.towerEnergy / GameConfig.DefenseTuning.TowerMaxEnergy
end

local function getConcordCount(laneEntry)
    local concordCount = 0

    for _, hasContributed in pairs(laneEntry.roleContributors or {}) do
        if hasContributed == true then
            concordCount += 1
        end
    end

    return concordCount
end

local function registerRoleContribution(laneEntry, player: Player)
    if roleService == nil then
        return
    end

    local selectedRoleName = roleService.getSelectedRoleName(player)

    if selectedRoleName == "" then
        return
    end

    laneEntry.roleContributors[selectedRoleName] = true
end

local function getBarricadePartSize(laneEntry)
    local fortificationLevel = laneEntry.fortificationLevel or 0
    local thickness = 2 + (fortificationLevel * 0.9)
    local height = 6 + fortificationLevel

    if laneEntry.name == "North" or laneEntry.name == "South" then
        return Vector3.new(16, height, thickness)
    end

    return Vector3.new(thickness, height, 16)
end

local function refreshInteractionPrompts(laneEntry)
    local promptsEnabled = laneEntry.promptsEnabled == true
    local repairPrompt = laneEntry.barricadePart:FindFirstChild("RepairPrompt")
    local chargePrompt = laneEntry.towerPart:FindFirstChild("ChargePrompt")
    local barricadeIsDamaged = laneEntry.barricadeHealth
        < GameConfig.DefenseTuning.BarricadeMaxHealth
    local towerNeedsCharge = laneEntry.towerEnergy < GameConfig.DefenseTuning.TowerMaxEnergy
    local concordCount = getConcordCount(laneEntry)
    local canReinforce = not barricadeIsDamaged
        and laneEntry.fortificationLevel < GameConfig.DefenseTuning.MaxFortificationLevel
    local canOvercharge = not towerNeedsCharge
        and laneEntry.overchargeLevel < GameConfig.DefenseTuning.MaxOverchargeLevel

    if repairPrompt ~= nil then
        if barricadeIsDamaged then
            repairPrompt.ActionText =
                string.format("Repair Barricade (-%d)", GameConfig.DefenseTuning.RepairSupplyCost)
        elseif canReinforce then
            repairPrompt.ActionText = string.format(
                "Reinforce Barricade (-%d)",
                GameConfig.DefenseTuning.ReinforceSupplyCost
            )
        else
            repairPrompt.ActionText = "Barricade Maxed"
        end

        repairPrompt.ObjectText = string.format(
            "%s Lane | Fort %d/%d | Concord %d/3",
            laneEntry.name,
            laneEntry.fortificationLevel,
            GameConfig.DefenseTuning.MaxFortificationLevel,
            concordCount
        )
        repairPrompt.Enabled = promptsEnabled and (barricadeIsDamaged or canReinforce)
    end

    if chargePrompt ~= nil then
        if towerNeedsCharge then
            chargePrompt.ActionText =
                string.format("Charge Tower (-%d)", GameConfig.DefenseTuning.ChargeSupplyCost)
        elseif canOvercharge then
            chargePrompt.ActionText = string.format(
                "Overcharge Tower (-%d)",
                GameConfig.DefenseTuning.OverchargeSupplyCost
            )
        else
            chargePrompt.ActionText = "Tower Maxed"
        end

        chargePrompt.ObjectText = string.format(
            "%s Tower | Boost %d/%d | Concord %d/3",
            laneEntry.name,
            laneEntry.overchargeLevel,
            GameConfig.DefenseTuning.MaxOverchargeLevel,
            concordCount
        )
        chargePrompt.Enabled = promptsEnabled and (towerNeedsCharge or canOvercharge)
    end
end

local function updateBarricadeVisuals(laneEntry)
    local healthRatio = math.clamp(getBarricadeHealthRatio(laneEntry), 0, 1)
    local fortificationLevel = laneEntry.fortificationLevel or 0

    laneEntry.barricadePart.Size = getBarricadePartSize(laneEntry)
    laneEntry.barricadePart.Material = if fortificationLevel >= 2
        then Enum.Material.Metal
        elseif fortificationLevel == 1 then Enum.Material.CorrodedMetal
        else Enum.Material.WoodPlanks
    laneEntry.barricadePart.Color = Color3.fromRGB(
        102 + math.floor(80 * healthRatio) + (fortificationLevel * 16),
        66 + math.floor(58 * healthRatio) + (fortificationLevel * 10),
        40 + math.floor(34 * healthRatio) + (fortificationLevel * 8)
    )
    laneEntry.barricadePart.Transparency = if laneEntry.barricadeHealth > 0 then 0 else 0.75
    laneEntry.barricadePart.CanCollide = laneEntry.barricadeHealth > 0
    laneEntry.barricadePart:SetAttribute("Health", laneEntry.barricadeHealth)
    laneEntry.barricadePart:SetAttribute("FortificationLevel", fortificationLevel)
    refreshInteractionPrompts(laneEntry)
end

local function updateTowerVisuals(laneEntry)
    local energyRatio = math.clamp(getTowerEnergyRatio(laneEntry), 0, 1)
    local overchargeLevel = laneEntry.overchargeLevel or 0

    laneEntry.towerPart.Size = Vector3.new(
        2.1 + (overchargeLevel * 0.25),
        6 + (overchargeLevel * 0.75),
        2.1 + (overchargeLevel * 0.25)
    )
    laneEntry.towerPart.Color = Color3.fromRGB(
        92 + math.floor(95 * energyRatio) + (overchargeLevel * 10),
        118 + math.floor(88 * energyRatio) + (overchargeLevel * 16),
        142 + math.floor(50 * energyRatio) + (overchargeLevel * 18)
    )
    laneEntry.towerPart:SetAttribute("OverchargeLevel", overchargeLevel)

    local light = laneEntry.towerPart:FindFirstChild("TowerLight")
    if light ~= nil then
        light.Brightness = 0.6 + (energyRatio * 3) + (overchargeLevel * 0.55)
        light.Range = 10 + math.floor(10 * energyRatio) + (overchargeLevel * 3)
    end

    refreshInteractionPrompts(laneEntry)
end

local function updateBeaconVisuals(laneEntry)
    local beacon = laneEntry.beaconPart
    local warningLevel = laneEntry.warningLevel or 0
    local energyRatio = math.clamp(getTowerEnergyRatio(laneEntry), 0, 1)
    local beaconLight = beacon:FindFirstChild("BeaconLight")

    if warningLevel <= 0 then
        beacon.Transparency = 0.35
        beacon.Color = Color3.fromRGB(
            86 + math.floor(32 * energyRatio),
            126 + math.floor(70 * energyRatio),
            150 + math.floor(65 * energyRatio)
        )

        if beaconLight ~= nil then
            beaconLight.Brightness = 0.4 + (energyRatio * 1.8)
            beaconLight.Range = 8 + math.floor(6 * energyRatio)
            beaconLight.Color = beacon.Color
        end

        return
    end

    local threatTypeName = laneEntry.warningThreatTypeName or "Runner"
    local archetypeConfig = GameConfig.ThreatTuning.Archetypes[threatTypeName]
    beacon.Transparency = 0.1
    beacon.Color = archetypeConfig.windupColor

    if beaconLight ~= nil then
        beaconLight.Brightness = 2.6 + warningLevel
        beaconLight.Range = 14 + (warningLevel * 4)
        beaconLight.Color = archetypeConfig.windupColor
    end
end

local function getAverage(values)
    if #values == 0 then
        return 0
    end

    local total = 0

    for _, value in ipairs(values) do
        total += value
    end

    return total / #values
end

local function rebuildPublicState()
    local laneSnapshots = {}
    local healthyBarricades = 0
    local barricadeIntegrityValues = {}
    local towerEnergyValues = {}
    local totalFortificationLevel = 0
    local totalOverchargeLevel = 0
    local totalConcordLanes = 0

    for _, laneName in ipairs(LANE_ORDER) do
        local laneEntry = laneEntriesByName[laneName]
        local barricadeIntegrity = math.floor(getBarricadeHealthRatio(laneEntry) * 100)
        local towerEnergy = math.floor(getTowerEnergyRatio(laneEntry) * 100)
        local concordCount = getConcordCount(laneEntry)

        if laneEntry.barricadeHealth > 0 then
            healthyBarricades += 1
        end

        if concordCount >= 2 then
            totalConcordLanes += 1
        end

        table.insert(barricadeIntegrityValues, barricadeIntegrity)
        table.insert(towerEnergyValues, towerEnergy)
        totalFortificationLevel += laneEntry.fortificationLevel or 0
        totalOverchargeLevel += laneEntry.overchargeLevel or 0
        table.insert(
            laneSnapshots,
            table.freeze({
                name = laneName,
                barricadeHealth = laneEntry.barricadeHealth,
                barricadeMaxHealth = GameConfig.DefenseTuning.BarricadeMaxHealth,
                barricadeIntegrity = barricadeIntegrity,
                towerEnergy = towerEnergy,
                towerMaxEnergy = GameConfig.DefenseTuning.TowerMaxEnergy,
                breached = laneEntry.barricadeHealth <= 0,
                fortificationLevel = laneEntry.fortificationLevel or 0,
                overchargeLevel = laneEntry.overchargeLevel or 0,
                concordCount = concordCount,
                concordLevel = math.max(0, concordCount - 1),
                warningLevel = laneEntry.warningLevel or 0,
                warningThreatTypeName = laneEntry.warningThreatTypeName,
            })
        )
    end

    setDefenseState({
        phaseName = defenseState.phaseName,
        roundNumber = defenseState.roundNumber,
        totalBarricades = #LANE_ORDER,
        healthyBarricades = healthyBarricades,
        averageBarricadeIntegrity = math.floor(getAverage(barricadeIntegrityValues)),
        averageTowerEnergy = math.floor(getAverage(towerEnergyValues)),
        totalFortificationLevel = totalFortificationLevel,
        totalOverchargeLevel = totalOverchargeLevel,
        totalConcordLanes = totalConcordLanes,
        lanes = table.freeze(laneSnapshots),
    })
end

local function broadcastDefenseState()
    rebuildPublicState()
    getRemoteEvent():FireAllClients(defenseState)
end

local function pushDefenseState(player: Player)
    rebuildPublicState()
    getRemoteEvent():FireClient(player, defenseState)
end

local function setPromptsEnabled(laneEntry, enabled: boolean)
    laneEntry.promptsEnabled = enabled
    refreshInteractionPrompts(laneEntry)
end

local function applyBarricadeHealth(laneEntry, nextHealth: number)
    laneEntry.barricadeHealth =
        math.clamp(math.floor(nextHealth), 0, GameConfig.DefenseTuning.BarricadeMaxHealth)

    if laneEntry.barricadeHealth <= 0 then
        laneEntry.fortificationLevel = 0
    end

    laneEntry.barricadePart:SetAttribute("LaneName", laneEntry.name)
    updateBarricadeVisuals(laneEntry)
end

local function applyTowerEnergy(laneEntry, nextEnergy: number)
    laneEntry.towerEnergy =
        math.clamp(math.floor(nextEnergy), 0, GameConfig.DefenseTuning.TowerMaxEnergy)
    updateTowerVisuals(laneEntry)
    updateBeaconVisuals(laneEntry)
end

local function handleBarricadeAction(player: Player, laneName: string)
    local laneEntry = laneEntriesByName[laneName]

    if defenseState.phaseName ~= "DayPrep" or laneEntry == nil then
        return
    end

    local roleModifiers = roleService.getRoleModifiersForPlayer(player)
    local echoModifiers = if echoService ~= nil then echoService.getCombinedModifiers() else nil

    if laneEntry.barricadeHealth < GameConfig.DefenseTuning.BarricadeMaxHealth then
        local repairCost = math.max(
            0,
            GameConfig.DefenseTuning.RepairSupplyCost - roleModifiers.repairCostReduction
        )

        if not objectiveService.consumeSupplies(repairCost) then
            return
        end

        applyBarricadeHealth(
            laneEntry,
            laneEntry.barricadeHealth
                + GameConfig.DefenseTuning.RepairAmountPerUse
                + roleModifiers.repairAmountBonus
                + (if echoModifiers ~= nil then echoModifiers.repairAmountBonus else 0)
        )
        registerRoleContribution(laneEntry, player)

        if echoService ~= nil then
            echoService.registerBarricadeAction(player, "Repair")
        end

        if dutyService ~= nil then
            dutyService.registerBarricadeAction(player, "Repair")
        end

        broadcastDefenseState()
        return
    end

    if laneEntry.fortificationLevel >= GameConfig.DefenseTuning.MaxFortificationLevel then
        return
    end

    local reinforceCost = math.max(
        0,
        GameConfig.DefenseTuning.ReinforceSupplyCost - roleModifiers.reinforceCostReduction
    )

    if not objectiveService.consumeSupplies(reinforceCost) then
        return
    end

    laneEntry.fortificationLevel += 1
    registerRoleContribution(laneEntry, player)
    updateBarricadeVisuals(laneEntry)

    if echoService ~= nil then
        echoService.registerBarricadeAction(player, "Reinforce")
    end

    if dutyService ~= nil then
        dutyService.registerBarricadeAction(player, "Reinforce")
    end

    broadcastDefenseState()
end

local function handleTowerAction(player: Player, laneName: string)
    local laneEntry = laneEntriesByName[laneName]

    if defenseState.phaseName ~= "DayPrep" or laneEntry == nil then
        return
    end

    local roleModifiers = roleService.getRoleModifiersForPlayer(player)
    local echoModifiers = if echoService ~= nil then echoService.getCombinedModifiers() else nil

    if laneEntry.towerEnergy < GameConfig.DefenseTuning.TowerMaxEnergy then
        local chargeCost = math.max(
            0,
            GameConfig.DefenseTuning.ChargeSupplyCost - roleModifiers.chargeCostReduction
        )

        if not objectiveService.consumeSupplies(chargeCost) then
            return
        end

        applyTowerEnergy(
            laneEntry,
            laneEntry.towerEnergy
                + GameConfig.DefenseTuning.ChargeAmountPerUse
                + roleModifiers.chargeAmountBonus
                + (if echoModifiers ~= nil then echoModifiers.chargeAmountBonus else 0)
        )
        registerRoleContribution(laneEntry, player)

        if echoService ~= nil then
            echoService.registerTowerAction(player, "Charge")
        end

        if dutyService ~= nil then
            dutyService.registerTowerAction(player, "Charge")
        end

        broadcastDefenseState()
        return
    end

    if laneEntry.overchargeLevel >= GameConfig.DefenseTuning.MaxOverchargeLevel then
        return
    end

    local overchargeCost = math.max(
        0,
        GameConfig.DefenseTuning.OverchargeSupplyCost - roleModifiers.overchargeCostReduction
    )

    if not objectiveService.consumeSupplies(overchargeCost) then
        return
    end

    laneEntry.overchargeLevel += 1
    registerRoleContribution(laneEntry, player)
    updateTowerVisuals(laneEntry)

    if echoService ~= nil then
        echoService.registerTowerAction(player, "Overcharge")
    end

    if dutyService ~= nil then
        dutyService.registerTowerAction(player, "Overcharge")
    end

    broadcastDefenseState()
end

local function ensurePrompt(
    parent: Instance,
    promptName: string,
    actionText: string,
    objectText: string
)
    local existingPrompt = parent:FindFirstChild(promptName)

    if existingPrompt ~= nil then
        return existingPrompt
    end

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = promptName
    prompt.ActionText = actionText
    prompt.ObjectText = objectText
    prompt.HoldDuration = 0.6
    prompt.MaxActivationDistance = 14
    prompt.Parent = parent

    return prompt
end

local function buildLaneEntry(laneName: string)
    local folder = getLanePartsFolder()
    local laneFolder = folder:FindFirstChild(laneName)

    if laneFolder == nil then
        laneFolder = Instance.new("Folder")
        laneFolder.Name = laneName
        laneFolder.Parent = folder
    end

    local barricadePosition = buildLanePosition(laneName, GameConfig.DefenseTuning.BarricadeRadius)
    local towerPosition = buildLanePosition(laneName, GameConfig.DefenseTuning.BarricadeRadius - 8)
    local spawnPosition = buildLanePosition(laneName, GameConfig.ThreatTuning.SpawnRingRadius)

    local barricade = laneFolder:FindFirstChild("Barricade")
    if barricade == nil then
        barricade = Instance.new("Part")
        barricade.Name = "Barricade"
        barricade.Anchored = true
        barricade.Material = Enum.Material.WoodPlanks
        barricade.Parent = laneFolder
    end

    barricade.Size = if laneName == "North" or laneName == "South"
        then Vector3.new(16, 6, 2)
        else Vector3.new(2, 6, 16)
    barricade.Position = barricadePosition
    barricade.CFrame = CFrame.lookAt(barricade.Position, objectiveService.getCampCenter())

    local tower = laneFolder:FindFirstChild("Tower")
    if tower == nil then
        tower = Instance.new("Part")
        tower.Name = "Tower"
        tower.Anchored = true
        tower.Shape = Enum.PartType.Cylinder
        tower.Material = Enum.Material.Metal
        tower.Parent = laneFolder

        local light = Instance.new("PointLight")
        light.Name = "TowerLight"
        light.Color = Color3.fromRGB(126, 186, 255)
        light.Parent = tower
    end

    tower.Size = Vector3.new(2, 6, 2)
    tower.Position = towerPosition
    tower.CFrame = CFrame.lookAt(tower.Position, objectiveService.getCampCenter())
        * CFrame.Angles(0, 0, math.rad(90))

    local beacon = laneFolder:FindFirstChild("Beacon")
    if beacon == nil then
        beacon = Instance.new("Part")
        beacon.Name = "Beacon"
        beacon.Anchored = true
        beacon.Shape = Enum.PartType.Ball
        beacon.Material = Enum.Material.Neon
        beacon.Parent = laneFolder

        local beaconLight = Instance.new("PointLight")
        beaconLight.Name = "BeaconLight"
        beaconLight.Parent = beacon
    end

    beacon.Size = Vector3.new(1.6, 1.6, 1.6)
    beacon.Position = towerPosition + Vector3.new(0, 4.6, 0)

    local repairPrompt =
        ensurePrompt(barricade, "RepairPrompt", "Repair Barricade", laneName .. " Lane")
    local chargePrompt = ensurePrompt(tower, "ChargePrompt", "Charge Tower", laneName .. " Tower")

    repairPrompt.Triggered:Connect(function(player)
        handleBarricadeAction(player, laneName)
    end)

    chargePrompt.Triggered:Connect(function(player)
        handleTowerAction(player, laneName)
    end)

    local laneEntry = laneEntriesByName[laneName]

    if laneEntry == nil then
        laneEntry = {
            name = laneName,
            barricadePart = barricade,
            towerPart = tower,
            beaconPart = beacon,
            barricadeHealth = GameConfig.DefenseTuning.BarricadeMaxHealth,
            towerEnergy = GameConfig.DefenseTuning.StartingTowerEnergy,
            nextAutoFireAt = 0,
            spawnPosition = spawnPosition,
            fortificationLevel = 0,
            overchargeLevel = 0,
            promptsEnabled = false,
            roleContributors = {},
            warningLevel = 0,
            warningThreatTypeName = nil,
        }
        laneEntriesByName[laneName] = laneEntry
    else
        laneEntry.barricadePart = barricade
        laneEntry.towerPart = tower
        laneEntry.beaconPart = beacon
        laneEntry.spawnPosition = spawnPosition
        laneEntry.fortificationLevel = laneEntry.fortificationLevel or 0
        laneEntry.overchargeLevel = laneEntry.overchargeLevel or 0
        laneEntry.promptsEnabled = laneEntry.promptsEnabled == true
        laneEntry.roleContributors = laneEntry.roleContributors or {}
    end

    applyBarricadeHealth(laneEntry, laneEntry.barricadeHealth)
    applyTowerEnergy(laneEntry, laneEntry.towerEnergy)
    updateBeaconVisuals(laneEntry)
    setPromptsEnabled(laneEntry, false)

    return laneEntry
end

function DefenseService.initialize(dependencies)
    dutyService = dependencies.dutyService
    echoService = dependencies.echoService
    objectiveService = dependencies.objectiveService
    rescueService = dependencies.rescueService
    riteService = dependencies.riteService
    roleService = dependencies.roleService

    for _, laneName in ipairs(LANE_ORDER) do
        buildLaneEntry(laneName)
    end

    setDefenseState({
        phaseName = "Lobby",
        roundNumber = 0,
        totalBarricades = #LANE_ORDER,
        healthyBarricades = #LANE_ORDER,
        averageBarricadeIntegrity = 100,
        averageTowerEnergy = GameConfig.DefenseTuning.StartingTowerEnergy,
        totalFortificationLevel = 0,
        totalOverchargeLevel = 0,
        totalConcordLanes = 0,
        lanes = {},
    })
    broadcastDefenseState()
end

function DefenseService.startDayPhase(roundNumber: number, options)
    local tutorialMode = options ~= nil and options.tutorialMode == true

    setDefenseState({
        phaseName = "DayPrep",
        roundNumber = roundNumber,
        totalBarricades = defenseState.totalBarricades,
        healthyBarricades = defenseState.healthyBarricades,
        averageBarricadeIntegrity = defenseState.averageBarricadeIntegrity,
        averageTowerEnergy = defenseState.averageTowerEnergy,
        totalFortificationLevel = defenseState.totalFortificationLevel,
        totalOverchargeLevel = defenseState.totalOverchargeLevel,
        totalConcordLanes = defenseState.totalConcordLanes,
        lanes = defenseState.lanes,
    })

    for _, laneName in ipairs(LANE_ORDER) do
        local laneEntry = laneEntriesByName[laneName]
        laneEntry.nextAutoFireAt = 0
        laneEntry.overchargeLevel = 0
        laneEntry.roleContributors = {}
        laneEntry.warningLevel = 0
        laneEntry.warningThreatTypeName = nil
        updateTowerVisuals(laneEntry)
        updateBarricadeVisuals(laneEntry)
        setPromptsEnabled(laneEntry, true)

        if roundNumber == 1 and laneEntry.towerEnergy == 0 then
            applyTowerEnergy(laneEntry, GameConfig.DefenseTuning.StartingTowerEnergy)
        end

        if tutorialMode then
            laneEntry.fortificationLevel = 0
            applyBarricadeHealth(laneEntry, GameConfig.DefenseTuning.BarricadeMaxHealth)
            applyTowerEnergy(laneEntry, GameConfig.DefenseTuning.StartingTowerEnergy)
        end
    end

    if tutorialMode then
        local barricadeLaneEntry =
            laneEntriesByName[GameConfig.TutorialTuning.TargetBarricadeLaneName]
        local towerLaneEntry = laneEntriesByName[GameConfig.TutorialTuning.TargetTowerLaneName]

        if barricadeLaneEntry ~= nil then
            applyBarricadeHealth(
                barricadeLaneEntry,
                math.floor(GameConfig.DefenseTuning.BarricadeMaxHealth * 0.58)
            )
        end

        if towerLaneEntry ~= nil then
            applyTowerEnergy(
                towerLaneEntry,
                math.floor(GameConfig.DefenseTuning.TowerMaxEnergy * 0.24)
            )
        end
    end

    broadcastDefenseState()

    return defenseState
end

function DefenseService.startNightPhase(roundNumber: number)
    setDefenseState({
        phaseName = "NightSurvival",
        roundNumber = roundNumber,
        totalBarricades = defenseState.totalBarricades,
        healthyBarricades = defenseState.healthyBarricades,
        averageBarricadeIntegrity = defenseState.averageBarricadeIntegrity,
        averageTowerEnergy = defenseState.averageTowerEnergy,
        totalFortificationLevel = defenseState.totalFortificationLevel,
        totalOverchargeLevel = defenseState.totalOverchargeLevel,
        totalConcordLanes = defenseState.totalConcordLanes,
        lanes = defenseState.lanes,
    })

    for _, laneName in ipairs(LANE_ORDER) do
        local laneEntry = laneEntriesByName[laneName]
        laneEntry.warningLevel = 0
        laneEntry.warningThreatTypeName = nil
        updateBeaconVisuals(laneEntry)
        setPromptsEnabled(laneEntry, false)
    end

    broadcastDefenseState()

    return defenseState
end

function DefenseService.finishRound(roundNumber: number)
    setDefenseState({
        phaseName = "Results",
        roundNumber = roundNumber,
        totalBarricades = defenseState.totalBarricades,
        healthyBarricades = defenseState.healthyBarricades,
        averageBarricadeIntegrity = defenseState.averageBarricadeIntegrity,
        averageTowerEnergy = defenseState.averageTowerEnergy,
        totalFortificationLevel = defenseState.totalFortificationLevel,
        totalOverchargeLevel = defenseState.totalOverchargeLevel,
        totalConcordLanes = defenseState.totalConcordLanes,
        lanes = defenseState.lanes,
    })

    for _, laneName in ipairs(LANE_ORDER) do
        local laneEntry = laneEntriesByName[laneName]
        laneEntry.warningLevel = 0
        laneEntry.warningThreatTypeName = nil
        updateBeaconVisuals(laneEntry)
        setPromptsEnabled(laneEntry, false)
    end

    broadcastDefenseState()

    return defenseState
end

function DefenseService.getPreferredLaneName(threatTypeName: string?, allowedLaneNames)
    local laneNames = if type(allowedLaneNames) == "table" and #allowedLaneNames > 0
        then allowedLaneNames
        else LANE_ORDER
    local preferredLaneName = laneNames[1]
    local weakestScore = math.huge
    local preferredTarget = "Any"

    if threatTypeName ~= nil and GameConfig.ThreatTuning.Archetypes[threatTypeName] ~= nil then
        preferredTarget = GameConfig.ThreatTuning.Archetypes[threatTypeName].preferredTarget
    end

    for _, laneName in ipairs(laneNames) do
        local laneEntry = laneEntriesByName[laneName]
        local barricadeWeight = if preferredTarget == "Barricade" then 0.82 else 0.7
        local towerWeight = if preferredTarget == "Barricade" then 0.18 else 0.3
        local fortificationRatio = (laneEntry.fortificationLevel or 0)
            / math.max(1, GameConfig.DefenseTuning.MaxFortificationLevel)
        local overchargeRatio = (laneEntry.overchargeLevel or 0)
            / math.max(1, GameConfig.DefenseTuning.MaxOverchargeLevel)
        local concordRatio = getConcordCount(laneEntry) / math.max(1, #GameConfig.RoleTuning.Order)
        local laneScore = (getBarricadeHealthRatio(laneEntry) * barricadeWeight)
            + (getTowerEnergyRatio(laneEntry) * towerWeight)
            + (fortificationRatio * 0.25)
            + (overchargeRatio * 0.15)
            + (concordRatio * 0.18)
            + (math.random() * 0.15)

        if laneScore < weakestScore then
            weakestScore = laneScore
            preferredLaneName = laneName
        end
    end

    return preferredLaneName
end

function DefenseService.setLaneWarning(
    laneName: string,
    warningLevel: number,
    threatTypeName: string?
)
    local laneEntry = laneEntriesByName[laneName]

    if laneEntry == nil then
        return
    end

    laneEntry.warningLevel = math.max(0, math.floor(warningLevel))
    laneEntry.warningThreatTypeName = threatTypeName
    updateBeaconVisuals(laneEntry)
    broadcastDefenseState()
end

function DefenseService.getLaneSpawnPosition(laneName: string): Vector3
    return laneEntriesByName[laneName].spawnPosition
end

function DefenseService.getLaneTarget(laneName: string)
    local laneEntry = laneEntriesByName[laneName]

    if laneEntry ~= nil and laneEntry.barricadeHealth > 0 then
        return "Barricade", laneEntry.barricadePart, laneEntry.barricadePart.Position
    end

    local lanternPart = objectiveService.getLanternPart()
    return "Lantern", lanternPart, lanternPart.Position
end

function DefenseService.applyBarricadeDamage(laneName: string, damageAmount: number)
    local laneEntry = laneEntriesByName[laneName]

    if laneEntry == nil or laneEntry.barricadeHealth <= 0 then
        return 0
    end

    local riteModifiers = riteService.getNightModifiers()
    local echoModifiers = if echoService ~= nil then echoService.getCombinedModifiers() else nil
    local rescueModifiers = if rescueService ~= nil
        then rescueService.getLaneModifiers(laneName)
        else nil
    local concordCount = getConcordCount(laneEntry)
    local fortificationMitigation = 1
        - ((laneEntry.fortificationLevel or 0) * GameConfig.DefenseTuning.FortificationDamageReductionPerLevel)
        - (concordCount * GameConfig.RoleTuning.ConcordMitigationBonusPerRole)
        - riteModifiers.barricadeMitigationBonus
        - (if echoModifiers ~= nil then echoModifiers.barricadeMitigationBonus else 0)
        - (if rescueModifiers ~= nil then rescueModifiers.barricadeMitigationBonus else 0)
    local effectiveDamage =
        math.max(1, math.floor(damageAmount * math.max(0.3, fortificationMitigation)))

    applyBarricadeHealth(laneEntry, laneEntry.barricadeHealth - effectiveDamage)
    broadcastDefenseState()

    return laneEntry.barricadeHealth
end

function DefenseService.applyTowerSabotage(
    laneName: string,
    energyDrainAmount: number,
    overchargeLoss: number
)
    local laneEntry = laneEntriesByName[laneName]

    if laneEntry == nil then
        return 0, 0
    end

    laneEntry.overchargeLevel = math.max(0, (laneEntry.overchargeLevel or 0) - overchargeLoss)
    applyTowerEnergy(laneEntry, laneEntry.towerEnergy - energyDrainAmount)
    broadcastDefenseState()

    return laneEntry.towerEnergy, laneEntry.overchargeLevel
end

function DefenseService.tryAutoFire(laneName: string, targetPart: BasePart, nowTime: number)
    local laneEntry = laneEntriesByName[laneName]

    if laneEntry == nil then
        return 0
    end

    local riteModifiers = riteService.getNightModifiers()
    local echoModifiers = if echoService ~= nil then echoService.getCombinedModifiers() else nil
    local rescueModifiers = if rescueService ~= nil
        then rescueService.getLaneModifiers(laneName)
        else nil
    local overchargeLevel = laneEntry.overchargeLevel or 0
    local concordCount = getConcordCount(laneEntry)
    local autoShotRange = GameConfig.DefenseTuning.AutoShotRange
        + (overchargeLevel * GameConfig.DefenseTuning.AutoShotRangeBonusPerOvercharge)
        + (concordCount * GameConfig.RoleTuning.ConcordRangeBonusPerRole)
        + riteModifiers.towerRangeBonus
        + (if rescueModifiers ~= nil then rescueModifiers.towerRangeBonus else 0)
    local autoShotDamage = GameConfig.DefenseTuning.AutoShotDamage
        + (overchargeLevel * GameConfig.DefenseTuning.AutoShotDamageBonusPerOvercharge)
        + (concordCount * GameConfig.RoleTuning.ConcordDamageBonusPerRole)
        + riteModifiers.towerDamageBonus
        + (if echoModifiers ~= nil then echoModifiers.towerDamageBonus else 0)
        + (if rescueModifiers ~= nil then rescueModifiers.towerDamageBonus else 0)
    local autoShotCooldown = math.max(
        0.45,
        GameConfig.DefenseTuning.AutoShotCooldownSeconds
            - (overchargeLevel * GameConfig.DefenseTuning.AutoShotCooldownReductionPerOvercharge)
    )

    if laneEntry.towerEnergy < GameConfig.DefenseTuning.AutoShotEnergyCost then
        return 0
    end

    if nowTime < laneEntry.nextAutoFireAt then
        return 0
    end

    local distanceToTarget = (laneEntry.towerPart.Position - targetPart.Position).Magnitude

    if distanceToTarget > autoShotRange then
        return 0
    end

    laneEntry.nextAutoFireAt = nowTime + autoShotCooldown
    applyTowerEnergy(laneEntry, laneEntry.towerEnergy - GameConfig.DefenseTuning.AutoShotEnergyCost)
    broadcastDefenseState()

    return autoShotDamage
end

function DefenseService.getState()
    rebuildPublicState()
    return defenseState
end

function DefenseService.syncPlayer(player: Player)
    pushDefenseState(player)
end

return DefenseService
