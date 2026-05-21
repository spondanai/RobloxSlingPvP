local StructureGraph = require(script.Parent.StructureGraph)
local BlueprintCodec = require(script.Parent.BlueprintCodec)

local BlueprintValidator = {}

local DEFAULT_CONFIG = {
	maxBlocks = 150,
	gridCols = 10,
	gridRows = 8,
	maxMass = 500,
}

local function getConfigValue(config, key)
	if config ~= nil and config[key] ~= nil then
		return config[key]
	end

	return DEFAULT_CONFIG[key]
end

local function positionKey(x, y, z)
	return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

local function isInteger(value)
	return type(value) == "number" and value % 1 == 0
end

local function isWithinBounds(pos, gridCols, gridRows)
	return isInteger(pos.x)
		and isInteger(pos.y)
		and isInteger(pos.z)
		and pos.x >= 0
		and pos.x < gridCols
		and pos.y >= 0
		and pos.y < gridRows
		and pos.z == 0
end

-- BlueprintValidator.validate(blueprint, config) -> {ok=bool, errors={}}
-- config = { maxBlocks=150, gridCols=10, gridRows=8, maxMass=500, blockDefs={wood={mass=1},...} }
-- Checks in order, collect ALL errors:
--   1. Schema valid (BlueprintCodec.validateSchema)
--   2. Block count <= maxBlocks
--   3. No duplicate positions (same x,y,z)
--   4. All blocks in bounds: 0 <= x < gridCols, 0 <= y < gridRows, z == 0
--   5. All block ids known (wood/stone/metal)
--   6. Total mass <= maxMass  (sum of blockDef.mass for each block)
--   7. No floating blocks (StructureGraph.getUnsupportedBlocks returns empty)
--   8. Core position is within bounds and not occupied by a block
function BlueprintValidator.validate(blueprint, config)
	config = config or {}

	local errors = {}
	local schemaOk, schemaErrors = BlueprintCodec.validateSchema(blueprint)
	for _, errorMessage in ipairs(schemaErrors) do
		errors[#errors + 1] = errorMessage
	end

	if not schemaOk then
		return {
			ok = false,
			errors = errors,
		}
	end

	local maxBlocks = getConfigValue(config, "maxBlocks")
	local gridCols = getConfigValue(config, "gridCols")
	local gridRows = getConfigValue(config, "gridRows")
	local maxMass = getConfigValue(config, "maxMass")
	local blockDefs = config.blockDefs or {}
	local blocks = blueprint.blocks
	local occupied = {}
	local totalMass = 0

	if #blocks > maxBlocks then
		errors[#errors + 1] = "Block count exceeds maxBlocks: " .. tostring(#blocks) .. " > " .. tostring(maxBlocks)
	end

	for index, block in ipairs(blocks) do
		local key = positionKey(block.x, block.y, block.z)

		if occupied[key] ~= nil then
			errors[#errors + 1] = "Duplicate block position at " .. key
		else
			occupied[key] = index
		end
	end

	for index, block in ipairs(blocks) do
		if not isWithinBounds(block, gridCols, gridRows) then
			errors[#errors + 1] = "Block " .. tostring(index) .. " is out of bounds"
		end
	end

	for index, block in ipairs(blocks) do
		local blockDef = blockDefs[block.id]

		if blockDef == nil then
			errors[#errors + 1] = "Unknown block id: " .. tostring(block.id)
		else
			totalMass += blockDef.mass or 0
		end
	end

	if totalMass > maxMass then
		errors[#errors + 1] = "Total mass exceeds maxMass: " .. tostring(totalMass) .. " > " .. tostring(maxMass)
	end

	local graphBlocks = {}
	for index, block in ipairs(blocks) do
		graphBlocks[#graphBlocks + 1] = {
			id = tostring(index),
			x = block.x,
			y = block.y,
			z = block.z,
			blockType = block.id,
		}
	end

	local graph = StructureGraph.build(graphBlocks)
	local unsupportedBlocks = StructureGraph.getUnsupportedBlocks(graph)
	if #unsupportedBlocks > 0 then
		errors[#errors + 1] = "Blueprint contains floating blocks: " .. table.concat(unsupportedBlocks, ", ")
	end

	if not isWithinBounds(blueprint.core, gridCols, gridRows) then
		errors[#errors + 1] = "Core position is out of bounds"
	end

	local coreKey = positionKey(blueprint.core.x, blueprint.core.y, blueprint.core.z)
	if occupied[coreKey] ~= nil then
		errors[#errors + 1] = "Core position is occupied by a block"
	end

	return {
		ok = #errors == 0,
		errors = errors,
	}
end

return BlueprintValidator
