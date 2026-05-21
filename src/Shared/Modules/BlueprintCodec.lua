local BlueprintCodec = {}

local function isArray(value)
	if type(value) ~= "table" then
		return false
	end

	local count = 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end

		count += 1
	end

	return count == #value
end

local function integerCoord(value)
	return math.floor(value)
end

local function appendSchemaErrors(data, errors)
	if type(data) ~= "table" then
		errors[#errors + 1] = "Blueprint must be a table"
		return
	end

	if data.version == nil then
		errors[#errors + 1] = "Blueprint version is required"
	end

	if not isArray(data.blocks) then
		errors[#errors + 1] = "Blueprint blocks must be an array"
	else
		for index, block in ipairs(data.blocks) do
			local prefix = "Block " .. tostring(index)

			if type(block) ~= "table" then
				errors[#errors + 1] = prefix .. " must be a table"
			else
				if type(block.id) ~= "string" then
					errors[#errors + 1] = prefix .. " id must be a string"
				end

				if type(block.x) ~= "number" then
					errors[#errors + 1] = prefix .. " x must be a number"
				end

				if type(block.y) ~= "number" then
					errors[#errors + 1] = prefix .. " y must be a number"
				end

				if type(block.z) ~= "number" then
					errors[#errors + 1] = prefix .. " z must be a number"
				end
			end
		end
	end

	if type(data.core) ~= "table" then
		errors[#errors + 1] = "Blueprint core must be a table"
	else
		if type(data.core.x) ~= "number" then
			errors[#errors + 1] = "Core x must be a number"
		end

		if type(data.core.y) ~= "number" then
			errors[#errors + 1] = "Core y must be a number"
		end

		if type(data.core.z) ~= "number" then
			errors[#errors + 1] = "Core z must be a number"
		end
	end
end

-- BlueprintCodec.encode(blocks, corePos) -> table
--   Returns {version=1, blocks={{id,x,y,z},...}, core={x,y,z}}
--   Strips unknown fields, ensures integer coords
function BlueprintCodec.encode(blocks, corePos)
	local encodedBlocks = {}

	for _, block in ipairs(blocks or {}) do
		encodedBlocks[#encodedBlocks + 1] = {
			id = block.id,
			x = integerCoord(block.x),
			y = integerCoord(block.y),
			z = integerCoord(block.z),
		}
	end

	return {
		version = 1,
		blocks = encodedBlocks,
		core = {
			x = integerCoord(corePos.x),
			y = integerCoord(corePos.y),
			z = integerCoord(corePos.z),
		},
	}
end

-- BlueprintCodec.decode(data) -> blocks, corePos, errorMsg
--   Returns nil,nil,errMsg on failure
function BlueprintCodec.decode(data)
	local ok, schemaErrors = BlueprintCodec.validateSchema(data)
	if not ok then
		return nil, nil, table.concat(schemaErrors, "; ")
	end

	local migratedData, migrateError = BlueprintCodec.migrate(data)
	if migratedData == nil then
		return nil, nil, migrateError
	end

	local blocks = {}
	for _, block in ipairs(migratedData.blocks) do
		blocks[#blocks + 1] = {
			id = block.id,
			x = integerCoord(block.x),
			y = integerCoord(block.y),
			z = integerCoord(block.z),
		}
	end

	local corePos = {
		x = integerCoord(migratedData.core.x),
		y = integerCoord(migratedData.core.y),
		z = integerCoord(migratedData.core.z),
	}

	return blocks, corePos, nil
end

-- BlueprintCodec.validateSchema(data) -> ok, errors[]
--   Check version exists, blocks is array, each block has id(string)/x/y/z(numbers), core has x/y/z
function BlueprintCodec.validateSchema(data)
	local errors = {}
	appendSchemaErrors(data, errors)

	return #errors == 0, errors
end

-- BlueprintCodec.migrate(data) -> data
--   Stub: if version==1 return data unchanged; else error
function BlueprintCodec.migrate(data)
	if type(data) ~= "table" then
		return nil, "Blueprint must be a table"
	end

	if data.version == 1 then
		return data
	end

	return nil, "Unsupported blueprint version: " .. tostring(data.version)
end

return BlueprintCodec
