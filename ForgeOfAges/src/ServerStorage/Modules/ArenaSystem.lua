-- ServerStorage/Modules/ArenaSystem.lua
-- Live, tick-based PvP - same DPS-race cadence as DungeonSystem/StageSystem,
-- just two real combatant sheets trading damage instead of one player vs a
-- wave. Requesting a battle joins a short matchmaking queue: if another
-- player is already waiting, they're paired immediately for a real human-vs-
-- human duel; if nobody shows up within QUEUE_WAIT_SECONDS, the queued
-- player is matched against a bot opponent (stats scaled off their own, same
-- idea the old instant-resolve version used) so nobody waits forever. Either
-- way the fight itself now runs as a live multi-second tick loop the client
-- watches happen in real time via ArenaSceneEvent, not a precomputed log
-- replayed after an instant server-side resolve.
--
-- There is still no real skill-based matchmaking (rating is only used for
-- the Elo update, not for pairing) - that's a fine upgrade once there's
-- enough concurrent players queuing for it to matter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkEvents = require(ReplicatedStorage.Modules.NetworkEvents)
local DataManager = require(script.Parent.DataManager)
local EconomySystem = require(script.Parent.EconomySystem)
local PowerCalculator = require(script.Parent.PowerCalculator)

local ArenaSystem = {}

local DAILY_ATTEMPTS = 3
local ARENA_REWARD = 60
local RATING_K = 24
local COMBAT_TICK = 1
local QUEUE_WAIT_SECONDS = 6
local MAX_MATCH_TICKS = 60

local BOT_NAMES = { "Rival Warrior", "Shadow Duelist", "Iron Challenger", "Grim Contender", "Storm Rival" }

type Side = {
	player: Player?,
	userId: number?,
	name: string,
	maxHP: number,
	hp: number,
	dps: number,
	regenPerSecond: number,
	rating: number,
	isBot: boolean,
}

type Match = {
	id: number,
	a: Side,
	b: Side,
	ticks: number,
}

local queue: { Player } = {}
local queueEnteredAt: { [number]: number } = {}
local matchByUserId: { [number]: number } = {}
local matches: { [number]: Match } = {}
local nextMatchId = 1

local arenaSceneEvent = NetworkEvents.get("ArenaSceneEvent")
local arenaResult = NetworkEvents.get("ArenaResult")

local function currentDayNumber(): number
	return math.floor(os.time() / 86400)
end

local function ensureDailyReset(data)
	local today = currentDayNumber()
	if data.arena.lastResetDay ~= today then
		data.arena.lastResetDay = today
		data.arena.rollsToday = 0
	end
	data.arena.rating = data.arena.rating or 1000
end

local function attemptsLeft(data): number
	return math.max(0, DAILY_ATTEMPTS - data.arena.rollsToday)
end

local function safeFire(player: Player?, remote: RemoteEvent, payload)
	if player and player.Parent then
		remote:FireClient(player, payload)
	end
end

local function buildSide(player: Player, data): Side
	local combatant = PowerCalculator.getCombatant(data)
	return {
		player = player,
		userId = player.UserId,
		name = player.Name,
		maxHP = combatant.maxHP,
		hp = combatant.maxHP,
		dps = combatant.dps,
		regenPerSecond = combatant.regenPerSecond,
		rating = data.arena.rating or 1000,
		isBot = false,
	}
end

