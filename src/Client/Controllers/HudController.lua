-- Knit Controller: Reactive HUD powered by Fusion v0.3
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages  = ReplicatedStorage:WaitForChild("Packages")
local Knit      = require(Packages.Knit)
local Janitor   = require(Packages.Janitor)
local Fusion    = require(Packages.Fusion)

local Shared    = ReplicatedStorage:WaitForChild("Shared")
local Modules   = Shared:WaitForChild("Modules")
local BlockDefinitions = require(Modules:WaitForChild("BlockDefinitions"))
local AmmoDefinitions  = require(Modules:WaitForChild("AmmoDefinitions"))
local GameConfig       = require(Modules:WaitForChild("GameConfig"))

local scoped    = Fusion.scoped
local Children  = Fusion.Children
local Value     = Fusion.Value
local Computed  = Fusion.Computed
local peek      = Fusion.peek

local HudController = Knit.CreateController({ Name = "HudController" })
local janitor = Janitor.new()

-- ── Reactive state ────────────────────────────────────────────────────────────
HudController.State = {
    Phase       = Value("Waiting"),   -- "Waiting"|"Workshop"|"Arena"|"GameOver"
    MyTeam      = Value(nil),         -- "A"|"B"
    BuildCap    = Value(GameConfig.MAX_MASS_BUDGET),
    Resources   = Value(0),
    IsMyTurn    = Value(false),
    CurrentTurn = Value("A"),
    SelectedBlock = Value("Wood"),
    SelectedAmmo  = Value("Rock"),
}

-- ── Colour helpers ────────────────────────────────────────────────────────────
local C = {
    bg      = Color3.fromRGB(12, 12, 18),
    panel   = Color3.fromRGB(25, 25, 38),
    border  = Color3.fromRGB(60, 60, 90),
    teamA   = Color3.fromRGB(60,  120, 220),
    teamB   = Color3.fromRGB(220, 60,  60),
    gold    = Color3.fromRGB(255, 200, 0),
    green   = Color3.fromRGB(60,  210, 80),
    red     = Color3.fromRGB(220, 60,  60),
    white   = Color3.new(1, 1, 1),
}

