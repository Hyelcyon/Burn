--!strict

--[=[
	@within DataTypes
	UTF-8 string TypeDescriptor prefixed with a 2-byte (u16) length (max 65,535 bytes).
]=]
@native
const function write(buf: buffer, offset: number, value: string): number
	const len = #value
	buffer.writeu16(buf, offset, len)
	buffer.writestring(buf, offset + 2, value)
	return offset + 2 + len
end

@native
const function read(buf: buffer, offset: number): (string, number)
	const len = buffer.readu16(buf, offset)
	const str = buffer.readstring(buf, offset + 2, len)
	return str, offset + 2 + len
end

@native
const function skip(buf: buffer, offset: number): number
	const len = buffer.readu16(buf, offset)
	return offset + 2 + len
end

return table.freeze({
	size = nil,
	write = write,
	read = read,
	skip = skip,
})
