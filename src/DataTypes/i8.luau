--!strict

@native
const function write(buf: buffer, offset: number, value: number): number
	buffer.writei8(buf, offset, value)
	return offset + 1
end

@native
const function read(buf: buffer, offset: number): (number, number)
	return buffer.readi8(buf, offset), offset + 1
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 1
end

return table.freeze({
	size = 1,
	write = write,
	read = read,
	skip = skip,
})
