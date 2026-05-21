-- WorkshopController: Handles the building phase UI and interactions
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Janitor = require(Packages.Janitor)
local Fusion = require(Packages.Fusion)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local GameConfig = require(Modules.GameConfig)
local BlockDefinitions = require(Modules.BlockDefinitions)

local Observer = Fusion.Observer
local peek     = Fusion.peek

local WorkshopController = Knit.CreateController({ Name = "WorkshopController" })

WorkshopController.selectedType = "Wood"

function WorkshopController:KnitInit()
	self._janitor = Janitor.new()
	self._phaseJanitor = Janitor.new()
	self._workshopFolder = Instance.new("Folder")
	self._workshopFolder.Name = "WorkshopAssets"
	self._workshopFolder.Parent = Workspace
	self._janitor:Add(self._workshopFolder)

	self:SetupHoverPreview()
end

function WorkshopController:SetupHoverPreview()
	self._ghostBlock = Instance.new("Part")
	self._ghostBlock.Name = "WS_Ghost"
	self._ghostBlock.Size = Vector3.new(3.8, 3.8, 3.8)
	self._ghostBlock.Anchored = true
	self._ghostBlock.CanCollide = false
	self._ghostBlock.Transparency = 1 -- Hidden by default
	self._ghostBlock.Color = Color3.fromRGB(255, 255, 100)
	self._ghostBlock.Material = Enum.Material.Neon
	self._ghostBlock.Parent = self._workshopFolder
	self._janitor:Add(self._ghostBlock)
end

function WorkshopController:UpdateGhostColor()
	local blockDef = BlockDefinitions[self.selectedType]
	if blockDef then
		self._ghostBlock.Color = blockDef.color
	end
end

function WorkshopController:KnitStart()
	local WorkshopService = Knit.GetService("WorkshopService")
	local HudController = Knit.GetController("HudController")
	local Player = Players.LocalPlayer
	local Camera = Workspace.CurrentCamera

	-- Watch for Phase changes
	local function onPhaseChanged()
		local phase = peek(HudController.State.Phase)
		if phase == "Workshop" then
			self:EnterWorkshop()
		else
			self:ExitWorkshop()
		end
	end

	self._janitor:Add(Observer(HudController.State.Phase):onChange(onPhaseChanged))
	onPhaseChanged() -- Initial check

	-- Watch for selected type changes
	self._janitor:Add(Observer(HudController.State.SelectedBlock):onChange(function()
		self.selectedType = peek(HudController.State.SelectedBlock)
		self:UpdateGhostColor()
	end))

	-- Workshop Service Signals
	WorkshopService.OnBlockPlaced:Connect(function(col, row, typeName)
		self:RenderBlock(col, row, typeName)
	end)

	WorkshopService.OnBlockRemoved:Connect(function(col, row)
		self:RemoveBlockRender(col, row)
	end)

	WorkshopService.OnCoreSet:Connect(function(col, row)
		self:RenderCore(col, row)
	end)

	WorkshopService.OnSessionCleared:Connect(function()
		self:ClearAllRenders()
		local myTeam = peek(HudController.State.MyTeam)
		if myTeam and peek(HudController.State.Phase) == "Workshop" then
			self:showGrid(myTeam)
		end
	end)

	WorkshopService.OnCollapse:Connect(function(positions, newCap)
		self:AnimateCollapse(positions, newCap)
	end)

	WorkshopService.OnFloatWarning:Connect(function(positions)
		self:ShowFloatWarning(positions)
	end)
end

function WorkshopController:EnterWorkshop()
	local HudController = Knit.GetController("HudController")
	local myTeam = peek(HudController.State.MyTeam)
	if not myTeam then return end

	self._phaseJanitor:Cleanup()

	-- Set Camera
	local Camera = Workspace.CurrentCamera
	Camera.CameraType = Enum.CameraType.Scriptable
	if myTeam == "A" then
		Camera.CFrame = CFrame.new(Vector3.new(-40, 20, 80), Vector3.new(-40, 8, 0))
	else
		Camera.CFrame = CFrame.new(Vector3.new(40, 20, 80), Vector3.new(40, 8, 0))
	end

	self:showGrid(myTeam)
	self:SetupInput()
	self:UpdateGhostColor()

	-- Hover preview logic
	local hoverConn = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local ray = Workspace.CurrentCamera:ScreenPointToRay(input.Position.X, input.Position.Y)
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Include
			raycastParams.FilterDescendantsInstances = {self._workshopFolder}
			
			local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
			if result and result.Instance.Name == "WS_GridCell" then
				local hit = result.Instance
				self._ghostBlock.Position = hit.Position
				self._ghostBlock.Transparency = 0.5
			else
				self._ghostBlock.Transparency = 1
			end
		end
	end)
	self._phaseJanitor:Add(hoverConn)
