local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Awards = require(ServerScriptService.Lib.Awards)

return function(t)
	t.test("each player gets exactly one award", function()
		local rows = {
			{ key = "a", stats = { Gathered = 10, Rescues = 0 } },
			{ key = "b", stats = { Gathered = 3, Rescues = 2 } },
			{ key = "c", stats = {} },
		}
		local result = Awards.assign(rows)
		t.expect(result.b).toBe("Cage Cracker")
		t.expect(result.a).toBe("Professional Log Hugger")
		t.expect(result.c).toBe(Awards.Default)
	end)

	t.test("glow titles by threshold", function()
		local titles = GameConfig.Rewards.Titles
		t.expect(Awards.titleForGlow(0, titles)).toBe(titles[1].Title)
		t.expect(Awards.titleForGlow(titles[2].Glow, titles)).toBe(titles[2].Title)
		t.expect(Awards.titleForGlow(100000, titles)).toBe(titles[#titles].Title)
	end)
end
