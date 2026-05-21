local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Janitor = require(Packages.Janitor)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")

local Players = game:GetService("Players")

local GameConfig          = require(Modules:WaitForChild("GameConfig"))
local BlockDefinitions    = require(Modules:WaitForChild("BlockDefinitions"))
local StructureGraph      = require(Modules:WaitForChild("StructureGraph"))
local BlueprintValidator  = require(Modules:WaitForChild("BlueprintValidator"))

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

local WorkshopService = Knit.CreateService({
	Name = "WorkshopService",
	Client = {
		OnBlockPlaced    = Knit.CreateSignal(),
		OnBlockRemoved   = Knit.CreateSignal(),
		OnCoreSet        = Knit.CreateSignal(),
		OnSessionCleared = Knit.CreateSignal(),
		-- fires with array of {col,row} that are floating (unsupported)
		OnFloatWarning   = Knit.CreateSignal(),
		-- fires with ordered array of {col,row} to collapse (top→bottom)
		OnCollapse       = Knit.CreateSignal(),
	},
})

local sessions = {}

local function makeSession()
	return {
		blocks = {},
		capRemaining = GameConfig.MAX_MASS_BUDGET,
		corePos = nil,
	}
end

local function getSession(player)
	local session = sessions[player]
	if session == nil then
		session = makeSession()
		sessions[player] = session
	end

	return session
end

local function isInteger(value)
	return type(value) == "number" and value % 1 == 0
end

local function isWithinGrid(col, row)
	return isInteger(col)
		and isInteger(row)
		and col >= 0
		and col < GameConfig.GRID_COLS
		and row >= 0
		and row < GameConfig.GRID_ROWS
end

local function getBlockDefinition(typeName)
	if type(typeName) ~= "string" then
		return nil, nil
	end

	for _, blockTypeName in ipairs(BlockDefinitions.Order) do
		local blockDefinition = BlockDefinitions[blockTypeName]
		if blockTypeName == typeName or string.lower(blockTypeName) == string.lower(typeName) then
			return blockTypeName, blockDefinition
		end
	end

	return nil, nil
end

local function findBlockIndex(session, col, row)
	for index, block in ipairs(session.blocks) do
		if block.x == col and block.y == row and block.z == 0 then
			return index, block
		end
	end

	return nil, nil
end

local function isCoreAt(session, col, row)
	local corePos = session.corePos
	return corePos ~= nil and corePos.x == col and corePos.y == row and corePos.z == 0
end

function WorkshopService:GetSession(player)
	return getSession(player)
end

