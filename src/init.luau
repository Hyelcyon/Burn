--!strict

const RunService = game:GetService("RunService")

const Types = require("@src/Types")
const Constants = require("@src/Constants")
const Buffer = require("@buffer")
const DataTypes = require("@datatypes")
const Packet = require("@packet")
const Network = require("@network")

export type TypeDescriptor<T> = Types.TypeDescriptor<T>
export type PacketType = Types.PacketType
export type PacketDefinition<T> = Types.PacketDefinition<T>
export type Connection = Types.Connection
export type ByteBuffer = Buffer.ByteBuffer
export type Cursor = Buffer.Cursor

const isServer = RunService:IsServer()
const isClient = RunService:IsClient()

const function on(packet: any, listener: any)
	if isServer then
		return Network.Server.on(packet, listener)
	else
		return Network.Client.on(packet, listener)
	end
end

const function once(packet, listener)
	local conn: Types.Connection
	conn = on(packet, function(...)
		conn:disconnect()
		listener(...)
	end)
	return conn
end

const function wait(packet)
	const thread = coroutine.running()
	local conn: Types.Connection
	conn = on(packet, function(...)
		conn:disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

const function send(target: any, packetOrData: any, maybeData: any?)
	if isServer then
		if maybeData ~= nil then
			Network.Server.send(target, packetOrData, maybeData)
		else
			Network.Server.broadcast(target, packetOrData)
		end
	else
		Network.Client.send(target, packetOrData)
	end
end

const function sendImmediate(target: any, packetOrData: any, maybeData: any?)
	if isServer then
		if maybeData ~= nil then
			Network.Server.sendImmediate(target, packetOrData, maybeData)
		else
			Network.Server.broadcastImmediate(target, packetOrData)
		end
	else
		Network.Client.sendImmediate(target, packetOrData)
	end
end

const function broadcast(packet, data)
	assert(isServer, "Burn.broadcast can only be called on the server")
	Network.Server.broadcast(packet, data)
end

const function broadcastExcept(excludedPlayer, packet, data)
	assert(isServer, "Burn.broadcastExcept can only be called on the server")
	Network.Server.broadcastExcept(excludedPlayer, packet, data)
end

const function broadcastImmediate(packet, data)
	assert(isServer, "Burn.broadcastImmediate can only be called on the server")
	Network.Server.broadcastImmediate(packet, data)
end

const function invoke(packet, responseSchema, data)
	assert(isClient, "Burn.invoke can only be called on the client")
	return Network.Client.invoke(packet, responseSchema, data)
end

const function handleRequest(packet, responseSchema, handler)
	assert(isServer, "Burn.handleRequest can only be called on the server")
	Network.Server.handleRequest(packet, responseSchema, handler)
end

const function definePacket(name, packetType, schema, explicitId)
	return Packet.Registry.register(name, packetType, schema, explicitId)
end

const Burn = table.freeze({
	Types = DataTypes,

	definePacket = definePacket,
	getPacketById = Packet.Registry.getById,
	getPacketByName = Packet.Registry.getByName,

	on = on,
	once = once,
	wait = wait,
	send = send,
	sendImmediate = sendImmediate,
	broadcast = broadcast,
	broadcastExcept = broadcastExcept,
	broadcastImmediate = broadcastImmediate,
	invoke = invoke,
	handleRequest = handleRequest,

	Buffer = Buffer.ByteBuffer,
	Cursor = Buffer.Cursor,

	Server = Network.Server,
	Client = Network.Client,

	isServer = isServer,
	isClient = isClient,

	Constants = Constants,
})

return Burn
