--!strict

const Types = require("@src/Types")

--[=[
	@within DataTypes
	Unsigned 8-bit integer TypeDescriptor (range [0, 255]).
]=]
@native
const function write(buf: buffer, offset: number, value: number): number
	buffer.writeu8(buf, offset, value)
	return offset + 1
end

@native
const function read(buf: buffer, offset: number): (number, number)
	return buffer.readu8(buf, offset), offset + 1
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 1
end

const descriptor: Types.TypeDescriptor<number> = table.freeze({
	size = 1,
	write = write,
	read = read,
	skip = skip,
})

return descriptor
