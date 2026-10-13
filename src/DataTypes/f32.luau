--!strict

@native
const function write(buf: buffer, offset: number, value: number): number
	buffer.writef32(buf, offset, value)
	return offset + 4
end

@native
const function read(buf: buffer, offset: number): (number, number)
	return buffer.readf32(buf, offset), offset + 4
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
