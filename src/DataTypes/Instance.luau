--!strict

const Types = require("@src/Types")

export type InstanceDescriptor<T = Instance?> = Types.TypeDescriptor<T>

--[=[
	@within DataTypes
	2-byte placeholder TypeDescriptor for Instance references.
	Raw Luau buffers cannot store Roblox instance pointers directly without external ID mapping.
]=]
@native
const function write(buf: buffer, offset: number, _value: Instance?): number
	buffer.writeu16(buf, offset, 0)
	return offset + 2
end

@native
const function read(buf: buffer, offset: number): (Instance?, number)
	const bufLen = buffer.len(buf)
	if offset + 2 > bufLen then
		error(`[Burn] Buffer underflow: cannot read Instance reference at offset {offset} (bufLen {bufLen})`)
	end
	return nil, offset + 2
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 2
end

const descriptor: Types.TypeDescriptor<Instance?> = table.freeze({
	size = 2,
	write = write,
	read = read,
	skip = skip,
})

return descriptor
