-- InteractionController: input bindings (keyboard, gamepad, touch) and client->server requests.
-- World interactions use ProximityPrompts, which already support mouse, keyboard, gamepad and touch.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local InteractionController = {}

local player = Players.LocalPlayer
local controllers
local lastSent = {} -- [remoteName] = os.clock()
local CLIENT_DEBOUNCE = 0.3

local function send(remoteName: string, ...)
	local now = os.clock()
	if lastSent[remoteName] and now - lastSent[remoteName] < CLIENT_DEBOUNCE then
		return
	end
	lastSent[remoteName] = now
	Remotes.get(remoteName):FireServer(...)
end

function InteractionController.requestUpgrade(upgradeId: string)
	send("RequestUpgrade", upgradeId)
end

function InteractionController.requestRestart()
	send("RequestRestart")
end

function InteractionController.requestUnhide()
	send("RequestUnhide")
end

local function onToggleCamp(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		controllers.HUD.toggleUpgradePanel()
	end
	return Enum.ContextActionResult.Sink
end

local function onLeaveHiding(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		InteractionController.requestUnhide()
	end
	return Enum.ContextActionResult.Sink
end

local function refreshHidingBinding()
	if player:GetAttribute(Types.PlayerAttr.Hidden) == true then
		ContextActionService:BindAction("LeaveHiding", onLeaveHiding, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	else
		ContextActionService:UnbindAction("LeaveHiding")
	end
end

function InteractionController.init(all)
	controllers = all
end

function InteractionController.start()
	ContextActionService:BindAction("ToggleCamp", onToggleCamp, false, Enum.KeyCode.C, Enum.KeyCode.ButtonY)

	player:GetAttributeChangedSignal(Types.PlayerAttr.Hidden):Connect(refreshHidingBinding)
	refreshHidingBinding()

	-- The workbench prompt opens the upgrade panel locally; building is still validated by the server.
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "UpgradeBenchPrompt" then
			controllers.HUD.setUpgradePanelVisible(true)
		end
	end)
end

return InteractionController
