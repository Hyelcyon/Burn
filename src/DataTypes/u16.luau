--!strict

const Types = require("@src/Types")

--[=[
	@within DataTypes
	Unsigned 16-bit integer TypeDescriptor (range [0, 65,535], little-endian).
]=]
@native
const function write(buf: buffer, offset: number, value: number): number
	buffer.writeu16(buf, offset, value)
	return offset + 2
end

@native
const function read(buf: buffer, offset: number): (number, number)
	return buffer.readu16(buf, offset), offset + 2
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 2
end

const descriptor: Types.TypeDescriptor<number> = table.freeze({
	size = 2,
	write = write,
	read = read,
	skip = skip,
})

return descriptor