local function buildBotSide(opponentSide: Side): Side
	local factor = 0.85 + math.random() * 0.3
	return {
		player = nil,
		userId = nil,
		name = BOT_NAMES[math.random(1, #BOT_NAMES)],
		maxHP = opponentSide.maxHP * factor,
		hp = opponentSide.maxHP * factor,
		dps = opponentSide.dps * factor,
		regenPerSecond = opponentSide.regenPerSecond * factor,
		rating = math.max(1, math.floor(opponentSide.rating * factor)),
		isBot = true,
	}
end

local function otherSide(match: Match, side: Side): Side
	return if match.a == side then match.b else match.a
end

local function fireStart(match: Match)
	for _, side in { match.a, match.b } do
		if side.player then
			local opponent = otherSide(match, side)
			safeFire(side.player, arenaSceneEvent, {
				kind = "Start",
				opponentName = opponent.name,
				isBot = opponent.isBot,
				playerMaxHP = side.maxHP,
				opponentMaxHP = opponent.maxHP,
			})
		end
	end
end

local function fireTick(match: Match)
	for _, side in { match.a, match.b } do
		if side.player then
			local opponent = otherSide(match, side)
			safeFire(side.player, arenaSceneEvent, {
				kind = "Tick",
				playerHP = side.hp,
				playerMaxHP = side.maxHP,
				opponentHP = opponent.hp,
				opponentMaxHP = opponent.maxHP,
			})
		end
	end
end

local function applyRatingAndReward(side: Side, opponent: Side, won: boolean)
	if not side.player then
		return nil
	end
	local data = DataManager.getData(side.player)
	if not data then
		return nil
	end

	local ratingBefore = data.arena.rating or 1000
	local expected = 1 / (1 + 10 ^ ((opponent.rating - ratingBefore) / 400))
	local ratingChange = math.floor(RATING_K * ((won and 1 or 0) - expected) + 0.5)
	data.arena.rating = math.max(0, ratingBefore + ratingChange)

	local gachaReward = nil
	if won then
		data.gachaCurrency += ARENA_REWARD
		gachaReward = ARENA_REWARD
	end

	EconomySystem.pushState(side.player, data)

	return {
		won = won,
		ratingBefore = ratingBefore,
		ratingAfter = data.arena.rating,
		ratingChange = ratingChange,
		gachaReward = gachaReward,
		attemptsLeft = attemptsLeft(data),
		opponentName = opponent.name,
		isBot = opponent.isBot,
	}
end

local function finishMatch(match: Match)
	matches[match.id] = nil
	if match.a.userId then
		matchByUserId[match.a.userId] = nil
	end
	if match.b.userId then
		matchByUserId[match.b.userId] = nil
	end

	local aWon: boolean
	if match.a.hp <= 0 and match.b.hp <= 0 then
		aWon = match.a.dps >= match.b.dps
	else
		aWon = match.b.hp <= 0
	end

	local resultA = applyRatingAndReward(match.a, match.b, aWon)
	local resultB = applyRatingAndReward(match.b, match.a, not aWon)

	if resultA then
		safeFire(match.a.player, arenaResult, resultA)
	end
	if resultB then
		safeFire(match.b.player, arenaResult, resultB)
	end
end

local function startMatch(sideA: Side, sideB: Side)
	local matchId = nextMatchId
	nextMatchId += 1

	local match: Match = { id = matchId, a = sideA, b = sideB, ticks = 0 }
	matches[matchId] = match
	if sideA.userId then
		matchByUserId[sideA.userId] = matchId
	end
	if sideB.userId then
		matchByUserId[sideB.userId] = matchId
	end

	fireStart(match)
end

local function removeFromQueue(player: Player)
	for index, queued in queue do
		if queued.UserId == player.UserId then
			table.remove(queue, index)
			break
		end
	end
	queueEnteredAt[player.UserId] = nil
end

local function tryEnterQueue(player: Player, data)
	if matchByUserId[player.UserId] or queueEnteredAt[player.UserId] then
		return
	end

	ensureDailyReset(data)
	if attemptsLeft(data) <= 0 then
		return
	end
	data.arena.rollsToday += 1
	EconomySystem.pushState(player, data)

	-- Immediate pairing: first still-connected player waiting in the queue.
	while #queue > 0 do
		local opponent = table.remove(queue, 1) :: Player
		queueEnteredAt[opponent.UserId] = nil
		if opponent.Parent and opponent.UserId ~= player.UserId then
			local opponentData = DataManager.getData(opponent)
			if opponentData then
				startMatch(buildSide(player, data), buildSide(opponent, opponentData))
				return
			end
		end
	end

	table.insert(queue, player)
	queueEnteredAt[player.UserId] = os.time()
	safeFire(player, arenaSceneEvent, { kind = "Searching" })
end

local function tickQueue()
	local now = os.time()
	local index = 1
	while index <= #queue do
		local queuedPlayer = queue[index]
		if not queuedPlayer.Parent then
			table.remove(queue, index)
			queueEnteredAt[queuedPlayer.UserId] = nil
		elseif now - (queueEnteredAt[queuedPlayer.UserId] or now) >= QUEUE_WAIT_SECONDS then
			table.remove(queue, index)
			queueEnteredAt[queuedPlayer.UserId] = nil
			local data = DataManager.getData(queuedPlayer)
			if data then
				local playerSide = buildSide(queuedPlayer, data)
				startMatch(playerSide, buildBotSide(playerSide))
			end
		else
			index += 1
		end
	end
end

local function tickMatches()
	for _, match in matches do
		match.ticks += 1
		local a, b = match.a, match.b

		a.hp = math.max(0, math.min(a.maxHP, a.hp - b.dps * COMBAT_TICK + a.regenPerSecond * COMBAT_TICK))
		b.hp = math.max(0, math.min(b.maxHP, b.hp - a.dps * COMBAT_TICK + b.regenPerSecond * COMBAT_TICK))

		if match.ticks >= MAX_MATCH_TICKS and a.hp > 0 and b.hp > 0 then
			-- Safety valve for a near-perfectly-even fight: decide by remaining
			-- HP fraction instead of ticking forever.
			if a.hp / a.maxHP < b.hp / b.maxHP then
				a.hp = 0
			else
				b.hp = 0
			end
		end

		fireTick(match)

		if a.hp <= 0 or b.hp <= 0 then
			finishMatch(match)
		end
	end
end

function ArenaSystem.init()
	NetworkEvents.get("RequestArenaBattle").OnServerEvent:Connect(function(player)
		local data = DataManager.getData(player)
		if not data then
			return
		end
		tryEnterQueue(player, data)
	end)

	Players.PlayerRemoving:Connect(function(player)
		removeFromQueue(player)
		local matchId = matchByUserId[player.UserId]
		if matchId then
			local match = matches[matchId]
			if match then
				if match.a.userId == player.UserId then
					match.a.hp = 0
				elseif match.b.userId == player.UserId then
					match.b.hp = 0
				end
				finishMatch(match)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(COMBAT_TICK)
			tickQueue()
			tickMatches()
		end
	end)
end

return ArenaSystem
