local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EventScheduler = require(ServerScriptService.Lib.EventScheduler)

local function build(night, count, seed)
	return EventScheduler.build({
		night = night,
		duration = 120,
		count = count,
		definitions = GameConfig.Events.Definitions,
		rng = Random.new(seed),
		eventsConfig = GameConfig.Events,
	})
end

return function(t)
	t.test("first night includes the guaranteed event", function()
		local schedule = build(1, 2, 7)
		local found = false
		for _, e in ipairs(schedule) do
			if e.id == GameConfig.Events.FirstNightGuaranteed then
				found = true
			end
		end
		t.expect(found).toBe(true)
	end)

	t.test("no duplicates and respects MinNight", function()
		for seed = 1, 20 do
			local schedule = build(1, 6, seed)
			local seen = {}
			for _, e in ipairs(schedule) do
				t.expect(seen[e.id]).toBe(nil)
				seen[e.id] = true
				t.expect(GameConfig.Events.Definitions[e.id].MinNight <= 1).toBe(true)
			end
		end
	end)

	t.test("times sorted, spaced and inside the night", function()
		for seed = 1, 20 do
			local schedule = build(3, 4, seed)
			for i, e in ipairs(schedule) do
				t.expect(e.at).toBeAtMost(118)
				t.expect(e.at > 0).toBe(true)
				if i > 1 then
					t.expect(e.at - schedule[i - 1].at >= GameConfig.Events.MinGap - 1e-6).toBe(true)
				end
			end
		end
	end)

	t.test("deterministic for a seed", function()
		t.expect(build(2, 3, 42)).toEqual(build(2, 3, 42))
	end)

	t.test("available filter excludes events", function()
		local schedule = EventScheduler.build({
			night = 2,
			duration = 120,
			count = 5,
			definitions = GameConfig.Events.Definitions,
			rng = Random.new(1),
			eventsConfig = GameConfig.Events,
			available = { FalseLantern = true },
		})
		t.expect(#schedule).toBe(1)
		t.expect(schedule[1].id).toBe("FalseLantern")
	end)
end
