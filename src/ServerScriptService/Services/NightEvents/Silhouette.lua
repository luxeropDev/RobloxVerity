-- Silhouette: a dark figure wearing a teammate's name stands in the forest. It vanishes when approached.

return {
	Id = "Silhouette",
	run = function(ctx)
		local PS = ctx.Services.PlayerStateService
		local players = PS.getPlayers()
		if #players == 0 then
			return
		end
		local named = players[ctx.Rng:NextInteger(1, #players)]
		local pos = ctx.randomDarkPosition(25, 55)
		local center = ctx.World.CampCenter
		local facing = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))

		local figure = Instance.new("Model")
		figure.Name = "Silhouette"
		figure.Parent = ctx.Folder
		ctx.Trove:Add(figure)
		local dark = Color3.fromRGB(14, 18, 24)
		local opts = { Parent = figure }
		ctx.part("LegL", Vector3.new(1, 2, 1), facing * CFrame.new(-0.5, 1, 0), dark, Enum.Material.SmoothPlastic, opts)
		ctx.part("LegR", Vector3.new(1, 2, 1), facing * CFrame.new(0.5, 1, 0), dark, Enum.Material.SmoothPlastic, opts)
		ctx.part("Torso", Vector3.new(2, 2, 1), facing * CFrame.new(0, 3, 0), dark, Enum.Material.SmoothPlastic, opts)
		ctx.part("ArmL", Vector3.new(1, 2, 1), facing * CFrame.new(-1.5, 3, 0), dark, Enum.Material.SmoothPlastic, opts)
		ctx.part("ArmR", Vector3.new(1, 2, 1), facing * CFrame.new(1.5, 3, 0), dark, Enum.Material.SmoothPlastic, opts)
		local head = ctx.part("Head", Vector3.new(1.2, 1.2, 1.2), facing * CFrame.new(0, 4.6, 0), dark, Enum.Material.SmoothPlastic, opts)
		ctx.part("EyeL", Vector3.new(0.2, 0.2, 0.1), facing * CFrame.new(-0.25, 4.7, -0.62), Color3.fromRGB(230, 255, 250), Enum.Material.Neon, opts)
		ctx.part("EyeR", Vector3.new(0.2, 0.2, 0.1), facing * CFrame.new(0.25, 4.7, -0.62), Color3.fromRGB(230, 255, 250), Enum.Material.Neon, opts)
		ctx.label(head, named.DisplayName, Color3.fromRGB(170, 170, 180))

		ctx.notifyAll("Is that... " .. named.DisplayName .. " standing out there?", "mystery")
		local namedRoot = PS.getRoot(named)
		if namedRoot and ctx.Services.CampService.isInSafeZone(namedRoot.Position, 0) then
			task.delay(2.5, function()
				if figure.Parent then
					ctx.notifyAll("Wait. " .. named.DisplayName .. " is right here at camp. So who is THAT?", "mystery")
				end
			end)
		end

		ctx.every(0.4, function()
			local _, dist = ctx.nearestPlayer(pos)
			if dist < 18 then
				figure:Destroy()
				ctx.playSound("Giggle", pos)
				ctx.notifyAll("The figure vanished.", "mystery")
				return false
			end
			return true
		end)
	end,
}
