--!strict

const Types = require("@src/Types")

export type PacketType = Types.PacketType
export type PacketPriority = Types.PacketPriority
export type PacketDefinition<T> = Types.PacketDefinition<T>

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

	return {
		id = id,
		name = name,
		packetType = resolvedPacketType,
		priority = resolvedPriority,
		priorityIndex = priorityIndex,
		schema = schema,
	}
end

return definePacket
