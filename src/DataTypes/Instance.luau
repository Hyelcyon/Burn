--!strict

const _Types = require("@src/Types")

export type InstanceDescriptor<T = Instance?> = {
	read size: number?,
	read write: (buf: buffer, offset: number, value: T) -> number,
	read read: (buf: buffer, offset: number) -> (T, number),
	read skip: (buf: buffer, offset: number) -> number,
	read setOutgoingInstances: (instances: { Instance }?) -> (),
	read getOutgoingInstances: () -> { Instance }?,
	read setIncomingInstances: (instances: { Instance }?) -> (),
	read getIncomingInstances: () -> { Instance }?,
}

-- Invariant: Luau buffers cannot store raw Roblox C++ Instance pointers.
-- Instances are tracked in an ephemeral side-car table replicated alongside the buffer
-- via Roblox's native RemoteEvent / RemoteFunction serialization.
-- The 2-byte (u16) payload encodes a 1-based index into the active instances array,
-- with 0 representing nil.
local activeOutgoingInstances: { Instance }? = nil
local activeIncomingInstances: { Instance }? = nil

const function setOutgoingInstances(instances: { Instance }?)
	activeOutgoingInstances = instances
end

const function getOutgoingInstances(): { Instance }?
	return activeOutgoingInstances
end

const function setIncomingInstances(instances: { Instance }?)
	activeIncomingInstances = instances
end

const function getIncomingInstances(): { Instance }?
	return activeIncomingInstances
end

@native
const function write(buf: buffer, offset: number, value: Instance?): number
	local outgoing = activeOutgoingInstances
	if value == nil or outgoing == nil then
		buffer.writeu16(buf, offset, 0)
		return offset + 2
	end

	const list: { Instance } = outgoing
	local id = #list + 1
	if id > 65535 then
		error(`[Burn] Instance count {id} exceeds maximum u16 limit (65535)`)
	end
	list[id] = value
	buffer.writeu16(buf, offset, id)
	return offset + 2
end

@native
const function read(buf: buffer, offset: number): (Instance?, number)
	const bufLen = buffer.len(buf)
	if offset + 2 > bufLen then
		error(`[Burn] Buffer underflow: cannot read Instance reference at offset {offset} (bufLen {bufLen})`)
	end
	const id = buffer.readu16(buf, offset)
	local incoming = activeIncomingInstances
	if id == 0 or incoming == nil then
		return nil, offset + 2
	end

	const list: { Instance } = incoming
	if id > #list then
		return nil, offset + 2
	end

	return list[id], offset + 2
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 2
end

const descriptor: InstanceDescriptor<Instance?> = table.freeze({
	size = 2,
	write = write,
	read = read,
	skip = skip,
	setOutgoingInstances = setOutgoingInstances,
	getOutgoingInstances = getOutgoingInstances,
	setIncomingInstances = setIncomingInstances,
	getIncomingInstances = getIncomingInstances,
})

return descriptor
