--!strict

const Types = require("@src/Types")

export type PacketType = Types.PacketType
export type PacketPriority = Types.PacketPriority
export type PacketDefinition<T> = Types.PacketDefinition<T>

-- Invariant: NetworkBindings decouples PacketDefinition from Burn root to avoid circular dependency.
-- Dynamic parameter signatures use boundary types to accept generic root dispatchers without contravariant solver errors.
export type NetworkBindings = {
	send: (targetOrPacket: any, packetOrData: any, maybeData: any?) -> (),
	sendImmediate: (targetOrPacket: any, packetOrData: any, maybeData: any?) -> (),
	broadcast: (packet: any, data: any) -> (),
	broadcastExcept: (excludedPlayer: Player, packet: any, data: any) -> (),
	broadcastImmediate: (packet: any, data: any) -> (),
	on: (packet: any, listener: any) -> Types.Connection,
	once: (packet: any, listener: any) -> Types.Connection,
	wait: (packet: any) -> ...any,
	invoke: (packet: any, responseSchema: any, data: any) -> any,
	handleRequest: (packet: any, responseSchema: any, handler: any) -> (),
}

local networkBindings: NetworkBindings? = nil

-- Maps priority labels to 1-based buffer queue indices (1=Low, 2=Medium, 3=High, 4=Max).
-- Queues are drained in descending index order (4 down to 1) when flushing batched frames.
const function priorityToIndex(priority: PacketPriority?): (PacketPriority, number)
	if priority == "Max" then
		return "Max", 4
	elseif priority == "High" then
		return "High", 3
	elseif priority == "Low" then
		return "Low", 1
	else
		return "Medium", 2
	end
end

const function isPlayerOrPlayerList(val: unknown): boolean
	if typeof(val) == "Instance" then
		return (val :: Instance):IsA("Player")
	elseif typeof(val) == "table" then
		return (val :: { id: unknown? }).id == nil
	end
	return false
end

local PacketMethods = {}
PacketMethods.__index = PacketMethods

function PacketMethods.send(self: Types.AnyPacketDefinition, arg1: any, arg2: any?)
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	if arg2 ~= nil or isPlayerOrPlayerList(arg1) then
		networkBindings.send(arg1, self, arg2)
	else
		networkBindings.send(self, arg1)
	end
end

function PacketMethods.sendImmediate(self: Types.AnyPacketDefinition, arg1: any, arg2: any?)
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	if arg2 ~= nil or isPlayerOrPlayerList(arg1) then
		networkBindings.sendImmediate(arg1, self, arg2)
	else
		networkBindings.sendImmediate(self, arg1)
	end
end

function PacketMethods.broadcast(self: Types.AnyPacketDefinition, data: any)
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	networkBindings.broadcast(self, data)
end

function PacketMethods.broadcastExcept(self: Types.AnyPacketDefinition, excludedPlayer: Player, data: any)
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	networkBindings.broadcastExcept(excludedPlayer, self, data)
end

function PacketMethods.broadcastImmediate(self: Types.AnyPacketDefinition, data: any)
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	networkBindings.broadcastImmediate(self, data)
end

function PacketMethods.on(self: Types.AnyPacketDefinition, listener: any): Types.Connection
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	return networkBindings.on(self, listener)
end

function PacketMethods.once(self: Types.AnyPacketDefinition, listener: any): Types.Connection
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	return networkBindings.once(self, listener)
end

function PacketMethods.wait(self: Types.AnyPacketDefinition): ...any
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	return networkBindings.wait(self)
end

function PacketMethods.invoke(self: Types.AnyPacketDefinition, responseSchema: any, data: any): any
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	return networkBindings.invoke(self, responseSchema, data)
end

function PacketMethods.handleRequest(self: Types.AnyPacketDefinition, responseSchema: any, handler: any)
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	networkBindings.handleRequest(self, responseSchema, handler)
end

--[=[
	@within Packet
	Validates packet parameters and constructs an immutable PacketDefinition.
]=]
const function definePacket<T>(
	id: number,
	name: string,
	packetType: PacketType,
	schema: Types.TypeDescriptor<T>,
	priority: PacketPriority?
): PacketDefinition<T>
	assert(typeof(id) == "number" and id % 1 == 0, "Packet ID must be an integer")
	assert(typeof(name) == "string" and #name > 0, "Packet name must be a non-empty string")
	const resolvedPacketType: PacketType = packetType
	assert(
		packetType == "Reliable" or packetType == "Unreliable" or packetType == "Request",
		"Invalid packetType; must be 'Reliable', 'Unreliable', or 'Request'"
	)
	assert(
		typeof(schema) == "table"
			and typeof(schema.write) == "function"
			and typeof(schema.read) == "function"
			and typeof(schema.skip) == "function",
		"Invalid schema; must have write, read, and skip functions"
	)

	const resolvedPriority, priorityIndex = priorityToIndex(priority)

	return table.freeze(setmetatable({
		id = id,
		name = name,
		packetType = resolvedPacketType,
		priority = resolvedPriority,
		priorityIndex = priorityIndex,
		schema = schema,
	}, PacketMethods)) :: PacketDefinition<T>
end

-- Invariant: Attaching helper functions to callable constructors requires boundary casting in Luau --!strict
-- as function and table types cannot intersect without type incompatibility.
local ExportDefinition = setmetatable({
	setNetworkBindings = function(bindings: NetworkBindings)
		networkBindings = bindings
	end,
}, {
	__call = function(_self, ...)
		return definePacket(...)
	end,
}) :: any

return ExportDefinition
