--!strict

const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const Constants = require(script.Parent.Parent.Constants)
const Types = require(script.Parent.Parent.Types)
const Registry = require(script.Parent.Parent.Packet.Registry)
const ByteBuffer = require(script.Parent.Parent.Buffer.ByteBuffer)
const Channel = require(script.Parent.Channel)
const OutgoingQueue = require(script.Parent.OutgoingQueue)

export type Connection = Types.Connection

type ListenerNode = {
	callback: (Player, any) -> (),
	next: ListenerNode?,
	prev: ListenerNode?,
}

type RateLimit = {
	lastTime: number,
	currentBytes: number,
}

const Server = {}

local listenerHeads: { [number]: ListenerNode? } = {}
local listenerTails: { [number]: ListenerNode? } = {}
local requestHandlersByPacketId: { [number]: (player: Player, reqData: any) -> (any, Types.TypeDescriptor<any>) } = {}
local playerRateLimits: { [Player]: RateLimit? } = {}
local isListening = false

@native
const function checkRateLimit(player: Player, size: number): boolean
	local limit: RateLimit
	const existing = playerRateLimits[player]
	if existing == nil then
		limit = {
			lastTime = os.clock(),
			currentBytes = Constants.RATE_LIMIT_BYTES_PER_SEC,
		}
		playerRateLimits[player] = limit
	else
		limit = existing
	end

	const now = os.clock()
	const elapsed = now - limit.lastTime
	limit.currentBytes = math.min(
		limit.currentBytes + (elapsed * Constants.RATE_LIMIT_BYTES_PER_SEC),
		Constants.RATE_LIMIT_BYTES_PER_SEC
	)
	limit.lastTime = now

	if limit.currentBytes >= size then
		limit.currentBytes -= size
		return true
	end

	return false
end

@native
const function decodeAndDispatch(player: Player, rawBuf: buffer)
	local offset = 0
	const bufLen = buffer.len(rawBuf)

	if bufLen == 0 or bufLen > Constants.MAX_PACKET_SIZE then
		return
	end

	if not checkRateLimit(player, bufLen) then
		return
	end

	while offset + Constants.HEADER_SIZE <= bufLen do
		const packetId = buffer.readu8(rawBuf, offset)
		const payloadLen = buffer.readu16(rawBuf, offset + 1)
		const payloadStart = offset + Constants.HEADER_SIZE
		const nextOffset = payloadStart + payloadLen

		if nextOffset > bufLen then
			break
		end

		const packetDef = Registry.getById(packetId)
		if packetDef ~= nil then
			local current = listenerHeads[packetId]
			if current ~= nil then
				local data
				data = packetDef.schema.read(rawBuf, payloadStart)
				while current ~= nil do
					const nextNode = current.next
					task.spawn(current.callback, player, data)
					current = nextNode
				end
			end
		end

		offset = nextOffset
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

	Players.PlayerRemoving:Connect(function(player)
		playerRateLimits[player] = nil
	end)

	Channel.getReliableEvent().OnServerEvent:Connect(function(player, rawBuf)
		if typeof(rawBuf) == "buffer" then
			decodeAndDispatch(player, rawBuf)
		end
	end)

	Channel.getUnreliableEvent().OnServerEvent:Connect(function(player, rawBuf)
		if typeof(rawBuf) == "buffer" then
			decodeAndDispatch(player, rawBuf)
		end
	end)

	Channel.getRequestFunction().OnServerInvoke = function(player: Player, reqBuf): buffer?
		if typeof(reqBuf) ~= "buffer" then
			return nil
		end
		const reqLen = buffer.len(reqBuf)
		if reqLen < Constants.HEADER_SIZE or reqLen > Constants.MAX_PACKET_SIZE then
			return nil
		end
		if not checkRateLimit(player, reqLen) then
			return nil
		end

		const packetId = buffer.readu8(reqBuf, 0)
		const _payloadLen = buffer.readu16(reqBuf, 1)
		const payloadStart = Constants.HEADER_SIZE

		const handler = requestHandlersByPacketId[packetId]
		if handler == nil then
			return nil
		end

		const packetDef = Registry.getById(packetId)
		if packetDef == nil then
			return nil
		end

		local reqData
		reqData = packetDef.schema.read(reqBuf, payloadStart)

		const success, resData, resSchema = pcall(handler, player, reqData)
		if not success then
			warn(`[Burn] Request handler error for packet {packetDef.name} (id {packetId}): {resData}`)
			return nil
		end
		if resSchema == nil then
			return nil
		end

		const scratch = ByteBuffer.getScratch()
		const resSize = resSchema.size
		const capacity = if typeof(resSize) == "number" then resSize else 256
		ByteBuffer.ensureCapacity(scratch, capacity)
		const resLen = resSchema.write(scratch.raw, 0, resData)

		const out = buffer.create(Constants.HEADER_SIZE + resLen)
		buffer.writeu8(out, 0, packetId)
		buffer.writeu16(out, 1, resLen)
		if resLen > 0 then
			buffer.copy(out, Constants.HEADER_SIZE, scratch.raw, 0, resLen)
		end

		return out
	end
end

function Server.send(target: Player | { Player }, packetDef, data)
	if typeof(target) == "table" then
		for _, player in target do
			OutgoingQueue.serverEnqueue(player, packetDef, data)
		end
	else
		OutgoingQueue.serverEnqueue(target, packetDef, data)
	end
end

function Server.sendImmediate(target: Player | { Player }, packetDef, data)
	if typeof(target) == "table" then
		for _, player in target do
			OutgoingQueue.serverSendImmediate(player, packetDef, data)
		end
	else
		OutgoingQueue.serverSendImmediate(target, packetDef, data)
	end
end

function Server.broadcast(packetDef, data)
	OutgoingQueue.serverBroadcast(packetDef, data)
end

function Server.broadcastExcept(excludedPlayer: Player, packetDef, data)
	OutgoingQueue.serverBroadcastExcept(excludedPlayer, packetDef, data)
end

function Server.broadcastImmediate(packetDef, data)
	OutgoingQueue.serverBroadcastImmediate(packetDef, data)
end

function Server.on(packetDef, listener): Connection
	ensureListening()

	const packetId = packetDef.id
	const node: ListenerNode = {
		callback = listener,
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

	local isConnected = true
	return {
		disconnect = function(_self: Connection)
			if not isConnected then
				return
			end
			isConnected = false

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
		end,
	}
end

function Server.handleRequest(packetDef, responseSchema: Types.TypeDescriptor<any>, handler: (Player, any) -> any)
	ensureListening()
	requestHandlersByPacketId[packetDef.id] = function(player, reqData)
		return handler(player, reqData), responseSchema
	end
end

return Server
