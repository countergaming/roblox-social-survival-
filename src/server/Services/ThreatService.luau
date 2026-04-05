local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))

local ThreatService = {}

local objectiveService = nil
local defenseService = nil
local dutyService = nil
local echoService = nil
local riteService = nil
local riteFocusService = nil
local roleService = nil
local rescueService = nil
local threatFolder = nil
local effectFolder = nil
local pulsePrompt = nil
local movementConnection = nil
local activeThreatEntries = {}
local spawnBudget = 0
local isNightActive = false
local activeNightToken = 0
local nextPulseReadyAt = 0
local threatState = table.freeze({
	phaseName = "Lobby",
	roundNumber = 0,
	lanternHealth = 0,
	lanternMaxHealth = 0,
	activeThreats = 0,
	spawnedThreats = 0,
	defeatedThreats = 0,
	pulseReadyInSeconds = 0,
	nightFailed = false,
	nightCleared = false,
	incomingLaneName = "",
	incomingThreatTypeName = "",
	pressureLaneName = "",
	waveLabel = "Quiet",
})

local function resolveOverride(overrides, key, currentValue)
	if overrides[key] ~= nil then
		return overrides[key]
	end

	return currentValue
end

local function getRemoteEvent(): RemoteEvent
	local remoteFolder = ReplicatedStorage:WaitForChild(RemoteNames.Folder)
	return remoteFolder:WaitForChild(RemoteNames.ThreatStateChanged) :: RemoteEvent
end

local function setThreatState(nextState)
	threatState = table.freeze(nextState)
end

local function countLiveThreats()
	local liveThreats = 0

	for _, entry in ipairs(activeThreatEntries) do
		if not entry.isDead and entry.part.Parent ~= nil then
			liveThreats += 1
		end
	end

	return liveThreats
end

local function updateThreatVisual(entry)
	if entry.part.Parent == nil then
		return
	end

	local healthRatio = entry.health / entry.maxHealth
	local archetype = entry.archetype

	if entry.isWindingUp then
		entry.part.Color = archetype.windupColor
		entry.part.Material = Enum.Material.Neon
		entry.part.Size = archetype.size * 1.08
		return
	end

	entry.part.Shape = Enum.PartType[archetype.shape]
	entry.part.Material = Enum.Material[archetype.material]
	entry.part.Color = Color3.fromRGB(
		math.max(32, math.floor(archetype.baseColor.R * 255 * (0.55 + (healthRatio * 0.45)))),
		math.max(24, math.floor(archetype.baseColor.G * 255 * (0.55 + (healthRatio * 0.45)))),
		math.max(24, math.floor(archetype.baseColor.B * 255 * (0.55 + (healthRatio * 0.45))))
	)
	entry.part.Size = archetype.size
end

local function buildState(overrides)
	return {
		phaseName = resolveOverride(overrides, "phaseName", threatState.phaseName),
		roundNumber = resolveOverride(overrides, "roundNumber", threatState.roundNumber),
		lanternHealth = resolveOverride(overrides, "lanternHealth", threatState.lanternHealth),
		lanternMaxHealth = resolveOverride(overrides, "lanternMaxHealth", threatState.lanternMaxHealth),
		activeThreats = resolveOverride(overrides, "activeThreats", threatState.activeThreats),
		spawnedThreats = resolveOverride(overrides, "spawnedThreats", threatState.spawnedThreats),
		defeatedThreats = resolveOverride(overrides, "defeatedThreats", threatState.defeatedThreats),
		pulseReadyInSeconds = resolveOverride(overrides, "pulseReadyInSeconds", threatState.pulseReadyInSeconds),
		nightFailed = if overrides.nightFailed ~= nil then overrides.nightFailed else threatState.nightFailed,
		nightCleared = if overrides.nightCleared ~= nil then overrides.nightCleared else threatState.nightCleared,
		incomingLaneName = resolveOverride(overrides, "incomingLaneName", threatState.incomingLaneName),
		incomingThreatTypeName = resolveOverride(
			overrides,
			"incomingThreatTypeName",
			threatState.incomingThreatTypeName
		),
		pressureLaneName = resolveOverride(overrides, "pressureLaneName", threatState.pressureLaneName),
		waveLabel = resolveOverride(overrides, "waveLabel", threatState.waveLabel),
	}
end

