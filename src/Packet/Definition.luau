--!strict

const Types = require(script.Parent.Parent.Types)

export type PacketType = Types.PacketType
export type PacketDefinition<T> = Types.PacketDefinition<T>

const function definePacket<T>(id: number, name: string, packetType: PacketType, schema: Types.TypeDescriptor<T>)
	assert(typeof(id) == "number", "Packet ID must be a number")
	assert(typeof(name) == "string" and #name > 0, "Packet name must be a non-empty string")
	assert(
		typeof(schema) == "table"
			and typeof(schema.write) == "function"
			and typeof(schema.read) == "function"
			and typeof(schema.skip) == "function",
		"Invalid schema; must have write, read, and skip functions"
	)

	return {
		id = id,
		name = name,
		packetType = packetType,
		schema = schema,
	}
end

return definePacket
