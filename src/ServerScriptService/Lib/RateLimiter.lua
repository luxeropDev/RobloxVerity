-- RateLimiter: sliding-window limiter keyed by any value (usually a Player).
-- The clock is injectable for unit tests.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(maxCalls: number, window: number, clock: (() -> number)?)
	assert(maxCalls >= 1, "maxCalls must be >= 1")
	assert(window > 0, "window must be > 0")
	return setmetatable({
		_max = maxCalls,
		_window = window,
		_clock = clock or os.clock,
		_calls = {},
	}, RateLimiter)
end

function RateLimiter:allow(key): boolean
	local now = self._clock()
	local calls = self._calls[key]
	if not calls then
		calls = {}
		self._calls[key] = calls
	end
	-- Drop timestamps outside the window.
	local cutoff = now - self._window
	local kept = 0
	for i = 1, #calls do
		if calls[i] > cutoff then
			kept += 1
			calls[kept] = calls[i]
		end
	end
	for i = #calls, kept + 1, -1 do
		calls[i] = nil
	end
	if kept >= self._max then
		return false
	end
	calls[kept + 1] = now
	return true
end

function RateLimiter:reset(key)
	self._calls[key] = nil
end

function RateLimiter:clear()
	table.clear(self._calls)
end

return RateLimiter