local function getPressureLaneName()
	local lanePressureByName = {}
	local mostPressure = 0
	local strongestLaneName = ""

	for _, entry in ipairs(activeThreatEntries) do
		if not entry.isDead and entry.part.Parent ~= nil then
			lanePressureByName[entry.laneName] = (lanePressureByName[entry.laneName] or 0)
				+ entry.archetype.pressureWeight
		end
	end

	for laneName, pressureAmount in pairs(lanePressureByName) do
		if pressureAmount > mostPressure then
			mostPressure = pressureAmount
			strongestLaneName = laneName
		end
	end

	if strongestLaneName == "" then
		return threatState.incomingLaneName
	end

	return strongestLaneName
end

local function getWaveLabel(roundNumber: number): string
	if roundNumber <= 2 then
		return "Opening Assault"
	end

	if roundNumber <= 4 then
		return "Pressure Wave"
	end

	return "Siege Wave"
end

local function chooseThreatType(roundNumber: number, spawnIndex: number): string
	if roundNumber >= 4 and spawnIndex % 5 == 0 then
		return "Sapper"
	end

	if roundNumber >= 2 and spawnIndex % 3 == 0 then
		return "Brute"
	end

	if roundNumber >= 3 and (spawnIndex + roundNumber) % 4 == 0 then
		return "Sapper"
	end

	return "Runner"
end

local function chooseNightThreatType(roundNumber: number, spawnIndex: number, nightPlan): string
	if type(nightPlan.threatSequence) == "table" and nightPlan.threatSequence[spawnIndex] ~= nil then
		return nightPlan.threatSequence[spawnIndex]
	end

	return chooseThreatType(roundNumber, spawnIndex)
end

local function chooseNightLaneName(roundNumber: number, spawnIndex: number, nightPlan): string
	if type(nightPlan.forcedLaneSequence) == "table" and nightPlan.forcedLaneSequence[spawnIndex] ~= nil then
		return nightPlan.forcedLaneSequence[spawnIndex]
	end

	local nextThreatTypeName = chooseNightThreatType(roundNumber, spawnIndex, nightPlan)
	local rescuePriorityLaneName = if rescueService ~= nil
		then rescueService.getPriorityLaneName(nextThreatTypeName, nightPlan.allowedLaneNames)
		else nil

	if rescuePriorityLaneName ~= nil then
		return rescuePriorityLaneName
	end

	return defenseService.getPreferredLaneName(nextThreatTypeName, nightPlan.allowedLaneNames)
end

local function broadcastThreatState()
	getRemoteEvent():FireAllClients(threatState)
end

local function pushThreatState(player: Player)
	getRemoteEvent():FireClient(player, threatState)
end

local function getThreatFolder()
	if threatFolder ~= nil and threatFolder.Parent ~= nil then
		return threatFolder
	end

	local runtimeFolder = objectiveService.getRuntimeFolder()
	local existingFolder = runtimeFolder:FindFirstChild("Threats")

	if existingFolder ~= nil then
		threatFolder = existingFolder
		return threatFolder
	end

	threatFolder = Instance.new("Folder")
	threatFolder.Name = "Threats"
	threatFolder.Parent = runtimeFolder

	return threatFolder
end

local function getEffectFolder()
	if effectFolder ~= nil and effectFolder.Parent ~= nil then
		return effectFolder
	end

	local runtimeFolder = objectiveService.getRuntimeFolder()
	local existingFolder = runtimeFolder:FindFirstChild("CombatEffects")

	if existingFolder ~= nil then
		effectFolder = existingFolder
		return effectFolder
	end

	effectFolder = Instance.new("Folder")
	effectFolder.Name = "CombatEffects"
	effectFolder.Parent = runtimeFolder

	return effectFolder
end

local function spawnEffect(
	effectName: string,
	position: Vector3,
	startSize: Vector3,
	endSize: Vector3,
	color: Color3,
	durationSeconds: number
)
	local effectPart = Instance.new("Part")
	effectPart.Name = effectName
	effectPart.Anchored = true
	effectPart.CanCollide = false
	effectPart.CanQuery = false
	effectPart.CanTouch = false
	effectPart.Shape = Enum.PartType.Ball
	effectPart.Material = Enum.Material.Neon
	effectPart.Color = color
	effectPart.Transparency = 0.2
	effectPart.Size = startSize
	effectPart.Position = position
	effectPart.Parent = getEffectFolder()

	local tween = TweenService:Create(
		effectPart,
		TweenInfo.new(durationSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = endSize,
			Transparency = 1,
		}
	)
	tween:Play()
	Debris:AddItem(effectPart, durationSeconds + 0.15)
end

local function spawnWarningEffect(laneName: string, threatTypeName: string, warningLevel: number)
	local archetype = GameConfig.ThreatTuning.Archetypes[threatTypeName]

	if archetype == nil then
		return
	end

	spawnEffect(
		string.format("Warning_%s", laneName),
		defenseService.getLaneSpawnPosition(laneName),
		Vector3.new(2.4, 2.4, 2.4),
		Vector3.new(8 + (warningLevel * 2), 8 + (warningLevel * 2), 8 + (warningLevel * 2)),
		archetype.windupColor,
		0.8
	)
