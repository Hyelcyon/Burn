--!strict

const Types = require(script.Parent.Parent.Types)

export type PacketType = Types.PacketType
export type PacketDefinition<T> = Types.PacketDefinition<T>

const function definePacket<T>(
	id: number,
	name: string,
	packetType: PacketType,
	schema: Types.TypeDescriptor<T>
): PacketDefinition<T>
	assert(typeof(id) == "number" and id % 1 == 0, "Packet ID must be an integer")
	assert(typeof(name) == "string" and #name > 0, "Packet name must be a non-empty string")
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

	return {
		id = id,
		name = name,
		packetType = packetType,
		schema = schema,
	}
end

return definePacket
