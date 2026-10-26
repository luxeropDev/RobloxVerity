-- InventoryLogic: pure functions for inventories, stockpiles and costs.
-- No yields, no Instances: safe to call between a check and a mutation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local InventoryLogic = {}

local VALID = {}
for _, name in ipairs(GameConfig.ResourceOrder) do
	VALID[name] = true
end

function InventoryLogic.isValidResource(name): boolean
	return type(name) == "string" and VALID[name] == true
end

function InventoryLogic.new()
	local inv = {}
	for _, name in ipairs(GameConfig.ResourceOrder) do
		inv[name] = 0
	end
	return inv
end

function InventoryLogic.total(inv): number
	local sum = 0
	for _, name in ipairs(GameConfig.ResourceOrder) do
		sum += inv[name] or 0
	end
	return sum
end

-- Adds up to `amount`, clamped by remaining capacity. Returns the amount added.
function InventoryLogic.add(inv, resource: string, amount: number, capacity: number?): number
	assert(InventoryLogic.isValidResource(resource), "invalid resource")
	if amount <= 0 then
		return 0
	end
	local added = amount
	if capacity then
		local free = math.max(0, capacity - InventoryLogic.total(inv))
		added = math.min(amount, free)
	end
	inv[resource] = (inv[resource] or 0) + added
	return added
end

-- Removes up to `amount`. Returns the amount removed.
function InventoryLogic.remove(inv, resource: string, amount: number): number
	assert(InventoryLogic.isValidResource(resource), "invalid resource")
	local removed = math.clamp(amount, 0, inv[resource] or 0)
	inv[resource] = (inv[resource] or 0) - removed
	return removed
end

function InventoryLogic.hasCost(stock, cost): boolean
	for resource, amount in pairs(cost) do
		if not InventoryLogic.isValidResource(resource) then
			return false
		end
		if (stock[resource] or 0) < amount then
			return false
		end
	end
	return true
end

-- All-or-nothing spend. Returns true if paid.
function InventoryLogic.spend(stock, cost): boolean
	if not InventoryLogic.hasCost(stock, cost) then
		return false
	end
	for resource, amount in pairs(cost) do
		stock[resource] -= amount
	end
	return true
end

-- Moves everything from `from` into `to`. Returns a table of moved amounts and the total.
function InventoryLogic.transferAll(from, to)
	local moved = {}
	local total = 0
	for _, name in ipairs(GameConfig.ResourceOrder) do
		local amount = from[name] or 0
		if amount > 0 then
			to[name] = (to[name] or 0) + amount
			from[name] = 0
			moved[name] = amount
			total += amount
		end
	end
	return moved, total
end

function InventoryLogic.formatCost(cost): string
	local parts = {}
	for _, name in ipairs(GameConfig.ResourceOrder) do
		local amount = cost[name]
		if amount and amount > 0 then
			table.insert(parts, string.format("%d %s", amount, GameConfig.Resources[name].DisplayName))
		end
	end
	if #parts == 0 then
		return "Free"
	end
	return table.concat(parts, ", ")
end

return InventoryLogic
