--!strict

const Types = require("@src/Types")

type function InferStructType(T: type)
	if not T:is("table") then
		return types.unknown
	end
	const resultTable = types.newtable()
	const readKey = types.singleton("read")
	for key, prop in T:properties() do
		const descType = prop.read or prop.write
		if descType and descType:is("table") then
			const readProp = descType:readproperty(readKey)
			if readProp and readProp:is("function") then
				const rets = readProp:returns().head
				if rets and #rets > 0 then
					resultTable:setproperty(key, rets[1])
				end
			end
		end
	end
	return resultTable
end

type FieldEntry = {
	key: string,
	desc: Types.AnyTypeDescriptor,
}

--[=[
	@within DataTypes
	Creates a structured record TypeDescriptor from a map of field descriptors.
	Fields are serialized in lexicographical order to guarantee wire-format stability.
]=]
const function Struct<F>(fields: F & { read [string]: Types.AnyTypeDescriptor }): Types.TypeDescriptor<InferStructType<F>>
	type T = InferStructType<F>

	const fieldMap: { read [string]: Types.AnyTypeDescriptor } = fields

	-- Luau hash map iteration order is non-deterministic. Sorting keys lexicographically
	-- guarantees an identical binary layout across sender and receiver runtimes.
	const keys: { string } = {}
	for k in fieldMap do
		table.insert(keys, k)
	end
	table.sort(keys)

	const orderedFields: { FieldEntry } = {}
	local totalFixedSize: number? = 0

	for _, k in keys do
		const desc = fieldMap[k]
		table.insert(orderedFields, {
			key = k,
			desc = desc,
		})
		if totalFixedSize ~= nil then
			const descSize = desc.size
			if descSize ~= nil then
				totalFixedSize = totalFixedSize + descSize
			else
				totalFixedSize = nil
			end
		end
	end

	const fieldCount = #orderedFields

	const fieldKeys = table.create(fieldCount, "")
	const fieldWrites: { (buf: buffer, offset: number, value: unknown) -> number } = {}
	const fieldReads: { (buf: buffer, offset: number) -> (unknown, number) } = {}
	const fieldSkips: { (buf: buffer, offset: number) -> number } = {}

	-- Pre-shaped template: table.clone(template) leverages the VM's fast allocation path
	-- with pre-allocated hash node capacity matching the struct shape.
	const template: { [string]: unknown } = {}
	for i = 1, fieldCount do
		const entry = orderedFields[i]
		fieldKeys[i] = entry.key
		fieldWrites[i] = entry.desc.write :: (buf: buffer, offset: number, value: unknown) -> number
		fieldReads[i] = entry.desc.read
		fieldSkips[i] = entry.desc.skip
		template[entry.key] = false
	end

	local write: (buf: buffer, offset: number, value: T) -> number
	local read: (buf: buffer, offset: number) -> (T, number)

	-- Specialized 1-6 field implementations eliminate loop counters and dynamic table lookup overhead.
	if fieldCount == 1 then
		const k1 = fieldKeys[1]
		const w1 = fieldWrites[1]
		const r1 = fieldReads[1]

		@native
		local function write1(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: unknown }
			return w1(buf, offset, val[k1])
		end

		@native
		local function read1(buf: buffer, offset: number): (T, number)
			const v1, o1 = r1(buf, offset)
			const res = table.clone(template)
			res[k1] = v1
			return res :: T, o1
		end

		write = write1
		read = read1
	elseif fieldCount == 2 then
		const k1, k2 = fieldKeys[1], fieldKeys[2]
		const w1, w2 = fieldWrites[1], fieldWrites[2]
		const r1, r2 = fieldReads[1], fieldReads[2]

		@native
		local function write2(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: unknown }
			const o1 = w1(buf, offset, val[k1])
			return w2(buf, o1, val[k2])
		end

		@native
		local function read2(buf: buffer, offset: number): (T, number)
			const v1, o1 = r1(buf, offset)
			const v2, o2 = r2(buf, o1)
			const res = table.clone(template)
			res[k1] = v1
			res[k2] = v2
			return res :: T, o2
		end

		write = write2
		read = read2
	elseif fieldCount == 3 then
		const k1, k2, k3 = fieldKeys[1], fieldKeys[2], fieldKeys[3]
		const w1, w2, w3 = fieldWrites[1], fieldWrites[2], fieldWrites[3]
		const r1, r2, r3 = fieldReads[1], fieldReads[2], fieldReads[3]

		@native
		local function write3(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: unknown }
			const o1 = w1(buf, offset, val[k1])
			const o2 = w2(buf, o1, val[k2])
			return w3(buf, o2, val[k3])
		end

		@native
		local function read3(buf: buffer, offset: number): (T, number)
			const v1, o1 = r1(buf, offset)
			const v2, o2 = r2(buf, o1)
			const v3, o3 = r3(buf, o2)
			const res = table.clone(template)
			res[k1] = v1
			res[k2] = v2
			res[k3] = v3
			return res :: T, o3
		end

		write = write3
		read = read3
	elseif fieldCount == 4 then
		const k1, k2, k3, k4 = fieldKeys[1], fieldKeys[2], fieldKeys[3], fieldKeys[4]
		const w1, w2, w3, w4 = fieldWrites[1], fieldWrites[2], fieldWrites[3], fieldWrites[4]
		const r1, r2, r3, r4 = fieldReads[1], fieldReads[2], fieldReads[3], fieldReads[4]

		@native
		local function write4(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: unknown }
			const o1 = w1(buf, offset, val[k1])
			const o2 = w2(buf, o1, val[k2])
			const o3 = w3(buf, o2, val[k3])
			return w4(buf, o3, val[k4])
		end

		@native
		local function read4(buf: buffer, offset: number): (T, number)
			const v1, o1 = r1(buf, offset)
			const v2, o2 = r2(buf, o1)
			const v3, o3 = r3(buf, o2)
			const v4, o4 = r4(buf, o3)
			const res = table.clone(template)
			res[k1] = v1
			res[k2] = v2
			res[k3] = v3
			res[k4] = v4
			return res :: T, o4
		end

		write = write4
		read = read4
	elseif fieldCount == 5 then
		const k1, k2, k3, k4, k5 = fieldKeys[1], fieldKeys[2], fieldKeys[3], fieldKeys[4], fieldKeys[5]
		const w1, w2, w3, w4, w5 = fieldWrites[1], fieldWrites[2], fieldWrites[3], fieldWrites[4], fieldWrites[5]
		const r1, r2, r3, r4, r5 = fieldReads[1], fieldReads[2], fieldReads[3], fieldReads[4], fieldReads[5]

		@native
		local function write5(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: unknown }
			const o1 = w1(buf, offset, val[k1])
			const o2 = w2(buf, o1, val[k2])
			const o3 = w3(buf, o2, val[k3])
			const o4 = w4(buf, o3, val[k4])
			return w5(buf, o4, val[k5])
		end

		@native
		local function read5(buf: buffer, offset: number): (T, number)
			const v1, o1 = r1(buf, offset)
			const v2, o2 = r2(buf, o1)
			const v3, o3 = r3(buf, o2)
			const v4, o4 = r4(buf, o3)
			const v5, o5 = r5(buf, o4)
			const res = table.clone(template)
			res[k1] = v1
			res[k2] = v2
			res[k3] = v3
			res[k4] = v4
			res[k5] = v5
			return res :: T, o5
		end

		write = write5
		read = read5
	elseif fieldCount == 6 then
		const k1, k2, k3, k4, k5, k6 =
			fieldKeys[1], fieldKeys[2], fieldKeys[3], fieldKeys[4], fieldKeys[5], fieldKeys[6]
		const w1, w2, w3, w4, w5, w6 =
			fieldWrites[1], fieldWrites[2], fieldWrites[3], fieldWrites[4], fieldWrites[5], fieldWrites[6]
		const r1, r2, r3, r4, r5 = fieldReads[1], fieldReads[2], fieldReads[3], fieldReads[4], fieldReads[5]
		const r6 = fieldReads[6]

		@native
		local function write6(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: unknown }
			const o1 = w1(buf, offset, val[k1])
			const o2 = w2(buf, o1, val[k2])
			const o3 = w3(buf, o2, val[k3])
			const o4 = w4(buf, o3, val[k4])
			const o5 = w5(buf, o4, val[k5])
			return w6(buf, o5, val[k6])
		end

		@native
		local function read6(buf: buffer, offset: number): (T, number)
			const v1, o1 = r1(buf, offset)
			const v2, o2 = r2(buf, o1)
			const v3, o3 = r3(buf, o2)
			const v4, o4 = r4(buf, o3)
			const v5, o5 = r5(buf, o4)
			const v6, o6 = r6(buf, o5)
			const res = table.clone(template)
			res[k1] = v1
			res[k2] = v2
			res[k3] = v3
			res[k4] = v4
			res[k5] = v5
			res[k6] = v6
			return res :: T, o6
		end

		write = write6
		read = read6
	else
		@native
		local function writeGeneral(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: unknown }
			local currentOffset = offset
			for index = 1, fieldCount do
				currentOffset = fieldWrites[index](buf, currentOffset, val[fieldKeys[index]])
			end
			return currentOffset
		end

		@native
		local function readGeneral(buf: buffer, offset: number): (T, number)
			local currentOffset = offset
			const result = table.clone(template)
			local item: unknown
			for index = 1, fieldCount do
				item, currentOffset = fieldReads[index](buf, currentOffset)
				result[fieldKeys[index]] = item
			end
			return result :: T, currentOffset
		end

		write = writeGeneral
		read = readGeneral
	end

	local skip: (buf: buffer, offset: number) -> number
	if totalFixedSize ~= nil then
		const fixedSize = totalFixedSize
		-- O(1) skip: When every field has a known fixed size, advance the offset directly without memory access.
		@native
		local function skipFixed(_buf: buffer, offset: number): number
			return offset + fixedSize
		end
		skip = skipFixed
	else
		@native
		local function skipDynamic(buf: buffer, offset: number): number
			local currentOffset = offset
			for index = 1, fieldCount do
				currentOffset = fieldSkips[index](buf, currentOffset)
			end
			return currentOffset
		end
		skip = skipDynamic
	end

	return {
		size = totalFixedSize,
		write = write,
		read = read,
		skip = skip,
	}
end

return Struct
