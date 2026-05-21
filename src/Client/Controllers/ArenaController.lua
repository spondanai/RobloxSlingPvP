local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local Fusion = require(Packages:WaitForChild("Fusion"))
local Janitor = require(Packages:WaitForChild("Janitor"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local BlockDefinitions = require(Modules:WaitForChild("BlockDefinitions"))

local peek = Fusion.peek

local ArenaController = Knit.CreateController {
	Name = "ArenaController",
}

function ArenaController:KnitInit()
	self._janitor = Janitor.new()
	self._phaseJanitor = Janitor.new()

	local arenaAssets = Instance.new("Folder")
	arenaAssets.Name = "ArenaAssets"
	arenaAssets.Parent = Workspace
	self._janitor:Add(arenaAssets)

	self._arcDots = {}
	for i = 1, 20 do
		local dot = Instance.new("Part")
		dot.Name = "Arena_ArcDot"
		dot.Size = Vector3.new(0.35, 0.35, 0.35)
		dot.Material = Enum.Material.Neon
		dot.Color = Color3.fromRGB(255, 255, 0)
		dot.Transparency = 1
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanTouch = false
		dot.CanQuery = false
		dot.Parent = arenaAssets
		table.insert(self._arcDots, dot)
	end
end

function ArenaController:KnitStart()
	local HudController = Knit.GetController("HudController")
	local ArenaService = Knit.GetService("ArenaService")

	Fusion.Observer(HudController.State.Phase):onChange(function()
		local phase = peek(HudController.State.Phase)
		if phase == "Arena" then
			self:EnterArena()
		else
			self:ExitArena()
		end
	end)

	self._janitor:Add(ArenaService.OnGameState:Connect(function(data)
		self._myTeam = data.myTeam
		HudController.State.MyTeam:set(data.myTeam)
		HudController.State.Resources:set(data.resources or 3)
		HudController.State.Phase:set(data.phase or "Arena")
		-- Render enemy's blocks and core so there are targets to shoot at
		local enemyTeam = (data.myTeam == "A") and "B" or "A"
		if data.enemyBlocks then
			self:RenderBlocks(data.enemyBlocks, enemyTeam)
		end
		if data.enemyCorePos then
			self:RenderCore(data.enemyCorePos, enemyTeam)
		end
	end))

	self._janitor:Add(ArenaService.OnTurnChanged:Connect(function(data)
		HudController.State.CurrentTurn:set(data.currentTurn)
		local isMyTurn = data.currentTurn == self._myTeam
		HudController.State.IsMyTurn:set(isMyTurn)
		if data.resources then
			HudController.State.Resources:set(data.resources[self._myTeam] or 0)
		end
	end))

	self._janitor:Add(ArenaService.OnHit:Connect(function(data)
		self:HandleHit(data)
	end))

	self._janitor:Add(ArenaService.OnCollapse:Connect(function(positions, team)
		self:HandleCollapse(positions, team)
	end))

	self._janitor:Add(ArenaService.OnMatchOver:Connect(function(reason, winner)
		HudController.State.Phase:set("GameOver")
		HudController.State.CurrentTurn:set(winner)
	end))
end

function ArenaController:EnterArena()
	self._phaseJanitor:Cleanup()
	local Camera = Workspace.CurrentCamera
	Camera.CameraType = Enum.CameraType.Scriptable
	Camera.CFrame = CFrame.new(Vector3.new(0, 60, 120), Vector3.new(0, 8, 0))
	self:SetupSlingshotInput()
end

function ArenaController:ExitArena()
	self._phaseJanitor:Cleanup()
	local Camera = Workspace.CurrentCamera
	Camera.CameraType = Enum.CameraType.Custom
	for _, dot in self._arcDots do
		dot.Transparency = 1
	end
end

function ArenaController:RenderBlocks(blocks, team)
	local centerX = (team == "A") and -40 or 40
	local dirX = (team == "A") and -1 or 1
	local blockSize = 4
	local groundY = 0.5

	for _, block in blocks do
		local wx = centerX + dirX * (block.x + 0.5) * blockSize
		local wy = groundY + (block.y + 0.5) * blockSize
		local wz = 0

		local blockName = block.id:gsub("^%l", string.upper)
		local def = BlockDefinitions[blockName]

		local part = Instance.new("Part")
		part.Name = "Arena_Block_" .. team .. "_" .. block.x .. "_" .. block.y
		part.Size = Vector3.new(3.8, 3.8, 3.8)
		part.Position = Vector3.new(wx, wy, wz)
		part.Anchored = true
		part.Color = def and def.color or Color3.new(1, 1, 1)
		part.Material = def and def.material or Enum.Material.Plastic
		part.Parent = Workspace.ArenaAssets

		part:SetAttribute("Col", block.x)
		part:SetAttribute("Row", block.y)
		part:SetAttribute("Team", team)
	end
end

function ArenaController:RenderCore(corePos, team)
	if not corePos then return end
	local assets = Workspace:FindFirstChild("ArenaAssets")
	if not assets then return end

	local centerX   = (team == "A") and -40 or 40
	local dirX      = (team == "A") and -1 or 1
	local blockSize = 4
	local groundY   = 0.5

	local wx = centerX + dirX * (corePos.x + 0.5) * blockSize
	local wy = groundY + (corePos.y + 0.5) * blockSize

	local core = Instance.new("Part")
	core.Name     = "Arena_Core_" .. team
	core.Shape    = Enum.PartType.Ball
	core.Size     = Vector3.new(2.5, 2.5, 2.5)
	core.Anchored = true
	core.Material = Enum.Material.Neon
	core.Color    = Color3.fromRGB(0, 255, 100)
	core.Position = Vector3.new(wx, wy, 0)
	core:SetAttribute("Col", corePos.x)
	core:SetAttribute("Row", corePos.y)
	core:SetAttribute("Team", team)
	core:SetAttribute("IsCore", true)
	core.Parent = assets
end

function ArenaController:SetupSlingshotInput()
	local HudController = Knit.GetController("HudController")
	local ArenaService = Knit.GetService("ArenaService")
	
	local myTeam = self._myTeam
	local origin = (myTeam == "A") and Vector3.new(-40, 2.5, 12) or Vector3.new(40, 2.5, 12)
	
	local isDragging = false
	local dragStart = nil

	self._phaseJanitor:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if peek(HudController.State.IsMyTurn) then
				isDragging = true
				dragStart = input.Position
			end
		end
	end))

	self._phaseJanitor:Add(UserInputService.InputChanged:Connect(function(input)
		if isDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = Vector2.new(input.Position.X - dragStart.X, input.Position.Y - dragStart.Y)
			local pullDist = math.min(delta.Magnitude, 40)
			local launchDir = Vector3.new(-delta.X / 40, math.max(-delta.Y / 40, 0.1), -1).Unit
			local velocity = launchDir * pullDist * 1.5
			local gravity = Vector3.new(0, -Workspace.Gravity, 0)

			for i = 1, 20 do
				local t = i * 0.15
				local pos = origin + velocity * t + 0.5 * gravity * t * t
				local dot = self._arcDots[i]
				dot.CFrame = CFrame.new(pos)
				dot.Transparency = 0
			end
		end
	end))

	self._phaseJanitor:Add(UserInputService.InputEnded:Connect(function(input)
		if isDragging and input.UserInputType == Enum.UserInputType.MouseButton1 then
			isDragging = false
			for _, dot in self._arcDots do
				dot.Transparency = 1
			end

			local delta = Vector2.new(input.Position.X - dragStart.X, input.Position.Y - dragStart.Y)
			local pullDist = math.min(delta.Magnitude, 40)
			local launchDir = Vector3.new(-delta.X / 40, math.max(-delta.Y / 40, 0.1), -1).Unit
			local velocity = launchDir * pullDist * 1.5
			local gravity = Vector3.new(0, -Workspace.Gravity, 0)

			local hitBlock = nil
			local lastPos = origin
			
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = {Workspace:FindFirstChild("ArenaAssets")}

			for i = 1, 20 do
				local t = i * 0.15
				local pos = origin + velocity * t + 0.5 * gravity * t * t
				local result = Workspace:Raycast(lastPos, pos - lastPos, params)
				if result then
					hitBlock = result.Instance
					break
				end
				lastPos = pos
			end

			if not hitBlock then
				local assets = Workspace:FindFirstChild("ArenaAssets")
				if assets then
					for _, child in assets:GetChildren() do
						if child:IsA("BasePart") and child:GetAttribute("Col") ~= nil then
							if (child.Position - lastPos).Magnitude <= 3 then
								hitBlock = child
								break
							end
						end
					end
				end
			end

			if hitBlock then
				local hitCol = hitBlock:GetAttribute("Col")
				local hitRow = hitBlock:GetAttribute("Row")
				local hitTeam = hitBlock:GetAttribute("Team")
				local ammoName = peek(HudController.State.SelectedAmmo)
				ArenaService:FireSling(ammoName, hitCol, hitRow, hitTeam, pullDist * 1.5)
			end
		end
	end))
