local ServerScriptService = game:GetService("ServerScriptService")
local Trove = require(ServerScriptService.Lib.Trove)
local Signal = require(ServerScriptService.Lib.Signal)

return function(t)
	t.test("cleans functions, instances and connections in reverse order", function()
		local trove = Trove.new()
		local order = {}
		trove:Add(function()
			table.insert(order, 1)
		end)
		local part = trove:Add(Instance.new("Part"))
		local folder = Instance.new("Folder")
		local conn = trove:Add(folder.ChildAdded:Connect(function() end))
		trove:Add(function()
			table.insert(order, 2)
		end)
		trove:Clean()
		t.expect(order[1]).toBe(2)
		t.expect(order[2]).toBe(1)
		t.expect(conn.Connected).toBe(false)
		t.expect(part.Parent).toBe(nil)
		t.expect(trove:Count()).toBe(0)
		folder:Destroy()
	end)

	t.test("adding after destroy cleans immediately", function()
		local trove = Trove.new()
		trove:Destroy()
		local ran = false
		trove:Add(function()
			ran = true
		end)
		t.expect(ran).toBe(true)
	end)

	t.test("cancels spawned threads", function()
		local trove = Trove.new()
		local ticks = 0
		trove:Spawn(function()
			while true do
				task.wait()
				ticks += 1
			end
		end)
		trove:Clean()
		local before = ticks
		task.wait(0.1)
		t.expect(ticks).toBe(before)
	end)

	t.test("signal fires handlers and disconnects", function()
		local signal = Signal.new()
		local count = 0
		local conn = signal:Connect(function(n)
			count += n
		end)
		signal:Fire(2)
		conn:Disconnect()
		signal:Fire(5)
		t.expect(count).toBe(2)
	end)
end
