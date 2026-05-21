-- Knit Service: queues players and starts 1v1 matches
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit     = require(Packages.Knit)
local Janitor  = require(Packages.Janitor)

local Shared   = ReplicatedStorage:WaitForChild("Shared")
local Modules  = Shared:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))

local MatchmakingService = Knit.CreateService({
    Name = "MatchmakingService",
    Client = {
        OnQueued      = Knit.CreateSignal(),
        OnMatchFound  = Knit.CreateSignal(),
    },
})

local queue   = {}  -- ordered waiting list
local janitor = Janitor.new()

local function tryMatch()
    if #queue < 2 then return end
    local pA = table.remove(queue, 1)
    local pB = table.remove(queue, 1)

    -- Notify both clients
    MatchmakingService.Client.OnMatchFound:Fire(pA, { team = "A", opponentName = pB.Name })
    MatchmakingService.Client.OnMatchFound:Fire(pB, { team = "B", opponentName = pA.Name })

    -- Register pending match; arena starts only when both players call ReadyUp
    local ArenaService = Knit.GetService("ArenaService")
    ArenaService:SetupPendingMatch(pA, pB)
end

function MatchmakingService:EnqueuePlayer(player)
    for _, p in ipairs(queue) do
        if p == player then return end  -- already queued
    end
    table.insert(queue, player)
    self.Client.OnQueued:Fire(player, #queue)
    tryMatch()
end

function MatchmakingService:DequeuePlayer(player)
    for i = #queue, 1, -1 do
        if queue[i] == player then
            table.remove(queue, i)
            return
        end
    end
end

function MatchmakingService:KnitStart()
    janitor:Add(Players.PlayerAdded:Connect(function(player)
        self:EnqueuePlayer(player)
    end))

    janitor:Add(Players.PlayerRemoving:Connect(function(player)
        self:DequeuePlayer(player)
        -- Let ArenaService handle in-match cleanup
        local ArenaService = Knit.GetService("ArenaService")
        ArenaService:HandlePlayerLeave(player)
    end))
end

function MatchmakingService:KnitInit()
    -- nothing pre-start
end

return MatchmakingService
