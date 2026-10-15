--!strict

--[=[
	@within DataTypes
	Raw binary buffer TypeDescriptor prefixed with a 4-byte (u32) byte length.
]=]
@native
const function write(buf: buffer, offset: number, value: buffer): number
	const len = buffer.len(value)
	buffer.writeu32(buf, offset, len)
	buffer.copy(buf, offset + 4, value, 0, len)
	return offset + 4 + len
end

@native
const function read(buf: buffer, offset: number): (buffer, number)
	const len = buffer.readu32(buf, offset)
	const result = buffer.create(len)
	buffer.copy(result, 0, buf, offset + 4, len)
	return result, offset + 4 + len
end

@native
const function skip(buf: buffer, offset: number): number
	const len = buffer.readu32(buf, offset)
	return offset + 4 + len
end

return table.freeze({
	size = nil,
	write = write,
	read = read,
	skip = skip,
})
