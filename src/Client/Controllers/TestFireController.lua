-- TestFireController: Local slingshot drag-aim + trajectory arc preview for Workshop phase.
-- No server calls; purely visual so players can feel the layout before saving.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Players           = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit     = require(Packages.Knit)
local Janitor  = require(Packages.Janitor)
local Fusion   = require(Packages.Fusion)

local Shared   = ReplicatedStorage:WaitForChild("Shared")
local Modules  = Shared:WaitForChild("Modules")
local GameConfig = require(Modules.GameConfig)

local peek     = Fusion.peek
local Value    = Fusion.Value

local TestFireController = Knit.CreateController({ Name = "TestFireController" })

-- How many arc dots to show
local ARC_STEPS       = 20
local ARC_DOT_SIZE    = Vector3.new(0.35, 0.35, 0.35)
local GRAVITY         = Vector3.new(0, -Workspace.Gravity, 0)
local MAX_PULL        = 40   -- studs, caps launch speed
local SPEED_SCALE     = 1.5  -- pull distance → launch speed multiplier
local HIT_FLASH_TIME  = 0.25

TestFireController.active = false  -- true while test-fire mode is on

function TestFireController:KnitInit()
	self._janitor      = Janitor.new()
	self._modeJanitor  = Janitor.new()
	self._arcParts     = {}
	self._folder       = Instance.new("Folder")
	self._folder.Name  = "TFAssets"
	self._folder.Parent = Workspace
	self._janitor:Add(self._folder)
end

-- ── Arc dot pool ──────────────────────────────────────────────────────────────

local function makeDot(folder)
	local p = Instance.new("Part")
	p.Name        = "TF_ArcDot"
	p.Size        = ARC_DOT_SIZE
	p.Anchored    = true
	p.CanCollide  = false
	p.CastShadow  = false
	p.Material    = Enum.Material.Neon
	p.Color       = Color3.fromRGB(255, 200, 50)
	p.Transparency = 0.3
	p.Parent      = folder
	return p
end