end

local function spawnHitEffect(entry, wasDefeated: boolean)
	local baseSize = entry.archetype.size
	local effectColor = if wasDefeated then Color3.fromRGB(255, 236, 182) else entry.archetype.windupColor
	local startScale = if wasDefeated then 0.7 else 0.45
	local endScale = if wasDefeated then 2.2 else 1.2
	local durationSeconds = if wasDefeated then 0.32 else 0.16

	spawnEffect(
		"ThreatImpact",
		entry.part.Position,
		baseSize * startScale,
		baseSize * endScale,
		effectColor,
		durationSeconds
	)
end

local function spawnPulseEffect(originPosition: Vector3, pulseRadius: number)
	spawnEffect(
		"LanternPulse",
		originPosition,
		Vector3.new(4, 4, 4),
		Vector3.new(pulseRadius * 2, pulseRadius * 2, pulseRadius * 2),
		Color3.fromRGB(255, 214, 138),
		0.35
	)
end

local function getLivePlayerTargetEntries(position: Vector3, radius: number, excludedUserId: number?)
	local playerEntries = {}

	for _, player in ipairs(Players:GetPlayers()) do
		if excludedUserId == nil or player.UserId ~= excludedUserId then
			local character = player.Character
			local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
			local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil

			if
				humanoid ~= nil
				and humanoid.Health > 0
				and rootPart ~= nil
				and player:GetAttribute("IsDowned") ~= true
			then
				local distance = (rootPart.Position - position).Magnitude

				if distance <= radius then
					table.insert(playerEntries, {
						player = player,
						position = rootPart.Position,
						distance = distance,
					})
				end
			end
		end
	end

	table.sort(playerEntries, function(left, right)
		return left.distance < right.distance
	end)

	return playerEntries
end

local function applyBruteShockwave(entry, targetPosition: Vector3, excludedUserId: number?)
	if rescueService == nil or entry.threatTypeName ~= "Brute" then
		return
	end

	local shockwaveDamage = math.max(1, math.floor(entry.damage * GameConfig.ThreatTuning.BruteShockwaveDamageRatio))
	local playerEntries =
		getLivePlayerTargetEntries(targetPosition, GameConfig.ThreatTuning.BruteShockwaveRadius, excludedUserId)

	if #playerEntries == 0 then
		return
	end

	spawnEffect(
		"BruteShockwave",
		targetPosition,
		Vector3.new(3.2, 3.2, 3.2),
		Vector3.new(
			GameConfig.ThreatTuning.BruteShockwaveRadius * 2,
			GameConfig.ThreatTuning.BruteShockwaveRadius * 2,
			GameConfig.ThreatTuning.BruteShockwaveRadius * 2
		),
		entry.archetype.windupColor,
		0.26
	)

	for _, playerEntry in ipairs(playerEntries) do
		rescueService.applyThreatHit(playerEntry.player, shockwaveDamage, entry.laneName)
	end
end

local function clearThreats()
	for _, entry in ipairs(activeThreatEntries) do
		if entry.part.Parent ~= nil then
			entry.part:Destroy()
		end
	end

	activeThreatEntries = {}

	for _, child in ipairs(getThreatFolder():GetChildren()) do
		child:Destroy()
	end

	if effectFolder ~= nil and effectFolder.Parent ~= nil then
		for _, child in ipairs(effectFolder:GetChildren()) do
			child:Destroy()
		end
	end
end

local function getPulsePrompt()
	if pulsePrompt ~= nil and pulsePrompt.Parent ~= nil then
		return pulsePrompt
	end

	local lanternPart = objectiveService.getLanternPart()
	local existingPrompt = lanternPart:FindFirstChild("PulsePrompt")

	if existingPrompt ~= nil then
		pulsePrompt = existingPrompt
		return pulsePrompt
	end

	pulsePrompt = Instance.new("ProximityPrompt")
	pulsePrompt.Name = "PulsePrompt"
	pulsePrompt.ActionText = "Pulse Lantern"
	pulsePrompt.ObjectText = "Lantern Core"
	pulsePrompt.HoldDuration = 0.5
	pulsePrompt.MaxActivationDistance = 14
	pulsePrompt.Enabled = false
	pulsePrompt.Parent = lanternPart

	return pulsePrompt
end

