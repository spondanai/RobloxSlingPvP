-- ProjectileModule: Lightweight projectile physics for SlingSiege (no FastCast dependency).
-- Client uses this for arc preview; server uses it for hit plausibility validation.
local ProjectileModule = {}

local GRAVITY_Y  = -workspace.Gravity  -- read at load time; stays in sync with studio setting
local MAX_SPEED  = 60    -- studs/s, cap for damage formula input
local ARC_STEPS  = 40    -- simulation steps for hit-test
local ARC_DT     = 0.1   -- seconds per step

-- Compute world position along a parabolic arc at time t
function ProjectileModule.positionAtTime(origin, velocity, t)
	return Vector3.new(
		origin.X + velocity.X * t,
		origin.Y + velocity.Y * t + 0.5 * GRAVITY_Y * t * t,
		origin.Z + velocity.Z * t
	)
end

-- Returns array of {pos=Vector3, t=number} for ARC_STEPS steps
function ProjectileModule.traceArc(origin, velocity, steps, dt)
	steps = steps or ARC_STEPS
	dt    = dt    or ARC_DT
	local out = {}
	for i = 1, steps do
		local t = i * dt
		out[i] = { pos = ProjectileModule.positionAtTime(origin, velocity, t), t = t }
	end
	return out
end

-- Convert screen-drag delta (Vector2) and pull distance to world velocity
-- dragDelta: Vector2 (screen pixels, positive right/down)
-- pullDist: number 0-40 (magnitude, capped)
-- Returns Vector3 velocity
function ProjectileModule.dragToVelocity(dragDelta, pullDist)
	pullDist = math.clamp(pullDist, 0, 40)
	local speed   = pullDist * 1.5
	local dirX    = -dragDelta.X / 40
	local dirY    = math.max(-dragDelta.Y / 40, 0.1)
	local dir     = Vector3.new(dirX, dirY, -1).Unit
	return dir * speed
end

-- Server-side plausibility check:
-- Given origin, velocity, targetWorldPos — does the arc come within threshold?
-- Returns true, closestDist | false
function ProjectileModule.canHit(origin, velocity, targetPos, threshold)
	threshold = threshold or 6  -- studs; generous for grid-aligned blocks
	local best = math.huge
	for i = 1, ARC_STEPS do
		local t = i * ARC_DT
		local p = ProjectileModule.positionAtTime(origin, velocity, t)
		local d = (p - targetPos).Magnitude
		if d < best then best = d end
		-- Early out once we've passed the target depth
		if p.Z < targetPos.Z - 20 then break end
	end
	return best <= threshold, best
end

-- Clamp speedFactor for damage calculation (0 to MAX_SPEED)
function ProjectileModule.clampSpeed(speedFactor)
	return math.clamp(speedFactor, 0, MAX_SPEED)
end

return ProjectileModule