function TestFireController:_ensureDots()
	while #self._arcParts < ARC_STEPS do
		self._arcParts[#self._arcParts + 1] = makeDot(self._folder)
	end
	-- hide all initially
	for _, d in ipairs(self._arcParts) do
		d.Transparency = 1
	end
end

function TestFireController:_hideDots()
	for _, d in ipairs(self._arcParts) do
		d.Transparency = 1
	end
end

-- ── Trajectory math ───────────────────────────────────────────────────────────

local function arcPositions(origin, velocity, steps, dt)
	local positions = {}
	for i = 1, steps do
		local t = i * dt
		positions[i] = origin + velocity * t + 0.5 * GRAVITY * t * t
	end
	return positions
end

-- ── Slingshot anchor (centre of team's grid, ground level) ───────────────────

local function slingshotOrigin(myTeam)
	local cx = (myTeam == "A") and GameConfig.TEAM_A_CENTER_X or GameConfig.TEAM_B_CENTER_X
	return Vector3.new(cx, GameConfig.GROUND_Y + GameConfig.BLOCK_SIZE * 0.5, 12)
end

-- ── Hit-flash a workshop block part ──────────────────────────────────────────

function TestFireController:_flashHit(part)
	if not part or not part.Parent then return end
	local origColor = part.Color
	TweenService:Create(part, TweenInfo.new(HIT_FLASH_TIME * 0.3), { Color = Color3.fromRGB(255,80,80) }):Play()
	task.delay(HIT_FLASH_TIME * 0.3, function()
		if part.Parent then
			TweenService:Create(part, TweenInfo.new(HIT_FLASH_TIME * 0.7), { Color = origColor }):Play()
		end
	end)
end

-- ── Enter / exit test-fire mode ───────────────────────────────────────────────

function TestFireController:EnterTestFire()
	if self.active then return end
	self.active = true
	self._modeJanitor:Cleanup()
	self:_ensureDots()

	local HudController     = Knit.GetController("HudController")
	local WorkshopController = Knit.GetController("WorkshopController")
	local myTeam   = peek(HudController.State.MyTeam)
	if not myTeam then self:ExitTestFire() return end

	local origin   = slingshotOrigin(myTeam)
	local isDragging = false
	local dragStart  = nil   -- screen position where drag began
	local Camera     = Workspace.CurrentCamera

	-- Show a static slingshot marker
	local marker = Instance.new("Part")
	marker.Name        = "TF_SlingshotMarker"
	marker.Size        = Vector3.new(1.2, 3, 1.2)
	marker.Anchored    = true
	marker.CanCollide  = false
	marker.Material    = Enum.Material.SmoothPlastic
	marker.Color       = Color3.fromRGB(180, 120, 40)
	marker.CFrame      = CFrame.new(origin)
	marker.Parent      = self._folder
	self._modeJanitor:Add(marker)

	-- Mouse-down starts drag
	local inputBegan = UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			isDragging = true
			dragStart  = input.Position
		end
	end)
	self._modeJanitor:Add(inputBegan)

	-- Mouse-move updates arc
	local inputChanged = UserInputService.InputChanged:Connect(function(input)
		if not isDragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

		local delta = Vector2.new(input.Position.X - dragStart.X, input.Position.Y - dragStart.Y)
		local pullDist = math.min(delta.Magnitude, MAX_PULL)
		if pullDist < 2 then self:_hideDots() return end

		-- Convert 2-D screen drag to world launch direction
		-- Drag left = launch right into grid; drag down = more loft
		local launchX = -delta.X / MAX_PULL
		local launchY = math.max(-delta.Y / MAX_PULL, 0.1)  -- always some upward
		local launchZ = -1  -- always shoot toward grid (into screen)
		local dir     = Vector3.new(launchX, launchY, launchZ).Unit
		local speed   = pullDist * SPEED_SCALE
		local velocity = dir * speed

		local positions = arcPositions(origin, velocity, ARC_STEPS, 0.15)
		for i, d in ipairs(self._arcParts) do
			if positions[i] then
				d.Position    = positions[i]
				d.Transparency = 0.2 + (i / ARC_STEPS) * 0.6
			end
		end
	end)
	self._modeJanitor:Add(inputChanged)

	-- Mouse-up fires the projectile (visual only)
	local inputEnded = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if not isDragging or not dragStart then return end
		isDragging = false

		local delta    = Vector2.new(input.Position.X - dragStart.X, input.Position.Y - dragStart.Y)
		local pullDist = math.min(delta.Magnitude, MAX_PULL)
		self:_hideDots()
		if pullDist < 2 then return end

		local launchX = -delta.X / MAX_PULL
		local launchY = math.max(-delta.Y / MAX_PULL, 0.1)
		local dir     = Vector3.new(launchX, launchY, -1).Unit
		local speed   = pullDist * SPEED_SCALE
		local velocity = dir * speed

		-- Spawn a visual projectile ball
		local ball = Instance.new("Part")
		ball.Name       = "TF_Projectile"
		ball.Shape      = Enum.PartType.Ball
		ball.Size       = Vector3.new(1.5, 1.5, 1.5)
		ball.Anchored   = true
		ball.CanCollide = false
		ball.Material   = Enum.Material.SmoothPlastic
		ball.Color      = Color3.fromRGB(120, 80, 40)
		ball.CFrame     = CFrame.new(origin)
		ball.Parent     = self._folder

		-- Simulate via heartbeat
		local elapsed = 0
		local conn
		conn = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			local newPos = origin + velocity * elapsed + 0.5 * GRAVITY * elapsed * elapsed
			ball.CFrame = CFrame.new(newPos)

			-- Hit-scan: check workshop blocks
			local folder = WorkshopController._workshopFolder
			if folder then
				for _, child in ipairs(folder:GetChildren()) do
					if child.Name:sub(1, 9) == "WS_Block_" then
						local dist = (child.Position - newPos).Magnitude
						if dist < (GameConfig.BLOCK_SIZE * 0.7) then
							conn:Disconnect()
							ball:Destroy()
							self:_flashHit(child)
							return
						end
					end
				end
			end

			-- Expire after 5 seconds or below ground
			if elapsed > 5 or newPos.Y < GameConfig.GROUND_Y - 10 then
				conn:Disconnect()
				ball:Destroy()
			end
		end)
		self._modeJanitor:Add(conn)
		self._modeJanitor:Add(ball)
	end)
	self._modeJanitor:Add(inputEnded)
end

function TestFireController:ExitTestFire()
	self.active = false
	self._modeJanitor:Cleanup()
	self:_hideDots()
end

-- ── Knit lifecycle ────────────────────────────────────────────────────────────

function TestFireController:KnitStart()
	local HudController = Knit.GetController("HudController")
	local Fusion2 = Fusion
	local Observer = Fusion2.Observer

	-- Auto-exit when leaving Workshop
	self._janitor:Add(Observer(HudController.State.Phase):onChange(function()
		if peek(HudController.State.Phase) ~= "Workshop" then
			self:ExitTestFire()
		end
	end))
end

return TestFireController
