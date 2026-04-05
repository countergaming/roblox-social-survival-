export type PhaseName = "Lobby" | "DayPrep" | "NightSurvival" | "Results"

export type PhasePayload = {
    name: PhaseName,
    roundNumber: number,
    durationSeconds: number,
    startedAtUnix: number,
    metadata: { [string]: any },
}

export type RoundOutcome = {
    nightNumber: number,
    alivePlayers: number,
    totalPlayers: number,
    lanternCharge: number,
    objectivesCompleted: number,
    lanternHealthRatio: number,
    barricadesStanding: number,
    fortificationLevel: number,
    overchargeLevel: number,
    suppliesCollected: number,
    suppliesSpent: number,
    teamCoverageCount: number,
    concordLanes: number,
    revivesCompleted: number,
    bleedouts: number,
    nightFailed: boolean,
    nightCleared: boolean,
}

export type RewardBreakdown = {
    coins: number,
    experience: number,
    survivalBonus: number,
    lanternBonus: number,
    defenseBonus: number,
    preparednessBonus: number,
    socialBonus: number,
    echoBonus: number,
    dutyBonus: number,
    clearBonus: number,
}

return {}
