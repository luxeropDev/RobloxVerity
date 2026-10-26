-- AudioController: plays sound keys from GameConfig.Audio. Empty ids are silent placeholders.
-- Positional sounds use a temporary Attachment in Terrain and are cleaned up after playing.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local AudioController = {}

local AUDIO = GameConfig.Audio
local templates = {} -- [key] = Sound
local ambience = {}
local MAX_REPEAT = 8

local function makeSound(key: string, parent: Instance): Sound?
	local def = AUDIO.Sounds[key]
	if not def or def.Id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = def.Id
	sound.Volume = def.Volume * AUDIO.MasterVolume
	sound.Parent = parent
	return sound
end

function AudioController.play(key: string, position: Vector3?, repeatCount: number?)
	if type(key) ~= "string" or not AUDIO.Sounds[key] then
		return
	end
	local count = 1
	if type(repeatCount) == "number" then
		count = math.clamp(math.floor(repeatCount), 1, MAX_REPEAT)
	end
	if typeof(position) == "Vector3" then
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = position
		attachment.Parent = workspace.Terrain
		local sound = makeSound(key, attachment)
		if not sound then
			attachment:Destroy()
			return
		end
		sound.RollOffMaxDistance = 120
		task.spawn(function()
			for _ = 1, count do
				if not sound.Parent then
					return
				end
				sound:Play()
				task.wait(math.max(0.4, sound.TimeLength))
			end
		end)
		Debris:AddItem(attachment, 2 + count * 2)
		return
	end
	local template = templates[key]
	if template then
		SoundService:PlayLocalSound(template)
	end
end

local function setAmbience(phase: string)
	local wantNight = phase == "Night"
	if ambience.Day then
		if wantNight then
			ambience.Day:Stop()
		elseif not ambience.Day.IsPlaying then
			ambience.Day:Play()
		end
	end
	if ambience.Night then
		if wantNight then
			if not ambience.Night.IsPlaying then
				ambience.Night:Play()
			end
		else
			ambience.Night:Stop()
		end
	end
end

function AudioController.init()
	local folder = Instance.new("Folder")
	folder.Name = "SurviveSounds"
	folder.Parent = SoundService
	for key in pairs(AUDIO.Sounds) do
		templates[key] = makeSound(key, folder)
	end
	ambience.Day = templates.DayAmbience
	ambience.Night = templates.NightAmbience
	for _, sound in pairs(ambience) do
		sound.Looped = true
	end
end

function AudioController.start()
	Remotes.get("PlaySound").OnClientEvent:Connect(AudioController.play)
	Remotes.get("SunnyAlert").OnClientEvent:Connect(function(level)
		if level == "Watched" or level == "Chased" then
			AudioController.play("Alert")
		end
	end)
	local state = Remotes.getState()
	state:GetAttributeChangedSignal(Types.StateAttr.Phase):Connect(function()
		setAmbience(state:GetAttribute(Types.StateAttr.Phase) or "Day")
	end)
	setAmbience(state:GetAttribute(Types.StateAttr.Phase) or "Day")
end

return AudioController
