local ServerScriptService = game:GetService("ServerScriptService")
local InventoryLogic = require(ServerScriptService.Lib.InventoryLogic)

return function(t)
	t.test("new inventory is empty", function()
		local inv = InventoryLogic.new()
		t.expect(InventoryLogic.total(inv)).toBe(0)
		t.expect(inv.Wood).toBe(0)
	end)

	t.test("add clamps to capacity", function()
		local inv = InventoryLogic.new()
		t.expect(InventoryLogic.add(inv, "Wood", 8, 10)).toBe(8)
		t.expect(InventoryLogic.add(inv, "Stone", 5, 10)).toBe(2)
		t.expect(InventoryLogic.total(inv)).toBe(10)
		t.expect(InventoryLogic.add(inv, "Food", 1, 10)).toBe(0)
	end)

	t.test("spend is all-or-nothing", function()
		local stock = { Wood = 5, Stone = 1, Food = 0, Token = 0 }
		t.expect(InventoryLogic.spend(stock, { Wood = 3, Stone = 2 })).toBe(false)
		t.expect(stock.Wood).toBe(5)
		t.expect(InventoryLogic.spend(stock, { Wood = 3, Stone = 1 })).toBe(true)
		t.expect(stock.Wood).toBe(2)
		t.expect(stock.Stone).toBe(0)
	end)

	t.test("rejects unknown resources in costs", function()
		local stock = { Wood = 99, Stone = 99, Food = 99, Token = 99 }
		t.expect(InventoryLogic.hasCost(stock, { Gold = 1 })).toBe(false)
		t.expect(InventoryLogic.isValidResource("Gold")).toBe(false)
		t.expect(InventoryLogic.isValidResource(42)).toBe(false)
	end)

	t.test("transferAll moves everything", function()
		local from = { Wood = 2, Stone = 0, Food = 1, Token = 3 }
		local to = InventoryLogic.new()
		local moved, total = InventoryLogic.transferAll(from, to)
		t.expect(total).toBe(6)
		t.expect(moved.Wood).toBe(2)
		t.expect(moved.Stone).toBe(nil)
		t.expect(InventoryLogic.total(from)).toBe(0)
		t.expect(to.Token).toBe(3)
	end)

	t.test("remove never goes negative", function()
		local inv = { Wood = 1, Stone = 0, Food = 0, Token = 0 }
		t.expect(InventoryLogic.remove(inv, "Wood", 5)).toBe(1)
		t.expect(inv.Wood).toBe(0)
	end)
end