local function refreshThreatState()
	local pulseReadyInSeconds = math.max(0, math.ceil(nextPulseReadyAt - os.clock()))
	local pressureLaneName = getPressureLaneName()

	setThreatState(table.freeze(buildState({
		activeThreats = countLiveThreats(),
		pulseReadyInSeconds = pulseReadyInSeconds,
		pressureLaneName = pressureLaneName,
	})))
end

local function broadcastRefreshedThreatState()
	refreshThreatState()
	broadcastThreatState()
end

local function setLanternHealth(nextHealth: number)
	local nextLanternHealth = math.clamp(math.floor(nextHealth), 0, threatState.lanternMaxHealth)

	local currentState = buildState({
		lanternHealth = nextLanternHealth,
		nightFailed = nextLanternHealth <= 0,
	})

	setThreatState(table.freeze(currentState))
end

local function removeDeadEntries()
	local liveEntries = {}

	for _, entry in ipairs(activeThreatEntries) do
		if not entry.isDead and entry.part.Parent ~= nil then
			table.insert(liveEntries, entry)
		end
	end

	activeThreatEntries = liveEntries
end

local function damageThreat(entry, damageAmount: number)
	if entry.isDead then
		return false
	end

	entry.health = math.max(0, entry.health - damageAmount)

	if entry.health > 0 then
		entry.isWindingUp = false
		entry.windupEndsAt = 0
		updateThreatVisual(entry)
		spawnHitEffect(entry, false)
		return false
	end

	entry.isDead = true
	spawnHitEffect(entry, true)

	if entry.part.Parent ~= nil then
		entry.part:Destroy()
	end

	setThreatState(table.freeze(buildState({
		defeatedThreats = threatState.defeatedThreats + 1,
	})))

	return true
end

local function getAttackTargetEntries(originPosition: Vector3, lookVector: Vector3)
	local candidates = {}
	local normalizedLookVector = Vector3.new(lookVector.X, 0, lookVector.Z)

	if normalizedLookVector.Magnitude <= 0 then
		normalizedLookVector = Vector3.new(0, 0, -1)
	else
		normalizedLookVector = normalizedLookVector.Unit
	end

	for _, entry in ipairs(activeThreatEntries) do
		if not entry.isDead and entry.part.Parent ~= nil then
			local offset = entry.part.Position - originPosition
			local horizontalOffset = Vector3.new(offset.X, 0, offset.Z)
			local distance = horizontalOffset.Magnitude

			if distance <= GameConfig.CombatTuning.SwingRange then
				local forwardDistance = normalizedLookVector:Dot(horizontalOffset)

				if forwardDistance > 0 then
					local lateralDistance = (horizontalOffset - (normalizedLookVector * forwardDistance)).Magnitude

					if lateralDistance <= GameConfig.CombatTuning.SwingWidth then
						table.insert(candidates, {
							entry = entry,
							distance = distance,
						})
					end
				end
			end
		end
	end

	table.sort(candidates, function(left, right)
		return left.distance < right.distance
	end)

	return candidates
end

local function emitPulse(player: Player?)
	if threatState.phaseName ~= "NightSurvival" then
		return
	end

	local nowTime = os.clock()
	if nowTime < nextPulseReadyAt then
		return
	end

	local riteModifiers = riteService.getNightModifiers()
	local roleModifiers = if player ~= nil and roleService ~= nil
		then roleService.getRoleModifiersForPlayer(player)
		else nil
	local echoModifiers = if echoService ~= nil then echoService.getCombinedModifiers() else nil
	local rescueModifiers = if rescueService ~= nil then rescueService.getCombatModifiers() else nil
	local riteFocusModifiers = if riteFocusService ~= nil then riteFocusService.getCombatModifiers() else nil
	local lanternPart = objectiveService.getLanternPart()
	local pulseCooldownSeconds = math.max(
		3,
		GameConfig.ThreatTuning.PulseCooldownSeconds
			+ riteModifiers.pulseCooldownDelta
			+ (if roleModifiers ~= nil then roleModifiers.pulseCooldownDelta else 0)
			+ (if echoModifiers ~= nil then echoModifiers.pulseCooldownDelta else 0)
			+ (if rescueModifiers ~= nil then rescueModifiers.pulseCooldownDelta else 0)
			+ (if riteFocusModifiers ~= nil then riteFocusModifiers.pulseCooldownDelta else 0)
	)
	local pulseRadius = GameConfig.ThreatTuning.PulseRadius
		+ riteModifiers.pulseRadiusBonus
		+ (if riteFocusModifiers ~= nil then riteFocusModifiers.pulseRadiusBonus else 0)
	local pulseDamage = GameConfig.ThreatTuning.PulseDamage
		+ riteModifiers.pulseDamageBonus
		+ (if roleModifiers ~= nil then roleModifiers.pulseDamageBonus else 0)
		+ (if echoModifiers ~= nil then echoModifiers.pulseDamageBonus else 0)
		+ (if rescueModifiers ~= nil then rescueModifiers.pulseDamageBonus else 0)
		+ (if riteFocusModifiers ~= nil then riteFocusModifiers.pulseDamageBonus else 0)

	nextPulseReadyAt = nowTime + pulseCooldownSeconds
	spawnPulseEffect(lanternPart.Position, pulseRadius)

	if echoService ~= nil then
		echoService.registerPulse(player)
	end

	if dutyService ~= nil then
		dutyService.registerPulse(player)
	end

	for _, entry in ipairs(activeThreatEntries) do
		if not entry.isDead and entry.part.Parent ~= nil then
			local distanceToLantern = (entry.part.Position - lanternPart.Position).Magnitude

			if distanceToLantern <= pulseRadius then
				damageThreat(entry, pulseDamage)
			end
		end
	end

	removeDeadEntries()
	broadcastRefreshedThreatState()
