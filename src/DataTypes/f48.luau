--!strict

const Types = require("@src/Types")

--[=[
	@within DataTypes
	48-bit (6-byte) floating-point TypeDescriptor.
	Truncates the 16 least-significant mantissa bits of a little-endian IEEE 754 double (bytes 0-1),
	preserving full dynamic range (sign + 11-bit exponent) and 36 bits of precision while saving 2 bytes.
]=]
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

const descriptor: Types.TypeDescriptor<number> = table.freeze({
	size = 6,
	write = write,
	read = read,
	skip = skip,
})

return descriptor
