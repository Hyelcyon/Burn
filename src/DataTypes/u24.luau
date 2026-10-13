--!strict

@native
const function write(buf: buffer, offset: number, value: number): number
	buffer.writeu16(buf, offset, bit32.band(value, 0xFFFF))
	buffer.writeu8(buf, offset + 2, bit32.rshift(value, 16))
	return offset + 3
end

@native
const function read(buf: buffer, offset: number): (number, number)
	const low = buffer.readu16(buf, offset)
	const high = buffer.readu8(buf, offset + 2)
	return low + high * 65536, offset + 3
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 3
end

return table.freeze({
	size = 3,
	write = write,
	read = read,
	skip = skip,
})