end

function WorkshopController:ExitWorkshop()
	self._phaseJanitor:Cleanup()
	self:clearGrid()
	self._ghostBlock.Transparency = 1
	
	local Camera = Workspace.CurrentCamera
	Camera.CameraType = Enum.CameraType.Custom
end

function WorkshopController:showGrid(myTeam)
	self:clearGrid()
	
	local centerX = (myTeam == "A") and GameConfig.TEAM_A_CENTER_X or GameConfig.TEAM_B_CENTER_X
	local dirX = (myTeam == "A") and -1 or 1
	local blockSize = GameConfig.BLOCK_SIZE
	local groundY = GameConfig.GROUND_Y

	for col = 0, GameConfig.GRID_COLS - 1 do
		for row = 0, GameConfig.GRID_ROWS - 1 do
			local wx = centerX + dirX * (col + 0.5) * blockSize
			local wy = groundY + (row + 0.5) * blockSize
			local wz = 0

			local cell = Instance.new("Part")
			cell.Name = "WS_GridCell"
			cell.Size = Vector3.new(blockSize - 0.2, blockSize - 0.2, 0.3)
			cell.Anchored = true
			cell.CanCollide = false
			cell.Transparency = 0.65
			cell.Color = Color3.fromRGB(255, 255, 100)
			cell.Material = Enum.Material.Neon
			cell.Position = Vector3.new(wx, wy, wz)
			cell:SetAttribute("Col", col)
			cell:SetAttribute("Row", row)
			cell.Parent = self._workshopFolder
			
			self._phaseJanitor:Add(cell)
		end
	end
end

function WorkshopController:clearGrid()
	for _, child in ipairs(self._workshopFolder:GetChildren()) do
		if child.Name == "WS_GridCell" then
			child:Destroy()
		end
	end
end

function WorkshopController:SetupInput()
	local WorkshopService = Knit.GetService("WorkshopService")
	local Player = Players.LocalPlayer
	local Mouse = Player:GetMouse()

	local inputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		local ray = Workspace.CurrentCamera:ScreenPointToRay(input.Position.X, input.Position.Y)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		raycastParams.FilterDescendantsInstances = {self._workshopFolder}
		
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
		if not result then return end
		
		local hit = result.Instance
		
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if hit.Name == "WS_GridCell" then
				local col = hit:GetAttribute("Col")
				local row = hit:GetAttribute("Row")
				WorkshopService:PlaceBlock(col, row, self.selectedType)
			elseif hit.Name == "WS_CoreMarker" then
				local col = hit:GetAttribute("Col")
				local row = hit:GetAttribute("Row")
				WorkshopService:SetCore(col, row)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			if hit.Name:sub(1, 9) == "WS_Block_" then
				local col = hit:GetAttribute("Col")
				local row = hit:GetAttribute("Row")
				WorkshopService:RemoveBlock(col, row)
			end
		end
	end)

	self._phaseJanitor:Add(inputConn)
end

function WorkshopController:RenderBlock(col, row, typeName)
	local HudController = Knit.GetController("HudController")
	local myTeam = peek(HudController.State.MyTeam)
	if not myTeam then return end

	local blockDef = BlockDefinitions[typeName]
	if not blockDef then return end

	local centerX = (myTeam == "A") and GameConfig.TEAM_A_CENTER_X or GameConfig.TEAM_B_CENTER_X
	local dirX = (myTeam == "A") and -1 or 1
	local blockSize = GameConfig.BLOCK_SIZE
	local groundY = GameConfig.GROUND_Y

	local wx = centerX + dirX * (col + 0.5) * blockSize
	local wy = groundY + (row + 0.5) * blockSize
	local wz = 0

	-- Remove existing render if any
	self:RemoveBlockRender(col, row)

	local block = Instance.new("Part")
	block.Name = string.format("WS_Block_%d_%d", col, row)
	block.Size = Vector3.new(blockSize - 0.2, blockSize - 0.2, blockSize - 0.2)
	block.Anchored = true
	block.Color = blockDef.color
	block.Material = blockDef.material
	block.Position = Vector3.new(wx, wy, wz)
	block:SetAttribute("Col", col)
	block:SetAttribute("Row", row)
	block.Parent = self._workshopFolder