end

local function createThreatPart(laneName: string, threatIndex: number, archetype)
	local threatPart = Instance.new("Part")
	threatPart.Name = string.format("Threat_%s_%d", laneName, threatIndex)
	threatPart.Anchored = true
	threatPart.Shape = Enum.PartType[archetype.shape]
	threatPart.Material = Enum.Material[archetype.material]
	threatPart.Size = archetype.size
	threatPart.Color = archetype.baseColor
	threatPart.Position = defenseService.getLaneSpawnPosition(laneName)
	threatPart.Parent = getThreatFolder()

	return threatPart
end

local function createThreat(roundNumber: number, laneName: string, threatTypeName: string)
	local threatIndex = threatState.spawnedThreats + 1
	local archetype = GameConfig.ThreatTuning.Archetypes[threatTypeName]
	local threatPart = createThreatPart(laneName, threatIndex, archetype)
	local threatRate = math.max(1, threatState.roundNumber)
	local riteModifiers = riteService.getNightModifiers()
	local threatSpeedMultiplier = riteModifiers.globalThreatSpeedMultiplier
	local damageMultiplier = 1

	if threatTypeName == "Runner" then
		threatSpeedMultiplier *= riteModifiers.runnerSpeedMultiplier
	end

	if threatTypeName == "Sapper" then
		damageMultiplier *= riteModifiers.sapperDamageMultiplier
	end

	local entry = {
		part = threatPart,
		laneName = laneName,
		threatTypeName = threatTypeName,
		archetype = archetype,
		health = math.floor(
			(
				GameConfig.ThreatTuning.EnemyBaseHealth
				+ ((roundNumber - 1) * GameConfig.ThreatTuning.EnemyHealthGrowthPerRound)
			) * archetype.healthMultiplier
		),
		maxHealth = math.floor(
			(
				GameConfig.ThreatTuning.EnemyBaseHealth
				+ ((roundNumber - 1) * GameConfig.ThreatTuning.EnemyHealthGrowthPerRound)
			) * archetype.healthMultiplier
		),
		damage = math.floor(
			(
				GameConfig.ThreatTuning.EnemyBaseDamage
				+ ((roundNumber - 1) * GameConfig.ThreatTuning.EnemyDamageGrowthPerRound)
			)
				* archetype.damageMultiplier
				* damageMultiplier
		),
		speed = (GameConfig.ThreatTuning.EnemyMoveSpeed + (threatRate * 0.4))
			* archetype.speedMultiplier
			* threatSpeedMultiplier,
		nextAttackAt = 0,
		windupEndsAt = 0,
		isWindingUp = false,
		isDead = false,
	}

	table.insert(activeThreatEntries, entry)
	updateThreatVisual(entry)
	spawnEffect(
		"ThreatSpawn",
		threatPart.Position,
		archetype.size * 0.55,
		archetype.size * 1.45,
		archetype.windupColor,
		0.24
	)

	setThreatState(table.freeze(buildState({
		spawnedThreats = threatIndex,
		activeThreats = countLiveThreats(),
		incomingLaneName = "",
		incomingThreatTypeName = "",
	})))
	broadcastRefreshedThreatState()
end

