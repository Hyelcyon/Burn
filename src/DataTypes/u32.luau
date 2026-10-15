--!strict

--[=[
	@within DataTypes
	Unsigned 32-bit integer TypeDescriptor (range [0, 4,294,967,295], little-endian).
]=]
@native
const function write(buf: buffer, offset: number, value: number): number
	buffer.writeu32(buf, offset, value)
	return offset + 4
end

@native
const function read(buf: buffer, offset: number): (number, number)
	return buffer.readu32(buf, offset), offset + 4
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 4
end

return table.freeze({
	size = 4,
	write = write,
	read = read,
	skip = skip,
})
