--!strict

const Types = require("@src/Types")

--[=[
	@within DataTypes
	1-byte boolean TypeDescriptor (0 = false, 1 = true).
]=]
@native
const function write(buf: buffer, offset: number, value: boolean): number
	buffer.writeu8(buf, offset, if value then 1 else 0)
	return offset + 1
end

@native
const function read(buf: buffer, offset: number): (boolean, number)
	return buffer.readu8(buf, offset) ~= 0, offset + 1
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 1
end

const descriptor: Types.TypeDescriptor<boolean> = table.freeze({
	size = 1,
	write = write,
	read = read,
	skip = skip,
})

return descriptor
