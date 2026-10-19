--!strict

const Types = require("@src/Types")

--[=[
	@within DataTypes
	UTF-8 string TypeDescriptor prefixed with a 2-byte (u16) length (max 65,535 bytes).
]=]
@native
const function write(buf: buffer, offset: number, value: string): number
	const len = #value
	if len > 65535 then
		error(`[Burn] String length {len} exceeds u16 limit (65535)`)
	end
	buffer.writeu16(buf, offset, len)
	buffer.writestring(buf, offset + 2, value)
	return offset + 2 + len
end

@native
const function read(buf: buffer, offset: number): (string, number)
	const bufLen = buffer.len(buf)
	if offset + 2 > bufLen then
		error(`[Burn] Buffer underflow: cannot read string length at offset {offset} (bufLen {bufLen})`)
	end
	const len = buffer.readu16(buf, offset)
	const nextOffset = offset + 2 + len
	if nextOffset > bufLen then
		error(
			`[Burn] Buffer underflow: string payload of length {len} at offset {offset + 2} exceeds buffer size {bufLen}`
		)
	end
	const str = buffer.readstring(buf, offset + 2, len)
	return str, nextOffset
end

@native
const function skip(buf: buffer, offset: number): number
	const bufLen = buffer.len(buf)
	if offset + 2 > bufLen then
		error(`[Burn] Buffer underflow: cannot read string length at offset {offset} (bufLen {bufLen})`)
	end
	const len = buffer.readu16(buf, offset)
	const nextOffset = offset + 2 + len
	if nextOffset > bufLen then
		error(
			`[Burn] Buffer underflow: string payload of length {len} at offset {offset + 2} exceeds buffer size {bufLen}`
		)
	end
	return nextOffset
end

const descriptor: Types.TypeDescriptor<string> = table.freeze({
	size = nil,
	write = write,
	read = read,
	skip = skip,
})

return descriptor
