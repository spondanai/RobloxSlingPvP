local AmmoDefinitions = {
	Rock = {
		resourceCost = 1,
		baseDamage = 40,
		mass = 2,
		isExplosive = false,
		explosionRadius = 0,
		partSize = Vector3.new(1.4, 1.4, 1.4),
		color = Color3.fromRGB(100, 90, 80),
		material = Enum.Material.SmoothPlastic,
		displayName = "หิน",
	},
	Bomb = {
		resourceCost = 3,
		baseDamage = 80,
		mass = 4,
		isExplosive = true,
		explosionRadius = 9,
		partSize = Vector3.new(1.2, 1.2, 1.2),
		color = Color3.fromRGB(20, 20, 20),
		material = Enum.Material.Neon,
		displayName = "ระเบิด",
	},

	Order = { "Rock", "Bomb" },
}

return AmmoDefinitions
