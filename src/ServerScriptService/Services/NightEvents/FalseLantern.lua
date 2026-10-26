-- FalseLantern: a warm lantern appears in the dark. Reaching it reveals a decoy and lures SUNNY there.

return {
	Id = "FalseLantern",
	run = function(ctx)
		local pos = ctx.randomDarkPosition(30, 70)
		ctx.part("FalseLanternPole", Vector3.new(0.4, 5, 0.4), CFrame.new(pos + Vector3.new(0, 2.5, 0)), Color3.fromRGB(80, 60, 40), Enum.Material.Wood, { CanCollide = true })
		local lamp = ctx.part("FalseLantern", Vector3.new(1.2, 1.4, 1.2), CFrame.new(pos + Vector3.new(0, 5.6, 0)), Color3.fromRGB(255, 200, 120), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Range = 18
		light.Brightness = 2
		light.Color = Color3.fromRGB(255, 190, 110)
		light.Parent = lamp

		ctx.notifyAll("A warm lantern flickers somewhere in the forest...", "mystery")

		ctx.every(0.5, function()
			local player, dist = ctx.nearestPlayer(pos)
			if player and dist < 9 then
				light.Enabled = false
				lamp.Color = Color3.fromRGB(110, 255, 230)
				lamp.Transparency = 0.6
				ctx.say("Ooh, you found my decoy lantern! Tag, you're it~", 4)
				ctx.playSound("Giggle", pos)
				ctx.Services.SunnyService.lure(pos)
				return false
			end
			light.Brightness = 1.2 + ctx.Rng:NextNumber() * 1.6
			return true
		end)
	end,
}