end

function WorkshopController:RemoveBlockRender(col, row)
	local name = string.format("WS_Block_%d_%d", col, row)
	local existing = self._workshopFolder:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end

function WorkshopController:AnimateCollapse(collapsePositions, newCap)
	local HudController = Knit.GetController("HudController")

	for _, position in ipairs(collapsePositions) do
		local col = position.col or position[1]
		local row = position.row or position[2]
		local part = self._workshopFolder:FindFirstChild(string.format("WS_Block_%d_%d", col, row))

		if part then
			local tween = TweenService:Create(
				part,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					Position = part.Position - Vector3.new(0, 8, 0),
					Transparency = 1,
				}
			)

			tween.Completed:Connect(function()
				part:Destroy()
			end)
			tween:Play()
		end
	end

	HudController.State.BuildCap:set(newCap)
end

function WorkshopController:ShowFloatWarning(positions)
	local WorkshopService = Knit.GetService("WorkshopService")
	local Player = Players.LocalPlayer
	local warnedParts = {}

	for _, position in ipairs(positions) do
		local col = position.col or position[1]
		local row = position.row or position[2]
		local part = self._workshopFolder:FindFirstChild(string.format("WS_Block_%d_%d", col, row))

		if part then
			warnedParts[#warnedParts + 1] = part
			TweenService:Create(
				part,
				TweenInfo.new(0.15),
				{ Color = Color3.fromRGB(255, 80, 80) }
			):Play()
		end
	end

	task.delay(1.5, function()
		local session
		local ok, result = pcall(function()
			return WorkshopService:GetSession(Player)
		end)
		if ok then
			session = result
		end

		for _, part in ipairs(warnedParts) do
			if part.Parent then
				local col = part:GetAttribute("Col")
				local row = part:GetAttribute("Row")
				local color = Color3.fromRGB(200, 200, 200)

				if session and session.blocks then
					for _, block in ipairs(session.blocks) do
						if block.x == col and block.y == row and block.z == 0 then
							for blockTypeName, blockDef in pairs(BlockDefinitions) do
								if type(blockDef) == "table" and string.lower(blockTypeName) == block.id then
									color = blockDef.color
									break
								end
							end
							break
						end
					end
				end

				TweenService:Create(
					part,
					TweenInfo.new(0.15),
					{ Color = color }
				):Play()
			end
		end
	end)
end

function WorkshopController:RenderCore(col, row)
	local HudController = Knit.GetController("HudController")
	local myTeam = peek(HudController.State.MyTeam)
	if not myTeam then return end

	-- Remove existing core marker
	local existing = self._workshopFolder:FindFirstChild("WS_CoreMarker")
	if existing then existing:Destroy() end

	local centerX = (myTeam == "A") and GameConfig.TEAM_A_CENTER_X or GameConfig.TEAM_B_CENTER_X
	local dirX = (myTeam == "A") and -1 or 1
	local blockSize = GameConfig.BLOCK_SIZE
	local groundY = GameConfig.GROUND_Y

	local wx = centerX + dirX * (col + 0.5) * blockSize
	local wy = groundY + (row + 0.5) * blockSize
	local wz = 0

	local core = Instance.new("Part")
	core.Name = "WS_CoreMarker"
	core.Size = Vector3.new(2, 2, 2)
	core.Anchored = true
	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(0, 255, 0)
	core.Position = Vector3.new(wx, wy, wz)
	core:SetAttribute("Col", col)
	core:SetAttribute("Row", row)
	core.Parent = self._workshopFolder
end

function WorkshopController:ClearAllRenders()
	for _, child in ipairs(self._workshopFolder:GetChildren()) do
		if child.Name:sub(1, 9) == "WS_Block_" or child.Name == "WS_CoreMarker" then
			child:Destroy()
		end
	end
end

return WorkshopController