local function stepThreats(deltaTime: number)
	if not isNightActive then
		return
	end

	local nowTime = os.clock()

	for _, entry in ipairs(activeThreatEntries) do
		if not entry.isDead and entry.part.Parent ~= nil then
			local towerDamage = defenseService.tryAutoFire(entry.laneName, entry.part, nowTime)
			if towerDamage > 0 then
				spawnEffect(
					"TowerShot",
					entry.part.Position,
					Vector3.new(1.2, 1.2, 1.2),
					Vector3.new(4.2, 4.2, 4.2),
					Color3.fromRGB(132, 206, 255),
					0.14
				)
				local wasDefeated = damageThreat(entry, towerDamage)
				if wasDefeated then
					continue
				end
			end

			local targetType, _, targetPosition = defenseService.getLaneTarget(entry.laneName)
			local playerIntercept = if rescueService ~= nil
				then rescueService.findInterceptTarget(entry.part.Position)
				else nil

			if playerIntercept ~= nil then
				local shouldIntercept = entry.archetype.preferredTarget ~= "Barricade"
					or playerIntercept.distance
						<= math.max(5, GameConfig.RescueTuning.PlayerInterceptDistance * 0.6)

				if shouldIntercept then
					targetType = "Player"
					targetPosition = playerIntercept.position
				end
			end

			if entry.archetype.preferredTarget == "Barricade" then
				local barricadeTargetType, _, barricadeTargetPosition = defenseService.getLaneTarget(entry.laneName)

				if barricadeTargetType == "Barricade" then
					targetType = barricadeTargetType
					targetPosition = barricadeTargetPosition
				end
			end

			local moveVector = targetPosition - entry.part.Position
			local horizontalMove = Vector3.new(moveVector.X, 0, moveVector.Z)
			local horizontalDistance = horizontalMove.Magnitude
			local runnerPressureMultiplier = 1
			local riteFocusThreatModifiers = if riteFocusService ~= nil
				then riteFocusService.getThreatModifiers(entry.laneName)
				else nil

			if
				rescueService ~= nil
				and entry.threatTypeName == "Runner"
				and rescueService.getDownedCountForLane(entry.laneName) > 0
			then
				runnerPressureMultiplier = GameConfig.ThreatTuning.RunnerDownedLaneSpeedMultiplier
			end

			if horizontalDistance > 0 then
				local movementStep = math.min(
					horizontalDistance,
					entry.speed
						* runnerPressureMultiplier
						* deltaTime
						* (if riteFocusThreatModifiers ~= nil then riteFocusThreatModifiers.speedMultiplier else 1)
				)
				local nextPosition = entry.part.Position + (horizontalMove.Unit * movementStep)
				entry.part.Position = Vector3.new(nextPosition.X, entry.part.Position.Y, nextPosition.Z)
			end

			if horizontalDistance <= GameConfig.ThreatTuning.EnemyHitDistance then
				if not entry.isWindingUp and nowTime >= entry.nextAttackAt then
					entry.isWindingUp = true
					entry.windupEndsAt = nowTime + GameConfig.ThreatTuning.EnemyAttackWindupSeconds
					updateThreatVisual(entry)
				end

				if entry.isWindingUp and nowTime >= entry.windupEndsAt then
					entry.isWindingUp = false
					entry.nextAttackAt = nowTime + GameConfig.ThreatTuning.EnemyAttackIntervalSeconds
					updateThreatVisual(entry)
					local effectiveDamage = entry.damage

					if
						rescueService ~= nil
						and entry.threatTypeName == "Runner"
						and rescueService.getDownedCountForLane(entry.laneName) > 0
					then
						effectiveDamage = math.max(
							entry.damage,
							math.floor(entry.damage * GameConfig.ThreatTuning.RunnerDownedLaneDamageMultiplier)
						)
					end

					if targetType == "Barricade" then
						defenseService.applyBarricadeDamage(entry.laneName, effectiveDamage)
						spawnEffect(
							"BarricadeHit",
							targetPosition,
							Vector3.new(2.4, 2.4, 2.4),
							Vector3.new(6.5, 6.5, 6.5),
							entry.archetype.windupColor,
							0.2
						)

						if entry.threatTypeName == "Brute" then
							applyBruteShockwave(entry, targetPosition, nil)
						elseif entry.threatTypeName == "Sapper" then
							defenseService.applyTowerSabotage(
								entry.laneName,
								GameConfig.ThreatTuning.SapperTowerDrain,
								GameConfig.ThreatTuning.SapperOverchargeBreak
							)
							spawnEffect(
								"SapperDisrupt",
								targetPosition,
								Vector3.new(2.6, 2.6, 2.6),
								Vector3.new(6.8, 6.8, 6.8),
								Color3.fromRGB(164, 255, 174),
								0.24
							)
						end
					elseif targetType == "Player" and playerIntercept ~= nil and rescueService ~= nil then
						local playerWasHit =
							rescueService.applyThreatHit(playerIntercept.player, effectiveDamage, entry.laneName)

						if playerWasHit then
							spawnEffect(
								"PlayerHit",
								targetPosition,
								Vector3.new(2.2, 2.2, 2.2),
								Vector3.new(5.4, 5.4, 5.4),
								entry.archetype.windupColor,
								0.18
							)

							if entry.threatTypeName == "Brute" then
								applyBruteShockwave(entry, targetPosition, playerIntercept.player.UserId)
							end
						end
					else
						setLanternHealth(threatState.lanternHealth - effectiveDamage)
						spawnEffect(
							"LanternHit",
							targetPosition,
							Vector3.new(3, 3, 3),
							Vector3.new(7.5, 7.5, 7.5),
							Color3.fromRGB(255, 186, 124),
							0.22
						)

						if entry.threatTypeName == "Sapper" then
							defenseService.applyTowerSabotage(
								entry.laneName,
								GameConfig.ThreatTuning.SapperTowerDrain,
								GameConfig.ThreatTuning.SapperOverchargeBreak
							)
							spawnEffect(
								"SapperDisrupt",
								targetPosition,
								Vector3.new(2.8, 2.8, 2.8),
								Vector3.new(7.4, 7.4, 7.4),
								Color3.fromRGB(164, 255, 174),
								0.24
							)
						elseif entry.threatTypeName == "Brute" then
							applyBruteShockwave(entry, targetPosition, nil)
						end
					end
				end
			elseif entry.isWindingUp then
				entry.isWindingUp = false
				entry.windupEndsAt = 0
				updateThreatVisual(entry)
			end
		end
	end

	removeDeadEntries()

	if threatState.lanternHealth <= 0 then
		isNightActive = false
	end

	if threatState.spawnedThreats >= spawnBudget and countLiveThreats() == 0 then
		setThreatState(table.freeze(buildState({
			nightCleared = true,
		})))
		isNightActive = false
	end

	broadcastRefreshedThreatState()
