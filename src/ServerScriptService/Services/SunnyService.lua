-- SunnyService: SUNNY's perception, state machine execution, movement, speech and capture.
-- Decisions come from Lib/SunnyBrain (pure). This service gathers perception and acts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)

local Lib = ServerScriptService.Lib
local SunnyBrain = require(Lib.SunnyBrain)

local SunnyModel = require(ServerScriptService.World.SunnyModel)
local SunnyNavigator = require(script.Parent.SunnyNavigator)

local SunnyService = {}

local CFG = GameConfig.Sunny
local S = SunnyBrain.States

local Services
local World

local h -- model handles
local navigator
local rng = Random.new()

local state = S.Dormant
local stateStartedAt = os.clock()
local target = nil
local lastSeenAt = 0
local lastKnownPos = nil
local suspicion = {} -- [Player] = number
local noise = nil -- { Position, Time }
local goal = nil
local goalSetAt = 0
local cooldownUntil = 0
local scriptedUntil = 0
local lastSpeechAt = 0
local speechClearAt = 0
local nextHintAt = 0
local targetHidSpotted = false
local targetCaptured = false
local alerted = {} -- [Player] = level
local hintIndex = 0
local lastBlink = 0
local greeted = false

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

local function groundPosition(): Vector3
	return flat(h.Root.Position)
end

-------------------------------------------------------------------------------
-- Speech and alerts
-------------------------------------------------------------------------------

function SunnyService.say(text: string, duration: number?, force: boolean?)
	local now = os.clock()
	if not force and now - lastSpeechAt < CFG.SpeechMinGap then
		return
	end
	lastSpeechAt = now
	local d = duration or 3.5
	speechClearAt = now + d
	SunnyModel.setSpeech(h, text)
	Remotes.get("SunnySpeech"):FireAllClients(text, d)
end

local function sayLine(category: string, force: boolean?)
	local lines = GameConfig.Dialogue[category]
	if lines and #lines > 0 then
		SunnyService.say(pick(lines), 3.5, force)
	end
end

local function setAlert(player: Player?, level: string)
	if not player or player.Parent ~= Players then
		return
	end
	if alerted[player] == level then
		return
	end
	alerted[player] = level
	Remotes.get("SunnyAlert"):FireClient(player, level)
end

local function clearAlerts()
	for player, level in pairs(alerted) do
		if level ~= "Clear" and player.Parent == Players then
			Remotes.get("SunnyAlert"):FireClient(player, "Clear")
		end
		alerted[player] = nil
	end
end

-------------------------------------------------------------------------------
-- Goals
-------------------------------------------------------------------------------

local function repelRadius(): number
	return Services.CampService.getRepelRadius()
end

-- Pushes a point outside the camp's repel radius (SUNNY never enters the light).
local function clampOutside(point: Vector3): (Vector3, boolean)
	local radius = repelRadius()
	if radius <= 0 then
		return point, false
	end
	local center = World.CampCenter
	local offset = flat(point - center)
	local minDist = radius + CFG.LightEdgeBuffer
	if offset.Magnitude >= minDist then
		return point, false
	end
	local dir = offset
	if dir.Magnitude < 0.1 then
		dir = flat(groundPosition() - center)
		if dir.Magnitude < 0.1 then
			dir = Vector3.new(1, 0, 0)
		end
	end
	return center + dir.Unit * minDist, true
end

