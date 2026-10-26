-- Remotes: single registry for every RemoteEvent and the replicated GameState folder.
-- Server calls Remotes.init() once. Both sides use Remotes.get(name).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local REMOTES_FOLDER = "Remotes"
local STATE_FOLDER = "GameState"
local CLIENT_WAIT_TIMEOUT = 30

-- Server -> client
local SERVER_TO_CLIENT = {
	"Notify", -- (text: string, kind: string)
	"SunnySpeech", -- (text: string, duration: number)
	"ObjectivesUpdated", -- (objectives: { ObjectiveView })
	"Recap", -- (recap: Recap?) nil hides the results screen
	"SunnyAlert", -- (level: "Clear" | "Watched" | "Chased")
	"PlaySound", -- (key: string, position: Vector3?, repeatCount: number?)
	"StockpileUpdated", -- (stock: Inventory, levels: { [string]: number })
	"ClueFound", -- (title: string, text: string, finderName: string)
}

-- Client -> server. Every entry must be rate limited and validated by its handler.
local CLIENT_TO_SERVER = {
	"RequestUpgrade", -- (upgradeId: string)
	"RequestRestart", -- ()
	"RequestUnhide", -- ()
}

local known = {}
for _, name in ipairs(SERVER_TO_CLIENT) do
	known[name] = "ServerToClient"
end
for _, name in ipairs(CLIENT_TO_SERVER) do
	known[name] = "ClientToServer"
end

local cache = {}

function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init is server only")
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = REMOTES_FOLDER
		folder.Parent = ReplicatedStorage
	end
	for name in pairs(known) do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		cache[name] = remote
	end
	if not ReplicatedStorage:FindFirstChild(STATE_FOLDER) then
		local state = Instance.new("Folder")
		state.Name = STATE_FOLDER
		state.Parent = ReplicatedStorage
	end
end

function Remotes.get(name: string): RemoteEvent
	local cached = cache[name]
	if cached then
		return cached
	end
	assert(known[name], "Unknown remote: " .. tostring(name))
	local folder
	if RunService:IsServer() then
		folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER)
		assert(folder, "Remotes.init must run before Remotes.get on the server")
	else
		folder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER, CLIENT_WAIT_TIMEOUT)
		assert(folder, "Remotes folder did not replicate")
	end
	local remote = folder:WaitForChild(name, CLIENT_WAIT_TIMEOUT)
	assert(remote, "Remote did not replicate: " .. name)
	cache[name] = remote
	return remote
end

function Remotes.getState(): Folder
	local state
	if RunService:IsServer() then
		state = ReplicatedStorage:FindFirstChild(STATE_FOLDER)
	else
		state = ReplicatedStorage:WaitForChild(STATE_FOLDER, CLIENT_WAIT_TIMEOUT)
	end
	assert(state, "GameState folder missing")
	return state
end

function Remotes.isClientToServer(name: string): boolean
	return known[name] == "ClientToServer"
end

function Remotes.clientToServerNames(): { string }
	return table.clone(CLIENT_TO_SERVER)
end

return Remotes
