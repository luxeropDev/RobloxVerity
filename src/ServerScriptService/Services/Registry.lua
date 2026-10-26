-- Registry: holds the live service table and world after Main.server.lua boots.
-- Integration tests and debugging tools read it; gameplay code receives services through init().

local Registry = {
	Services = nil,
	World = nil,
	Ready = false,
	BootError = nil,
}

-- Yields until the server finished booting or the timeout passes. Returns true when ready.
function Registry.waitUntilReady(timeout: number?): boolean
	local deadline = os.clock() + (timeout or 30)
	while not Registry.Ready and Registry.BootError == nil and os.clock() < deadline do
		task.wait(0.1)
	end
	return Registry.Ready
end

return Registry