local function randomPatrolPoint(minCampDistance: number?): Vector3
	local points = World.PatrolPoints
	for _ = 1, 8 do
		local p = points[rng:NextInteger(1, #points)]
		if not minCampDistance or flatDistance(p, World.CampCenter) >= minCampDistance then
			return p
		end
	end
	return points[rng:NextInteger(1, #points)]
end

local function edgePoint(extra: number): Vector3
	local angle = rng:NextNumber() * math.pi * 2
	local r = math.max(repelRadius(), GameConfig.Camp.SafeRadiusBase) + extra
	return World.CampCenter + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
end

local function setGoal(p: Vector3)
	goal = flat(p)
	goalSetAt = os.clock()
end

-------------------------------------------------------------------------------
-- Perception
-------------------------------------------------------------------------------

local function headOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

local function canSee(player: Player): boolean
	local head = headOf(player)
	if not head then
		return false
	end
	local eye = h.Root.Position + Vector3.new(0, CFG.EyeHeight, 0)
	local direction = head.Position - eye
	local result = workspace:Raycast(eye, direction, rayParams)
	if not result then
		return true
	end
	return result.Instance:IsDescendantOf(player.Character)
end

local function updatePerception(dt: number)
	local PS = Services.PlayerStateService
	local esc = Services.PhaseService.getEscalation()
	local sunnyPos = groundPosition()
	local entries = {}
	local targetVisible = false
	for _, player in ipairs(PS.getPlayers()) do
		local value = suspicion[player] or 0
		local root = PS.getRoot(player)
		local eligible = root ~= nil and PS.isTargetable(player)
		local visible = false
		if eligible then
			local pos = root.Position
			local dist = flatDistance(pos, sunnyPos)
			local inLight = Services.CampService.isInSafeZone(pos, 0)
			if dist <= esc.DetectRadius * 1.2 then
				visible = canSee(player)
			end
			if visible and not inLight and dist <= esc.DetectRadius then
				local moving = root.AssemblyLinearVelocity.Magnitude > 2
				value += SunnyBrain.suspicionGain(dist, esc.DetectRadius, esc.SuspicionRate, moving, CFG.MovingSuspicionMult) * dt
			else
				local decay = CFG.SuspicionDecay
				if inLight then
					decay *= 2
				end
				value -= decay * dt
			end
			if player == target and visible then
				targetVisible = true
				lastSeenAt = os.clock()
				lastKnownPos = flat(pos)
			end
		else
			value -= CFG.SuspicionDecay * 2 * dt
		end
		value = math.clamp(value, 0, CFG.SuspicionThreshold * 2)
		suspicion[player] = value
		if eligible then
			table.insert(entries, { key = player, suspicion = value })
		end
	end
	return entries, targetVisible
end

-------------------------------------------------------------------------------
-- State entry
-------------------------------------------------------------------------------

local function moodFor(s: string): string
	local phase = Services.PhaseService.getPhase()
	if phase ~= "Night" then
		return "Day"
	end
	if s == S.Chasing then
		return "Chase"
	end
	return "Night"
end

local function enterState(newState: string, reason: string)
	local previous = state
	state = newState
	stateStartedAt = os.clock()
	Remotes.getState():SetAttribute(Types.StateAttr.SunnyState, newState)
	if GameConfig.Debug.LogSunnyStates then
		print(string.format("[SUNNY] %s -> %s (%s)", previous, newState, reason))
	end
	SunnyModel.setMood(h, moodFor(newState))

	if newState == S.Stalking then
		targetHidSpotted = false
		setAlert(target, "Watched")
		sayLine("Stalk")
		Services.PlayerStateService.playSound("Giggle", h.Root.Position)
	elseif newState == S.Chasing then
		setAlert(target, "Chased")
		sayLine("Chase", true)
		if target then
			Services.PlayerStateService.addStat(target, "TimesChased", 1)
		end
	elseif newState == S.Searching then
		setAlert(target, "Clear")
		sayLine("Search")
		setGoal(lastKnownPos or groundPosition())
		targetHidSpotted = false -- consumed by this transition
	elseif newState == S.Retreating then
		clearAlerts()
		if reason == "target reached light" then
			sayLine("LightEdge", true)
		elseif not targetCaptured then
			sayLine("Retreat")
		end
		target = nil
		targetCaptured = false
		targetHidSpotted = false
		setGoal(randomPatrolPoint(90))
	elseif newState == S.Investigating then
		target = nil
		targetHidSpotted = false
		setGoal(randomPatrolPoint(nil))
	elseif newState == S.Observing then
		if Services.PhaseService.getPhase() == "Night" then
			setGoal(edgePoint(14))
		end
	elseif newState == S.Dormant then
		clearAlerts()
		target = nil
		setGoal(World.ShrinePosition)
	end
	navigator:reset()
end

-------------------------------------------------------------------------------
-- Acting
-------------------------------------------------------------------------------

local function nearestPlayerTo(position: Vector3): (Player?, Vector3?)
	local PS = Services.PlayerStateService
	local best, bestPos, bestDist = nil, nil, math.huge
	for _, player in ipairs(PS.getPlayers()) do
		local root = PS.getRoot(player)
		if root then
			local d = flatDistance(root.Position, position)
			if d < bestDist then
				best, bestPos, bestDist = player, root.Position, d
			end
		end
	end
	return best, bestPos
end

local function tryCapture()
	local PS = Services.PlayerStateService
	if not target or not PS.isTargetable(target) then
		return
	end
	local root = PS.getRoot(target)
	if not root then
		return
	end
	if Services.CampService.isInSafeZone(root.Position, 0) then
		return
	end
	if flatDistance(root.Position, groundPosition()) > GameConfig.Capture.Distance then
		return
	end
	if math.abs(root.Position.Y - h.Root.Position.Y) > 10 then
		return
	end
	if PS.capture(target) then
		targetCaptured = true
		cooldownUntil = os.clock() + CFG.PostCaptureCooldown
		table.clear(suspicion)
		sayLine("Capture", true)
	end
end

local function act(dt: number)
	local now = os.clock()
	local phase = Services.PhaseService.getPhase()
	local esc = Services.PhaseService.getEscalation()
	local PS = Services.PlayerStateService
	local speed = CFG.DaySpeed
	local faceTarget = nil

	if state == S.Dormant then
		speed = CFG.RetreatSpeed
		setGoal(World.ShrinePosition)
	elseif state == S.Observing and phase ~= "Night" then
		local player, pos = nearestPlayerTo(groundPosition())
		if player and pos then
			local toSunny = flat(groundPosition() - pos)
			if toSunny.Magnitude < 0.1 then
				toSunny = Vector3.new(1, 0, 0)
			end
			setGoal(flat(pos) + toSunny.Unit * CFG.DayFollowDistance)
			faceTarget = pos
		end
		if now >= nextHintAt then
			nextHintAt = now + CFG.DayHintInterval
			if greeted then
				hintIndex = hintIndex % #GameConfig.Dialogue.DayHints + 1
				SunnyService.say(GameConfig.Dialogue.DayHints[hintIndex], 5)
			end
		end
	elseif state == S.Observing then
		speed = esc.SunnySpeed * CFG.InvestigateSpeedMult
		faceTarget = World.CampCenter
	elseif state == S.Investigating then
		speed = esc.SunnySpeed * CFG.InvestigateSpeedMult
		if noise and now - noise.Time <= CFG.NoiseMemory then
			if not goal or flatDistance(goal, noise.Position) > 2 then
				setGoal(noise.Position)
			end
		end
		local arrived = goal and flatDistance(groundPosition(), goal) <= CFG.ArriveDistance
		if arrived or now - goalSetAt > CFG.InvestigateMaxTime then
			if noise and goal and flatDistance(goal, noise.Position) <= 2 then
				noise = nil
			end
			setGoal(randomPatrolPoint(nil))
		end
	elseif state == S.Stalking and target then
		speed = esc.SunnySpeed * CFG.StalkSpeedMult
		local root = PS.getRoot(target)
		if root then
			local away = flat(groundPosition() - root.Position)
			if away.Magnitude < 0.1 then
				away = Vector3.new(1, 0, 0)
			end
			setGoal(flat(root.Position) + away.Unit * CFG.StalkDistance)
			faceTarget = root.Position
		end
	elseif state == S.Chasing and target then
		speed = esc.SunnySpeed
		local root = PS.getRoot(target)
		if root then
			setGoal(root.Position)
			faceTarget = root.Position
		end
		tryCapture()
	elseif state == S.Searching then
		speed = esc.SunnySpeed * CFG.InvestigateSpeedMult
		if goal and flatDistance(groundPosition(), goal) <= CFG.ArriveDistance then
			local base = lastKnownPos or groundPosition()
			setGoal(base + Vector3.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-12, 12)))
		end
	elseif state == S.Retreating then
		speed = CFG.RetreatSpeed
	end

	if not goal then
		return
	end

	-- Light and barricade enforcement (night only; by day SUNNY is a harmless guide).
	local moveGoal = goal
	if phase == "Night" then
		local clamped, wasClamped = clampOutside(goal)
		moveGoal = clamped
		if wasClamped and (state == S.Chasing or state == S.Stalking or state == S.Searching) then
			local camp = Services.CampService
			local nearRing = flatDistance(groundPosition(), World.CampCenter) <= repelRadius() + CFG.LightEdgeBuffer + 3
			if nearRing and camp.isBarricadeActive() and camp.getSafeRadius() < GameConfig.Camp.BarricadeRadius then
				camp.hitBarricade()
			end
		end
	end

	local here = groundPosition()
	navigator:setGoal(here, moveGoal)
	local nextPoint, mode = navigator:step(here)
	nextPoint = nextPoint or moveGoal
	if phase == "Night" then
		nextPoint = clampOutside(nextPoint)
	end
	local offset = flat(nextPoint - here)
	local stepTarget = here
	if offset.Magnitude > 0.05 then
		stepTarget = here + offset.Unit * math.min(offset.Magnitude, 10)
	end
	local height = CFG.HoverHeight + math.sin(now * CFG.BobSpeed) * CFG.BobAmplitude
	if mode == "drift" then
		height += CFG.Path.DriftHeight
	end
	h.Align.MaxVelocity = speed
	h.Align.Position = Vector3.new(stepTarget.X, height, stepTarget.Z)

	local lookAt = faceTarget
	if not lookAt and offset.Magnitude > 0.5 then
		lookAt = here + offset
	end
	if lookAt then
		local dir = flat(lookAt - here)
		if dir.Magnitude > 0.1 then
			h.Orient.CFrame = CFrame.lookAt(Vector3.zero, dir.Unit)
		end
	end
end

-------------------------------------------------------------------------------
-- Tick
-------------------------------------------------------------------------------

local function tick(dt: number)
	local now = os.clock()
	if speechClearAt > 0 and now >= speechClearAt then
		speechClearAt = 0
		SunnyModel.setSpeech(h, nil)
	end
	if now - lastBlink > 0.6 then
		lastBlink = now
		if h.Tip.Transparency < 0.5 then
			h.Tip.Transparency = 0.7
		else
			h.Tip.Transparency = 0
		end
	end

	if now < scriptedUntil then
		return
	end

	local phase = Services.PhaseService.getPhase()
	local PS = Services.PlayerStateService
	local entries, targetVisible = {}, false
	if phase == "Night" then
		entries, targetVisible = updatePerception(dt)
	end

	-- Validate current target / choose a new one.
	if target and (target.Parent ~= Players or not PS.isTargetable(target)) then
		if target.Parent ~= Players then
			targetHidSpotted = false
		end
		local stillChasing = state == S.Chasing or state == S.Stalking
		if not stillChasing then
			target = nil
		end
	end
	local hasTarget
	if state == S.Stalking or state == S.Chasing then
		hasTarget = target ~= nil and target.Parent == Players and PS.isTargetable(target)
	else
		local candidate = nil
		if now >= cooldownUntil then
			candidate = SunnyBrain.pickTarget(entries, CFG.SuspicionThreshold, target)
		end
		if candidate ~= target then
			target = candidate
			if target then
				lastSeenAt = now
				local root = PS.getRoot(target)
				if root then
					lastKnownPos = flat(root.Position)
				end
			end
		end
		hasTarget = target ~= nil
		if target and state == S.Searching then
			targetVisible = true
		end
	end

	local targetInLight = false
	if target then
		local root = PS.getRoot(target)
		if root then
			targetInLight = Services.CampService.isInSafeZone(root.Position, 0)
		end
	end

	local timeSinceSeen = 0
	if state == S.Stalking or state == S.Chasing then
		timeSinceSeen = now - lastSeenAt
		if not hasTarget then
			timeSinceSeen = math.max(timeSinceSeen, 0.01)
		end
	end

	local ctx = {
		phase = phase,
		stateTime = now - stateStartedAt,
		hasTarget = hasTarget,
		targetVisible = targetVisible,
		targetInLight = targetInLight,
		timeSinceSeen = timeSinceSeen,
		cooldownActive = now < cooldownUntil,
		targetCaptured = targetCaptured,
		targetHidSpotted = targetHidSpotted,
		config = CFG,
	}
	local newState, reason = SunnyBrain.decide(state, ctx)
	if newState ~= state then
		enterState(newState, reason)
	end
	act(dt)
end

-------------------------------------------------------------------------------
-- Public API used by events and other services
-------------------------------------------------------------------------------

function SunnyService.getState(): string
	return state
end

function SunnyService.getTarget(): Player?
	return target
end

function SunnyService.getPosition(): Vector3
	return h.Root.Position
end

function SunnyService.isBusyHunting(): boolean
	return state == S.Stalking or state == S.Chasing
end

function SunnyService.reportNoise(position: Vector3, loudness: number)
	if Services.PhaseService.getPhase() ~= "Night" then
		return
	end
	if state ~= S.Investigating and state ~= S.Observing and state ~= S.Searching then
		return
	end
	local hearing = 90 * (loudness or 1)
	if flatDistance(position, groundPosition()) > hearing then
		return
	end
	noise = { Position = flat(position), Time = os.clock() }
end

-- Keeps a point inside the playable map on the camp side of the ravine.
local function clampToMap(p: Vector3): Vector3
	local half = GameConfig.World.MapHalfSize - 10
	local minZ = GameConfig.World.RavineZ + GameConfig.World.RavineWidth
	return Vector3.new(math.clamp(p.X, -half, half), 0, math.clamp(p.Z, minZ, half))
end

-- Forces SUNNY to investigate a spot (lures from night events).
function SunnyService.lure(position: Vector3)
	if state == S.Stalking or state == S.Chasing then
		return
	end
	position = clampToMap(position)
	noise = { Position = flat(position), Time = os.clock() }
	if state == S.Observing or state == S.Searching or state == S.Retreating then
		enterState(S.Investigating, "lured")
	end
	setGoal(position)
end

-- Scripted scare: SUNNY appears at the light edge, stares, then leaves. No capture.
function SunnyService.appearAtLightEdge(duration: number): boolean
	if state == S.Stalking or state == S.Chasing then
		return false
	end
	local PS = Services.PlayerStateService
	local center = World.CampCenter
	-- Face the side of camp where most players are.
	local sum = Vector3.zero
	local count = 0
	for _, player in ipairs(PS.getPlayers()) do
		local root = PS.getRoot(player)
		if root then
			sum += flat(root.Position - center)
			count += 1
		end
	end
	local dir
	if count > 0 and sum.Magnitude > 1 then
		dir = sum.Unit
	else
		local a = rng:NextNumber() * math.pi * 2
		dir = Vector3.new(math.cos(a), 0, math.sin(a))
	end
	local radius = math.max(repelRadius(), 12) + CFG.LightEdgeBuffer + 2
	local pos = center + dir * radius
	SunnyModel.teleport(h, Vector3.new(pos.X, CFG.HoverHeight, pos.Z))
	h.Orient.CFrame = CFrame.lookAt(Vector3.zero, -dir)
	SunnyModel.setMood(h, "Night")
	scriptedUntil = os.clock() + duration
	sayLine("LightEdge", true)
	Services.PlayerStateService.playSound("Giggle", pos)
	task.delay(duration, function()
		if Services.PhaseService.getPhase() == "Night" and os.clock() >= scriptedUntil - 0.05 then
			local away = randomPatrolPoint(100)
			SunnyModel.teleport(h, Vector3.new(away.X, CFG.HoverHeight, away.Z))
			if state ~= S.Stalking and state ~= S.Chasing then
				enterState(S.Investigating, "scripted appearance over")
			end
		end
	end)
	return true
end

function SunnyService.nearestLandmarkName(): string
	local best, bestDist = "somewhere", math.huge
	local pos = groundPosition()
	for _, lm in ipairs(World.Landmarks) do
		local d = flatDistance(pos, lm.Position)
		if d < bestDist then
			best, bestDist = lm.Name, d
		end
	end
	return best
end

function SunnyService.onEnding(endingId: string)
	scriptedUntil = os.clock() + 9999 -- frozen until reset
	clearAlerts()
	target = nil
	local campEdge = edgePoint(6)
	SunnyModel.teleport(h, Vector3.new(campEdge.X, CFG.HoverHeight, campEdge.Z))
	h.Orient.CFrame = CFrame.lookAt(Vector3.zero, flat(World.CampCenter - campEdge).Unit)
	if endingId == "SunnysGoodbye" then
		SunnyModel.setMood(h, "Off")
		sayLine("SecretVictory", true)
	elseif endingId == "OverTheBridge" then
		SunnyModel.setMood(h, "Day")
		sayLine("Victory", true)
	elseif endingId == "ForeverCampers" then
		SunnyModel.setMood(h, "Night")
		sayLine("Forever", true)
	else
		SunnyModel.setMood(h, "Chase")
		sayLine("Defeat", true)
	end
	speechClearAt = os.clock() + 8
end

local function onPhaseChanged(phase: string, night: number)
	if phase == "Day" then
		local p = edgePoint(4)
		SunnyModel.teleport(h, Vector3.new(p.X, CFG.HoverHeight, p.Z))
		enterState(S.Observing, "day began")
		if not greeted then
			greeted = true
			nextHintAt = os.clock() + CFG.DayHintInterval
			task.delay(2, function()
				sayLine("Greeting", true)
			end)
		end
	elseif phase == "Sunset" then
		sayLine("Sunset", true)
	elseif phase == "Night" then
		table.clear(suspicion)
		noise = nil
		cooldownUntil = 0
		local p = edgePoint(16)
		SunnyModel.teleport(h, Vector3.new(p.X, CFG.HoverHeight, p.Z))
		enterState(S.Observing, "night began")
		task.delay(1, function()
			sayLine("NightStart", true)
		end)
	elseif phase == "Dawn" then
		clearAlerts()
		sayLine("Dawn", true)
	end
	if night and night > 0 and phase == "Night" and GameConfig.Debug.LogSunnyStates then
		print("[SUNNY] night", night)
	end
end

function SunnyService.reset()
	scriptedUntil = 0
	state = S.Dormant
	stateStartedAt = os.clock()
	target = nil
	lastKnownPos = nil
	table.clear(suspicion)
	noise = nil
	cooldownUntil = 0
	targetHidSpotted = false
	targetCaptured = false
	greeted = false
	hintIndex = 0
	clearAlerts()
	navigator:reset()
	SunnyModel.setMood(h, "Day")
	SunnyModel.setSpeech(h, nil)
	local home = World.ShrinePosition
	SunnyModel.teleport(h, Vector3.new(home.X, CFG.HoverHeight, home.Z))
	setGoal(home)
	Remotes.getState():SetAttribute(Types.StateAttr.SunnyState, state)
end

function SunnyService.getNavigatorStats()
	return navigator.stats
end

function SunnyService.init(services, world)
	Services = services
	World = world
end

function SunnyService.start()
	local home = World.ShrinePosition
	h = SunnyModel.build(workspace, Vector3.new(home.X, CFG.HoverHeight, home.Z))
	rayParams.FilterDescendantsInstances = { h.Model }
	navigator = SunnyNavigator.new(CFG.Path)
	SunnyService.reset()

	local PS = Services.PlayerStateService
	PS.Hid:Connect(function(player, spot)
		if player == target and (state == S.Chasing or state == S.Stalking) then
			if os.clock() - lastSeenAt <= GameConfig.Hiding.SpottedGrace then
				targetHidSpotted = true
				lastKnownPos = flat(spot.Position)
			end
		end
	end)
	PS.PlayerLeft:Connect(function(player)
		suspicion[player] = nil
		alerted[player] = nil
	end)
	Services.PhaseService.PhaseChanged:Connect(onPhaseChanged)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(CFG.TickInterval)
			local now = os.clock()
			local dt = math.min(now - last, 0.5)
			last = now
			local ok, err = pcall(tick, dt)
			if not ok then
				warn("[SUNNY] tick error: " .. tostring(err))
			end
		end
	end)
end

return SunnyService
