-- StrangeCrate: a "FREE STUFF :)" crate in the dark. Either real loot or a confetti prank. Always drops a clue.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

return {
	Id = "StrangeCrate",
	run = function(ctx)
		local PS = ctx.Services.PlayerStateService
		local pos = ctx.randomDarkPosition(18, 45)
		local crate = ctx.part("StrangeCrate", Vector3.new(3, 3, 3), CFrame.new(pos + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, ctx.Rng:NextNumber() * 6, 0), Color3.fromRGB(170, 90, 200), Enum.Material.WoodPlanks, { CanCollide = true })
		ctx.label(crate, "FREE STUFF :)", Color3.fromRGB(255, 230, 90))
		ctx.notifyAll("A strange crate appeared in the dark. It says FREE STUFF :)", "mystery")

		local opened = false
		local prompt = ctx.prompt(crate, "Open", "Strange Crate", 0.8, 8)
		prompt.Triggered:Connect(function(player)
			if opened then
				return
			end
			if not ctx.canInteract(player, crate.Position, 13) then
				return
			end
			opened = true
			prompt.Enabled = false
			if ctx.Rng:NextNumber() < 0.5 then
				local added = PS.addResource(player, "Token", 2)
				ctx.notifyAll(player.DisplayName .. " opened the crate: +" .. added .. " Tokens!", "success")
			else
				local confetti = Instance.new("ParticleEmitter")
				confetti.Rate = 0
				confetti.Speed = NumberRange.new(12, 20)
				confetti.SpreadAngle = Vector2.new(60, 60)
				confetti.Lifetime = NumberRange.new(1, 1.6)
				confetti.Color = ColorSequence.new(Color3.fromRGB(255, 120, 200), Color3.fromRGB(120, 255, 230))
				confetti.Parent = crate
				confetti:Emit(40)
				PS.spook(player, GameConfig.Player.SpookedDuration)
				ctx.say("GOTCHA! Free stuff is never free! Hahaha!", 4)
				ctx.notifyAll(player.DisplayName .. " got pranked by the crate!", "warn")
				ctx.Services.SunnyService.reportNoise(crate.Position, 1.5)
			end
			ctx.Services.ObjectiveService.awardClue("crate_receipt", player)
			task.delay(2, function()
				if crate.Parent then
					crate:Destroy()
				end
			end)
		end)
	end,
}
