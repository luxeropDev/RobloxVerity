-- SunnyBrain: pure state-transition function for SUNNY.
-- SunnyService gathers perception into a context table and applies the result.
-- Keeping this pure makes the behavior deterministic and unit-testable.

local SunnyBrain = {}

SunnyBrain.States = table.freeze({
	Dormant = "Dormant",
	Observing = "Observing",
	Investigating = "Investigating",
	Stalking = "Stalking",
	Chasing = "Chasing",
	Searching = "Searching",
	Retreating = "Retreating",
})

local S = SunnyBrain.States

--[[
ctx fields:
	phase: string                 -- current game phase
	stateTime: number             -- seconds in current state
	hasTarget: boolean            -- a targetable player has suspicion >= threshold
	targetVisible: boolean        -- current target is in line of sight
	targetInLight: boolean        -- current target is inside the repel radius
	timeSinceSeen: number         -- seconds since the target was last visible
	cooldownActive: boolean       -- post-capture cooldown running
	targetCaptured: boolean       -- the target was just captured
	targetHidSpotted: boolean     -- target hid while SUNNY was watching
	reachedDestination: boolean   -- arrived at investigate/search goal
	config: GameConfig.Sunny
]]
function SunnyBrain.decide(state: string, ctx): (string, string)
	local cfg = ctx.config
	local phase = ctx.phase

	if phase ~= "Night" then
		if phase == "Day" or phase == "Sunset" then
			if state ~= S.Observing then
				return S.Observing, "daytime"
			end
			return state, "daytime"
		end
		if state ~= S.Dormant then
			return S.Dormant, "inactive phase"
		end
		return state, "inactive phase"
	end

	-- Night from here on.
	if state == S.Dormant then
		return S.Observing, "night began"
	end

	if ctx.targetCaptured then
		return S.Retreating, "captured target"
	end

	if state == S.Observing then
		if ctx.hasTarget and not ctx.cooldownActive and ctx.stateTime >= cfg.ObserveDuration * 0.5 then
			return S.Stalking, "spotted target while observing"
		end
		if ctx.stateTime >= cfg.ObserveDuration then
			return S.Investigating, "observe finished"
		end
		return state, "observing"
	end

	if state == S.Investigating then
		if ctx.hasTarget and not ctx.cooldownActive then
			return S.Stalking, "spotted target"
		end
		return state, "investigating"
	end

	if state == S.Stalking then
		if ctx.targetInLight then
			return S.Retreating, "target reached light"
		end
		if ctx.targetHidSpotted or ctx.timeSinceSeen >= cfg.LoseSightTime then
			return S.Searching, "lost target while stalking"
		end
		if not ctx.hasTarget and ctx.timeSinceSeen > 0 then
			return S.Searching, "target no longer valid"
		end
		if ctx.stateTime >= cfg.StalkDuration then
			return S.Chasing, "stalk complete"
		end
		return state, "stalking"
	end

	if state == S.Chasing then
		if ctx.targetInLight then
			return S.Retreating, "target reached light"
		end
		if ctx.targetHidSpotted or ctx.timeSinceSeen >= cfg.LoseSightTime then
			return S.Searching, "lost target while chasing"
		end
		if not ctx.hasTarget and ctx.timeSinceSeen > 0 then
			return S.Searching, "target no longer valid"
		end
		if ctx.stateTime >= cfg.ChaseMaxDuration then
			return S.Searching, "chase timed out"
		end
		return state, "chasing"
	end

	if state == S.Searching then
		if ctx.hasTarget and ctx.targetVisible and not ctx.cooldownActive and ctx.stateTime >= 1 then
			return S.Stalking, "re-acquired target"
		end
		if ctx.stateTime >= cfg.SearchDuration then
			return S.Retreating, "search finished"
		end
		return state, "searching"
	end

	if state == S.Retreating then
		if ctx.stateTime >= cfg.RetreatDuration then
			return S.Investigating, "retreat finished"
		end
		return state, "retreating"
	end

	return S.Investigating, "unknown state recovered"
end

-- Suspicion gain per second for one player.
-- distance: studs to SUNNY, radius: detect radius, rate: escalation rate, moving: player is moving.
function SunnyBrain.suspicionGain(distance: number, radius: number, rate: number, moving: boolean, movingMult: number): number
	if distance >= radius or radius <= 0 then
		return 0
	end
	local closeness = 1 - (distance / radius) -- 0 at edge, 1 on top of SUNNY
	local gain = rate * (0.35 + closeness)
	if moving then
		gain *= movingMult
	end
	return gain
end

-- Picks the most suspicious eligible player above the threshold. `entries` = { {key=any, suspicion=number} }
function SunnyBrain.pickTarget(entries, threshold: number, currentKey)
	local best, bestValue = nil, -math.huge
	for _, entry in ipairs(entries) do
		local value = entry.suspicion
		-- Small stickiness bonus so SUNNY does not flip between equal targets.
		if currentKey ~= nil and entry.key == currentKey then
			value += 0.25
		end
		if entry.suspicion >= threshold and value > bestValue then
			best, bestValue = entry.key, value
		end
	end
	return best
end

return SunnyBrain
