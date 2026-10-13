--!strict

const Constants = require(script.Parent.Parent.Constants)
const Types = require(script.Parent.Parent.Types)
const Definition = require(script.Parent.Definition)

const Registry = {}

local packetsById: { [number]: Types.PacketDefinition<any> } = {}
local packetsByName: { [string]: Types.PacketDefinition<any> } = {}
local nextAutoId = 1

function Registry.register<T>(
	name: string,
	packetType: Types.PacketType,
	schema: Types.TypeDescriptor<T>,
	explicitId: number?
): Types.PacketDefinition<T>
	assert(packetsByName[name] == nil, `Packet '{name}' is already registered`)

	local id: number
	if explicitId == nil then
		while packetsById[nextAutoId] ~= nil do
			nextAutoId += 1
			if nextAutoId > Constants.MAX_PACKET_ID then
				error("Maximum packet ID limit reached (255)")
			end
		end
		id = nextAutoId
		nextAutoId += 1
	else
		assert(
			packetsById[explicitId] == nil,
			`Packet ID {explicitId} is already in use by '{if packetsById[explicitId]
				then packetsById[explicitId].name
				else ""}'`
		)
		assert(
			explicitId >= 0 and explicitId <= Constants.MAX_PACKET_ID,
			`Packet ID must be between 0 and {Constants.MAX_PACKET_ID}`
		)
		id = explicitId
	end

	const def = Definition(id, name, packetType, schema)
	packetsById[id] = def
	packetsByName[name] = def

	return def
end

function Registry.getById(id: number): Types.PacketDefinition<any>?
	return packetsById[id]
end

function Registry.getByName(name: string): Types.PacketDefinition<any>?
	return packetsByName[name]
end

function Registry.clear()
	table.clear(packetsById)
	table.clear(packetsByName)
	nextAutoId = 1
end

return Registry
