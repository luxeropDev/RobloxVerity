-- Integration: requires a running server (Studio Play/Run). Verifies world generation and tags.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Registry = require(ServerScriptService.Services.Registry)

return function(t)
	t.test("server booted", function()
		t.expect(Registry.waitUntilReady(20)).toBe(true)
		t.expect(Registry.BootError).toBe(nil)
	end)

	t.test("world has required POIs and stays in part budget", function()
		local world = Registry.World
		t.expect(world.FirePart ~= nil).toBe(true)
		t.expect(world.SupplyCrate ~= nil).toBe(true)
		t.expect(world.Radio ~= nil).toBe(true)
		t.expect(#world.BridgePlanks).toBe(GameConfig.Objectives.BridgeStages)
		t.expect(world.CageLock ~= nil).toBe(true)
		t.expect(world.PartCount).toBeAtMost(GameConfig.World.MaxParts)
	end)

	t.test("resource nodes, hiding spots and clue spots are tagged", function()
		t.expect(#CollectionService:GetTagged("ResourceNode")).toBeGreaterThan(20)
		t.expect(#CollectionService:GetTagged("HidingSpot")).toBeGreaterThan(3)
		t.expect(#CollectionService:GetTagged("ClueSpot")).toBe(4)
	end)

	t.test("remotes exist", function()
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		t.expect(folder ~= nil).toBe(true)
		for _, name in ipairs({ "Notify", "RequestUpgrade", "RequestRestart", "RequestUnhide", "Recap" }) do
			t.expect(folder:FindFirstChild(name) ~= nil).toBe(true)
		end
	end)

	t.test("spawn is inside the safe radius", function()
		local world = Registry.World
		local camp = Registry.Services.CampService
		t.expect(camp.isInSafeZone(world.SpawnLocation.Position, 0)).toBe(true)
	end)
end
