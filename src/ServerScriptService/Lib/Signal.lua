-- Signal: minimal server-side event. Handlers run in their own thread, so one
-- failing handler cannot break the caller (for example the phase loop).

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {}, _nextId = 0 }, Signal)
end

function Signal:Connect(handler)
	assert(type(handler) == "function", "Signal:Connect expects a function")
	self._nextId += 1
	local id = self._nextId
	self._handlers[id] = handler
	local connection = { Connected = true }
	function connection.Disconnect()
		connection.Connected = false
		self._handlers[id] = nil
	end
	return connection
end

function Signal:Fire(...)
	for _, handler in pairs(self._handlers) do
		task.spawn(handler, ...)
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
