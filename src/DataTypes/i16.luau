--!strict

@native
const function write(buf: buffer, offset: number, value: number): number
	buffer.writei16(buf, offset, value)
	return offset + 2
end

@native
const function read(buf: buffer, offset: number): (number, number)
	return buffer.readi16(buf, offset), offset + 2
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 2
end

return table.freeze({
	size = 2,
	write = write,
	read = read,
	skip = skip,
})
