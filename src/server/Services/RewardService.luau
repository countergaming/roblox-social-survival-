local RewardService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

function RewardService.calculateRewards(roundOutcome, echoState, dutyState)
	local rewardTuning = GameConfig.RewardTuning
	local echoTuning = GameConfig.EchoTuning
	local objectiveCoins = roundOutcome.objectivesCompleted * rewardTuning.ObjectiveCoins
	local objectiveExperience = roundOutcome.objectivesCompleted * rewardTuning.ObjectiveExperience
	local defenseBonus = (roundOutcome.barricadesStanding * rewardTuning.BarricadeHoldCoins)
		+ (roundOutcome.fortificationLevel * rewardTuning.FortificationCoins)
		+ (roundOutcome.overchargeLevel * rewardTuning.OverchargeCoins)
	local preparednessBonus = roundOutcome.suppliesSpent * rewardTuning.SupplySpendCoins
	local socialBonus = (roundOutcome.teamCoverageCount * rewardTuning.TeamCoverageCoins)
		+ (roundOutcome.concordLanes * rewardTuning.ConcordLaneCoins)
		+ ((roundOutcome.revivesCompleted or 0) * rewardTuning.ReviveCoins)
	local echoBonus = 0
	local dutyBonus = 0
	local clearBonus = if roundOutcome.nightCleared then rewardTuning.NightClearCoins else 0

	if echoState ~= nil then
		echoBonus = (echoState.completedDirectives or 0) * echoTuning.RewardCoinsPerDirective

		if echoState.latestUnlockedBoonName ~= "" then
			echoBonus += echoTuning.NewBoonCoins
		end
	end

	if dutyState ~= nil then
		dutyBonus = (dutyState.completedDutyCount or 0) * GameConfig.DutyTuning.RewardCoinsPerCompleted

		if dutyState.fullRosterBonusReady then
			dutyBonus += GameConfig.DutyTuning.FullRosterCoins
		end
	end

	local survivalRatio = 0
	if roundOutcome.totalPlayers > 0 then
		survivalRatio = roundOutcome.alivePlayers / roundOutcome.totalPlayers
	end

	local survivalBonus =
		math.floor((rewardTuning.BaseCoins + objectiveCoins) * survivalRatio * rewardTuning.SurvivalBonusMultiplier)
	local lanternBonus = math.floor(roundOutcome.lanternCharge * rewardTuning.LanternChargeBonus)
	local defenseExperience = math.floor(defenseBonus * 0.6)
	local preparednessExperience = math.floor(preparednessBonus * 0.5)
	local socialExperience = math.floor(
		(roundOutcome.teamCoverageCount * rewardTuning.TeamCoverageCoins * 0.5)
			+ (roundOutcome.concordLanes * rewardTuning.ConcordLaneCoins * 0.5)
			+ ((roundOutcome.revivesCompleted or 0) * rewardTuning.ReviveExperience)
	)
	local echoExperience = 0

	if echoState ~= nil then
		echoExperience = (echoState.completedDirectives or 0) * echoTuning.RewardExperiencePerDirective

		if echoState.latestUnlockedBoonName ~= "" then
			echoExperience += echoTuning.NewBoonExperience
		end
	end

	local dutyExperience = 0

	if dutyState ~= nil then
		dutyExperience = (dutyState.completedDutyCount or 0) * GameConfig.DutyTuning.RewardExperiencePerCompleted

		if dutyState.fullRosterBonusReady then
			dutyExperience += GameConfig.DutyTuning.FullRosterExperience
		end
	end

	local clearExperience = if roundOutcome.nightCleared then rewardTuning.NightClearExperience else 0

	return table.freeze({
		coins = rewardTuning.BaseCoins
			+ objectiveCoins
			+ survivalBonus
			+ lanternBonus
			+ defenseBonus
			+ preparednessBonus
			+ socialBonus
			+ echoBonus
			+ dutyBonus
			+ clearBonus,
		experience = rewardTuning.BaseExperience
			+ objectiveExperience
			+ lanternBonus
			+ defenseExperience
			+ preparednessExperience
			+ socialExperience
			+ echoExperience
			+ dutyExperience
			+ clearExperience,
		survivalBonus = survivalBonus,
		lanternBonus = lanternBonus,
		defenseBonus = defenseBonus,
		preparednessBonus = preparednessBonus,
		socialBonus = socialBonus,
		echoBonus = echoBonus,
		dutyBonus = dutyBonus,
		clearBonus = clearBonus,
	})
end

return RewardService
