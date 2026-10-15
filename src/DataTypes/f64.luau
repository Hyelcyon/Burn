--!strict

--[=[
	@within DataTypes
	64-bit IEEE 754 double-precision floating-point TypeDescriptor (8 bytes, little-endian).
]=]
@native
const function write(buf: buffer, offset: number, value: number): number
	buffer.writef64(buf, offset, value)
	return offset + 8
end

@native
const function read(buf: buffer, offset: number): (number, number)
	return buffer.readf64(buf, offset), offset + 8
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 8
end

return table.freeze({
	size = 8,
	write = write,
	read = read,
	skip = skip,
})
