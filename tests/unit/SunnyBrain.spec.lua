local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SunnyBrain = require(ServerScriptService.Lib.SunnyBrain)

local S = SunnyBrain.States

local function ctx(overrides)
	local c = {
		phase = "Night",
		stateTime = 0,
		hasTarget = false,
		targetVisible = false,
		targetInLight = false,
		timeSinceSeen = 0,
		cooldownActive = false,
		targetCaptured = false,
		targetHidSpotted = false,
		config = GameConfig.Sunny,
	}
	for k, v in pairs(overrides or {}) do
		c[k] = v
	end
	return c
end

return function(t)
	local cfg = GameConfig.Sunny

	t.test("daytime is always Observing", function()
		t.expect((SunnyBrain.decide(S.Chasing, ctx({ phase = "Day" })))).toBe(S.Observing)
		t.expect((SunnyBrain.decide(S.Dormant, ctx({ phase = "Sunset" })))).toBe(S.Observing)
	end)

	t.test("inactive phases are Dormant", function()
		t.expect((SunnyBrain.decide(S.Chasing, ctx({ phase = "Results" })))).toBe(S.Dormant)
		t.expect((SunnyBrain.decide(S.Observing, ctx({ phase = "Dawn" })))).toBe(S.Dormant)
	end)

	t.test("investigating spots target -> stalking", function()
		t.expect((SunnyBrain.decide(S.Investigating, ctx({ hasTarget = true })))).toBe(S.Stalking)
	end)

	t.test("cooldown blocks stalking", function()
		t.expect((SunnyBrain.decide(S.Investigating, ctx({ hasTarget = true, cooldownActive = true })))).toBe(S.Investigating)
	end)

	t.test("stalk is telegraphed before chase", function()
		local early = SunnyBrain.decide(S.Stalking, ctx({ hasTarget = true, targetVisible = true, stateTime = cfg.StalkDuration * 0.5 }))
		t.expect(early).toBe(S.Stalking)
		local done = SunnyBrain.decide(S.Stalking, ctx({ hasTarget = true, targetVisible = true, stateTime = cfg.StalkDuration }))
		t.expect(done).toBe(S.Chasing)
	end)

	t.test("light ends a chase", function()
		t.expect((SunnyBrain.decide(S.Chasing, ctx({ hasTarget = true, targetInLight = true })))).toBe(S.Retreating)
	end)

	t.test("losing sight -> searching", function()
		t.expect((SunnyBrain.decide(S.Chasing, ctx({ hasTarget = true, timeSinceSeen = cfg.LoseSightTime })))).toBe(S.Searching)
	end)

	t.test("hiding in view -> searching, never capture", function()
		t.expect((SunnyBrain.decide(S.Chasing, ctx({ hasTarget = false, targetHidSpotted = true, timeSinceSeen = 0.1 })))).toBe(S.Searching)
	end)

	t.test("chase times out", function()
		t.expect((SunnyBrain.decide(S.Chasing, ctx({ hasTarget = true, stateTime = cfg.ChaseMaxDuration })))).toBe(S.Searching)
	end)

	t.test("capture -> retreating", function()
		t.expect((SunnyBrain.decide(S.Chasing, ctx({ targetCaptured = true })))).toBe(S.Retreating)
	end)

	t.test("search and retreat finish", function()
		t.expect((SunnyBrain.decide(S.Searching, ctx({ stateTime = cfg.SearchDuration })))).toBe(S.Retreating)
		t.expect((SunnyBrain.decide(S.Retreating, ctx({ stateTime = cfg.RetreatDuration })))).toBe(S.Investigating)
	end)

	t.test("all seven states are reachable", function()
		local seen = {}
		seen[(SunnyBrain.decide(S.Chasing, ctx({ phase = "Results" })))] = true
		seen[(SunnyBrain.decide(S.Dormant, ctx({ phase = "Day" })))] = true
		seen[(SunnyBrain.decide(S.Observing, ctx({ stateTime = cfg.ObserveDuration })))] = true
		seen[(SunnyBrain.decide(S.Investigating, ctx({ hasTarget = true })))] = true
		seen[(SunnyBrain.decide(S.Stalking, ctx({ hasTarget = true, stateTime = cfg.StalkDuration })))] = true
		seen[(SunnyBrain.decide(S.Chasing, ctx({ hasTarget = true, timeSinceSeen = 99 })))] = true
		seen[(SunnyBrain.decide(S.Chasing, ctx({ targetCaptured = true })))] = true
		for _, name in pairs(S) do
			t.expect(seen[name]).toBe(true)
		end
	end)

	t.test("suspicion gain is zero outside radius and grows when closer", function()
		t.expect(SunnyBrain.suspicionGain(60, 50, 1, false, 1.3)).toBe(0)
		local far = SunnyBrain.suspicionGain(40, 50, 1, false, 1.3)
		local near = SunnyBrain.suspicionGain(10, 50, 1, false, 1.3)
		t.expect(near).toBeGreaterThan(far)
		t.expect(SunnyBrain.suspicionGain(10, 50, 1, true, 1.3)).toBeGreaterThan(near)
	end)

	t.test("pickTarget respects threshold", function()
		local entries = { { key = "a", suspicion = 0.5 }, { key = "b", suspicion = 1.2 } }
		t.expect(SunnyBrain.pickTarget(entries, 1, nil)).toBe("b")
		t.expect(SunnyBrain.pickTarget({ { key = "a", suspicion = 0.5 } }, 1, nil)).toBe(nil)
	end)

	t.test("chase speed always below player walk speed", function()
		for _, e in ipairs(GameConfig.Escalation) do
			t.expect(e.SunnySpeed < GameConfig.Player.WalkSpeed).toBe(true)
		end
	end)
end
