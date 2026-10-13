--!strict

export type TypeDescriptor<T> = {
	size: number?,
	write: (buf: buffer, offset: number, value: T) -> number,
	read: (buf: buffer, offset: number) -> (T, number),
	skip: (buf: buffer, offset: number) -> number,
}

export type PacketType = "Reliable" | "Unreliable" | "Request"

export type PacketDefinition<T> = {
	id: number,
	name: string,
	packetType: PacketType,
	schema: TypeDescriptor<T>,
}

export type Connection = {
	disconnect: (self: Connection) -> (),
}

export type NetworkContext = {
	instances: { Instance }?,
}

return nil
