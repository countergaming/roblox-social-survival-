local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local CombatService = {}

local threatService = nil
local playerAttackTimes = {}
local isStarted = false

local function removeNamedTool(container: Instance?, toolName: string)
	if container == nil then
		return
	end

	local existingTool = container:FindFirstChild(toolName)
	if existingTool ~= nil then
		existingTool:Destroy()
	end
end

local function buildToolHandle()
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 4, 1)
	handle.Material = Enum.Material.Metal
	handle.Color = Color3.fromRGB(186, 182, 168)
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth

	local light = Instance.new("PointLight")
	light.Name = "PikeLight"
	light.Brightness = 0.8
	light.Range = 8
	light.Color = Color3.fromRGB(255, 210, 112)
	light.Parent = handle

	return handle
end

local function attachActivation(tool: Tool, player: Player)
	tool.Activated:Connect(function()
		local character = player.Character
		if character == nil then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local rootPart = character:FindFirstChild("HumanoidRootPart")

		if humanoid == nil or humanoid.Health <= 0 or rootPart == nil then
			return
		end

		if player:GetAttribute("IsDowned") == true then
			return
		end

		local nowTime = os.clock()
		local lastAttackAt = playerAttackTimes[player.UserId] or 0

		if (nowTime - lastAttackAt) < GameConfig.CombatTuning.SwingCooldownSeconds then
			return
		end

		playerAttackTimes[player.UserId] = nowTime
		local handle = tool:FindFirstChild("Handle")
		local pikeLight = if handle ~= nil then handle:FindFirstChild("PikeLight") else nil
		tool.Name = string.format("%s*", GameConfig.CombatTuning.ToolName)
		if handle ~= nil then
			handle.Material = Enum.Material.Neon
			handle.Color = Color3.fromRGB(255, 210, 128)
		end

		if pikeLight ~= nil then
			pikeLight.Brightness = 2.2
			pikeLight.Range = 12
		end

		task.delay(GameConfig.CombatTuning.SwingCooldownSeconds, function()
			if tool.Parent ~= nil then
				tool.Name = GameConfig.CombatTuning.ToolName
			end

			if handle ~= nil and handle.Parent ~= nil then
				handle.Material = Enum.Material.Metal
				handle.Color = Color3.fromRGB(186, 182, 168)
			end

			if pikeLight ~= nil and pikeLight.Parent ~= nil then
				pikeLight.Brightness = 0.8
				pikeLight.Range = 8
			end
		end)

		local hitCount = threatService.applyPlayerAttack(player, rootPart.Position, rootPart.CFrame.LookVector)

		if hitCount > 0 and pikeLight ~= nil and pikeLight.Parent ~= nil then
			pikeLight.Brightness = 4.5
			pikeLight.Range = 15
		end
	end)
end

local function buildCombatTool(player: Player)
	local tool = Instance.new("Tool")
	tool.Name = GameConfig.CombatTuning.ToolName
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.GripForward = Vector3.new(0, 0, -1)
	tool.GripUp = Vector3.new(0, 1, 0)
	tool.GripRight = Vector3.new(1, 0, 0)
	tool.GripPos = Vector3.new(0, -1.2, -0.2)

	buildToolHandle().Parent = tool
	attachActivation(tool, player)

	return tool
end

local function giveCombatTool(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local starterGear = player:FindFirstChild("StarterGear")

	if backpack == nil or starterGear == nil then
		return
	end

	removeNamedTool(backpack, GameConfig.CombatTuning.ToolName)
	removeNamedTool(starterGear, GameConfig.CombatTuning.ToolName)
	removeNamedTool(player.Character, GameConfig.CombatTuning.ToolName)

	buildCombatTool(player).Parent = starterGear
	buildCombatTool(player).Parent = backpack
end

function CombatService.start(dependencies)
	if isStarted then
		return
	end

	isStarted = true
	threatService = dependencies.threatService

	Players.PlayerAdded:Connect(function(player)
		playerAttackTimes[player.UserId] = 0

		player.CharacterAdded:Connect(function()
			task.delay(0.2, function()
				if player.Parent ~= nil then
					giveCombatTool(player)
				end
			end)
		end)

		task.delay(0.2, function()
			if player.Parent ~= nil then
				giveCombatTool(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerAttackTimes[player.UserId] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		playerAttackTimes[player.UserId] = 0

		player.CharacterAdded:Connect(function()
			task.delay(0.2, function()
				if player.Parent ~= nil then
					giveCombatTool(player)
				end
			end)
		end)

		task.delay(0.2, function()
			if player.Parent ~= nil then
				giveCombatTool(player)
			end
		end)
	end
end

return CombatService
