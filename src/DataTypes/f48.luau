--!strict

const scratch = buffer.create(8)

@native
const function write(buf: buffer, offset: number, value: number): number
	buffer.writef64(scratch, 0, value)
	buffer.copy(buf, offset, scratch, 2, 6)
	return offset + 6
end

@native
const function read(buf: buffer, offset: number): (number, number)
	buffer.writeu16(scratch, 0, 0)
	buffer.copy(scratch, 2, buf, offset, 6)
	return buffer.readf64(scratch, 0), offset + 6
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 6
end

return table.freeze({
	size = 6,
	write = write,
	read = read,
	skip = skip,
})
