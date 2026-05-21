local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit     = require(Packages.Knit)
local Janitor  = require(Packages.Janitor)

local Shared   = ReplicatedStorage:WaitForChild("Shared")
local Modules  = Shared:WaitForChild("Modules")
local GameConfig       = require(Modules:WaitForChild("GameConfig"))
local BlockDefinitions = require(Modules:WaitForChild("BlockDefinitions"))
local AmmoDefinitions  = require(Modules:WaitForChild("AmmoDefinitions"))
local DamageModel      = require(Modules:WaitForChild("DamageModel"))
local ProjectileModule = require(Modules:WaitForChild("ProjectileModule"))

local ArenaService = Knit.CreateService({
	Name = "ArenaService",
	Client = {
		OnGameState          = Knit.CreateSignal(),
		OnTurnChanged        = Knit.CreateSignal(),
		OnHit                = Knit.CreateSignal(),
		OnCollapse           = Knit.CreateSignal(),
		OnMatchOver          = Knit.CreateSignal(),
		OnWaitingForOpponent = Knit.CreateSignal(),
	},
})

local activeSessions = {}   -- [playerA] = match session
local pendingMatches  = {}  -- [playerA] = { players={A,B}, ready={} }

local CORE_HP          = GameConfig.CORE_HP or 500
local RESOURCES_BASE   = GameConfig.RESOURCES_BASE   or 3
local RESOURCES_INC    = GameConfig.RESOURCES_PER_TURN_INCREASE or 1
local RESOURCES_MAX    = GameConfig.MAX_RESOURCES     or 8
local BLOCK_SIZE       = GameConfig.BLOCK_SIZE        or 4

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getWorkshopService()
	return Knit.GetService("WorkshopService")
end

local function blockKey(col, row)
	return col .. "_" .. row
end

local function getBlockDef(id)
	for _, name in ipairs(BlockDefinitions.Order) do
		if string.lower(name) == string.lower(id) then
			return BlockDefinitions[name]
		end
	end
	return nil
end

local function buildTeamData(session)
	local blockHp = {}
	-- Shallow-copy blocks so arena data is independent of the workshop session
	local blocks = { table.unpack(session.blocks) }
	for _, b in ipairs(blocks) do
		local def = getBlockDef(b.id)
		blockHp[blockKey(b.x, b.y)] = def and def.hp or 60
	end
	return {
		blocks  = blocks,
		corePos = session.corePos,
		coreHp  = CORE_HP,
		blockHp = blockHp,
	}
end

local function sessionForPlayer(player)
	for _, s in pairs(activeSessions) do
		if s.players.A == player or s.players.B == player then
			return s, (s.players.A == player) and "A" or "B"
		end
	end
	return nil, nil
end

local function nextResources(session, team)
	local base = RESOURCES_BASE + (session.turnNumber - 1) * RESOURCES_INC
	return math.min(base, RESOURCES_MAX)
end

-- ── Match lifecycle ───────────────────────────────────────────────────────────

-- Called by MatchmakingService after pairing — waits for both players to ReadyUp
function ArenaService:SetupPendingMatch(playerA, playerB)
	pendingMatches[playerA] = { players = { A = playerA, B = playerB }, ready = {} }
end

-- Client RPC: player signals they finished building and are ready to fight
function ArenaService.Client:ReadyUp(player)
	-- Server-side guard: reject invalid builds regardless of what the client claims
	local ws = getWorkshopService()
	local validation = ws:ValidateSession(player)
	if not validation or not validation.ok then
		local reason = validation and validation.errors and validation.errors[1] or "invalid build"
		return false, reason
	end

	for key, pending in pairs(pendingMatches) do
		if pending.players.A == player or pending.players.B == player then
			pending.ready[player] = true
			local pA, pB = pending.players.A, pending.players.B
			if pending.ready[pA] and pending.ready[pB] then
				pendingMatches[key] = nil
				self.Server:StartMatch(pA, pB)
			else
				self.Server.Client.OnWaitingForOpponent:Fire(player)
			end
			return true
		end
	end
	return false, "no pending match"
end

