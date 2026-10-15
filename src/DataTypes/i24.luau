--!strict

--[=[
	@within DataTypes
	Signed 24-bit integer TypeDescriptor (range [-8,388,608, 8,388,607]).
	Encoded in 3 bytes: little-endian u16 low bits + i8 sign-extended high bits.
]=]
@native
const function write(buf: buffer, offset: number, value: number): number
	buffer.writeu16(buf, offset, bit32.band(value, 0xFFFF))
	buffer.writei8(buf, offset + 2, bit32.arshift(value, 16))
	return offset + 3
end

@native
const function read(buf: buffer, offset: number): (number, number)
	const low = buffer.readu16(buf, offset)
	const high = buffer.readi8(buf, offset + 2)
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
