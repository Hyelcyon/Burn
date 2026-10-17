--!strict

const Types = require("@src/Types")

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
const function read(_buf: buffer, offset: number): (Instance?, number)
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
