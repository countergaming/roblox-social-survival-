local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))

local EchoService = {}

local EMPTY_MODIFIERS = table.freeze({
	extraSuppliesPerCrate = 0,
	repairAmountBonus = 0,
	barricadeMitigationBonus = 0,
	chargeAmountBonus = 0,
	towerDamageBonus = 0,
	pulseCooldownDelta = 0,
	pulseDamageBonus = 0,
})

local domainProgressByName = {}
local directiveTargetsByDomain = {}
local unlockedBoonNames = {}
local latestUnlockedBoonName = ""
local echoState = table.freeze({
	phaseName = "Lobby",
	roundNumber = 0,
	completedDirectives = 0,
	unlockedBoonCount = 0,
	latestUnlockedBoonName = "",
	latestUnlockedBoonTitle = "",
	latestUnlockedBoonSummary = "",
	directives = table.freeze({}),
	unlockedBoons = table.freeze({}),
})

local function getRemoteEvent(): RemoteEvent
	local remoteFolder = ReplicatedStorage:WaitForChild(RemoteNames.Folder)
	return remoteFolder:WaitForChild(RemoteNames.EchoStateChanged) :: RemoteEvent
end

local function getDirectiveConfig(domainName: string)
	return GameConfig.EchoTuning.Directives[domainName]
end

local function getBoonConfig(domainName: string)
	return GameConfig.EchoTuning.Boons[domainName]
end

local function isBoonUnlocked(domainName: string): boolean
	for _, unlockedDomainName in ipairs(unlockedBoonNames) do
		if unlockedDomainName == domainName then
			return true
		end
	end

	return false
end

local function getDirectiveTarget(domainName: string, roundNumber: number, playerCount: number): number
	local targetConfig = GameConfig.EchoTuning.DirectiveTargets
	local adjustedPlayerCount = math.max(1, playerCount)

	if domainName == "Wilds" then
		return targetConfig.WildsBase + (adjustedPlayerCount - 1) * targetConfig.WildsPerPlayer
	end

	if domainName == "Bulwark" then
		return targetConfig.BulwarkBase + math.max(0, roundNumber - 1) * targetConfig.BulwarkPerRound
	end

	return targetConfig.StormfireBase + math.max(0, roundNumber - 1) * targetConfig.StormfirePerRound
end

local function resetProgress(roundNumber: number, playerCount: number)
	domainProgressByName = {}
	directiveTargetsByDomain = {}
	latestUnlockedBoonName = ""

	for _, domainName in ipairs(GameConfig.EchoTuning.Domains) do
		domainProgressByName[domainName] = 0
		directiveTargetsByDomain[domainName] = getDirectiveTarget(domainName, roundNumber, playerCount)
	end
end

local function buildDirectiveSnapshots()
	local directiveSnapshots = {}
	local completedDirectives = 0

	for _, domainName in ipairs(GameConfig.EchoTuning.Domains) do
		local directiveConfig = getDirectiveConfig(domainName)
		local currentValue = domainProgressByName[domainName] or 0
		local targetValue = directiveTargetsByDomain[domainName] or 0
		local completed = currentValue >= targetValue and targetValue > 0

		if completed then
			completedDirectives += 1
		end

		table.insert(
			directiveSnapshots,
			table.freeze({
				name = domainName,
				title = directiveConfig.title,
				shortTitle = directiveConfig.shortTitle,
				summary = directiveConfig.summary,
				currentValue = currentValue,
				targetValue = targetValue,
				completed = completed,
			})
		)
	end

	return table.freeze(directiveSnapshots), completedDirectives
end

local function buildUnlockedBoonSnapshots()
	local snapshots = {}

	for _, domainName in ipairs(unlockedBoonNames) do
		local boonConfig = getBoonConfig(domainName)

		if boonConfig ~= nil then
			table.insert(
				snapshots,
				table.freeze({
					name = domainName,
					title = boonConfig.title,
					summary = boonConfig.summary,
				})
			)
		end
	end

	return table.freeze(snapshots)
end

local function rebuildState(phaseName: string, roundNumber: number)
	local directives, completedDirectives = buildDirectiveSnapshots()
	local unlockedBoons = buildUnlockedBoonSnapshots()
	local latestUnlockedBoonConfig = getBoonConfig(latestUnlockedBoonName)

	echoState = table.freeze({
		phaseName = phaseName,
		roundNumber = roundNumber,
		completedDirectives = completedDirectives,
		unlockedBoonCount = #unlockedBoonNames,
		latestUnlockedBoonName = latestUnlockedBoonName,
		latestUnlockedBoonTitle = if latestUnlockedBoonConfig ~= nil then latestUnlockedBoonConfig.title else "",
		latestUnlockedBoonSummary = if latestUnlockedBoonConfig ~= nil then latestUnlockedBoonConfig.summary else "",
		directives = directives,
		unlockedBoons = unlockedBoons,
	})
