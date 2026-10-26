local ServerScriptService = game:GetService("ServerScriptService")
local RateLimiter = require(ServerScriptService.Lib.RateLimiter)

return function(t)
	t.test("allows up to max calls in window", function()
		local now = 0
		local limiter = RateLimiter.new(2, 1, function()
			return now
		end)
		t.expect(limiter:allow("a")).toBe(true)
		t.expect(limiter:allow("a")).toBe(true)
		t.expect(limiter:allow("a")).toBe(false)
	end)

	t.test("window slides", function()
		local now = 0
		local limiter = RateLimiter.new(1, 1, function()
			return now
		end)
		t.expect(limiter:allow("a")).toBe(true)
		now = 0.5
		t.expect(limiter:allow("a")).toBe(false)
		now = 1.01
		t.expect(limiter:allow("a")).toBe(true)
	end)

	t.test("keys are independent and reset works", function()
		local now = 0
		local limiter = RateLimiter.new(1, 10, function()
			return now
		end)
		t.expect(limiter:allow("a")).toBe(true)
		t.expect(limiter:allow("b")).toBe(true)
		t.expect(limiter:allow("a")).toBe(false)
		limiter:reset("a")
		t.expect(limiter:allow("a")).toBe(true)
	end)
end
