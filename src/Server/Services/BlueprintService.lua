-- Knit Service: save/load player blueprints via ProfileService
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

local Packages       = ReplicatedStorage:WaitForChild("Packages")
local ServerPackages = ServerStorage:WaitForChild("ServerPackages")
local Knit           = require(Packages.Knit)

local Shared   = ReplicatedStorage:WaitForChild("Shared")
local Modules  = Shared:WaitForChild("Modules")
local GameConfig        = require(Modules:WaitForChild("GameConfig"))
local BlueprintCodec    = require(Modules:WaitForChild("BlueprintCodec"))
local BlueprintValidator= require(Modules:WaitForChild("BlueprintValidator"))
local BlockDefinitions  = require(Modules:WaitForChild("BlockDefinitions"))

local ProfileService = require(ServerPackages:WaitForChild("ProfileService"))

local PROFILE_TEMPLATE = {
    blueprints = {},   -- array of encoded blueprint tables (max 5)
    currency   = 0,
}

local ProfileStore = ProfileService.GetProfileStore("PlayerData_v1", PROFILE_TEMPLATE)
local profiles = {}  -- [player] = profile

local VALIDATOR_CONFIG = {
    maxBlocks = GameConfig.MAX_BLOCKS_PER_PLAYER,
    gridCols  = GameConfig.GRID_COLS,
    gridRows  = GameConfig.GRID_ROWS,
    maxMass   = GameConfig.MAX_MASS_BUDGET,
    blockDefs = {
        wood  = { mass = BlockDefinitions.Wood.mass  },
        stone = { mass = BlockDefinitions.Stone.mass },
        metal = { mass = BlockDefinitions.Metal.mass },
    },
}
local BlueprintService = Knit.CreateService({
    Name = "BlueprintService",
    Client = {
        OnBlueprintSaved = Knit.CreateSignal(),
    },
})

local function getWorkshopService()
    return Knit.GetService("WorkshopService")
end

-- ── Profile lifecycle ────────────────────────────────────────────────────────

local function loadProfile(player)
    local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)
    if not profile then
        player:Kick("Profile load failed. Please rejoin.")
        return
    end
    profile:AddUserId(player.UserId)
    profile:Reconcile()
    profile:ListenToRelease(function()
        profiles[player] = nil
    end)
    if player.Parent then
        profiles[player] = profile
    else
        profile:Release()
    end
end

function BlueprintService:GetProfile(player)
    return profiles[player]
end

-- ── Public API ───────────────────────────────────────────────────────────────

local function getBlueprintMetadata(profile)
    local result = {}
    for i, bp in ipairs(profile.Data.blueprints) do
        result[i] = {
            index      = i,
            name       = bp.name or ("Blueprint " .. i),
            blockCount = bp.blocks and #bp.blocks or 0,
            version    = bp.version,
        }
    end
    return result
end

function BlueprintService:GetAllForPlayer(player)
    local profile = profiles[player]
    if not profile then return nil, "no profile" end
    return getBlueprintMetadata(profile)
end

-- Returns all saved blueprints (decoded metadata only, not full blocks)
function BlueprintService.Client:GetAll(player)
    return BlueprintService:GetAllForPlayer(player)
end

-- Validate + save a blueprint submitted from Workshop
function BlueprintService.Client:Save(player, rawBlocks, corePos, name)
    local profile = profiles[player]
    if not profile then return false, "no profile" end
    if #profile.Data.blueprints >= GameConfig.MAX_SAVED_BLUEPRINTS then
        return false, "max blueprints reached (" .. GameConfig.MAX_SAVED_BLUEPRINTS .. ")"
    end

    if name == nil and corePos == nil and type(rawBlocks) == "string" then
        name = rawBlocks
    end

    local session = getWorkshopService():GetSession(player)
    rawBlocks = session.blocks
    corePos = session.corePos

    if not corePos then
        return false, "core not set"
    end

    local encoded = BlueprintCodec.encode(rawBlocks, corePos)
    local result  = BlueprintValidator.validate(encoded, VALIDATOR_CONFIG)
    if not result.ok then
        return false, result.errors
    end

    encoded.name = tostring(name or ""):sub(1, 32)
    table.insert(profile.Data.blueprints, encoded)

    local index = #profile.Data.blueprints
    BlueprintService.Client.OnBlueprintSaved:Fire(player, index, encoded.name)

    return true, index
end

-- Load a blueprint by index (returns full blocks array for Arena/Workshop)
function BlueprintService.Client:Load(player, index)
    local profile = profiles[player]
    if not profile then return nil, "no profile" end
    local bp = profile.Data.blueprints[index]
    if not bp then return nil, "not found" end
    local blocks, corePos, err = BlueprintCodec.decode(bp)
    if err then return nil, err end
    return { blocks = blocks, core = corePos, name = bp.name }
end

-- Delete a saved blueprint by index
function BlueprintService.Client:Delete(player, index)
    local profile = profiles[player]
    if not profile then return false end
    if not profile.Data.blueprints[index] then return false end
    table.remove(profile.Data.blueprints, index)
    return true
end

-- ── Knit lifecycle ───────────────────────────────────────────────────────────

function BlueprintService:KnitInit()
    game:GetService("Players").PlayerAdded:Connect(loadProfile)
    game:GetService("Players").PlayerRemoving:Connect(function(player)
        local profile = profiles[player]
        if profile then profile:Release() end
    end)
end

function BlueprintService:KnitStart()
    getWorkshopService()
end

return BlueprintService
