--!strict

const Types = require("@src/Types")

--[=[
	@within DataTypes
	Creates a variable-length list TypeDescriptor with a 2-byte (u16) element count prefix.
]=]
const function Array<T>(elementDescriptor: Types.TypeDescriptor<T>): Types.TypeDescriptor<{ T }>
	const elemWrite = elementDescriptor.write
	const elemRead = elementDescriptor.read
	const elemSkip = elementDescriptor.skip
	const elemSize = elementDescriptor.size

	@native
	const function write(buf: buffer, offset: number, list: { T }): number
		local currentOffset = offset
		const count = #list
		if count > 65535 then
			error(`[Burn] Array element count {count} exceeds u16 limit (65535)`)
		end
		buffer.writeu16(buf, currentOffset, count)
		currentOffset += 2

		for index = 1, count do
			currentOffset = elemWrite(buf, currentOffset, list[index])
		end

		return currentOffset
	end

	@native
	const function read(buf: buffer, offset: number): ({ T }, number)
		const bufLen = buffer.len(buf)
		if offset + 2 > bufLen then
			error(`[Burn] Buffer underflow: cannot read array count at offset {offset} (bufLen {bufLen})`)
		end
		const count = buffer.readu16(buf, offset)
		local currentOffset = offset + 2

		if elemSize ~= nil and currentOffset + count * elemSize > bufLen then
			error(`[Burn] Buffer underflow: array of {count} fixed elements exceeds buffer size {bufLen}`)
		end

		const list: { T } = table.create(count)
		local item: T
		for index = 1, count do
			item, currentOffset = elemRead(buf, currentOffset)
			list[index] = item
		end

		return list, currentOffset
	end

	local skip: (buf: buffer, offset: number) -> number
	if elemSize ~= nil then
		-- O(1) skip: Fixed-size elements allow calculating the total payload offset without loop traversal.
		@native
		local function skipFixed(buf: buffer, offset: number): number
			const count = buffer.readu16(buf, offset)
			return offset + 2 + count * elemSize
		end
		skip = skipFixed
	else
		@native
		local function skipDynamic(buf: buffer, offset: number): number
			const count = buffer.readu16(buf, offset)
			local currentOffset = offset + 2

			for _ = 1, count do
				currentOffset = elemSkip(buf, currentOffset)
			end

			return currentOffset
		end
		skip = skipDynamic
	end

	return {
		size = nil,
		write = write,
		read = read,
		skip = skip,
	}
end

return Array
