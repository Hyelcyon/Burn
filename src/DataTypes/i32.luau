--!strict

--[=[
	@within DataTypes
	Signed 32-bit integer TypeDescriptor (range [-2,147,483,648, 2,147,483,647], little-endian).
]=]
@native
const function write(buf: buffer, offset: number, value: number): number
	buffer.writei32(buf, offset, value)
	return offset + 4
end

@native
const function read(buf: buffer, offset: number): (number, number)
	return buffer.readi32(buf, offset), offset + 4
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
