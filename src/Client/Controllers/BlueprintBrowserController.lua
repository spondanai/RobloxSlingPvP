local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit     = require(Packages.Knit)
local Janitor  = require(Packages.Janitor)
local Fusion   = require(Packages.Fusion)

local scoped   = Fusion.scoped
local Children = Fusion.Children
local Value    = Fusion.Value
local Computed = Fusion.Computed
local ForValues= Fusion.ForValues
local peek     = Fusion.peek
local Observer = Fusion.Observer

local BlueprintBrowserController = Knit.CreateController({ Name = "BlueprintBrowserController" })

local C = {
	bg     = Color3.fromRGB(12, 12, 18),
	panel  = Color3.fromRGB(25, 25, 38),
	border = Color3.fromRGB(60, 60, 90),
	gold   = Color3.fromRGB(255, 200, 0),
	green  = Color3.fromRGB(60, 210, 80),
	red    = Color3.fromRGB(220, 60, 60),
	white  = Color3.new(1, 1, 1),
}

-- State lives inside KnitStart (passed to buildBrowser) so it's scoped per-run, not module-level
local function buildBrowser(scope, screenGui, HudController, janitor, blueprintList, statusMsg, statusIsError, setStatus, refreshList)
	local BlueprintService = Knit.GetService("BlueprintService")
	local WorkshopService  = Knit.GetService("WorkshopService")

	local isVisible = Computed(scope, function(use)
		return use(HudController.State.Phase) == "Workshop"
	end)

	local panel = scope:New "Frame" {
		Name             = "BlueprintBrowser",
		Size             = UDim2.new(0, 240, 0, 320),
		Position         = UDim2.new(0, 12, 0.5, -160),
		BackgroundColor3 = C.panel,
		BorderSizePixel  = 0,
		Visible          = isVisible,
		Parent           = screenGui,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 10) },
			scope:New "UIStroke" { Color = C.border, Thickness = 1 },
		},
	}

	scope:New "TextLabel" {
		Name                   = "Title",
		Size                   = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		TextColor3             = C.gold,
		Font                   = Enum.Font.GothamBold,
		TextScaled             = true,
		Text                   = "Blueprints",
		Parent                 = panel,
	}

	local scroll = scope:New "ScrollingFrame" {
		Name                = "List",
		Size                = UDim2.new(1, -8, 0, 196),
		Position            = UDim2.new(0, 4, 0, 36),
		BackgroundTransparency = 1,
		BorderSizePixel     = 0,
		ScrollBarThickness  = 4,
		CanvasSize          = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent              = panel,
		[Children] = {
			scope:New "UIListLayout" {
				Padding       = UDim.new(0, 4),
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder     = Enum.SortOrder.LayoutOrder,
			},
			ForValues(scope, blueprintList, function(use, s, bp)
				return s:New "Frame" {
					Name             = "Row_" .. bp.index,
					Size             = UDim2.new(1, 0, 0, 44),
					BackgroundColor3 = C.bg,
					BorderSizePixel  = 0,
					LayoutOrder      = bp.index,
					[Children] = {
						s:New "UICorner" { CornerRadius = UDim.new(0, 6) },
						s:New "TextLabel" {
							Size                   = UDim2.new(0.58, 0, 1, 0),
							Position               = UDim2.new(0, 6, 0, 0),
							BackgroundTransparency = 1,
							TextColor3             = C.white,
							Font                   = Enum.Font.Gotham,
							TextScaled             = true,
							TextXAlignment         = Enum.TextXAlignment.Left,
							Text                   = bp.name .. " (" .. bp.blockCount .. ")",
						},
						s:New "TextButton" {
							Size             = UDim2.new(0, 50, 0, 28),
							Position         = UDim2.new(0.58, 2, 0.5, -14),
							BackgroundColor3 = C.green,
							Text             = "Load",
							TextColor3       = C.white,
							Font             = Enum.Font.GothamBold,
							TextScaled       = true,
							[Children] = { s:New "UICorner" { CornerRadius = UDim.new(0, 5) } },
							[Fusion.OnEvent "MouseButton1Click"] = function()
								local ok, err2 = WorkshopService:LoadBlueprint(bp.index)
								if ok then
									setStatus("Loaded: " .. bp.name, false, 2)
								else
									setStatus("Load failed: " .. tostring(err2), true, 3)
								end
							end,
						},
						s:New "TextButton" {
							Size             = UDim2.new(0, 50, 0, 28),
							Position         = UDim2.new(0.58, 56, 0.5, -14),
							BackgroundColor3 = C.red,
							Text             = "Del",
							TextColor3       = C.white,
							Font             = Enum.Font.GothamBold,
							TextScaled       = true,
							[Children] = { s:New "UICorner" { CornerRadius = UDim.new(0, 5) } },
							[Fusion.OnEvent "MouseButton1Click"] = function()
								local ok = BlueprintService:Delete(bp.index)
								if ok then
									setStatus("Deleted.", false, 2)
									refreshList()
								end
							end,
						},
					},
				}
			end, Fusion.cleanup),
		},
	}

	scope:New "TextButton" {
		Name             = "SaveBtn",
		Size             = UDim2.new(1, -8, 0, 36),
		Position         = UDim2.new(0, 4, 1, -76),
		BackgroundColor3 = C.green,
		Text             = "Save Current Build",
		TextColor3       = C.white,
		Font             = Enum.Font.GothamBold,
		TextScaled       = true,
		Parent           = panel,
		[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0, 7) } },
		[Fusion.OnEvent "MouseButton1Click"] = function()
			local result = WorkshopService:Validate()
			if not result then
				setStatus("Validate failed", true, 3)
				return
			end
			if not result.ok then
				setStatus("X " .. (result.errors[1] or "Invalid"), true, 3)
				return
			end
			local ok, idxOrErr = BlueprintService:Save()
			if ok then
				setStatus("Saved! (#" .. tostring(idxOrErr) .. ")", false, 2.5)
				refreshList()
			else
				setStatus("X " .. tostring(idxOrErr), true, 3)
			end
		end,
	}

	scope:New "TextLabel" {
		Name                   = "Status",
		Size                   = UDim2.new(1, -8, 0, 28),
		Position               = UDim2.new(0, 4, 1, -36),
		BackgroundTransparency = 1,
		TextColor3             = Computed(scope, function(use)
			return use(statusIsError) and C.red or C.green
		end),
		Font       = Enum.Font.Gotham,
		TextScaled = true,
		Text       = Computed(scope, function(use) return use(statusMsg) end),
		Parent     = panel,
	}

	janitor:Add(BlueprintService.OnBlueprintSaved:Connect(function()
		refreshList()
	end))

	janitor:Add(Observer(HudController.State.Phase):onChange(function()
		if peek(HudController.State.Phase) == "Workshop" then
			refreshList()
		end
	end))
end

function BlueprintBrowserController:KnitStart()
	local HudController = Knit.GetController("HudController")
	local playerGui     = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screenGui     = playerGui:WaitForChild("SlingSiegeHud")

	local janitor       = Janitor.new()

	-- Reactive state scoped to this run, not the module
	local blueprintList = Value({})
	local statusMsg     = Value("")
	local statusIsError = Value(false)

	local function setStatus(msg, isError, clearDelay)
		statusMsg:set(msg)
		statusIsError:set(isError or false)
		if clearDelay then
			task.delay(clearDelay, function() statusMsg:set("") end)
		end
	end

	local function refreshList()
		local bs = Knit.GetService("BlueprintService")
		local data = bs:GetAll()
		blueprintList:set(data or {})
	end

	local scope = scoped(Fusion)
	janitor:Add(function() scope:doCleanup() end)

	buildBrowser(scope, screenGui, HudController, janitor, blueprintList, statusMsg, statusIsError, setStatus, refreshList)
	refreshList()
end

function BlueprintBrowserController:KnitInit() end

return BlueprintBrowserController
