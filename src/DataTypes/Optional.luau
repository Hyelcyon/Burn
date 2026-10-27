--!strict

const Types = require("@src/Types")

export type OptionalDescriptor<T> = Types.TypeDescriptor<T?>

--[=[
	@within DataTypes
	Creates an Optional TypeDescriptor prefixed with a 1-byte presence flag (0 = nil, 1 = present).
]=]
const function Optional<T>(descriptor: Types.TypeDescriptor<T>): OptionalDescriptor<T>
	const innerWrite = descriptor.write
	const innerRead = descriptor.read
	const innerSkip = descriptor.skip
	const innerSize = descriptor.size

	@native
	const function write(buf: buffer, offset: number, value: T?): number
		if value == nil then
			buffer.writeu8(buf, offset, 0)
			return offset + 1
		end
		buffer.writeu8(buf, offset, 1)
		return innerWrite(buf, offset + 1, value)
	end

	@native
	const function read(buf: buffer, offset: number): (T?, number)
		const bufLen = buffer.len(buf)
		if offset >= bufLen then
			error(`[Burn] Buffer underflow: cannot read Optional flag at offset {offset} (bufLen {bufLen})`)
		end
		if buffer.readu8(buf, offset) ~= 0 then
			return innerRead(buf, offset + 1)
		end
		return nil, offset + 1
	end

	local skip: (buf: buffer, offset: number) -> number
	if innerSize ~= nil then
		const fixedSize = innerSize
		@native
		local function skipFixed(buf: buffer, offset: number): number
			const bufLen = buffer.len(buf)
			if offset >= bufLen then
				error(`[Burn] Buffer underflow: cannot read Optional flag at offset {offset} (bufLen {bufLen})`)
			end
			if buffer.readu8(buf, offset) ~= 0 then
				const nextOffset = offset + 1 + fixedSize
				if nextOffset > bufLen then
					error(`[Burn] Buffer underflow: Optional payload exceeds buffer size {bufLen}`)
				end
				return nextOffset
			end
			return offset + 1
		end
		skip = skipFixed
	else
		@native
		local function skipDynamic(buf: buffer, offset: number): number
			const bufLen = buffer.len(buf)
			if offset >= bufLen then
				error(`[Burn] Buffer underflow: cannot read Optional flag at offset {offset} (bufLen {bufLen})`)
			end
			if buffer.readu8(buf, offset) ~= 0 then
				return innerSkip(buf, offset + 1)
			end
			return offset + 1
		end
		skip = skipDynamic
	end

	return table.freeze({
		size = nil,
		write = write,
		read = read,
		skip = skip,
	})
end

return Optional
