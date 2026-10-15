--!strict

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

export type PacketType = "Reliable" | "Unreliable" | "Request"

export type PacketPriority = "Low" | "Medium" | "High" | "Max"

export type PacketOptions = {
	id: number?,
	priority: PacketPriority?,
}

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

export type Connection = {
	disconnect: (self: Connection) -> (),
}

export type NetworkContext = {
	instances: { Instance }?,
}

return nil
