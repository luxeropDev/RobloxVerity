-- AtmosphereController: client-side lighting per phase (colorful day, blue-green night, warm dawn/sunset)
-- plus a small contrast pulse when SUNNY is hunting the local player. Purely cosmetic.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local AtmosphereController = {}

local state
local atmosphere
local correction
local currentPreset = nil
local alertLevel = "Clear"

local function getOrCreate(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

local function presetFor(phase: string)
	local L = GameConfig.Lighting
	if phase == "Night" then
		return L.Night
	elseif phase == "Sunset" then
		return L.Sunset
	elseif phase == "Dawn" then
		return L.Dawn
	end
	return L.Day
end

local function applyPreset(preset, instant: boolean?)
	currentPreset = preset
	local info = TweenInfo.new(GameConfig.Lighting.TweenTime, Enum.EasingStyle.Sine)
	if instant then
		info = TweenInfo.new(0)
	end
	TweenService:Create(Lighting, info, {
		ClockTime = preset.ClockTime,
		Brightness = preset.Brightness,
		Ambient = preset.Ambient,
		OutdoorAmbient = preset.OutdoorAmbient,
		FogEnd = preset.FogEnd,
		FogColor = preset.FogColor,
	}):Play()
	TweenService:Create(correction, info, {
		Saturation = preset.Saturation,
		TintColor = preset.Tint,
	}):Play()
	local density = 0.3
	if preset == GameConfig.Lighting.Night then
		density = 0.45
	end
	TweenService:Create(atmosphere, info, { Density = density, Color = preset.FogColor }):Play()
end

local function onPhase(instant: boolean?)
	local phase = state:GetAttribute(Types.StateAttr.Phase) or "Day"
	applyPreset(presetFor(phase), instant)
end

-- During the day, slowly move the sun from morning to late afternoon.
local function dayClockLoop()
	while true do
		task.wait(1)
		local phase = state:GetAttribute(Types.StateAttr.Phase)
		if phase == "Day" and currentPreset == GameConfig.Lighting.Day then
			local timings = GameConfig.Phases.Normal
			if state:GetAttribute(Types.StateAttr.TestMode) then
				timings = GameConfig.Phases.Test
			end
			local left = (state:GetAttribute(Types.StateAttr.PhaseEndsAt) or 0) - workspace:GetServerTimeNow()
			local progress = math.clamp(1 - left / timings.Day, 0, 1)
			TweenService:Create(Lighting, TweenInfo.new(1, Enum.EasingStyle.Linear), { ClockTime = 8 + progress * 9 }):Play()
		end
	end
end

local function onAlert(level: string)
	alertLevel = level
	local contrast = 0
	if level == "Watched" then
		contrast = 0.1
	elseif level == "Chased" then
		contrast = 0.25
	end
	TweenService:Create(correction, TweenInfo.new(0.6), { Contrast = contrast }):Play()
end

function AtmosphereController.init()
	state = Remotes.getState()
	atmosphere = getOrCreate("Atmosphere", "SurviveAtmosphere")
	correction = getOrCreate("ColorCorrectionEffect", "SurviveColor")
	Lighting.GlobalShadows = true
end

function AtmosphereController.start()
	state:GetAttributeChangedSignal(Types.StateAttr.Phase):Connect(function()
		onPhase(false)
	end)
	onPhase(true)
	Remotes.get("SunnyAlert").OnClientEvent:Connect(function(level)
		if type(level) == "string" and level ~= alertLevel then
			onAlert(level)
		end
	end)
	task.spawn(dayClockLoop)
end

return AtmosphereController
