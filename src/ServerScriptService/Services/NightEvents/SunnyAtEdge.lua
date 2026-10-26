-- SunnyAtEdge: SUNNY appears just outside the light and stares. A telegraphed scare with no capture.

return {
	Id = "SunnyAtEdge",
	run = function(ctx)
		local ok = ctx.Services.SunnyService.appearAtLightEdge(ctx.Definition.Duration)
		if ok then
			ctx.notifyAll("Something is watching from the edge of the light...", "danger")
		end
	end,
}