function WorkshopService:PlaceBlock(player, col, row, typeName)
	if not isWithinGrid(col, row) then
		return false, "out of bounds"
	end

	local canonicalTypeName, blockDefinition = getBlockDefinition(typeName)
	if blockDefinition == nil then
		return false, "unknown block type"
	end

	local session = getSession(player)
	if #session.blocks >= GameConfig.MAX_BLOCKS_PER_PLAYER then
		return false, "max blocks reached"
	end

	if session.capRemaining < blockDefinition.cap then
		return false, "not enough cap"
	end

	if findBlockIndex(session, col, row) ~= nil then
		return false, "occupied"
	end

	if isCoreAt(session, col, row) then
		return false, "core occupied"
	end

	session.capRemaining -= blockDefinition.cap
	session.blocks[#session.blocks + 1] = {
		id = string.lower(canonicalTypeName),
		x = col,
		y = row,
		z = 0,
	}

	self.Client.OnBlockPlaced:Fire(player, col, row, canonicalTypeName, session.capRemaining)

	-- Warn about any floating blocks after placement
	local graph     = StructureGraph.build(session.blocks)
	local floating  = StructureGraph.getUnsupportedBlocks(graph)
	if #floating > 0 then
		local positions = {}
		for _, bid in ipairs(floating) do
			local b = session.blocks[bid]
			if b then positions[#positions + 1] = { col = b.x, row = b.y } end
		end
		self.Client.OnFloatWarning:Fire(player, positions)
	end

	return true, session.capRemaining
end

function WorkshopService:RemoveBlock(player, col, row)
	if not isWithinGrid(col, row) then
		return false, "out of bounds"
	end

	local session = getSession(player)
	local blockIndex, block = findBlockIndex(session, col, row)
	if blockIndex == nil then
		return false, "not found"
	end

	-- Build graph BEFORE removal to find which blocks will collapse
	local graphBefore = StructureGraph.build(session.blocks)
	-- Use block position as id (index in session.blocks)
	local collapseChain = StructureGraph.getCollapseChain(graphBefore, blockIndex)

	-- Refund cap for the removed block
	local _, blockDefinition = getBlockDefinition(block.id)
	if blockDefinition ~= nil then
		session.capRemaining = math.min(
			GameConfig.MAX_MASS_BUDGET,
			session.capRemaining + blockDefinition.cap
		)
	end
	table.remove(session.blocks, blockIndex)

	self.Client.OnBlockRemoved:Fire(player, col, row, session.capRemaining)

	-- Cascade: remove all collapsed blocks (high→low so indices stay valid)
	if #collapseChain > 0 then
		-- collapseChain is ordered highest-y first; indices shift as we remove
		-- so rebuild lookup by position
		local collapsePositions = {}
		for _, cid in ipairs(collapseChain) do
			-- cid was index before removal; shift if needed
			local adjustedId = cid > blockIndex and cid - 1 or cid
			local cb = session.blocks[adjustedId]
			if cb then
				collapsePositions[#collapsePositions + 1] = { col = cb.x, row = cb.y, id = cb.id }
			end
		end

		-- Sort top-down (highest row first) for visual order
		table.sort(collapsePositions, function(a, b) return a.row > b.row end)

		-- Remove from session (iterate in reverse to preserve indices)
		for i = #collapsePositions, 1, -1 do
			local cp = collapsePositions[i]
			local idx = findBlockIndex(session, cp.col, cp.row)
			if idx then
				local _, cbd = getBlockDefinition(session.blocks[idx].id)
				if cbd then
					session.capRemaining = math.min(
						GameConfig.MAX_MASS_BUDGET,
						session.capRemaining + cbd.cap
					)
				end
				table.remove(session.blocks, idx)
			end
		end

		self.Client.OnCollapse:Fire(player, collapsePositions, session.capRemaining)
	end

	return true, session.capRemaining
end

function WorkshopService:SetCore(player, col, row)
	if not isWithinGrid(col, row) then
		return false, "out of bounds"
	end

	local session = getSession(player)
	if findBlockIndex(session, col, row) ~= nil then
		return false, "occupied"
	end

	session.corePos = {
		x = col,
		y = row,
		z = 0,
	}

	self.Client.OnCoreSet:Fire(player, col, row)
	return true, session.corePos
end

function WorkshopService:ClearSession(player)
	sessions[player] = makeSession()
	self.Client.OnSessionCleared:Fire(player)
	return true
end

function WorkshopService:LoadBlueprint(player, index)
	local BlueprintService = Knit.GetService("BlueprintService")
	local data, err = BlueprintService:Load(player, index)
	if not data then return false, err end

	local session = sessions[player]
	if not session then
		session = makeSession()
		sessions[player] = session
	end

	session.blocks = data.blocks
	session.corePos = data.core
	
	-- Recalculate cap
	session.capRemaining = GameConfig.MAX_MASS_BUDGET
	for _, block in ipairs(session.blocks) do
		local _, def = getBlockDefinition(block.id)
		if def then
			session.capRemaining -= def.cap
		end
	end

	self.Client.OnSessionCleared:Fire(player)

	for _, block in ipairs(session.blocks) do
		local canonicalName = getBlockDefinition(block.id)
		self.Client.OnBlockPlaced:Fire(player, block.x, block.y, canonicalName, session.capRemaining)
	end

	if session.corePos then
		self.Client.OnCoreSet:Fire(player, session.corePos.x, session.corePos.y)
	end

	return true
end

function WorkshopService.Client:PlaceBlock(player, col, row, typeName)
	return WorkshopService:PlaceBlock(player, col, row, typeName)
end

function WorkshopService.Client:RemoveBlock(player, col, row)
	return WorkshopService:RemoveBlock(player, col, row)
end

function WorkshopService.Client:SetCore(player, col, row)
	return WorkshopService:SetCore(player, col, row)
end

function WorkshopService.Client:GetSession(player)
	return WorkshopService:GetSession(player)
end

-- Public server method — safe to call from other services (e.g. ArenaService:ReadyUp)
function WorkshopService:ValidateSession(player)
	local session = getSession(player)
	if not session.corePos then
		return { ok = false, errors = { "core not set" } }
	end
	local blueprint = {
		version = 1,
		blocks  = session.blocks,
		core    = session.corePos,
	}
	return BlueprintValidator.validate(blueprint, VALIDATOR_CONFIG)
end

-- Client RPC wrapper
function WorkshopService.Client:Validate(player)
	return self.Server:ValidateSession(player)
end

function WorkshopService.Client:ClearSession(player)
	return WorkshopService:ClearSession(player)
end

function WorkshopService.Client:LoadBlueprint(player, index)
	return WorkshopService:LoadBlueprint(player, index)
end

function WorkshopService:KnitInit()
	self._janitor = Janitor.new()
	self._janitor:Add(Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end), "Disconnect")
end

function WorkshopService:KnitStart() end

return WorkshopService
