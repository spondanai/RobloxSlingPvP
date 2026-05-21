local DamageModel = {}

local REFERENCE_SPEED = 50

function DamageModel.calculate(ammo, speedFactor, blockDef)
	local speedMultiplier = math.clamp(speedFactor / REFERENCE_SPEED, 0.5, 2.0)
	local finalDamage = ammo.baseDamage * speedMultiplier * (1 - blockDef.damageReduction)
	return finalDamage
end

function DamageModel.calculateAoe(ammo, distFromCenter, blockDef)
	if distFromCenter >= ammo.explosionRadius then
		return 0
	end

	local falloff = 1 - (distFromCenter / ammo.explosionRadius)
	local finalDamage = ammo.baseDamage * falloff * (1 - blockDef.damageReduction)
	return finalDamage
end

function DamageModel.calculateCoreDamage(ammo, speedFactor)
	local speedMultiplier = math.clamp(speedFactor / REFERENCE_SPEED, 0.5, 2.0)
	local finalDamage = ammo.baseDamage * speedMultiplier * 1.2
	return finalDamage
end

return DamageModel
