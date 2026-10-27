--!strict

const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const Constants = require("@src/Constants")
const Types = require("@src/Types")
const Registry = require("@packet/Registry")
const ByteBuffer = require("@buffer/ByteBuffer")
const Channel = require("@network/Channel")
const OutgoingQueue = require("@network/OutgoingQueue")
const InstanceCodec = require("@datatypes/Instance")

export type Connection = Types.Connection

type ListenerNode = {
	callback: ((Player, unknown) -> ())?,
	connected: boolean,
	next: ListenerNode?,
	prev: ListenerNode?,
}

type RateLimit = {
	lastTime: number,
	currentBytes: number,
}

--[=[
	@class Server
	@server
	@within Burn
	Server-side networking module handling packet dispatch, token-bucket rate limiting,
	DoS batch guards, and two-way request handling.
]=]
const Server = {}

local listenerHeads: { [number]: ListenerNode? } = {}
local listenerTails: { [number]: ListenerNode? } = {}
local requestHandlersByPacketId: {
	[number]: (player: Player, reqData: unknown) -> (unknown, Types.AnyTypeDescriptor),
} =
	{}
local playerRateLimits: { [Player]: RateLimit? } = setmetatable({} :: { [Player]: RateLimit? }, { __mode = "k" })
local removingPlayers = setmetatable({} :: { [Player]: boolean? }, { __mode = "k" })
local isListening = false

const function isPlayerActive(player: Player): boolean
	return not removingPlayers[player] and player.Parent == Players
end

-- Token bucket rate limiter replenishing at 64 KB/sec. Every incoming packet is charged
-- a minimum of MIN_PACKET_COST_BYTES (32 bytes) to penalize zero-byte and malformed flood attacks.
@native
const function checkRateLimit(player: Player, size: number): boolean
	const cost = math.max(size, Constants.MIN_PACKET_COST_BYTES)
	const now = os.clock()
	const existing = playerRateLimits[player]
	if existing == nil then
		playerRateLimits[player] = {
			lastTime = now,
			currentBytes = Constants.RATE_LIMIT_BYTES_PER_SEC - cost,
		}
		return true
	end

	const limit = existing
	const elapsed = math.max(0, now - limit.lastTime)
	limit.currentBytes = math.min(
		limit.currentBytes + (elapsed * Constants.RATE_LIMIT_BYTES_PER_SEC),
		Constants.RATE_LIMIT_BYTES_PER_SEC
	)
	limit.lastTime = now

	if limit.currentBytes >= cost then
		limit.currentBytes -= cost
		return true
	end

	return false
end

const packetsById = Registry.rawById

-- Parses sequential packets from an incoming buffer.
-- Terminated if packet count exceeds MAX_PACKETS_PER_BATCH (256) to bound CPU execution time.
@native
const function decodeBatchFast(
	player: Player,
	rawBuf: buffer,
	rawInstances: { Instance }?,
	bufLen: number,
	expectedType: Types.PacketType
)
	local offset = 0
	local packetCount = 0
	InstanceCodec.setIncomingInstances(rawInstances)

	while offset + Constants.HEADER_SIZE <= bufLen do
		packetCount += 1
		if packetCount > Constants.MAX_PACKETS_PER_BATCH then
			break
		end

		const packetId = buffer.readu8(rawBuf, offset)
		const payloadLen = buffer.readu16(rawBuf, offset + 1)
		const payloadStart = offset + Constants.HEADER_SIZE
		const nextOffset = payloadStart + payloadLen

		if nextOffset > bufLen then
			break
		end

		local current = listenerHeads[packetId]
		if current ~= nil then
			const packetDef = packetsById[packetId]
			if packetDef ~= nil and packetDef.packetType == expectedType then
				const fixedSize = packetDef.schema.size
				if typeof(fixedSize) == "number" and payloadLen ~= fixedSize then
					offset = nextOffset
					continue
				end

				local success: boolean, res1: unknown, res2: unknown =
					pcall(packetDef.schema.read, rawBuf, payloadStart)
				if not success then
					warn(`[Burn] Malformed packet '{packetDef.name}' (id {packetId}) from {player.Name}: {res1}`)
					offset = nextOffset
					continue
				end

				const data = res1
				const readEndOffset = res2
				if typeof(readEndOffset) == "number" and readEndOffset ~= nextOffset then
					warn(
						`[Burn] Packet '{packetDef.name}' payload desync from {player.Name}: read end {readEndOffset}, expected {nextOffset}`
					)
					offset = nextOffset
					continue
				end

				while current ~= nil do
					if current.connected and current.callback ~= nil then
						task.spawn(current.callback, player, data)
					end
					current = current.next
				end
			end
		end

		offset = nextOffset
	end

	InstanceCodec.setIncomingInstances(nil)
end

