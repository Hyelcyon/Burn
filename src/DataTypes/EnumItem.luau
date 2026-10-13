--!strict

const Types = require(script.Parent.Parent.Types)

@native
const function write(buf: buffer, offset: number, value: EnumItem): number
	buffer.writeu16(buf, offset, value.Value)
	return offset + 2
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 2
end

const function createEnumItemDescriptor(enumType): Types.TypeDescriptor<EnumItem>
	const itemsByValue: { [number]: EnumItem } = {}
	for _, item in enumType:GetEnumItems() do
		itemsByValue[item.Value] = item
	end

	@native
	const function read(buf: buffer, offset: number): (EnumItem, number)
		const val = buffer.readu16(buf, offset)
		return itemsByValue[val], offset + 2
	end

	return {
		size = 2,
		write = write,
		read = read,
		skip = skip,
	}
end

return createEnumItemDescriptor
