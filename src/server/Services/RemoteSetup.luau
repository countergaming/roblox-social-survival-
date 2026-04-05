local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))

local RemoteSetup = {}

local function ensureInstance(container: Instance, className: string, name: string): Instance
	local existing = container:FindFirstChild(name)

	if existing ~= nil and existing.ClassName == className then
		return existing
	end

	if existing ~= nil then
		existing:Destroy()
	end

	local created = Instance.new(className)
	created.Name = name
	created.Parent = container

	return created
end

function RemoteSetup.ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild(RemoteNames.Folder)

	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = RemoteNames.Folder
		folder.Parent = ReplicatedStorage
	end

	ensureInstance(folder, "RemoteEvent", RemoteNames.PhaseChanged)
	ensureInstance(folder, "RemoteEvent", RemoteNames.RewardPreview)
	ensureInstance(folder, "RemoteEvent", RemoteNames.ProfileStateChanged)
	ensureInstance(folder, "RemoteEvent", RemoteNames.ObjectiveStateChanged)
	ensureInstance(folder, "RemoteEvent", RemoteNames.EchoStateChanged)
	ensureInstance(folder, "RemoteEvent", RemoteNames.DutyStateChanged)
	ensureInstance(folder, "RemoteEvent", RemoteNames.RoleStateChanged)
	ensureInstance(folder, "RemoteEvent", RemoteNames.RiteStateChanged)
	ensureInstance(folder, "RemoteEvent", RemoteNames.DefenseStateChanged)
	ensureInstance(folder, "RemoteEvent", RemoteNames.ThreatStateChanged)
	ensureInstance(folder, "RemoteEvent", RemoteNames.RescueStateChanged)
	ensureInstance(folder, "RemoteEvent", RemoteNames.SignalStateChanged)
	ensureInstance(folder, "RemoteEvent", RemoteNames.RiteFocusStateChanged)

	return folder
end

return RemoteSetup
