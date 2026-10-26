-- Integration: exercises server validation paths directly. Needs at least one player in Play mode.
-- Changes live game state (stockpile, inventory, events). Local Studio sessions only.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Registry = require(ServerScriptService.Services.Registry)

return function(t)
	Registry.waitUntilReady(20)
	local S = Registry.Services
	local player = Players:GetPlayers()[1]

	t.test("invalid upgrade requests are ignored", function()
		if not player then
			return
		end
		local before = S.CampService.getLevels()
		S.CampService.requestUpgrade(player, 12345)
		S.CampService.requestUpgrade(player, "NotAnUpgrade")
		S.CampService.requestUpgrade(player, { "FireRing" })
		S.CampService.requestUpgrade(player, nil)
		t.expect(S.CampService.getLevels()).toEqual(before)
	end)

	t.test("unaffordable upgrade changes nothing", function()
		if not player then
			return
		end
		local stock = S.CampService.getStock()
		if stock.Wood >= 8 then
			return -- the team already has resources; skip to avoid spending them
		end
		local before = S.CampService.getLevels()
		task.wait(2.1) -- let the rate limiter window pass
		S.CampService.requestUpgrade(player, "FireRing")
		t.expect(S.CampService.getLevels()).toEqual(before)
	end)

	t.test("out-of-range gather is rejected", function()
		if not player then
			return
		end
		local root = S.PlayerStateService.getRoot(player)
		if not root then
			return
		end
		local far
		for _, model in ipairs(Registry.World.ResourceNodes) do
			if model.PrimaryPart and (model.PrimaryPart.Position - root.Position).Magnitude > 60 then
				far = model
				break
			end
		end
		t.expect(far ~= nil).toBe(true)
		local inv = table.clone(S.PlayerStateService.getInventory(player))
		S.ResourceService.tryGather(player, far)
		t.expect(S.PlayerStateService.getInventory(player)).toEqual(inv)
	end)

	t.test("every night event runs and cleans up", function()
		local folder = workspace:FindFirstChild("NightEventObjects")
		t.expect(folder ~= nil).toBe(true)
		for _, id in ipairs(S.NightEventService.getEventIds()) do
			t.expect(S.NightEventService.runEvent(id)).toBe(true)
		end
		t.expect(S.NightEventService.getActiveCount()).toBeGreaterThan(0)
		S.NightEventService.stopAll()
		t.expect(S.NightEventService.getActiveCount()).toBe(0)
		t.expect(#folder:GetChildren()).toBe(0)
	end)

	t.test("eight night events are registered", function()
		t.expect(#S.NightEventService.getEventIds()).toBe(8)
	end)

	t.test("courage never exceeds max and capture/release is idempotent", function()
		if not player then
			return
		end
		local PS = S.PlayerStateService
		local _, max = PS.getCourage()
		PS.changeCourage(100)
		local current = PS.getCourage()
		t.expect(current).toBe(max)
		PS.release(player, "test") -- not captured: no-op
		t.expect(PS.get(player).Captured).toBe(false)
	end)
end