end

local function startMovementLoop()
	if movementConnection ~= nil then
		movementConnection:Disconnect()
	end

	movementConnection = RunService.Heartbeat:Connect(function(deltaTime)
		stepThreats(deltaTime)
	end)
end

local function stopMovementLoop()
	if movementConnection ~= nil then
		movementConnection:Disconnect()
		movementConnection = nil
	end
end

function ThreatService.initialize(dependencies)
	dutyService = dependencies.dutyService
	objectiveService = dependencies.objectiveService
	defenseService = dependencies.defenseService
	echoService = dependencies.echoService
	rescueService = dependencies.rescueService
	riteService = dependencies.riteService
	riteFocusService = dependencies.riteFocusService
	roleService = dependencies.roleService

	getThreatFolder()
	local createdPrompt = getPulsePrompt()
	createdPrompt.Triggered:Connect(function(player)
		emitPulse(player)
	end)

	setThreatState(table.freeze({
		phaseName = "Lobby",
		roundNumber = 0,
		lanternHealth = 0,
		lanternMaxHealth = 0,
		activeThreats = 0,
		spawnedThreats = 0,
		defeatedThreats = 0,
		pulseReadyInSeconds = 0,
		nightFailed = false,
		nightCleared = false,
		incomingLaneName = "",
		incomingThreatTypeName = "",
		pressureLaneName = "",
		waveLabel = "Quiet",
	}))
end

