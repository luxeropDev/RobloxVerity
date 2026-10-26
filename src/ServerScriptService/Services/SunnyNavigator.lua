-- SunnyNavigator: pathfinding for SUNNY with compute timeouts, stuck detection and fallbacks.
-- Positions are ground-level (Y = 0 plane); SunnyService adds hover height.
-- Fallback order: computed path -> direct line -> "drift" (float over obstacles for a moment).

local PathfindingService = game:GetService("PathfindingService")

local SunnyNavigator = {}
SunnyNavigator.__index = SunnyNavigator

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function SunnyNavigator.new(cfg)
	return setmetatable({
		cfg = cfg,
		waypoints = nil,
		index = 0,
		goal = nil,
		lastCompute = 0,
		computing = false,
		computeId = 0,
		computeStarted = 0,
		failedUntil = 0,
		driftUntil = 0,
		lastProgressPos = nil,
		lastProgressTime = os.clock(),
		stats = { computes = 0, failures = 0, timeouts = 0, drifts = 0 },
	}, SunnyNavigator)
end

function SunnyNavigator:reset()
	self.computeId += 1 -- discard any in-flight result
	self.computing = false
	self.waypoints = nil
	self.index = 0
	self.goal = nil
	self.computedGoal = nil
	self.failedUntil = 0
	self.driftUntil = 0
	self.lastProgressPos = nil
	self.lastProgressTime = os.clock()
end

function SunnyNavigator:_compute(from: Vector3, goal: Vector3)
	local cfg = self.cfg
	self.computing = true
	self.computeId += 1
	local id = self.computeId
	self.lastCompute = os.clock()
	self.computeStarted = self.lastCompute
	self.stats.computes += 1
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = cfg.AgentRadius,
			AgentHeight = cfg.AgentHeight,
			AgentCanJump = false,
			WaypointSpacing = cfg.WaypointSpacing,
		})
		local ok = pcall(function()
			path:ComputeAsync(from + Vector3.new(0, 2, 0), goal + Vector3.new(0, 2, 0))
		end)
		if id ~= self.computeId then
			return -- superseded or timed out
		end
		self.computing = false
		local waypoints = nil
		if ok and path.Status == Enum.PathStatus.Success then
			waypoints = path:GetWaypoints()
		end
		if waypoints and #waypoints > 0 then
			self.waypoints = waypoints
			self.index = math.min(2, #waypoints)
		else
			self.waypoints = nil
			self.failedUntil = os.clock() + 1
			self.stats.failures += 1
		end
	end)
end

function SunnyNavigator:setGoal(from: Vector3, goal: Vector3)
	local cfg = self.cfg
	local now = os.clock()
	goal = flat(goal)
	-- Always steer toward the newest goal; only recompute the path when it moved enough or got old.
	local moved = self.computedGoal == nil or (goal - self.computedGoal).Magnitude > cfg.RecomputeDistance
	self.goal = goal
	if self.computing or now < self.failedUntil then
		return
	end
	if moved or now - self.lastCompute > cfg.RecomputeInterval then
		self.computedGoal = goal
		self:_compute(flat(from), goal)
	end
end

-- Returns the next point to move toward and the mode ("path" | "direct" | "drift").
function SunnyNavigator:step(position: Vector3): (Vector3?, string)
	local cfg = self.cfg
	local now = os.clock()
	local pos = flat(position)
	local goal = self.goal
	if not goal then
		return nil, "direct"
	end

	if self.computing and now - self.computeStarted > cfg.Timeout then
		self.computeId += 1
		self.computing = false
		self.waypoints = nil
		self.failedUntil = now + 1
		self.stats.timeouts += 1
	end

	-- Stuck detection
	if self.lastProgressPos == nil or (pos - self.lastProgressPos).Magnitude >= cfg.StuckProgress then
		self.lastProgressPos = pos
		self.lastProgressTime = now
	elseif now - self.lastProgressTime > cfg.StuckTime and (goal - pos).Magnitude > 6 then
		self.driftUntil = now + cfg.DriftDuration
		self.waypoints = nil
		self.lastProgressTime = now
		self.stats.drifts += 1
	end

	if now < self.driftUntil then
		return goal, "drift"
	end

	local waypoints = self.waypoints
	if waypoints and self.index <= #waypoints then
		local wp = flat(waypoints[self.index].Position)
		while (wp - pos).Magnitude < 3 and self.index < #waypoints do
			self.index += 1
			wp = flat(waypoints[self.index].Position)
		end
		if self.index >= #waypoints and (wp - pos).Magnitude < 3 then
			self.waypoints = nil
			return goal, "direct"
		end
		return wp, "path"
	end
	return goal, "direct"
end

return SunnyNavigator
