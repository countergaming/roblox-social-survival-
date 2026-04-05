local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local HonorDisplayService = {}

local objectiveService = nil
local profileService = nil
local roleService = nil
local displayFolder = nil
local boardPart = nil
local isStarted = false

local function getDisplayFolder()
	if displayFolder ~= nil and displayFolder.Parent ~= nil then
		return displayFolder
	end

	local runtimeFolder = objectiveService.getRuntimeFolder()
	local existingFolder = runtimeFolder:FindFirstChild("HonorDisplay")

	if existingFolder ~= nil then
		displayFolder = existingFolder
		return displayFolder
	end

	displayFolder = Instance.new("Folder")
	displayFolder.Name = "HonorDisplay"
	displayFolder.Parent = runtimeFolder

	return displayFolder
end

local function ensureBoard()
	if boardPart ~= nil and boardPart.Parent ~= nil then
		return boardPart
	end

	local folder = getDisplayFolder()
	local existingBoard = folder:FindFirstChild("CampHonorBoard")

	if existingBoard ~= nil then
		boardPart = existingBoard
		return boardPart
	end

	boardPart = Instance.new("Part")
	boardPart.Name = "CampHonorBoard"
	boardPart.Anchored = true
	boardPart.CanCollide = false
	boardPart.Size = Vector3.new(18, 10, 1)
	boardPart.Position = Vector3.new(0, 5.5, 18)
	boardPart.CFrame = CFrame.lookAt(boardPart.Position, objectiveService.getCampCenter())
	boardPart.Color = Color3.fromRGB(62, 49, 42)
	boardPart.Material = Enum.Material.WoodPlanks
	boardPart.TopSurface = Enum.SurfaceType.Smooth
	boardPart.BottomSurface = Enum.SurfaceType.Smooth
	boardPart.Parent = folder

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Display"
	surface.Face = Enum.NormalId.Front
	surface.AlwaysOnTop = true
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 36
	surface.Parent = boardPart

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(18, 14)
	title.Size = UDim2.new(1, -36, 0, 38)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextWrapped = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Camp Honors"
	title.TextColor3 = Color3.fromRGB(255, 220, 148)
	title.Parent = surface

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(18, 60)
	body.Size = UDim2.new(1, -36, 1, -76)
	body.Font = Enum.Font.GothamMedium
	body.TextSize = 20
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextColor3 = Color3.fromRGB(242, 232, 216)
	body.Parent = surface

	return boardPart
end

local function getHonorSummary(player: Player)
	local publicProfile = profileService.getPublicProfile(player)
	local roleName = roleService.getSelectedRoleName(player)
	local roleTitle = if roleName ~= "" then roleService.getRoleTitle(roleName) else "Unassigned"
	local honorTitle = player:GetAttribute("HonorDisplayTitle")
	local bannerTitle = player:GetAttribute("HonorBannerTitle")

	if type(honorTitle) ~= "string" or honorTitle == "" then
		if publicProfile ~= nil and publicProfile.honors ~= nil then
			honorTitle = publicProfile.honors.displayTitle
		else
			honorTitle = "Lanternkeeper"
		end
	end

	if type(bannerTitle) ~= "string" or bannerTitle == "" then
		if publicProfile ~= nil and publicProfile.honors ~= nil then
			bannerTitle = publicProfile.honors.bannerTitle
		else
			bannerTitle = ""
		end
	end

	return {
		roleName = roleName,
		roleTitle = roleTitle,
		honorTitle = honorTitle,
		bannerTitle = bannerTitle,
		level = if publicProfile ~= nil then publicProfile.level else 1,
		unlockedHonorCount = if publicProfile ~= nil and publicProfile.honors ~= nil
			then publicProfile.honors.totalUnlockedCount
			else 0,
	}
end

local function ensureNameplate(player: Player)
	local character = player.Character

	if character == nil then
		return nil
	end

	local head = character:FindFirstChild("Head")

	if head == nil then
		return nil
	end

	local existingGui = head:FindFirstChild("HonorNameplate")

	if existingGui ~= nil then
		return existingGui
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HonorNameplate"
	billboard.Size = UDim2.fromOffset(240, 72)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 90
	billboard.Parent = head

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
	container.BackgroundTransparency = 0.18
	container.Size = UDim2.fromScale(1, 1)
	container.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = Color3.fromRGB(255, 210, 112)
	stroke.Transparency = 0.35
	stroke.Parent = container

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(10, 6)
	nameLabel.Size = UDim2.new(1, -20, 0, 22)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextColor3 = Color3.fromRGB(255, 247, 228)
	nameLabel.TextScaled = false
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = container

	local honorLabel = Instance.new("TextLabel")
	honorLabel.Name = "HonorLabel"
	honorLabel.BackgroundTransparency = 1
	honorLabel.Position = UDim2.fromOffset(10, 28)
	honorLabel.Size = UDim2.new(1, -20, 0, 18)
	honorLabel.Font = Enum.Font.GothamMedium
	honorLabel.TextSize = 13
	honorLabel.TextColor3 = Color3.fromRGB(255, 214, 140)
	honorLabel.TextXAlignment = Enum.TextXAlignment.Left
	honorLabel.Parent = container

	local roleLabel = Instance.new("TextLabel")
	roleLabel.Name = "RoleLabel"
	roleLabel.BackgroundTransparency = 1
	roleLabel.Position = UDim2.fromOffset(10, 46)
	roleLabel.Size = UDim2.new(1, -20, 0, 18)
	roleLabel.Font = Enum.Font.Gotham
	roleLabel.TextSize = 12
	roleLabel.TextColor3 = Color3.fromRGB(198, 214, 236)
	roleLabel.TextXAlignment = Enum.TextXAlignment.Left
	roleLabel.Parent = container

	return billboard