function ThreatService.startNightPhase(roundNumber: number, durationSeconds: number, nightPlan, objectiveState)
	activeNightToken += 1
	isNightActive = true
	clearThreats()
	nextPulseReadyAt = os.clock()
	spawnBudget = if nightPlan.desiredSpawnCount ~= nil
		then math.max(1, math.floor(nightPlan.desiredSpawnCount))
		else math.max(
			6,
			math.ceil(durationSeconds / math.max(4, nightPlan.spawnIntervalSeconds))
				* math.max(1, math.ceil(nightPlan.threatRate))
		)

	local riteModifiers = riteService.getNightModifiers()
	local lanternMaxHealth = GameConfig.ThreatTuning.LanternBaseHealth
		+ math.floor((objectiveState.lanternCharge or 0) * GameConfig.ThreatTuning.LanternChargeHealthBonus)
		+ riteModifiers.lanternHealthBonus

	setThreatState(table.freeze({
		phaseName = "NightSurvival",
		roundNumber = roundNumber,
		lanternHealth = lanternMaxHealth,
		lanternMaxHealth = lanternMaxHealth,
		activeThreats = 0,
		spawnedThreats = 0,
		defeatedThreats = 0,
		pulseReadyInSeconds = 0,
		nightFailed = false,
		nightCleared = false,
		incomingLaneName = "",
		incomingThreatTypeName = "",
		pressureLaneName = "",
		waveLabel = if nightPlan.waveLabelOverride ~= nil and nightPlan.waveLabelOverride ~= ""
			then nightPlan.waveLabelOverride
			else getWaveLabel(roundNumber),
	}))

	getPulsePrompt().Enabled = true
	startMovementLoop()
	broadcastRefreshedThreatState()

	local nightToken = activeNightToken
	local baseWarningLeadSeconds = if nightPlan.warningLeadSeconds ~= nil
		then nightPlan.warningLeadSeconds
		else GameConfig.ThreatTuning.WarningLeadSeconds
	local warningLeadSeconds = math.min(
		baseWarningLeadSeconds + riteModifiers.warningLeadBonus,
		math.max(0.35, nightPlan.spawnIntervalSeconds * 0.45)
	)
	task.spawn(function()
		while isNightActive and nightToken == activeNightToken and threatState.spawnedThreats < spawnBudget do
			if countLiveThreats() < nightPlan.maxSimultaneousThreats then
				local nextSpawnIndex = threatState.spawnedThreats + 1
				local nextThreatTypeName = chooseNightThreatType(roundNumber, nextSpawnIndex, nightPlan)
				local nextLaneName = chooseNightLaneName(roundNumber, nextSpawnIndex, nightPlan)
				local warningLevel = if nextThreatTypeName == "Runner" then 1 else 2

				defenseService.setLaneWarning(nextLaneName, warningLevel, nextThreatTypeName)
				spawnWarningEffect(nextLaneName, nextThreatTypeName, warningLevel)
				setThreatState(table.freeze(buildState({
					incomingLaneName = nextLaneName,
					incomingThreatTypeName = nextThreatTypeName,
				})))
				broadcastRefreshedThreatState()

				task.wait(warningLeadSeconds)

				if isNightActive and nightToken == activeNightToken then
					createThreat(roundNumber, nextLaneName, nextThreatTypeName)
				end

				defenseService.setLaneWarning(nextLaneName, 0, nil)
			end

			task.wait(math.max(0.5, nightPlan.spawnIntervalSeconds - warningLeadSeconds))
		end
	end)

	return threatState
end

function ThreatService.hasNightEnded(): boolean
	return threatState.nightFailed or threatState.nightCleared
end

function ThreatService.finishNightPhase(roundNumber: number)
	isNightActive = false
	stopMovementLoop()
	getPulsePrompt().Enabled = false
	clearThreats()

	setThreatState(table.freeze({
		phaseName = "Results",
		roundNumber = roundNumber,
		lanternHealth = threatState.lanternHealth,
		lanternMaxHealth = threatState.lanternMaxHealth,
		activeThreats = 0,
		spawnedThreats = threatState.spawnedThreats,
		defeatedThreats = threatState.defeatedThreats,
		pulseReadyInSeconds = 0,
		nightFailed = threatState.nightFailed,
		nightCleared = threatState.nightCleared,
		incomingLaneName = "",
		incomingThreatTypeName = "",
		pressureLaneName = threatState.pressureLaneName,
		waveLabel = threatState.waveLabel,
	}))
	broadcastThreatState()

	return threatState
end

function ThreatService.getState()
	return threatState
end

function ThreatService.applyPlayerAttack(player: Player, originPosition: Vector3, lookVector: Vector3)
	if threatState.phaseName ~= "NightSurvival" then
		return 0
	end

	local hitCount = 0
	local defeatedCount = 0
	local candidates = getAttackTargetEntries(originPosition, lookVector)
	local roleModifiers = roleService.getRoleModifiersForPlayer(player)
	local rescueModifiers = if rescueService ~= nil then rescueService.getCombatModifiers() else nil
	local swingDamage = GameConfig.CombatTuning.SwingDamage
		+ roleModifiers.meleeDamageBonus
		+ (if rescueModifiers ~= nil then rescueModifiers.meleeDamageBonus else 0)

	for _, candidate in ipairs(candidates) do
		if hitCount >= GameConfig.CombatTuning.MaxTargetsPerSwing then
			break
		end

		local wasDefeated = damageThreat(candidate.entry, swingDamage)
		hitCount += 1

		if wasDefeated then
			defeatedCount += 1
			player:SetAttribute("LastThreatDefeatAt", os.time())
		end
	end

	removeDeadEntries()
	broadcastRefreshedThreatState()

	if echoService ~= nil and defeatedCount > 0 then
		echoService.registerThreatDefeats(player, defeatedCount)
	end

	return hitCount
end

function ThreatService.syncPlayer(player: Player)
	pushThreatState(player)
end

return ThreatService
