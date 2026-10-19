--!strict

--[=[
	@interface TypeDescriptor
	@within Burn
	.size number? -- Fixed byte length if statically known; nil for variable-length types.
	.write (buf: buffer, offset: number, value: T) -> number -- Serializes `value` into `buf` starting at `offset`, returning the next offset.
	.read (buf: buffer, offset: number) -> (T, number) -- Deserializes a value from `buf` at `offset`, returning the value and next offset.
	.skip (buf: buffer, offset: number) -> number -- Advances `offset` past the encoded value without allocating or decoding.

	Contract defining binary serialization, deserialization, and skipping for a type.
]=]
export type TypeDescriptor<T> = {
	read size: number?,
	read write: (buf: buffer, offset: number, value: T) -> number,
	read read: (buf: buffer, offset: number) -> (T, number),
	read skip: (buf: buffer, offset: number) -> number,
}

export type AnyTypeDescriptor = {
	read size: number?,
	read write: (buf: buffer, offset: number, value: never) -> number,
	read read: (buf: buffer, offset: number) -> (unknown, number),
	read skip: (buf: buffer, offset: number) -> number,
}

export type ErasedTypeDescriptor = AnyTypeDescriptor

--[=[
	@type PacketType "Reliable" | "Unreliable" | "Request"
	@within Burn
	Underlying network transport:
	- `Reliable`: Ordered and guaranteed delivery via RemoteEvent.
	- `Unreliable`: Unordered, drop-tolerant delivery via UnreliableRemoteEvent.
	- `Request`: Two-way synchronous invocation via RemoteFunction.
]=]
export type PacketType = "Reliable" | "Unreliable" | "Request"

--[=[
	@type PacketPriority "Low" | "Medium" | "High" | "Max"
	@within Burn
	Transmission priority determining the order in which packets are concatenated into batched buffers.
]=]
export type PacketPriority = "Low" | "Medium" | "High" | "Max"

--[=[
	@interface PacketOptions
	@within Burn
	.id number? -- Optional explicit packet ID (0-255).
	.priority PacketPriority? -- Transmission priority.
]=]
export type PacketOptions = {
	id: number?,
	priority: PacketPriority?,
}

--[=[
	@interface PacketDefinition
	@within Burn
	.id number -- 1-byte wire identifier.
	.name string -- Unique human-readable packet name.
	.packetType PacketType -- Reliable, Unreliable, or Request.
	.priority PacketPriority -- Transmission priority.
	.priorityIndex number -- Numeric priority index (1=Low, 4=Max).
	.schema TypeDescriptor<T> -- Binary schema for payload serialization.
]=]
export type PacketDefinition<T> = {
	read id: number,
	read name: string,
	read packetType: PacketType,
	read priority: PacketPriority,
	read priorityIndex: number,
	read schema: TypeDescriptor<T>,

	read send: (self: PacketDefinition<T>, targetOrData: Player | { Player } | T, maybeData: T?) -> (),
	read sendImmediate: (self: PacketDefinition<T>, targetOrData: Player | { Player } | T, maybeData: T?) -> (),
	read broadcast: (self: PacketDefinition<T>, data: T) -> (),
	read broadcastExcept: (self: PacketDefinition<T>, excludedPlayer: Player, data: T) -> (),
	read broadcastImmediate: (self: PacketDefinition<T>, data: T) -> (),
	read on: (self: PacketDefinition<T>, listener: ((T) -> ()) | ((Player, T) -> ())) -> Connection,
	read once: (self: PacketDefinition<T>, listener: ((T) -> ()) | ((Player, T) -> ())) -> Connection,
	read wait: (self: PacketDefinition<T>) -> (Player?, T),
	read invoke: <Res>(self: PacketDefinition<T>, responseSchema: TypeDescriptor<Res>, data: T) -> Res?,
	read handleRequest: <Res>(
		self: PacketDefinition<T>,
		responseSchema: TypeDescriptor<Res>,
		handler: (Player, T) -> Res
	) -> (),
}

export type AnyPacketDefinition = {
	read id: number,
	read name: string,
	read packetType: PacketType,
	read priority: PacketPriority,
	read priorityIndex: number,
	read schema: AnyTypeDescriptor,

	read send: (self: AnyPacketDefinition, targetOrData: unknown, maybeData: unknown?) -> (),
	read sendImmediate: (self: AnyPacketDefinition, targetOrData: unknown, maybeData: unknown?) -> (),
	read broadcast: (self: AnyPacketDefinition, data: unknown) -> (),
	read broadcastExcept: (self: AnyPacketDefinition, excludedPlayer: Player, data: unknown) -> (),
	read broadcastImmediate: (self: AnyPacketDefinition, data: unknown) -> (),
	read on: (self: AnyPacketDefinition, listener: (unknown, unknown?) -> ()) -> Connection,
	read once: (self: AnyPacketDefinition, listener: (unknown, unknown?) -> ()) -> Connection,
	read wait: (self: AnyPacketDefinition) -> ...unknown,
	read invoke: (self: AnyPacketDefinition, responseSchema: AnyTypeDescriptor, data: unknown) -> unknown,
	read handleRequest: (
		self: AnyPacketDefinition,
		responseSchema: AnyTypeDescriptor,
		handler: (unknown, unknown) -> unknown
	) -> (),
}

export type ErasedPacketDefinition = AnyPacketDefinition

--[=[
	@interface Connection
	@within Burn
	.disconnect (self: Connection) -> () -- Unregisters the listener callback.
	.Disconnect (self: Connection) -> () -- PascalCase alias conforming to Roblox convention.
]=]
export type Connection = {
	disconnect: (self: Connection) -> (),
	Disconnect: (self: Connection) -> (),
}

export type NetworkContext = {
	instances: { Instance }?,
}

type function InferType(D: type)
	if not D:is("table") then
		return types.unknown
	end

	local target = D
	const schemaProp = D:readproperty(types.singleton("schema"))
	if schemaProp and schemaProp:is("table") then
		target = schemaProp
	end

	const readProp = target:readproperty(types.singleton("read"))
	if readProp and readProp:is("function") then
		const rets = readProp:returns().head
		if rets and #rets > 0 then
			return rets[1]
		end
	end

	return types.unknown
end

export type Infer<D> = InferType<D>
export type TypeOf<D> = InferType<D>
export type InferPacket<P> = InferType<P>

return nil
