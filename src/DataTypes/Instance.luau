--!strict

@native
const function write(buf: buffer, offset: number, _value: Instance?): number
	buffer.writeu16(buf, offset, 0)
	return offset + 2
end

@native
const function read(_buf: buffer, offset: number): (Instance?, number)
	return nil, offset + 2
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
