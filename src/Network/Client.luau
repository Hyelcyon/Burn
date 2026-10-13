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
	next: ListenerNode?,
	prev: ListenerNode?,
}

const Client = {}

local listenerHeads: { [number]: ListenerNode? } = {}
local listenerTails: { [number]: ListenerNode? } = {}
local isListening = false

@native
const function decodeAndDispatch(rawBuf: buffer)
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
		if packetDef ~= nil then
			local current = listenerHeads[packetId]
			if current ~= nil then
				local data
				data = packetDef.schema.read(rawBuf, payloadStart)
				while current ~= nil do
					const nextNode = current.next
					task.spawn(current.callback, data)
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

	if not RunService:IsClient() then
		return
	end

	Channel.getReliableEvent().OnClientEvent:Connect(function(rawBuf)
		if typeof(rawBuf) == "buffer" then
			decodeAndDispatch(rawBuf)
		end
	end)

	Channel.getUnreliableEvent().OnClientEvent:Connect(function(rawBuf)
		if typeof(rawBuf) == "buffer" then
			decodeAndDispatch(rawBuf)
		end
	end)
end

function Client.send(packetDef, data)
	OutgoingQueue.clientEnqueue(packetDef, data)
end

function Client.sendImmediate(packetDef, data)
	OutgoingQueue.clientSendImmediate(packetDef, data)
end

function Client.on(packetDef, listener): Connection
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

function Client.invoke(packetDef, responseSchema, data)
	const scratch = ByteBuffer.getScratch()
	const schemaSize = packetDef.schema.size
	const capacity = if typeof(schemaSize) == "number" then schemaSize else 256
	ByteBuffer.ensureCapacity(scratch, capacity)
	const reqLen = packetDef.schema.write(scratch.raw, 0, data)

	const reqBuf = buffer.create(Constants.HEADER_SIZE + reqLen)
	buffer.writeu8(reqBuf, 0, packetDef.id)
	buffer.writeu16(reqBuf, 1, reqLen)
	if reqLen > 0 then
		buffer.copy(reqBuf, Constants.HEADER_SIZE, scratch.raw, 0, reqLen)
	end

	const resBuf = Channel.getRequestFunction():InvokeServer(reqBuf)
	if typeof(resBuf) ~= "buffer" then
		return nil
	end
	if buffer.len(resBuf) < Constants.HEADER_SIZE then
		return nil
	end

	local resData
	resData = responseSchema.read(resBuf, Constants.HEADER_SIZE)
	return resData
end

return Client
