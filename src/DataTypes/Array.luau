--!strict

const Types = require("@src/Types")

const function Array<T>(elementDescriptor: Types.TypeDescriptor<T>): Types.TypeDescriptor<{ T }>
	const elemWrite = elementDescriptor.write
	const elemRead = elementDescriptor.read
	const elemSkip = elementDescriptor.skip

	@native
	const function write(buf: buffer, offset: number, list: { T }): number
		local currentOffset = offset
		const count = #list
		buffer.writeu16(buf, currentOffset, count)
		currentOffset += 2

		for index = 1, count do
			currentOffset = elemWrite(buf, currentOffset, list[index])
		end

		return currentOffset
	end

	@native
	const function read(buf: buffer, offset: number): ({ T }, number)
		const count = buffer.readu16(buf, offset)
		local currentOffset = offset + 2

		const list: { T } = table.create(count)
		local item: T
		for index = 1, count do
			item, currentOffset = elemRead(buf, currentOffset)
			list[index] = item
		end

		return list, currentOffset
	end

	local skip: (buf: buffer, offset: number) -> number
	const elemSize = elementDescriptor.size
	if elemSize ~= nil then
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
