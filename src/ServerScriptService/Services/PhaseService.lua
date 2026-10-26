-- PhaseService: server-owned round/phase state machine.
-- Intermission -> (Day -> Sunset -> Night -> Dawn)* -> Results -> Intermission ...

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)

local Lib = ServerScriptService.Lib
local Signal = require(Lib.Signal)
local RateLimiter = require(Lib.RateLimiter)
local Awards = require(Lib.Awards)

local PhaseService = {}

PhaseService.PhaseChanged = Signal.new() -- (phase, night, round)
PhaseService.RoundReset = Signal.new() -- (round)

local Services
local World

local phase = Types.Phase.Intermission
local night = 0
local round = 0
local phaseEndsAt = 0
local endRequest = nil -- ending id that interrupts the current phase
local restartVotes = {} -- [Player] = true
local restartLimiter = RateLimiter.new(GameConfig.RateLimits.RequestRestart.MaxCalls, GameConfig.RateLimits.RequestRestart.Window)
local roundStartedAt = 0

local function log(...)
	if GameConfig.Debug.LogPhases then
		print("[Phase]", ...)
	end
end

function PhaseService.isTestMode(): boolean
	local mode = GameConfig.SoloTestMode
	if mode == "On" then
		return true
	end
	if mode == "Off" then
		return false
	end
	return RunService:IsStudio() and #Players:GetPlayers() <= 1
end

function PhaseService.getTimings()
	if PhaseService.isTestMode() then
		return GameConfig.Phases.Test
	end
	return GameConfig.Phases.Normal
end

function PhaseService.getPhase(): string
	return phase
end

function PhaseService.getNight(): number
	return night
end

function PhaseService.getRound(): number
	return round
end

function PhaseService.isNight(): boolean
	return phase == Types.Phase.Night
end

function PhaseService.getTimeLeft(): number
	return math.max(0, phaseEndsAt - workspace:GetServerTimeNow())
end