function ArenaService:StartMatch(playerA, playerB)
	local ws = getWorkshopService()
	local sessionA = ws:GetSession(playerA)
	local sessionB = ws:GetSession(playerB)

	local match = {
		players    = { A = playerA, B = playerB },
		teams      = {
			A = buildTeamData(sessionA),
			B = buildTeamData(sessionB),
		},
		currentTurn = "A",
		turnNumber  = 1,
		resources   = { A = RESOURCES_BASE, B = RESOURCES_BASE },
		janitor     = Janitor.new(),
	}
	activeSessions[playerA] = match

	-- Notify each player of their team, enemy blocks, and enemy core position
	self.Client.OnGameState:Fire(playerA, {
		myTeam        = "A",
		phase         = "Arena",
		currentTurn   = "A",
		resources     = RESOURCES_BASE,
		enemyBlocks   = match.teams.B.blocks,
		enemyCorePos  = match.teams.B.corePos,
	})
	self.Client.OnGameState:Fire(playerB, {
		myTeam        = "B",
		phase         = "Arena",
		currentTurn   = "A",
		resources     = RESOURCES_BASE,
		enemyBlocks   = match.teams.A.blocks,
		enemyCorePos  = match.teams.A.corePos,
	})
	self.Client.OnTurnChanged:Fire(playerA, {
		currentTurn = "A",
		isMyTurn    = true,
		resources   = { A = match.resources.A, B = match.resources.B },
	})
	self.Client.OnTurnChanged:Fire(playerB, {
		currentTurn = "A",
		isMyTurn    = false,
		resources   = { A = match.resources.A, B = match.resources.B },
	})
end

function ArenaService:GetSession(player)
	local s = sessionForPlayer(player)
	return s
end

function ArenaService:HandlePlayerLeave(player)
	-- Clean up any pending match this player was part of
	for key, pending in pairs(pendingMatches) do
		if pending.players.A == player or pending.players.B == player then
			local opponent = (pending.players.A == player) and pending.players.B or pending.players.A
			self.Client.OnMatchOver:Fire(opponent, "PlayerLeft", nil)
			pendingMatches[key] = nil
			break
		end
	end

	local match, myTeam = sessionForPlayer(player)
	if not match then return end
	local winnerTeam = (myTeam == "A") and "B" or "A"
	self.Client.OnMatchOver:Fire(match.players.A, "PlayerLeft", winnerTeam)
	self.Client.OnMatchOver:Fire(match.players.B, "PlayerLeft", winnerTeam)
	match.janitor:Destroy()
	activeSessions[match.players.A] = nil
end

-- ── Turn processing ───────────────────────────────────────────────────────────

local function blockWorldPos(col, row, team)
	local cx  = (team == "A") and GameConfig.TEAM_A_CENTER_X or GameConfig.TEAM_B_CENTER_X
	local dirX = (team == "A") and -1 or 1
	local wx  = cx + dirX * (col + 0.5) * BLOCK_SIZE
	local wy  = GameConfig.GROUND_Y + (row + 0.5) * BLOCK_SIZE
	return Vector3.new(wx, wy, 0)
end

local function removeBlock(teamData, col, row)
	local key = blockKey(col, row)
	teamData.blockHp[key] = nil
	for i = #teamData.blocks, 1, -1 do
		local b = teamData.blocks[i]
		if b.x == col and b.y == row then
			table.remove(teamData.blocks, i)
			break
		end
	end
end