-- Validates rate limits and isolates batch decoding within a pcall to ensure malformed
-- or adversarial client buffers are dropped without terminating server frame execution.
const function decodeAndDispatch(
	player: Player,
	rawBuf: buffer,
	rawInstances: { Instance }?,
	expectedType: Types.PacketType
)
	const bufLen = buffer.len(rawBuf)
	if bufLen < Constants.HEADER_SIZE or bufLen > Constants.MAX_PACKET_SIZE then
		checkRateLimit(player, Constants.MIN_PACKET_COST_BYTES)
		return
	end

	if not checkRateLimit(player, bufLen) then
		return
	end

	const ok: boolean, err: unknown? = pcall(decodeBatchFast, player, rawBuf, rawInstances, bufLen, expectedType)
	InstanceCodec.setIncomingInstances(nil)
	if not ok then
		warn(`[Burn] Dropped malformed packet batch from {player.Name}: {err}`)
	end
end

const function ensureListening()
	if isListening then
		return
	end
	isListening = true

	if not RunService:IsServer() then
		return
	end

	Channel.init()

	Players.PlayerRemoving:Connect(function(player)
		removingPlayers[player] = true
		playerRateLimits[player] = nil
	end)

	Channel.getReliableEvent().OnServerEvent:Connect(function(player, rawBuf, rawInstances)
		if not isPlayerActive(player) then
			return
		end
		if typeof(rawBuf) == "buffer" then
			const instances = if typeof(rawInstances) == "table" and #rawInstances <= 65535 then rawInstances else nil
			decodeAndDispatch(player, rawBuf, instances, "Reliable")
		else
			checkRateLimit(player, Constants.MIN_PACKET_COST_BYTES)
		end
	end)

	Channel.getUnreliableEvent().OnServerEvent:Connect(function(player, rawBuf, rawInstances)
		if not isPlayerActive(player) then
			return
		end
		if typeof(rawBuf) == "buffer" then
			const instances = if typeof(rawInstances) == "table" and #rawInstances <= 65535 then rawInstances else nil
			decodeAndDispatch(player, rawBuf, instances, "Unreliable")
		else
			checkRateLimit(player, Constants.MIN_PACKET_COST_BYTES)
		end
	end)

	Channel.getRequestFunction().OnServerInvoke = function(
		player: Player,
		reqBuf: unknown,
		reqInstances: unknown
	): (buffer?, { Instance }?)
		if not isPlayerActive(player) then
			return nil, nil
		end
		if typeof(reqBuf) ~= "buffer" then
			checkRateLimit(player, Constants.MIN_PACKET_COST_BYTES)
			return nil, nil
		end
		const reqLen = buffer.len(reqBuf)
		if reqLen < Constants.HEADER_SIZE or reqLen > Constants.MAX_PACKET_SIZE then
			checkRateLimit(player, Constants.MIN_PACKET_COST_BYTES)
			return nil, nil
		end
		if not checkRateLimit(player, reqLen) then
			return nil, nil
		end

		const packetId = buffer.readu8(reqBuf, 0)
		const payloadLen = buffer.readu16(reqBuf, 1)
		const payloadStart = Constants.HEADER_SIZE
		const expectedEnd = payloadStart + payloadLen

		if expectedEnd ~= reqLen then
			return nil, nil
		end

		const handler = requestHandlersByPacketId[packetId]
		if handler == nil then
			return nil, nil
		end

		const packetDef = Registry.getById(packetId)
		if packetDef == nil or packetDef.packetType ~= "Request" then
			return nil, nil
		end

		const fixedReqSize = packetDef.schema.size
		if typeof(fixedReqSize) == "number" and payloadLen ~= fixedReqSize then
			return nil, nil
		end

		const instances = if typeof(reqInstances) == "table" and #reqInstances <= 65535
			then reqInstances :: { Instance }
			else nil
		InstanceCodec.setIncomingInstances(instances)
		const readOk, reqData, readEndOffset = pcall(packetDef.schema.read, reqBuf, payloadStart)
		InstanceCodec.setIncomingInstances(nil)

		if not readOk then
			return nil, nil
		end
		if typeof(readEndOffset) == "number" and readEndOffset ~= expectedEnd then
			return nil, nil
		end

		const success, resData, resSchema = pcall(handler, player, reqData)
		if not success or resSchema == nil then
			if not success then
				warn(`[Burn] Request handler error for '{packetDef.name}': {resData}`)
			end
			return nil, nil
		end

		local resInstances: { Instance } = {}
		InstanceCodec.setOutgoingInstances(resInstances)

		const resSize = resSchema.size
		local out: buffer
		const writeFn = resSchema.write :: (buf: buffer, offset: number, value: unknown) -> number

		if typeof(resSize) == "number" then
			-- Fast path: Known fixed response size allows direct zero-copy write into wire buffer.
			if resSize > Constants.MAX_PAYLOAD_SIZE then
				InstanceCodec.setOutgoingInstances(nil)
				return nil, nil
			end
			out = buffer.create(Constants.HEADER_SIZE + resSize)
			buffer.writeu8(out, 0, packetId)
			buffer.writeu16(out, 1, resSize)
			const writeOk, endOffsetOrErr = pcall(writeFn, out, Constants.HEADER_SIZE, resData)
			if not writeOk or endOffsetOrErr ~= Constants.HEADER_SIZE + resSize then
				InstanceCodec.setOutgoingInstances(nil)
				return nil, nil
			end
		else
			-- Dynamic path: Serialize into reusable thread-local scratch buffer first, then copy exact payload.
			const scratch = ByteBuffer.getScratch()
			ByteBuffer.ensureCapacity(scratch, Constants.MAX_PACKET_SIZE)

			const writeOk, resLenOrErr = pcall(writeFn, scratch.raw, 0, resData)
			if not writeOk then
				InstanceCodec.setOutgoingInstances(nil)
				return nil, nil
			end

			const resLen = resLenOrErr :: number
			if resLen < 0 or resLen > Constants.MAX_PAYLOAD_SIZE then
				InstanceCodec.setOutgoingInstances(nil)
				return nil, nil
			end

			out = buffer.create(Constants.HEADER_SIZE + resLen)
			buffer.writeu8(out, 0, packetId)
			buffer.writeu16(out, 1, resLen)
			if resLen > 0 then
				buffer.copy(out, Constants.HEADER_SIZE, scratch.raw, 0, resLen)
			end
		end

		InstanceCodec.setOutgoingInstances(nil)
		return out, if #resInstances > 0 then resInstances else nil
	end
