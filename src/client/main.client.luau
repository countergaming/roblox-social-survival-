local controllersFolder = script.Parent:WaitForChild("Controllers")
local HudController = require(controllersFolder:WaitForChild("HudController"))

HudController.start()