function ArenaService.Client:FireSling(player, ammoName, hitCol, hitRow, hitTeam, speedFactor)
	local match, myTeam = sessionForPlayer(player)
	if not match then return false, "not in match" end
	if match.currentTurn ~= myTeam then return false, "not your turn" end

	-- Validate ammo
	local ammoDef = AmmoDefinitions[ammoName]
	if not ammoDef then return false, "unknown ammo" end
	if match.resources[myTeam] < ammoDef.resourceCost then return false, "not enough resources" end

	-- Validate hit target
	if hitCol == nil or hitRow == nil or hitTeam == nil then return false, "no target" end
	local enemyTeam = (myTeam == "A") and "B" or "A"
	if hitTeam ~= enemyTeam then return false, "invalid target team" end

	-- Deduct cost
	match.resources[myTeam] = math.max(0, match.resources[myTeam] - ammoDef.resourceCost)
	speedFactor = ProjectileModule.clampSpeed(speedFactor or 30)

	local teamData = match.teams[hitTeam]
	local results  = {}  -- {col, row, damage, destroyed}

	local function applyDamageToBlock(col, row, dmg)
		local key = blockKey(col, row)
		local currentHp = teamData.blockHp[key]
		if not currentHp then return end
		local newHp = currentHp - dmg
		teamData.blockHp[key] = newHp
		local destroyed = newHp <= 0
		if destroyed then
			removeBlock(teamData, col, row)
		end
		results[#results + 1] = { col = col, row = row, damage = dmg, destroyed = destroyed }
	end

	-- Check if hit is a block or core
	local key = blockKey(hitCol, hitRow)
	local corePos = teamData.corePos
	local hitCore = corePos and corePos.x == hitCol and corePos.y == hitRow

	if hitCore then
		local coreDmg = DamageModel.calculateCoreDamage(ammoDef, speedFactor)
		teamData.coreHp = teamData.coreHp - coreDmg
		results[#results + 1] = { col = hitCol, row = hitRow, damage = coreDmg, destroyed = teamData.coreHp <= 0, isCore = true }
	elseif teamData.blockHp[key] then
		local blockId = nil
		for _, b in ipairs(teamData.blocks) do
			if b.x == hitCol and b.y == hitRow then blockId = b.id; break end
		end
		local def = blockId and getBlockDef(blockId) or { damageReduction = 0 }
		local dmg = DamageModel.calculate(ammoDef, speedFactor, def)
		applyDamageToBlock(hitCol, hitRow, dmg)
	end

	-- AOE for explosive ammo — snapshot first so removeBlock() doesn't corrupt iteration
	if ammoDef.isExplosive and ammoDef.explosionRadius then
		local radius    = ammoDef.explosionRadius
		local hitWPos   = blockWorldPos(hitCol, hitRow, hitTeam)
		local snapshot  = { table.unpack(teamData.blocks) }
		for _, b in ipairs(snapshot) do
			if not (b.x == hitCol and b.y == hitRow) then
				local bwp  = blockWorldPos(b.x, b.y, hitTeam)
				local dist = (bwp - hitWPos).Magnitude
				if dist <= radius then
					local def2 = getBlockDef(b.id) or { damageReduction = 0 }
					local aoe  = DamageModel.calculateAoe(ammoDef, dist, def2)
					applyDamageToBlock(b.x, b.y, aoe)
				end
			end
		end
	end

	-- Fire hit signal to both — promote primary-hit fields so HandleHit can read them directly
	local primary = results[1]
	local hitPayload = {
		col      = hitCol,
		row      = hitRow,
		team     = hitTeam,
		ammoName = ammoName,
		isCore   = primary and primary.isCore   or false,
		destroyed= primary and primary.destroyed or false,
		results  = results,
	}
	self.Server.Client.OnHit:Fire(match.players.A, hitPayload)
	self.Server.Client.OnHit:Fire(match.players.B, hitPayload)

	-- Fire collapse for destroyed blocks
	local collapsed = {}
	for _, r in ipairs(results) do
		if r.destroyed and not r.isCore then
			collapsed[#collapsed + 1] = { col = r.col, row = r.row }
		end
	end
	if #collapsed > 0 then
		self.Server.Client.OnCollapse:Fire(match.players.A, collapsed, hitTeam)
		self.Server.Client.OnCollapse:Fire(match.players.B, collapsed, hitTeam)
	end

	-- Win condition
	if teamData.coreHp <= 0 then
		self.Server.Client.OnMatchOver:Fire(match.players.A, "CoreDestroyed", myTeam)
		self.Server.Client.OnMatchOver:Fire(match.players.B, "CoreDestroyed", myTeam)
		match.janitor:Destroy()
		activeSessions[match.players.A] = nil
		return true
	end

	-- Advance turn
	local nextTurn = (match.currentTurn == "A") and "B" or "A"
	match.currentTurn = nextTurn
	match.turnNumber  = match.turnNumber + 1
	match.resources[nextTurn] = nextResources(match, nextTurn)

	local turnPayloadA = {
		currentTurn = nextTurn,
		isMyTurn    = (nextTurn == "A"),
		resources   = { A = match.resources.A, B = match.resources.B },
	}
	local turnPayloadB = {
		currentTurn = nextTurn,
		isMyTurn    = (nextTurn == "B"),
		resources   = { A = match.resources.A, B = match.resources.B },
	}
	self.Server.Client.OnTurnChanged:Fire(match.players.A, turnPayloadA)
	self.Server.Client.OnTurnChanged:Fire(match.players.B, turnPayloadB)

	return true
end

-- PassTurn: skip firing this turn (no ammo spent, just advance)
function ArenaService.Client:PassTurn(player)
	local match, myTeam = sessionForPlayer(player)
	if not match then return false, "not in match" end
	if match.currentTurn ~= myTeam then return false, "not your turn" end

	local nextTurn = (myTeam == "A") and "B" or "A"
	match.currentTurn = nextTurn
	match.turnNumber  = match.turnNumber + 1
	match.resources[nextTurn] = nextResources(match, nextTurn)

	self.Server.Client.OnTurnChanged:Fire(match.players.A, {
		currentTurn = nextTurn,
		isMyTurn    = (nextTurn == "A"),
		resources   = { A = match.resources.A, B = match.resources.B },
	})
	self.Server.Client.OnTurnChanged:Fire(match.players.B, {
		currentTurn = nextTurn,
		isMyTurn    = (nextTurn == "B"),
		resources   = { A = match.resources.A, B = match.resources.B },
	})
	return true
end

-- ── Knit lifecycle ────────────────────────────────────────────────────────────

function ArenaService:KnitInit()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		self:HandlePlayerLeave(player)
	end)
end

function ArenaService:KnitStart() end

return ArenaService
