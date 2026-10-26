-- Client entry point. Loads controllers, then starts them. Controllers only display state and send requests;
-- the server validates everything.

local Controllers = script.Parent:WaitForChild("Controllers")

local controllers = {
	HUD = require(Controllers:WaitForChild("HUDController")),
	Interaction = require(Controllers:WaitForChild("InteractionController")),
	Atmosphere = require(Controllers:WaitForChild("AtmosphereController")),
	Audio = require(Controllers:WaitForChild("AudioController")),
}

local ORDER = { "Audio", "Atmosphere", "HUD", "Interaction" }

for _, name in ipairs(ORDER) do
	local ok, err = pcall(controllers[name].init, controllers)
	if not ok then
		warn("[Client] " .. name .. ".init failed: " .. tostring(err))
	end
end
for _, name in ipairs(ORDER) do
	local ok, err = pcall(controllers[name].start)
	if not ok then
		warn("[Client] " .. name .. ".start failed: " .. tostring(err))
	end
end