end

function ArenaController:HandleHit(data)
	local assets = Workspace:FindFirstChild("ArenaAssets")
	if not assets then return end
	-- Core hits use a different part name than block hits
	local name = data.isCore
		and ("Arena_Core_" .. data.team)
		or string.format("Arena_Block_%s_%d_%d", data.team, data.col, data.row)
	local part = assets:FindFirstChild(name)
	if not part then return end

	local originalColor = part.Color
	local tweenInfoIn = TweenInfo.new(0.15)
	local tweenInfoOut = TweenInfo.new(0.3)

	TweenService:Create(part, tweenInfoIn, { Color = Color3.new(1, 0, 0) }):Play()
	task.delay(0.15, function()
		if part and part.Parent then
			TweenService:Create(part, tweenInfoOut, { Color = originalColor }):Play()
		end
	end)

	if data.destroyed then
		local tweenDestroy = TweenService:Create(part, TweenInfo.new(0.3), {
			Transparency = 1,
			Size = Vector3.new(0, 0, 0)
		})
		tweenDestroy:Play()
		tweenDestroy.Completed:Connect(function()
			part:Destroy()
		end)
	end
end

function ArenaController:HandleCollapse(positions, team)
	local assets = Workspace:FindFirstChild("ArenaAssets")
	if not assets then return end
	for _, pos in ipairs(positions) do
		local name = "Arena_Block_" .. team .. "_" .. (pos.col or pos.x) .. "_" .. (pos.row or pos.y)
		local part = assets:FindFirstChild(name)
		if part then
			part:Destroy()
		end
	end
end

function ArenaController:EndTurn()
	Knit.GetService("ArenaService"):PassTurn()
end

return ArenaController
