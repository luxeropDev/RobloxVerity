-- Main: server entry point. Validates config, builds the world, initializes and starts services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local ConfigValidator = require(ServerScriptService.Lib.ConfigValidator)
local WorldBootstrap = require(ServerScriptService.World.WorldBootstrap)

local ServicesFolder = script.Parent.Services
local Registry = require(ServicesFolder.Registry)

local services = {
	PlayerStateService = require(ServicesFolder.PlayerStateService),
	CampService = require(ServicesFolder.CampService),
	ResourceService = require(ServicesFolder.ResourceService),
	ObjectiveService = require(ServicesFolder.ObjectiveService),
	SunnyService = require(ServicesFolder.SunnyService),
	NightEventService = require(ServicesFolder.NightEventService),
	PhaseService = require(ServicesFolder.PhaseService),
}

-- Start order matters: PhaseService last, because it begins the round loop.
local ORDER = {
	"PlayerStateService",
	"CampService",
	"ResourceService",
	"ObjectiveService",
	"SunnyService",
	"NightEventService",
	"PhaseService",
}

local function boot()
	local problems = ConfigValidator.validate(GameConfig)
	for _, problem in ipairs(problems) do
		warn("[Config] " .. problem)
	end

	Remotes.init()

	local seed = GameConfig.Seed
	if seed == nil then
		seed = Random.new():NextInteger(1, 1000000000)
	end
	local world = WorldBootstrap.build(seed)
	print(string.format("[Main] World built: seed=%d parts=%d nodes=%d", seed, world.PartCount, #world.ResourceNodes))

	for _, name in ipairs(ORDER) do
		services[name].init(services, world)
	end
	for _, name in ipairs(ORDER) do
		services[name].start()
	end

	Registry.Services = services
	Registry.World = world
	Registry.Ready = true
	print("[Main] " .. GameConfig.GameTitle .. " v" .. GameConfig.Version .. " ready")
end

local ok, err = pcall(boot)
if not ok then
	Registry.BootError = tostring(err)
	warn("[Main] Boot failed: " .. tostring(err))
end