function PhaseService.getEscalation()
	local list = GameConfig.Escalation
	local index = math.clamp(night, 1, #list)
	return list[index]
end

-- Ends the current phase early with an ending (used for defeat during night).
function PhaseService.requestEnding(endingId: string)
	if endRequest == nil and phase == Types.Phase.Night then
		endRequest = endingId
		log("ending requested", endingId)
	end
end

local function setState()
	local state = Remotes.getState()
	state:SetAttribute(Types.StateAttr.Phase, phase)
	state:SetAttribute(Types.StateAttr.PhaseEndsAt, phaseEndsAt)
	state:SetAttribute(Types.StateAttr.Night, night)
	state:SetAttribute(Types.StateAttr.Round, round)
	state:SetAttribute(Types.StateAttr.TestMode, PhaseService.isTestMode())
end

local function updateVotes()
	local count = 0
	for player in pairs(restartVotes) do
		if player.Parent == Players then
			count += 1
		else
			restartVotes[player] = nil
		end
	end
	local needed = math.max(1, math.ceil(#Players:GetPlayers() / 2))
	local state = Remotes.getState()
	state:SetAttribute(Types.StateAttr.RestartVotes, count)
	state:SetAttribute(Types.StateAttr.RestartNeeded, needed)
	return count >= needed
end

-- Runs one phase. `canEndEarly` returns true to cut it short.
local function runPhase(newPhase: string, duration: number, canEndEarly)
	phase = newPhase
	phaseEndsAt = workspace:GetServerTimeNow() + duration
	setState()
	log(newPhase, "night", night, "duration", duration)
	PhaseService.PhaseChanged:Fire(newPhase, night, round)
	local deadline = os.clock() + duration
	while os.clock() < deadline do
		task.wait(0.2)
		if canEndEarly and canEndEarly() then
			break
		end
	end
end

local function playersPresent(): boolean
	return #Players:GetPlayers() >= GameConfig.Phases.MinPlayersToStart
end

local function resetRound()
	round += 1
	night = 0
	endRequest = nil
	table.clear(restartVotes)
	roundStartedAt = os.clock()
	Services.NightEventService.stopAll()
	Services.ResourceService.reset()
	Services.CampService.reset()
	Services.ObjectiveService.reset()
	Services.PlayerStateService.resetRound()
	Services.PlayerStateService.resetCourage()
	Services.SunnyService.reset()
	Remotes.get("Recap"):FireAllClients(nil)
	PhaseService.RoundReset:Fire(round)
end

local function buildRecap(endingId: string, nightsSurvived: number)
	local info = Types.EndingInfo[endingId]
	local PS = Services.PlayerStateService
	local rows = {}
	local awardInput = {}
	for _, player in ipairs(PS.getPlayers()) do
		local stats = PS.getStats(player)
		if stats then
			table.insert(awardInput, { key = player, stats = stats })
		end
	end
	local awards = Awards.assign(awardInput)
	for _, entry in ipairs(awardInput) do
		local player = entry.key
		local rec = PS.get(player)
		table.insert(rows, {
			Name = player.DisplayName,
			Gathered = entry.stats.Gathered,
			FuelAdded = entry.stats.FuelAdded,
			Rescues = entry.stats.Rescues,
			Captures = entry.stats.Captures,
			CluesFound = entry.stats.CluesFound,
			Glow = rec and rec.Glow or 0,
			Award = awards[player],
		})
	end
	local found, total = Services.ObjectiveService.getCluesFound()
	return {
		EndingId = endingId,
		EndingTitle = info.Title,
		EndingText = info.Text,
		Victory = info.Victory,
		NightsSurvived = nightsSurvived,
		CluesFound = found,
		CluesTotal = total,
		BridgeStages = Services.ObjectiveService.getBridgeStage(),
		Minutes = math.floor((os.clock() - roundStartedAt) / 60 * 10) / 10,
		Rows = rows,
	}
end

local function dawnRewards()
	local PS = Services.PlayerStateService
	for _, player in ipairs(PS.getPlayers()) do
		local rec = PS.get(player)
		if rec and not rec.Captured then
			PS.awardGlow(player, GameConfig.Rewards.GlowPerNightSurvived)
		end
	end
	PS.releaseAll("dawn")
end

local function pickEnding(): string?
	local OS = Services.ObjectiveService
	if night >= GameConfig.Nights.VictoryNight and OS.isBridgeRepaired() then
		local found, total = OS.getCluesFound()
		if found >= total then
			return Types.Ending.SunnysGoodbye
		end
		return Types.Ending.OverTheBridge
	end
	if night >= GameConfig.Nights.MaxNights then
		return Types.Ending.ForeverCampers
	end
	return nil
end

local function runRound()
	resetRound()
	local timings = PhaseService.getTimings()
	local ending = nil
	while ending == nil do
		timings = PhaseService.getTimings()
		runPhase(Types.Phase.Day, timings.Day, nil)
		runPhase(Types.Phase.Sunset, timings.Sunset, nil)
		night += 1
		runPhase(Types.Phase.Night, timings.Night, function()
			return endRequest ~= nil
		end)
		if endRequest then
			ending = endRequest
			break
		end
		dawnRewards()
		ending = pickEnding()
		local dawnTime = timings.Dawn
		if ending then
			dawnTime += GameConfig.Phases.FinalDawnBonus
		end
		runPhase(Types.Phase.Dawn, dawnTime, nil)
		if not playersPresent() then
			return
		end
	end

	local info = Types.EndingInfo[ending]
	if info.Victory then
		for _, player in ipairs(Services.PlayerStateService.getPlayers()) do
			Services.PlayerStateService.awardGlow(player, GameConfig.Rewards.GlowVictory)
		end
	end
	local nightsSurvived = night
	if not info.Victory and ending == Types.Ending.LightsOut then
		nightsSurvived = night - 1
	end
	local recap = buildRecap(ending, nightsSurvived)
	Services.SunnyService.onEnding(ending)
	Remotes.get("Recap"):FireAllClients(recap)
	table.clear(restartVotes)
	updateVotes()
	runPhase(Types.Phase.Results, PhaseService.getTimings().Results, function()
		return updateVotes()
	end)
end

local function mainLoop()
	while true do
		phase = Types.Phase.Intermission
		night = 0
		local timings = PhaseService.getTimings()
		runPhase(Types.Phase.Intermission, timings.Intermission, nil)
		while not playersPresent() do
			task.wait(1)
		end
		local ok, err = pcall(runRound)
		if not ok then
			warn("[Phase] round crashed, restarting: " .. tostring(err))
			task.wait(2)
		end
	end
end

local function onRestartRequest(player: Player)
	if not restartLimiter:allow(player) then
		return
	end
	if phase ~= Types.Phase.Results then
		return
	end
	restartVotes[player] = true
	updateVotes()
end

function PhaseService.init(services, world)
	Services = services
	World = world
end

function PhaseService.start()
	Remotes.get("RequestRestart").OnServerEvent:Connect(onRestartRequest)
	Players.PlayerRemoving:Connect(function(player)
		restartVotes[player] = nil
		restartLimiter:reset(player)
	end)
	local PS = Services.PlayerStateService
	PS.CourageDepleted:Connect(function()
		PhaseService.requestEnding(Types.Ending.LightsOut)
	end)
	PS.AllCaptured:Connect(function()
		PhaseService.requestEnding(Types.Ending.LightsOut)
	end)
	setState()
	task.spawn(mainLoop)
end

return PhaseService
