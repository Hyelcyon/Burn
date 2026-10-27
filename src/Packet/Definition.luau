--!strict

const Types = require("@src/Types")

export type PacketType = Types.PacketType
export type PacketPriority = Types.PacketPriority
export type PacketDefinition<T> = Types.PacketDefinition<T>
export type NetworkBindings = Types.NetworkBindings

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

function PacketMethods.send<T>(self: Types.PacketDefinition<T>, arg1: Player | { Player } | T, arg2: T?)
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	if arg2 ~= nil or isPlayerOrPlayerList(arg1) then
		networkBindings.send(arg1 :: Player | { Player }, self, arg2)
	else
		networkBindings.send(self, arg1 :: T)
	end
end

function PacketMethods.sendImmediate<T>(self: Types.PacketDefinition<T>, arg1: Player | { Player } | T, arg2: T?)
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	if arg2 ~= nil or isPlayerOrPlayerList(arg1) then
		networkBindings.sendImmediate(arg1 :: Player | { Player }, self, arg2)
	else
		networkBindings.sendImmediate(self, arg1 :: T)
	end
end

function PacketMethods.broadcast<T>(self: Types.PacketDefinition<T>, data: T)
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	networkBindings.broadcast(self, data)
end

function PacketMethods.broadcastExcept<T>(self: Types.PacketDefinition<T>, excludedPlayer: Player, data: T)
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	networkBindings.broadcastExcept(excludedPlayer, self, data)
end

function PacketMethods.broadcastImmediate<T>(self: Types.PacketDefinition<T>, data: T)
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	networkBindings.broadcastImmediate(self, data)
end

function PacketMethods.on<T>(
	self: Types.PacketDefinition<T>,
	listener: ((T) -> ()) | ((Player, T) -> ())
): Types.Connection
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	return networkBindings.on(self, listener :: (Player, T) -> ())
end

function PacketMethods.once<T>(
	self: Types.PacketDefinition<T>,
	listener: ((T) -> ()) | ((Player, T) -> ())
): Types.Connection
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	return networkBindings.once(self, listener :: (Player, T) -> ())
end

function PacketMethods.wait<T>(self: Types.PacketDefinition<T>): (Player?, T)
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	return networkBindings.wait(self)
end

function PacketMethods.invoke<T, ResD>(self: Types.PacketHandle<T>, responseSchema: ResD, data: T): Types.InferType<ResD>?
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	return networkBindings.invoke(self, responseSchema, data)
end

function PacketMethods.handleRequest<T, ResD>(
	self: Types.PacketHandle<T>,
	responseSchema: ResD,
	handler: (Player, T) -> Types.InferType<ResD>
)
	if networkBindings == nil then
		error("[Burn] Network bindings not initialized; require Burn root first")
	end
	networkBindings.handleRequest(self, responseSchema, handler)
end

--[=[
	@within Packet
	Validates packet parameters and constructs an immutable PacketDefinition.
]=]
const function definePacket<D>(
	id: number,
	name: string,
	packetType: PacketType,
	schema: D,
	priority: PacketPriority?
): PacketDefinition<Types.InferType<D>>
	type T = Types.InferType<D>

	assert(typeof(id) == "number" and id % 1 == 0, "Packet ID must be an integer")
	assert(typeof(name) == "string" and #name > 0, "Packet name must be a non-empty string")
	const resolvedPacketType: PacketType = packetType
	assert(
		packetType == "Reliable" or packetType == "Unreliable" or packetType == "Request",
		"Invalid packetType; must be 'Reliable', 'Unreliable', or 'Request'"
	)
	const schemaDesc = schema :: Types.AnyTypeDescriptor
	assert(
		typeof(schemaDesc) == "table"
			and typeof(schemaDesc.write) == "function"
			and typeof(schemaDesc.read) == "function"
			and typeof(schemaDesc.skip) == "function",
		"Invalid schema; must have write, read, and skip functions"
	)

	const resolvedPriority, priorityIndex = priorityToIndex(priority)

	return table.freeze(setmetatable({
		id = id,
		name = name,
		packetType = resolvedPacketType,
		priority = resolvedPriority,
		priorityIndex = priorityIndex,
		schema = schema :: any,
	}, PacketMethods)) :: PacketDefinition<T>
end

-- Invariant: Attaching helper functions to callable constructors requires boundary casting in Luau --!strict
-- as function and table types cannot intersect without type incompatibility.
local ExportDefinition = setmetatable({
	setNetworkBindings = function(bindings: NetworkBindings)
		networkBindings = bindings
	end,
}, {
	__call = function<D>(
		_self: unknown,
		id: number,
		name: string,
		packetType: PacketType,
		schema: D,
		priority: PacketPriority?
	): PacketDefinition<Types.InferType<D>>
		return definePacket(id, name, packetType, schema, priority)
	end,
})

return ExportDefinition
