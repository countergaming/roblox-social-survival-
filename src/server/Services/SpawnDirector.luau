local SpawnDirector = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

function SpawnDirector.isGuidedRound(roundNumber: number): boolean
    return roundNumber <= GameConfig.TutorialTuning.GuidedRounds
end

function SpawnDirector.getThreatRate(roundNumber: number, playerCount: number): number
    if SpawnDirector.isGuidedRound(roundNumber) then
        return GameConfig.TutorialTuning.ThreatRate
    end

    local spawnTuning = GameConfig.SpawnTuning
    local adjustedPlayerCount = math.max(playerCount, 1)

    local threatRate = spawnTuning.BaseThreatRate
        + ((roundNumber - 1) * spawnTuning.NightGrowth)
        + ((adjustedPlayerCount - 1) * spawnTuning.AdditionalThreatPerPlayer)

    return math.clamp(threatRate, spawnTuning.BaseThreatRate, spawnTuning.MaxThreatRate)
end

function SpawnDirector.buildNightPlan(roundNumber: number, playerCount: number)
    local threatRate = SpawnDirector.getThreatRate(roundNumber, playerCount)

    if SpawnDirector.isGuidedRound(roundNumber) then
        local tutorialTuning = GameConfig.TutorialTuning

        return table.freeze({
            tutorialMode = true,
            tutorialTitle = tutorialTuning.Title,
            tutorialSummary = tutorialTuning.Summary,
            threatRate = threatRate,
            spawnIntervalSeconds = tutorialTuning.SpawnIntervalSeconds,
            maxSimultaneousThreats = tutorialTuning.MaxSimultaneousThreats,
            eliteChance = 0,
            warningLeadSeconds = tutorialTuning.WarningLeadSeconds,
            allowedLaneNames = tutorialTuning.AllowedLaneNames,
            forcedLaneSequence = tutorialTuning.ForcedLaneSequence,
            threatSequence = tutorialTuning.ThreatSequence,
            desiredSpawnCount = #tutorialTuning.ThreatSequence,
            waveLabelOverride = tutorialTuning.Title,
        })
    end

    return table.freeze({
        tutorialMode = false,
        threatRate = threatRate,
        spawnIntervalSeconds = math.max(4, math.floor(12 / threatRate)),
        maxSimultaneousThreats = math.max(3, math.ceil(playerCount * threatRate)),
        eliteChance = math.min(0.5, 0.08 * roundNumber),
    })
end

return SpawnDirector
