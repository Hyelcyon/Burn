--!strict

const Types = require("@src/Types")

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
	const bufLen = buffer.len(buf)
	if offset + 4 > bufLen then
		error(`[Burn] Buffer underflow: cannot read raw buffer length at offset {offset} (bufLen {bufLen})`)
	end
	const len = buffer.readu32(buf, offset)
	const nextOffset = offset + 4 + len
	if nextOffset > bufLen then
		error(
			`[Burn] Buffer underflow: raw buffer payload of length {len} at offset {offset + 4} exceeds buffer size {bufLen}`
		)
	end
	const result = buffer.create(len)
	buffer.copy(result, 0, buf, offset + 4, len)
	return result, nextOffset
end

@native
const function skip(buf: buffer, offset: number): number
	const bufLen = buffer.len(buf)
	if offset + 4 > bufLen then
		error(`[Burn] Buffer underflow: cannot read raw buffer length at offset {offset} (bufLen {bufLen})`)
	end
	const len = buffer.readu32(buf, offset)
	const nextOffset = offset + 4 + len
	if nextOffset > bufLen then
		error(
			`[Burn] Buffer underflow: raw buffer payload of length {len} at offset {offset + 4} exceeds buffer size {bufLen}`
		)
	end
	return nextOffset
end

const descriptor: Types.TypeDescriptor<buffer> = table.freeze({
	size = nil,
	write = write,
	read = read,
	skip = skip,
})

return descriptor
