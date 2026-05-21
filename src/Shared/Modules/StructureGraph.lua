local StructureGraph = {}

local DIRECTIONS = {
	{ 1, 0, 0 }, { -1, 0, 0 },
	{ 0, 1, 0 }, { 0, -1, 0 },
	{ 0, 0, 1 }, { 0, 0, -1 },
}

local function positionKey(x, y, z)
	return x .. ":" .. y .. ":" .. z
end

local function cloneBlock(block)
	return { id = block.id, x = block.x, y = block.y, z = block.z }
end

local function floodSupported(graph)
	local reached = {}
	local queue   = {}
	local head    = 1
	for _, id in ipairs(graph.grounded) do
		reached[id] = true
		queue[#queue + 1] = id
	end
	while head <= #queue do
		local id = queue[head]; head += 1
		for neighborId in pairs(graph.adjacency[id] or {}) do
			if not reached[neighborId] then
				reached[neighborId] = true
				queue[#queue + 1] = neighborId
			end
		end
	end
	return reached
end

-- build(blocks) → graph
-- blockId = integer index into the blocks array (stable, unique per block)
function StructureGraph.build(blocks)
	local graph = {
		blocks    = {},   -- [blockId] = block data
		blockOrder= {},   -- ordered list of blockIds
		positions = {},   -- posKey → blockId
		adjacency = {},   -- [blockId] = {neighborId=true,...}
		grounded  = {},
		supported = {},
	}

	for i, block in ipairs(blocks or {}) do
		local blockId   = i  -- integer index, unique per block regardless of type
		local blockCopy = cloneBlock(block)

		graph.blocks[blockId]     = blockCopy
		graph.blockOrder[i]       = blockId
		graph.positions[positionKey(blockCopy.x, blockCopy.y, blockCopy.z)] = blockId
		graph.adjacency[blockId]  = {}

		if blockCopy.y == 0 then
			graph.grounded[#graph.grounded + 1] = blockId
		end
	end

	for _, blockId in ipairs(graph.blockOrder) do
		local block = graph.blocks[blockId]
		for _, dir in ipairs(DIRECTIONS) do
			local nKey = positionKey(block.x + dir[1], block.y + dir[2], block.z + dir[3])
			local nId  = graph.positions[nKey]
			if nId ~= nil then
				graph.adjacency[blockId][nId] = true
			end
		end
	end

	graph.supported = floodSupported(graph)
	return graph
end

function StructureGraph.isSupported(graph, blockId)
	return graph.supported[blockId] == true
end

-- getUnsupportedBlocks(graph) → array of blockIds (integer indices into original blocks array)
function StructureGraph.getUnsupportedBlocks(graph)
	local reached     = floodSupported(graph)
	local unsupported = {}
	for _, blockId in ipairs(graph.blockOrder) do
		if not reached[blockId] then
			unsupported[#unsupported + 1] = blockId
		end
	end
	return unsupported
end

-- removeBlock(graph, blockId) → newGraph
function StructureGraph.removeBlock(graph, blockId)
	local blocks = {}
	for _, existingId in ipairs(graph.blockOrder) do
		if existingId ~= blockId then
			blocks[#blocks + 1] = cloneBlock(graph.blocks[existingId])
		end
	end
	return StructureGraph.build(blocks)
end

-- getCollapseChain(graph, removedBlockId) → array of original blockIds, highest-y first
-- Returns blocks that WERE supported but become unsupported after removal.
-- IDs are indices into the ORIGINAL blocks array (same as those stored in graph.blockOrder).
function StructureGraph.getCollapseChain(graph, removedBlockId)
	local afterGraph      = StructureGraph.removeBlock(graph, removedBlockId)
	local unsupportedNew  = StructureGraph.getUnsupportedBlocks(afterGraph)
	local collapseChain   = {}

	for _, newId in ipairs(unsupportedNew) do
		local b = afterGraph.blocks[newId]
		if b then
			-- Map back to original graph via position (position is unchanged by removal)
			local origId = graph.positions[positionKey(b.x, b.y, b.z)]
			if origId and graph.supported[origId] then
				collapseChain[#collapseChain + 1] = origId
			end
		end
	end

	-- Sort highest-y first (top falls before bottom visually)
	table.sort(collapseChain, function(a, b)
		local ba, bb = graph.blocks[a], graph.blocks[b]
		if ba.y ~= bb.y then return ba.y > bb.y end
		return a < b
	end)

	return collapseChain
end

return StructureGraph
