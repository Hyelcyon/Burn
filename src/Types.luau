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
}

export type AnyPacketDefinition = {
	read id: number,
	read name: string,
	read packetType: PacketType,
	read priority: PacketPriority,
	read priorityIndex: number,
	read schema: AnyTypeDescriptor,
}

export type ErasedPacketDefinition = AnyPacketDefinition

--[=[
	@interface Connection
	@within Burn
	.disconnect (self: Connection) -> () -- Unregisters the listener callback.
]=]
export type Connection = {
	disconnect: (self: Connection) -> (),
}

export type NetworkContext = {
	instances: { Instance }?,
}

return nil
