-- FakeSign: a helpful-looking sign points away from camp. It is not helpful. SUNNY waits where it points.

return {
	Id = "FakeSign",
	run = function(ctx)
		local center = ctx.World.CampCenter
		local pos = ctx.randomDarkPosition(4, 12)
		local away = Vector3.new(pos.X - center.X, 0, pos.Z - center.Z)
		if away.Magnitude < 0.1 then
			away = Vector3.new(1, 0, 0)
		end
		away = away.Unit
		local facing = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
		ctx.part("FakeSignPole", Vector3.new(0.5, 6, 0.5), facing * CFrame.new(0, 3, 0), Color3.fromRGB(90, 62, 40), Enum.Material.Wood, { CanCollide = true })
		local board = ctx.part("FakeSignBoard", Vector3.new(5, 1.6, 0.3), facing * CFrame.new(0, 5.5, 0), Color3.fromRGB(170, 125, 80), Enum.Material.Wood)
		ctx.label(board, "SAFE ZONE THIS WAY -->", Color3.fromRGB(120, 255, 140))
		ctx.notifyAll("A new sign appeared near camp. That was not there before...", "mystery")

		local lurePoint = pos + away * 45
		ctx.Services.SunnyService.lure(lurePoint)

		local prompt = ctx.prompt(board, "Read", "Sign", 0.3, 9)
		prompt.Triggered:Connect(function(player)
			if not ctx.canInteract(player, board.Position, 14) then
				return
			end
			ctx.Services.PlayerStateService.notify(player, "The tiny print says: '(trust me) - definitely not SUNNY'", "mystery")
		end)
	end,
}
