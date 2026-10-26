--!strict

const RunService = game:GetService("RunService")

const Constants = require("@src/Constants")
const Types = require("@src/Types")
const Registry = require("@packet/Registry")
const ByteBuffer = require("@buffer/ByteBuffer")
const Channel = require("@network/Channel")
const OutgoingQueue = require("@network/OutgoingQueue")

export type Connection = Types.Connection

type ListenerNode = {
	callback: ((unknown) -> ())?,
	connected: boolean,
	next: ListenerNode?,
	prev: ListenerNode?,
}

--[=[
	@class Client
	@client
	@within Burn
	Client-side networking module handling packet dispatch, stream frame validation,
	and synchronous two-way request invocations.
]=]
const Client = {}

local listenerHeads: { [number]: ListenerNode? } = {}
local listenerTails: { [number]: ListenerNode? } = {}
local isListening = false

const packetsById = Registry.rawById

@native
const function decodeAndDispatch(rawBuf: buffer, expectedType: Types.PacketType)
	local offset = 0
	const bufLen = buffer.len(rawBuf)

	while offset + Constants.HEADER_SIZE <= bufLen do
		const packetId = buffer.readu8(rawBuf, offset)
		const payloadLen = buffer.readu16(rawBuf, offset + 1)
		const payloadStart = offset + Constants.HEADER_SIZE
		const nextOffset = payloadStart + payloadLen

		-- Guard against truncated frames where the advertised payload exceeds the buffer.
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
					warn(`[Burn] Failed to decode incoming packet '{packetDef.name}' (id {packetId}): {res1}`)
					offset = nextOffset
					continue
				end

				const data = res1
				const readEndOffset = res2

				-- Deserializer must consume exactly the advertised payload bytes.
				-- Any discrepancy indicates stream corruption or schema drift; skip packet to prevent desync.
				if typeof(readEndOffset) == "number" and readEndOffset ~= nextOffset then
					warn(
						`[Burn] Packet '{packetDef.name}' payload desync: read end {readEndOffset}, expected {nextOffset}`
					)
					offset = nextOffset
					continue
				end

				while current ~= nil do
					if current.connected and current.callback ~= nil then
						task.spawn(current.callback, data)
					end
					current = current.next
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

	if not RunService:IsClient() then
		return
	end

	task.spawn(function()
		Channel.getReliableEvent().OnClientEvent:Connect(function(rawBuf)
			if typeof(rawBuf) == "buffer" then
				decodeAndDispatch(rawBuf, "Reliable")
			end
		end)
	end)

	task.spawn(function()
		Channel.getUnreliableEvent().OnClientEvent:Connect(function(rawBuf)
			if typeof(rawBuf) == "buffer" then
				decodeAndDispatch(rawBuf, "Unreliable")
			end
		end)
	end)
end

function Client.send<T>(packetDef: Types.PacketDefinition<T>, data: T)
	OutgoingQueue.clientEnqueue(packetDef, data)
end

function Client.sendImmediate<T>(packetDef: Types.PacketDefinition<T>, data: T)
	OutgoingQueue.clientSendImmediate(packetDef, data)
end

--[=[
	Registers a persistent packet listener. Returns a Connection whose `:disconnect()`
	unlinks the node in O(1) time without shifting listener arrays.
]=]
function Client.on<T>(packetDef: Types.PacketDefinition<T>, listener: (T) -> ()): Connection
	if packetDef.packetType ~= "Reliable" and packetDef.packetType ~= "Unreliable" then
		error(`Cannot register event listener for Request packet '{packetDef.name}'`)
	end

	const packetId = packetDef.id
	const node: ListenerNode = {
		callback = listener :: (unknown) -> (),
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

	ensureListening()

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
	Sends a two-way request to the server and returns the decoded response, or nil on failure.
	@yields
]=]
function Client.invoke<Req, Res>(
	packetDef: Types.PacketDefinition<Req>,
	responseSchema: Types.TypeDescriptor<Res>,
	data: Req
): Res?
	if packetDef.packetType ~= "Request" then
		error(`Client.invoke requires a packet with packetType == 'Request' (got '{packetDef.packetType}')`)
	end

	local reqBuf: buffer
	const schemaSize = packetDef.schema.size
	if typeof(schemaSize) == "number" then
		-- Fast path: Known fixed schema size allows zero-copy serialization directly into wire buffer.
		if schemaSize > Constants.MAX_PAYLOAD_SIZE then
			error(`Request payload ({schemaSize} bytes) exceeds limit ({Constants.MAX_PAYLOAD_SIZE} bytes)`)
		end
		reqBuf = buffer.create(Constants.HEADER_SIZE + schemaSize)
		buffer.writeu8(reqBuf, 0, packetDef.id)
		buffer.writeu16(reqBuf, 1, schemaSize)
		const writtenEnd = packetDef.schema.write(reqBuf, Constants.HEADER_SIZE, data)
		if writtenEnd ~= Constants.HEADER_SIZE + schemaSize then
			error(
				`[Burn] Fixed-size schema '{packetDef.name}' wrote {writtenEnd - Constants.HEADER_SIZE} bytes, expected {schemaSize}`
			)
		end
	else
		-- Dynamic path: Serialize into reusable thread-local scratch buffer first, then copy exact payload.
		const scratch = ByteBuffer.getScratch()
		ByteBuffer.ensureCapacity(scratch, Constants.MAX_PACKET_SIZE)
		const reqLen = packetDef.schema.write(scratch.raw, 0, data)
		if reqLen < 0 or reqLen > Constants.MAX_PAYLOAD_SIZE then
			error(`Request payload ({reqLen} bytes) exceeds limit ({Constants.MAX_PAYLOAD_SIZE} bytes)`)
		end

		reqBuf = buffer.create(Constants.HEADER_SIZE + reqLen)
		buffer.writeu8(reqBuf, 0, packetDef.id)
		buffer.writeu16(reqBuf, 1, reqLen)
		if reqLen > 0 then
			buffer.copy(reqBuf, Constants.HEADER_SIZE, scratch.raw, 0, reqLen)
		end
	end

	const invokeOk, resBuf = pcall(function()
		return Channel.getRequestFunction():InvokeServer(reqBuf)
	end)
	if not invokeOk or typeof(resBuf) ~= "buffer" then
		return nil
	end

	const resBufLen = buffer.len(resBuf)
	if resBufLen < Constants.HEADER_SIZE then
		return nil
	end

	const resPacketId = buffer.readu8(resBuf, 0)
	const resPayloadLen = buffer.readu16(resBuf, 1)
	const expectedEnd = Constants.HEADER_SIZE + resPayloadLen
	if resPacketId ~= packetDef.id or expectedEnd ~= resBufLen then
		return nil
	end

	const readOk, res1, res2 = pcall(responseSchema.read, resBuf, Constants.HEADER_SIZE)
	if not readOk then
		return nil
	end

	const resData = res1
	const readEndOffset = res2
	if typeof(readEndOffset) == "number" and readEndOffset ~= expectedEnd then
		return nil
	end

	return resData :: Res
end

if RunService:IsClient() then
	ensureListening()
end

return Client
