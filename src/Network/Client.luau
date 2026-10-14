--!strict

const RunService = game:GetService("RunService")

const Constants = require(script.Parent.Parent.Constants)
const Types = require(script.Parent.Parent.Types)
const Registry = require(script.Parent.Parent.Packet.Registry)
const ByteBuffer = require(script.Parent.Parent.Buffer.ByteBuffer)
const Channel = require(script.Parent.Channel)
const OutgoingQueue = require(script.Parent.OutgoingQueue)

export type Connection = Types.Connection

type ListenerNode = {
	callback: (any) -> (),
	connected: boolean,
	next: ListenerNode?,
	prev: ListenerNode?,
}

const Client = {}

local listenerHeads: { [number]: ListenerNode? } = {}
local listenerTails: { [number]: ListenerNode? } = {}
local isListening = false

@native
const function decodeAndDispatch(rawBuf: buffer, expectedType: Types.PacketType)
	local offset = 0
	const bufLen = buffer.len(rawBuf)

	while offset + Constants.HEADER_SIZE <= bufLen do
		const packetId = buffer.readu8(rawBuf, offset)
		const payloadLen = buffer.readu16(rawBuf, offset + 1)
		const payloadStart = offset + Constants.HEADER_SIZE
		const nextOffset = payloadStart + payloadLen

		if nextOffset > bufLen then
			break
		end

		const packetDef = Registry.getById(packetId)
		if packetDef ~= nil and packetDef.packetType == expectedType then
			local current = listenerHeads[packetId]
			if current ~= nil then
				const data, readEndOffset = packetDef.schema.read(rawBuf, payloadStart)
				if typeof(readEndOffset) == "number" and readEndOffset ~= nextOffset then
					break
				end

				while current ~= nil do
					if current.connected then
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

function Client.on<T>(packetDef: Types.PacketDefinition<T>, listener: (T) -> ()): Connection
	if packetDef.packetType ~= "Reliable" and packetDef.packetType ~= "Unreliable" then
		error(`Cannot register event listener for Request packet '{packetDef.name}'`)
	end

	const packetId = packetDef.id
	const node: ListenerNode = {
		callback = listener,
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

	return {
		disconnect = function(_self: Connection)
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
		end,
	}
end

function Client.invoke<Req, Res>(
	packetDef: Types.PacketDefinition<Req>,
	responseSchema: Types.TypeDescriptor<Res>,
	data: Req
): Res?
	if packetDef.packetType ~= "Request" then
		error(`Client.invoke requires a packet with packetType == 'Request' (got '{packetDef.packetType}')`)
	end

	const scratch = ByteBuffer.getScratch()
	const schemaSize = packetDef.schema.size
	const capacity = if typeof(schemaSize) == "number" then schemaSize else Constants.MAX_PACKET_SIZE
	ByteBuffer.ensureCapacity(scratch, capacity)
	const reqLen = packetDef.schema.write(scratch.raw, 0, data)
	if reqLen < 0 or reqLen > Constants.MAX_PAYLOAD_SIZE then
		error(`Request payload ({reqLen} bytes) exceeds limit ({Constants.MAX_PAYLOAD_SIZE} bytes)`)
	end

	const reqBuf = buffer.create(Constants.HEADER_SIZE + reqLen)
	buffer.writeu8(reqBuf, 0, packetDef.id)
	buffer.writeu16(reqBuf, 1, reqLen)
	if reqLen > 0 then
		buffer.copy(reqBuf, Constants.HEADER_SIZE, scratch.raw, 0, reqLen)
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

	const resData, readEndOffset = responseSchema.read(resBuf, Constants.HEADER_SIZE)
	if typeof(readEndOffset) == "number" and readEndOffset ~= expectedEnd then
		return nil
	end

	return resData
end

return Client
