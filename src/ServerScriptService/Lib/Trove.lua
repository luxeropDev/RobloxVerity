-- Trove: collects Instances, connections, threads and cleanup functions and
-- releases all of them at once. Used by night events, rounds and SUNNY.

local Trove = {}
Trove.__index = Trove

local function cleanupItem(item)
	local kind = typeof(item)
	if kind == "Instance" then
		item:Destroy()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "function" then
		local ok, err = pcall(item)
		if not ok then
			warn("[Trove] cleanup function failed: " .. tostring(err))
		end
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" then
			pcall(task.cancel, item)
		end
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		end
	end
end

function Trove.new()
	return setmetatable({ _items = {}, _destroyed = false }, Trove)
end

function Trove:Add(item)
	if self._destroyed then
		cleanupItem(item)
		return item
	end
	table.insert(self._items, item)
	return item
end

-- Runs fn in a new thread owned by this trove.
function Trove:Spawn(fn, ...)
	return self:Add(task.spawn(fn, ...))
end

function Trove:Count(): number
	return #self._items
end

function Trove:Clean()
	local items = self._items
	self._items = {}
	for i = #items, 1, -1 do
		cleanupItem(items[i])
	end
end

function Trove:Destroy()
	self:Clean()
	self._destroyed = true
end

function Trove:IsDestroyed(): boolean
	return self._destroyed
end

return Trove