end

function Server.send<T>(target: Player | { Player }, packetDef: Types.PacketHandle<T>, data: T)
	if typeof(target) == "table" then
		OutgoingQueue.serverEnqueueList(target, packetDef, data)
	else
		OutgoingQueue.serverEnqueue(target, packetDef, data)
	end
end

function Server.sendImmediate<T>(target: Player | { Player }, packetDef: Types.PacketHandle<T>, data: T)
	if typeof(target) == "table" then
		OutgoingQueue.serverSendImmediateList(target, packetDef, data)
	else
		OutgoingQueue.serverSendImmediate(target, packetDef, data)
	end
end

function Server.broadcast<T>(packetDef: Types.PacketHandle<T>, data: T)
	OutgoingQueue.serverBroadcast(packetDef, data)
end

function Server.broadcastExcept<T>(excludedPlayer: Player, packetDef: Types.PacketHandle<T>, data: T)
	OutgoingQueue.serverBroadcastExcept(excludedPlayer, packetDef, data)
end

function Server.broadcastImmediate<T>(packetDef: Types.PacketHandle<T>, data: T)
	OutgoingQueue.serverBroadcastImmediate(packetDef, data)
end

--[=[
	Registers a persistent listener callback on the server for incoming client packets.
]=]
function Server.on<T>(packetDef: Types.PacketHandle<T>, listener: (Player, T) -> ()): Connection
	if packetDef.packetType ~= "Reliable" and packetDef.packetType ~= "Unreliable" then
		error(`Cannot register event listener for Request packet '{packetDef.name}'`)
	end
	ensureListening()

	const packetId = packetDef.id
	const node: ListenerNode = {
		callback = listener :: (Player, unknown) -> (),
		connected = true,
		next = nil,
		prev = listenerTails[packetId],
	}

	const tail = listenerTails[packetId]
	if tail ~= nil then
		tail.next = node
		listenerTails[packetId] = node
	else
		listenerHeads[packetId] = node
		listenerTails[packetId] = node
	end

	const function disconnectFn(_self: Connection)
		if not node.connected then
			return
		end
		node.connected = false

		if node.prev ~= nil then
			node.prev.next = node.next
		else
			listenerHeads[packetId] = node.next
		end

		if node.next ~= nil then
			node.next.prev = node.prev
		else
			listenerTails[packetId] = node.prev
		end

		node.prev = nil
		node.next = nil
		node.callback = nil
	end

	return {
		disconnect = disconnectFn,
		Disconnect = disconnectFn,
	}
end

--[=[
	Registers a synchronous request-response handler for two-way client invocations.
]=]
function Server.handleRequest<Req, ResD>(
	packetDef: Types.PacketHandle<Req>,
	responseSchema: ResD,
	handler: (Player, Req) -> Types.InferType<ResD>
)
	if packetDef.packetType ~= "Request" then
		error(`Server.handleRequest requires a packet with packetType == 'Request' (got '{packetDef.packetType}')`)
	end
	ensureListening()
	requestHandlersByPacketId[packetDef.id] = function(player: Player, reqData: unknown)
		const resData = handler(player, reqData :: Req)
		return resData, responseSchema :: Types.AnyTypeDescriptor
	end
end

if RunService:IsServer() then
	ensureListening()
end

return Server