end

local function updateNameplate(player: Player)
	local nameplate = ensureNameplate(player)

	if nameplate == nil then
		return
	end

	local honorSummary = getHonorSummary(player)
	local roleColor = Color3.fromRGB(198, 214, 236)

	if honorSummary.roleName ~= "" and GameConfig.RoleTuning.Roles[honorSummary.roleName] ~= nil then
		roleColor = GameConfig.RoleTuning.Roles[honorSummary.roleName].color
	end

	local container = nameplate:FindFirstChild("Container")
	if container == nil then
		return
	end

	local nameLabel = container:FindFirstChild("NameLabel")
	local honorLabel = container:FindFirstChild("HonorLabel")
	local roleLabel = container:FindFirstChild("RoleLabel")
	local stroke = container:FindFirstChild("Stroke")

	if nameLabel ~= nil then
		nameLabel.Text = string.format("%s  Lv %d", player.DisplayName, honorSummary.level)
	end

	if honorLabel ~= nil then
		if honorSummary.bannerTitle ~= "" then
			honorLabel.Text = string.format("%s | Banner: %s", honorSummary.honorTitle, honorSummary.bannerTitle)
		else
			honorLabel.Text = honorSummary.honorTitle
		end
	end

	if roleLabel ~= nil then
		roleLabel.Text = string.format("%s | Honors %d", honorSummary.roleTitle, honorSummary.unlockedHonorCount)
		roleLabel.TextColor3 = roleColor
	end

	if stroke ~= nil and stroke:IsA("UIStroke") then
		stroke.Color = roleColor
	end
end

local function buildBoardLines()
	local playerEntries = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local honorSummary = getHonorSummary(player)
		table.insert(playerEntries, {
			player = player,
			honorSummary = honorSummary,
		})
	end

	table.sort(playerEntries, function(left, right)
		if left.honorSummary.unlockedHonorCount == right.honorSummary.unlockedHonorCount then
			if left.honorSummary.level == right.honorSummary.level then
				return left.player.DisplayName < right.player.DisplayName
			end

			return left.honorSummary.level > right.honorSummary.level
		end

		return left.honorSummary.unlockedHonorCount > right.honorSummary.unlockedHonorCount
	end)

	if #playerEntries == 0 then
		return "No lanternkeepers at camp."
	end

	local lines = {}

	for index, entry in ipairs(playerEntries) do
		if index > 5 then
			break
		end

		table.insert(
			lines,
			string.format(
				"%s | %s | %s",
				entry.player.DisplayName,
				entry.honorSummary.honorTitle,
				entry.honorSummary.roleTitle
			)
		)
	end

	return table.concat(lines, "\n")
end

local function updateBoard()
	local board = ensureBoard()
	local surface = board:FindFirstChild("Display")

	if surface == nil then
		return
	end

	local title = surface:FindFirstChild("Title")
	local body = surface:FindFirstChild("Body")

	if title ~= nil then
		title.Text = "Camp Honors"
	end

	if body ~= nil then
		body.Text = buildBoardLines()
	end
end

local function refreshAllDisplays()
	for _, player in ipairs(Players:GetPlayers()) do
		updateNameplate(player)
	end

	updateBoard()
end

local function attachPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		task.delay(0.25, function()
			if player.Parent ~= nil then
				updateNameplate(player)
				updateBoard()
			end
		end)
	end)

	task.delay(0.25, function()
		if player.Parent ~= nil then
			updateNameplate(player)
			updateBoard()
		end
	end)
end

local function startRefreshLoop()
	task.spawn(function()
		while true do
			task.wait(1)
			refreshAllDisplays()
		end
	end)
end

function HonorDisplayService.start(dependencies)
	if isStarted then
		return
	end

	isStarted = true
	objectiveService = dependencies.objectiveService
	profileService = dependencies.profileService
	roleService = dependencies.roleService

	ensureBoard()

	Players.PlayerAdded:Connect(function(player)
		attachPlayer(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		attachPlayer(player)
	end

	refreshAllDisplays()
	startRefreshLoop()
end

return HonorDisplayService