-- ── Fusion UI builder ─────────────────────────────────────────────────────────
local function buildHud(scope, screenGui)

    -- Helper: create a rounded frame
    local function Panel(s, props)
        local callerChildren = props[Children] or {}
        local mergedChildren = {
            s:New "UICorner" { CornerRadius = UDim.new(0, 10) },
            s:New "UIStroke" { Color = C.border, Thickness = 1 },
        }
        for _, v in ipairs(callerChildren) do
            mergedChildren[#mergedChildren + 1] = v
        end
        local merged = { BackgroundColor3 = C.panel, BorderSizePixel = 0 }
        for k, v in pairs(props) do merged[k] = v end
        merged[Children] = mergedChildren
        return s:New "Frame" (merged)
    end

    -- ── QUEUE / WAITING screen ─────────────────────────────────────────────
    local waitingScreen = scope:New "Frame" {
        Name             = "WaitingScreen",
        Size             = UDim2.new(1,0,1,0),
        BackgroundColor3 = C.bg,
        BackgroundTransparency = 0.3,
        Visible          = Computed(scope, function(use)
            return use(HudController.State.Phase) == "Waiting"
        end),
        [Children] = {
            scope:New "TextLabel" {
                Size = UDim2.new(0,400,0,60),
                Position = UDim2.new(0.5,-200,0.5,-30),
                BackgroundTransparency = 1,
                Text = "กำลังรอคู่ต่อสู้...",
                TextColor3 = C.gold,
                Font = Enum.Font.GothamBold,
                TextScaled = true,
            },
        },
        Parent = screenGui,
    }

    -- ── WORKSHOP HUD ───────────────────────────────────────────────────────
    local workshopHud = scope:New "Frame" {
        Name    = "WorkshopHud",
        Size    = UDim2.new(1,0,1,0),
        BackgroundTransparency = 1,
        Visible = Computed(scope, function(use)
            return use(HudController.State.Phase) == "Workshop"
        end),
        Parent  = screenGui,
    }

    -- Cap bar (top center)
    Panel(scope, {
        Name     = "CapBar",
        Size     = UDim2.new(0,300,0,48),
        Position = UDim2.new(0.5,-150,0,12),
        Parent   = workshopHud,
        [Children] = {
            scope:New "TextLabel" {
                Size = UDim2.new(1,0,1,0),
                BackgroundTransparency = 1,
                TextColor3 = C.gold,
                Font = Enum.Font.GothamBold,
                TextScaled = true,
                Text = Computed(scope, function(use)
                    return "Cap เหลือ: " .. use(HudController.State.BuildCap)
                end),
            },
        },
    })

    -- Hint label
    scope:New "TextLabel" {
        Name     = "Hint",
        Size     = UDim2.new(0,500,0,28),
        Position = UDim2.new(0.5,-250,0,68),
        BackgroundTransparency = 1,
        TextColor3 = C.white,
        Font = Enum.Font.Gotham,
        TextScaled = true,
        Text = "คลิก = วางบล็อก  |  คลิกขวา = ลบบล็อก",
        Parent = workshopHud,
    }

    -- Block selector (bottom center)
    local blockPanel = Panel(scope, {
        Name     = "BlockPanel",
        Size     = UDim2.new(0, (#BlockDefinitions.Order * 120) + 20, 0, 100),
        Position = UDim2.new(0.5, -(#BlockDefinitions.Order * 60), 1, -118),
        Parent   = workshopHud,
    })

    for i, name in ipairs(BlockDefinitions.Order) do
        local def = BlockDefinitions[name]
        local isSelected = Computed(scope, function(use)
            return use(HudController.State.SelectedBlock) == name
        end)

        scope:New "TextButton" {
            Name     = "Btn_" .. name,
            Size     = UDim2.new(0,110,0,80),
            Position = UDim2.new(0, 5 + (i-1)*115, 0, 10),
            BackgroundColor3 = def.color,
            Text     = def.displayName .. "\n(" .. def.cap .. " cap)",
            TextColor3 = C.white,
            Font     = Enum.Font.GothamBold,
            TextScaled = true,
            BorderSizePixel = Computed(scope, function(use)
                return use(isSelected) and 3 or 0
            end),
            Parent   = blockPanel,
            [Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0,6) } },
            [Fusion.OnEvent "MouseButton1Click"] = function()
                HudController.State.SelectedBlock:set(name)
                -- Tell WorkshopController
                local wc = Knit.GetController("WorkshopController")
                if wc then wc.selectedType = name end
            end,
        }
    end

    -- Validation feedback label (shows errors from server)
    local validateMsg = Value("")
    local validateColor = Value(C.red)

    scope:New "TextLabel" {
        Name     = "ValidateMsg",
        Size     = UDim2.new(0,300,0,36),
        Position = UDim2.new(1,-320,1,-100),
        BackgroundTransparency = 1,
        TextColor3 = Computed(scope, function(use) return use(validateColor) end),
        Font     = Enum.Font.Gotham,
        TextScaled = true,
        Text     = Computed(scope, function(use) return use(validateMsg) end),
        Parent   = workshopHud,
    }

    -- Test-Fire toggle button
    local testFireActive = Value(false)
    scope:New "TextButton" {
        Name     = "TestFireBtn",
        Size     = UDim2.new(0,140,0,44),
        Position = UDim2.new(1,-310,1,-55),
        BackgroundColor3 = Computed(scope, function(use)
            return use(testFireActive) and C.red or Color3.fromRGB(80, 120, 220)
        end),
        Text = Computed(scope, function(use)
            return use(testFireActive) and "ออกโหมดทดสอบ" or "ทดสอบยิง"
        end),
        TextColor3 = C.white,
        Font       = Enum.Font.GothamBold,
        TextScaled = true,
        Parent     = workshopHud,
        [Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0,8) } },
        [Fusion.OnEvent "MouseButton1Click"] = function()
            local tfc = Knit.GetController("TestFireController")
            if not tfc then return end
            if tfc.active then
                tfc:ExitTestFire()
                testFireActive:set(false)
            else
                tfc:EnterTestFire()
                testFireActive:set(true)
            end
        end,
    }

    -- Submit button — runs server validation before saving
    scope:New "TextButton" {
        Name     = "SubmitBtn",
        Size     = UDim2.new(0,140,0,44),
        Position = UDim2.new(1,-155,1,-55),
        BackgroundColor3 = C.green,
        Text     = "ส่งฐาน ✓",
        TextColor3 = C.white,
        Font     = Enum.Font.GothamBold,
        TextScaled = true,
        Parent   = workshopHud,
        [Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0,8) } },
        [Fusion.OnEvent "MouseButton1Click"] = function()
            local ws = Knit.GetService("WorkshopService")
            local bs = Knit.GetService("BlueprintService")
            if not ws or not bs then return end

            -- Server-side validate first
            local result = ws:Validate()
            if not result then return end

            if not result.ok then
                validateColor:set(C.red)
                validateMsg:set("❌ " .. (result.errors[1] or "โครงสร้างไม่ผ่าน"))
                task.delay(3, function() validateMsg:set("") end)
                return
            end

            -- Validation passed → save, then signal ready to fight
            local ok, idxOrErr = bs:Save()
            if ok then
                validateColor:set(C.green)
                validateMsg:set("✓ บันทึกแล้ว รอคู่ต่อสู้...")
                -- Stay visible until phase changes; ReadyUp triggers match start when both ready
                local readyOk, readyErr = Knit.GetService("ArenaService"):ReadyUp()
                if not readyOk then
                    validateColor:set(C.red)
                    validateMsg:set("❌ " .. tostring(readyErr or "ส่งไม่ได้"))
                    task.delay(3, function() validateMsg:set("") end)
                end
            else
                validateColor:set(C.red)
                validateMsg:set("❌ " .. tostring(idxOrErr))
                task.delay(2.5, function() validateMsg:set("") end)
            end
        end,
    }

    -- ── ARENA HUD ─────────────────────────────────────────────────────────
    local arenaHud = scope:New "Frame" {
        Name    = "ArenaHud",
        Size    = UDim2.new(1,0,1,0),
        BackgroundTransparency = 1,
        Visible = Computed(scope, function(use)
            return use(HudController.State.Phase) == "Arena"
        end),
        Parent  = screenGui,
    }

    -- Resource + turn indicator (top center)
    Panel(scope, {
        Name     = "TurnBar",
        Size     = UDim2.new(0,360,0,52),
        Position = UDim2.new(0.5,-180,0,12),
        Parent   = arenaHud,
        [Children] = {
            scope:New "TextLabel" {
                Size = UDim2.new(0.55,0,1,0),
                BackgroundTransparency = 1,
                TextColor3 = Computed(scope, function(use)
                    return use(HudController.State.IsMyTurn) and C.green or C.red
                end),
                Font = Enum.Font.GothamBold,
                TextScaled = true,
                Text = Computed(scope, function(use)
                    return use(HudController.State.IsMyTurn) and "เทิร์นของคุณ!" or "รอ..."
                end),
            },
            scope:New "TextLabel" {
                Size     = UDim2.new(0.45,0,1,0),
                Position = UDim2.new(0.55,0,0,0),
                BackgroundTransparency = 1,
                TextColor3 = C.gold,
                Font = Enum.Font.GothamBold,
                TextScaled = true,
                Text = Computed(scope, function(use)
                    return "⚡ " .. use(HudController.State.Resources)
                end),
            },
        },
    })

    -- Ammo selector (bottom center)
    local ammoPanel = Panel(scope, {
        Name     = "AmmoPanel",
        Size     = UDim2.new(0, (#AmmoDefinitions.Order * 130) + 20, 0, 100),
        Position = UDim2.new(0.5, -(#AmmoDefinitions.Order * 65), 1, -118),
        Parent   = arenaHud,
    })

    for i, name in ipairs(AmmoDefinitions.Order) do
        local def = AmmoDefinitions[name]
        local btnColor = (def.color == Color3.fromRGB(20,20,20))
            and Color3.fromRGB(55,55,65) or def.color

        scope:New "TextButton" {
            Name     = "Ammo_" .. name,
            Size     = UDim2.new(0,120,0,80),
            Position = UDim2.new(0, 5 + (i-1)*125, 0, 10),
            BackgroundColor3 = btnColor,
            Text     = def.displayName .. "\n(cost " .. def.resourceCost .. ")",
            TextColor3 = C.white,
            Font     = Enum.Font.GothamBold,
            TextScaled = true,
            BorderSizePixel = Computed(scope, function(use)
                return use(HudController.State.SelectedAmmo) == name and 3 or 0
            end),
            Parent   = ammoPanel,
            [Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0,6) } },
            [Fusion.OnEvent "MouseButton1Click"] = function()
                HudController.State.SelectedAmmo:set(name)
                local ac = Knit.GetController("ArenaController")
                if ac then ac.selectedAmmo = name end
            end,
        }
    end

    -- End Turn button
    scope:New "TextButton" {
        Name     = "EndTurnBtn",
        Size     = UDim2.new(0,130,0,44),
        Position = UDim2.new(1,-148,1,-55),
        BackgroundColor3 = C.green,
        Text     = "จบเทิร์น",
        TextColor3 = C.white,
        Font     = Enum.Font.GothamBold,
        TextScaled = true,
        Visible  = Computed(scope, function(use)
            return use(HudController.State.IsMyTurn)
        end),
        Parent   = arenaHud,
        [Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0,8) } },
        [Fusion.OnEvent "MouseButton1Click"] = function()
            local ac = Knit.GetController("ArenaController")
            if ac then ac:EndTurn() end
        end,
    }

    -- ── GAME OVER screen ───────────────────────────────────────────────────
    local gameOverScreen = scope:New "Frame" {
        Name    = "GameOverScreen",
        Size    = UDim2.new(1,0,1,0),
        BackgroundColor3 = C.bg,
        BackgroundTransparency = 0.25,
        Visible = Computed(scope, function(use)
            return use(HudController.State.Phase) == "GameOver"
        end),
        Parent  = screenGui,
        [Children] = {
            scope:New "TextLabel" {
                Size     = UDim2.new(0,500,0,80),
                Position = UDim2.new(0.5,-250,0.5,-40),
                BackgroundTransparency = 1,
                TextColor3 = C.gold,
                Font = Enum.Font.GothamBold,
                TextScaled = true,
                Text = Computed(scope, function(use)
                    local team   = use(HudController.State.MyTeam)
                    local turn   = use(HudController.State.CurrentTurn)
                    if team == nil then return "" end
                    -- CurrentTurn repurposed as winner team in GameOver
                    return turn == team and "ชนะแล้ว! 🏆" or "แพ้แล้ว... 💀"
                end),
            },
        },
    }
end

-- ── Knit lifecycle ────────────────────────────────────────────────────────────
function HudController:KnitStart()
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name          = "SlingSiegeHud"
    screenGui.ResetOnSpawn  = false
    screenGui.ZIndexBehavior= Enum.ZIndexBehavior.Sibling
    screenGui.Parent        = playerGui

    local scope = scoped(Fusion)
    janitor:Add(function() scope:doCleanup() end)
    buildHud(scope, screenGui)

    -- Transition Waiting → Workshop when a match is found
    local MatchmakingService = Knit.GetService("MatchmakingService")
    janitor:Add(MatchmakingService.OnMatchFound:Connect(function(data)
        HudController.State.MyTeam:set(data.team)
        HudController.State.Phase:set("Workshop")
    end))
end

function HudController:KnitInit() end

return HudController
