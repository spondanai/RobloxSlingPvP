local BlockDefinitions = {
	Wood = {
		cap = 1,
		mass = 1,
		hp = 60,
		supportCapacity = 2,
		damageReduction = 0.00,
		color = Color3.fromRGB(160, 100, 40),
		material = Enum.Material.Wood,
		displayName = "ไม้",
	},
	Stone = {
		cap = 5,
		mass = 3,
		hp = 180,
		supportCapacity = 5,
		damageReduction = 0.20,
		color = Color3.fromRGB(120, 120, 120),
		material = Enum.Material.SmoothPlastic,
		displayName = "หิน",
	},
	Metal = {
		cap = 20,
		mass = 8,
		hp = 380,
		supportCapacity = 10,
		damageReduction = 0.45,
		color = Color3.fromRGB(160, 170, 190),
		material = Enum.Material.Metal,
		displayName = "เหล็ก",
	},

	Order = { "Wood", "Stone", "Metal" },
}

return BlockDefinitions
