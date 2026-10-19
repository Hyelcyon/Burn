--!strict

const Constants = require("@src/Constants")
const Types = require("@src/Types")
const Definition = require("@packet/Definition")

export type PacketOptions = Types.PacketOptions

--[=[
	@class Registry
	@within Packet
	Central registry mapping unique packet names and 1-byte wire IDs (0-255).
]=]
const Registry = {}

local packetsById: { [number]: Types.ErasedPacketDefinition } = {}
local packetsByName: { [string]: Types.ErasedPacketDefinition } = {}
local nextAutoId = 1

Registry.rawById = packetsById

--[=[
	Registers a packet definition with a unique name, wire transport type, and payload schema.
	Allocates the lowest available numeric ID if none is explicitly specified.
]=]
function Registry.register<T>(
	name: string,
	packetType: Types.PacketType,
	schema: Types.TypeDescriptor<T>,
	optionsOrId: (number | PacketOptions | Types.PacketPriority)?,
	maybePriority: Types.PacketPriority?
): Types.PacketDefinition<T>
	assert(packetsByName[name] == nil, `Packet '{name}' is already registered`)

	local explicitId: number?
	local priority: Types.PacketPriority? = maybePriority

	if typeof(optionsOrId) == "table" then
		explicitId = optionsOrId.id
		if optionsOrId.priority ~= nil then
			priority = optionsOrId.priority
		end
	elseif typeof(optionsOrId) == "number" then
		explicitId = optionsOrId
	elseif typeof(optionsOrId) == "string" then
		priority = optionsOrId :: Types.PacketPriority
	end

	local id: number
	if explicitId == nil then
		while packetsById[nextAutoId] ~= nil do
			nextAutoId += 1
		end
		if nextAutoId > Constants.MAX_PACKET_ID then
			error(`Maximum packet ID limit reached ({Constants.MAX_PACKET_ID})`)
		end
		id = nextAutoId
		nextAutoId += 1
	else
		assert(typeof(explicitId) == "number" and explicitId % 1 == 0, "Explicit packet ID must be an integer")
		assert(
			explicitId >= 0 and explicitId <= Constants.MAX_PACKET_ID,
			`Packet ID must be between 0 and {Constants.MAX_PACKET_ID}`
		)
		assert(
			packetsById[explicitId] == nil,
			`Packet ID {explicitId} is already in use by '{if packetsById[explicitId]
				then packetsById[explicitId].name
				else ""}'`
		)
		id = explicitId
	end

	const def = Definition(id, name, packetType, schema, priority)
	packetsById[id] = def
	packetsByName[name] = def

	return def
end

function Registry.getById(id: number): Types.ErasedPacketDefinition?
	return packetsById[id]
end

function Registry.getByName(name: string): Types.ErasedPacketDefinition?
	return packetsByName[name]
end

function Registry.clear()
	table.clear(packetsById)
	table.clear(packetsByName)
	nextAutoId = 1
end

return Registry
