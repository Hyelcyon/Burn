--!strict

--[=[
	@interface TypeDescriptor<T>
	@within Types
	.size number? -- Exact byte size if statically known (enables O(1) skips and zero-copy direct serialization).
	.write (buf: buffer, offset: number, value: T) -> number -- Encodes value into buffer at offset, returns next offset.
	.read (buf: buffer, offset: number) -> (T, number) -- Decodes value from buffer at offset, returns (value, nextOffset).
	.skip (buf: buffer, offset: number) -> number -- Advances offset past value without allocating objects.

	Core binary serialization contract for all Burn schemas.
	Properties are annotated with `read` for immutable property covariance under Luau New Type Solver V2.
]=]
export type TypeDescriptor<T> = {
	read size: number?,
	read write: (buf: buffer, offset: number, value: T) -> number,
	read read: (buf: buffer, offset: number) -> (T, number),
	read skip: (buf: buffer, offset: number) -> number,
}

--[=[
	@interface AnyTypeDescriptor
	@within Types

	Universal covariant supertype for heterogeneous TypeDescriptors without using `any`.
]=]
export type AnyTypeDescriptor = {
	read size: number?,
	read write: (buf: buffer, offset: number, value: never) -> number,
	read read: (buf: buffer, offset: number) -> (unknown, number),
	read skip: (buf: buffer, offset: number) -> number,
}

export type ErasedTypeDescriptor = AnyTypeDescriptor

--[=[
	@type PacketType "Reliable" | "Unreliable" | "Request"
	@within Types

	Transmission reliability mode:
	- `Reliable`: Ordered, guaranteed delivery via RemoteEvent.
	- `Unreliable`: Unordered, loss-tolerant delivery via UnreliableRemoteEvent (max 900 bytes/batch).
	- `Request`: Two-way client-server RPC request/response via RemoteFunction.
]=]
export type PacketType = "Reliable" | "Unreliable" | "Request"

--[=[
	@type PacketPriority "Low" | "Medium" | "High" | "Max"
	@within Types

	4-tier packet priority channel for congestion-controlled queueing and flush ordering:
	- `Low`: Background syncing, telemetry, low-frequency stats.
	- `Medium`: Default priority for general gameplay interactions.
	- `High`: Time-sensitive combat, state changes, physics inputs.
	- `Max`: Critical handshakes, immediate state reconciliation, transactional packets.
]=]
export type PacketPriority = "Low" | "Medium" | "High" | "Max"

--[=[
	@interface PacketOptions
	@within Types
	.id number? -- Optional explicit packet ID (0..255).
	.priority PacketPriority? -- Packet dispatch priority channel.
]=]
export type PacketOptions = {
	id: number?,
	priority: PacketPriority?,
}

--[=[
	@interface PacketDefinition<T>
	@within Types
	.id number -- Pre-assigned unique 1-byte packet identifier (0..255).
	.name string -- Human-readable identifier registered in packet registry.
	.packetType PacketType -- Reliability mode ("Reliable" | "Unreliable" | "Request").
	.priority PacketPriority -- Pre-assigned priority level.
	.priorityIndex number -- Precomputed 1-based index (1..4) for O(1) buffer queue routing.
	.schema TypeDescriptor<T> -- Binary serialization descriptor for payload.
]=]
export type PacketDefinition<T> = {
	read id: number,
	read name: string,
	read packetType: PacketType,
	read priority: PacketPriority,
	read priorityIndex: number,
	read schema: TypeDescriptor<T>,
}

--[=[
	@interface AnyPacketDefinition
	@within Types

	Universal erased packet definition supertype for heterogeneous packet lookup arrays.
]=]
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
	@within Types
	.disconnect (self: Connection) -> () -- Disconnects the listener from incoming packet events.
]=]
export type Connection = {
	disconnect: (self: Connection) -> (),
}

export type NetworkContext = {
	instances: { Instance }?,
}

return nil