end

local function broadcastState()
	getRemoteEvent():FireAllClients(echoState)
end

local function pushState(player: Player)
	getRemoteEvent():FireClient(player, echoState)
end

local function applyState(phaseName: string, roundNumber: number)
	rebuildState(phaseName, roundNumber)
	broadcastState()
end

local function incrementDomain(domainName: string, amount: number)
	if echoState.phaseName ~= "DayPrep" and echoState.phaseName ~= "NightSurvival" then
		return
	end

	if directiveTargetsByDomain[domainName] == nil then
		return
	end

	domainProgressByName[domainName] = math.max(0, (domainProgressByName[domainName] or 0) + amount)
	applyState(echoState.phaseName, echoState.roundNumber)
end

local function selectUnlock(roundOutcome)
	if not roundOutcome.nightCleared then
		latestUnlockedBoonName = ""
		return
	end

	local rankedDomains = {}

	for _, domainName in ipairs(GameConfig.EchoTuning.Domains) do
		table.insert(rankedDomains, {
			name = domainName,
			progress = domainProgressByName[domainName] or 0,
			target = directiveTargetsByDomain[domainName] or 0,
		})
	end

	table.sort(rankedDomains, function(left, right)
		if left.progress == right.progress then
			return left.name < right.name
		end

		return left.progress > right.progress
	end)

	latestUnlockedBoonName = ""

	for _, rankedDomain in ipairs(rankedDomains) do
		if
			rankedDomain.progress >= rankedDomain.target
			and rankedDomain.target > 0
			and not isBoonUnlocked(rankedDomain.name)
		then
			unlockedBoonNames = table.clone(unlockedBoonNames)
			table.insert(unlockedBoonNames, rankedDomain.name)
			latestUnlockedBoonName = rankedDomain.name
			return
		end
	end
end

function EchoService.initialize()
	domainProgressByName = {}
	directiveTargetsByDomain = {}
	unlockedBoonNames = {}
	latestUnlockedBoonName = ""
	applyState("Lobby", 0)
end

function EchoService.startDayPhase(roundNumber: number, playerCount: number)
	if roundNumber == 1 then
		unlockedBoonNames = {}
	end

	resetProgress(roundNumber, playerCount)
	applyState("DayPrep", roundNumber)

	return echoState
end

function EchoService.startNightPhase(roundNumber: number)
	applyState("NightSurvival", roundNumber)
	return echoState
end

function EchoService.finishRound(roundNumber: number, roundOutcome, roleState, defenseState)
	if roleState ~= nil and (roleState.teamCoverageCount or 0) >= 3 then
		domainProgressByName.Bulwark = (domainProgressByName.Bulwark or 0) + 1
	end

	if defenseState ~= nil and (defenseState.totalConcordLanes or 0) > 0 then
		domainProgressByName.Bulwark = (domainProgressByName.Bulwark or 0) + defenseState.totalConcordLanes
	end

	selectUnlock(roundOutcome)
	applyState("Results", roundNumber)

	return echoState
end

function EchoService.registerResourceCollected(_player: Player, collectedCount: number)
	incrementDomain("Wilds", math.max(1, math.floor(collectedCount)))
end

function EchoService.registerBarricadeAction(_player: Player, actionName: string)
	incrementDomain("Bulwark", if actionName == "Reinforce" then 2 else 1)
end

function EchoService.registerTowerAction(_player: Player, actionName: string)
	incrementDomain("Stormfire", if actionName == "Overcharge" then 2 else 1)
end

function EchoService.registerPulse(_player: Player?)
	incrementDomain("Stormfire", 2)
end

function EchoService.registerThreatDefeats(_player: Player, defeatCount: number)
	incrementDomain("Stormfire", math.max(0, math.floor(defeatCount)))
end

function EchoService.getCombinedModifiers()
	if #unlockedBoonNames == 0 then
		return EMPTY_MODIFIERS
	end

	local combinedModifiers = {
		extraSuppliesPerCrate = 0,
		repairAmountBonus = 0,
		barricadeMitigationBonus = 0,
		chargeAmountBonus = 0,
		towerDamageBonus = 0,
		pulseCooldownDelta = 0,
		pulseDamageBonus = 0,
	}

	for _, domainName in ipairs(unlockedBoonNames) do
		local boonConfig = getBoonConfig(domainName)

		if boonConfig ~= nil then
			for modifierName, modifierValue in pairs(boonConfig.modifiers) do
				combinedModifiers[modifierName] += modifierValue
			end
		end
	end

	return table.freeze(combinedModifiers)
end

function EchoService.getState()
	return echoState
end

function EchoService.syncPlayer(player: Player)
	pushState(player)
end

return EchoService
