--!strict

const Types = require("@src/Types")
const vec3 = require("@datatypes/Vector3")
const cf = require("@datatypes/CFrame")
const color3 = require("@datatypes/Color3")

const TAG_NIL = 0x0
const TAG_BOOLEAN = 0x1
const TAG_SMALL_INT = 0x2
const TAG_I8 = 0x3
const TAG_I16 = 0x4
const TAG_I32 = 0x5
const TAG_F64 = 0x6
const TAG_SHORT_STRING = 0x7
const TAG_LONG_STRING = 0x8
const TAG_BUFFER = 0x9
const TAG_VECTOR3 = 0xA
const TAG_CFRAME = 0xB
const TAG_COLOR3 = 0xC
const TAG_SHORT_ARRAY = 0xD
const TAG_LONG_ARRAY = 0xE
const TAG_MAP = 0xF

@native
const function write(buf: buffer, offset: number, value: unknown): number
	if value == nil then
		buffer.writeu8(buf, offset, bit32.lshift(TAG_NIL, 4))
		return offset + 1
	end

	const valType = typeof(value)

	if valType == "boolean" then
		const flag = if value then 1 else 0
		buffer.writeu8(buf, offset, bit32.bor(bit32.lshift(TAG_BOOLEAN, 4), flag))
		return offset + 1
	elseif valType == "number" then
		const num = value :: number
		if num % 1 == 0 and num >= 0 and num <= 15 then
			buffer.writeu8(buf, offset, bit32.bor(bit32.lshift(TAG_SMALL_INT, 4), num))
			return offset + 1
		elseif num % 1 == 0 and num >= -128 and num <= 127 then
			buffer.writeu8(buf, offset, bit32.lshift(TAG_I8, 4))
			buffer.writei8(buf, offset + 1, num)
			return offset + 2
		elseif num % 1 == 0 and num >= -32768 and num <= 32767 then
			buffer.writeu8(buf, offset, bit32.lshift(TAG_I16, 4))
			buffer.writei16(buf, offset + 1, num)
			return offset + 3
		elseif num % 1 == 0 and num >= -2147483648 and num <= 2147483647 then
			buffer.writeu8(buf, offset, bit32.lshift(TAG_I32, 4))
			buffer.writei32(buf, offset + 1, num)
			return offset + 5
		else
			buffer.writeu8(buf, offset, bit32.lshift(TAG_F64, 4))
			buffer.writef64(buf, offset + 1, num)
			return offset + 9
		end
	elseif valType == "string" then
		const str = value :: string
		const len = #str
		if len <= 14 then
			buffer.writeu8(buf, offset, bit32.bor(bit32.lshift(TAG_SHORT_STRING, 4), len))
			if len > 0 then
				buffer.writestring(buf, offset + 1, str, len)
			end
			return offset + 1 + len
		else
			buffer.writeu8(buf, offset, bit32.lshift(TAG_LONG_STRING, 4))
			buffer.writeu16(buf, offset + 1, len)
			buffer.writestring(buf, offset + 3, str, len)
			return offset + 3 + len
		end
	elseif valType == "buffer" then
		const raw = value :: buffer
		const len = buffer.len(raw)
		buffer.writeu8(buf, offset, bit32.lshift(TAG_BUFFER, 4))
		buffer.writeu16(buf, offset + 1, len)
		if len > 0 then
			buffer.copy(buf, offset + 3, raw, 0, len)
		end
		return offset + 3 + len
	elseif valType == "Vector3" then
		buffer.writeu8(buf, offset, bit32.lshift(TAG_VECTOR3, 4))
		return vec3.write(buf, offset + 1, value :: Vector3)
	elseif valType == "CFrame" then
		buffer.writeu8(buf, offset, bit32.lshift(TAG_CFRAME, 4))
		return cf.write(buf, offset + 1, value :: CFrame)
	elseif valType == "Color3" then
		buffer.writeu8(buf, offset, bit32.lshift(TAG_COLOR3, 4))
		return color3.write(buf, offset + 1, value :: Color3)
	elseif valType == "table" then
		const tbl = value :: { [unknown]: unknown }
		const arrLen = #tbl
		const isArray = (arrLen > 0 or tbl[1] ~= nil or next(tbl) == nil)
			and next(tbl, if arrLen > 0 then arrLen else nil) == nil

		if isArray then
			if arrLen <= 14 then
				buffer.writeu8(buf, offset, bit32.bor(bit32.lshift(TAG_SHORT_ARRAY, 4), arrLen))
				local curr = offset + 1
				for i = 1, arrLen do
					curr = write(buf, curr, tbl[i])
				end
				return curr
			else
				buffer.writeu8(buf, offset, bit32.lshift(TAG_LONG_ARRAY, 4))
				buffer.writeu16(buf, offset + 1, arrLen)
				local curr = offset + 3
				for i = 1, arrLen do
					curr = write(buf, curr, tbl[i])
				end
				return curr
			end
		else
			buffer.writeu8(buf, offset, bit32.lshift(TAG_MAP, 4))
			local count = 0
			local curr = offset + 3
			for k, v in tbl do
				count += 1
				curr = write(buf, curr, k)
				curr = write(buf, curr, v)
			end
			buffer.writeu16(buf, offset + 1, count)
			return curr
		end
	end

	error(`[Burn] Unsupported type for Auto serializer: '{valType}'`)
end

@native
const function read(buf: buffer, offset: number): (unknown, number)
	const tagByte = buffer.readu8(buf, offset)
	const tagType = bit32.rshift(tagByte, 4)
	const inlineData = bit32.band(tagByte, 0x0F)

	if tagType == TAG_NIL then
		return nil, offset + 1
	elseif tagType == TAG_BOOLEAN then
		return inlineData == 1, offset + 1
	elseif tagType == TAG_SMALL_INT then
		return inlineData, offset + 1
	elseif tagType == TAG_I8 then
		return buffer.readi8(buf, offset + 1), offset + 2
	elseif tagType == TAG_I16 then
		return buffer.readi16(buf, offset + 1), offset + 3
	elseif tagType == TAG_I32 then
		return buffer.readi32(buf, offset + 1), offset + 5
	elseif tagType == TAG_F64 then
		return buffer.readf64(buf, offset + 1), offset + 9
	elseif tagType == TAG_SHORT_STRING then
		if inlineData == 0 then
			return "", offset + 1
		end
		return buffer.readstring(buf, offset + 1, inlineData), offset + 1 + inlineData
	elseif tagType == TAG_LONG_STRING then
		const len = buffer.readu16(buf, offset + 1)
		if len == 0 then
			return "", offset + 3
		end
		return buffer.readstring(buf, offset + 3, len), offset + 3 + len
	elseif tagType == TAG_BUFFER then
		const len = buffer.readu16(buf, offset + 1)
		const res = buffer.create(len)
		if len > 0 then
			buffer.copy(res, 0, buf, offset + 3, len)
		end
		return res, offset + 3 + len
	elseif tagType == TAG_VECTOR3 then
		return vec3.read(buf, offset + 1)
	elseif tagType == TAG_CFRAME then
		return cf.read(buf, offset + 1)
	elseif tagType == TAG_COLOR3 then
		return color3.read(buf, offset + 1)
	elseif tagType == TAG_SHORT_ARRAY then
		const count = inlineData
		const arr = table.create(count)
		local curr = offset + 1
		local item: unknown
		for i = 1, count do
			item, curr = read(buf, curr)
			arr[i] = item
		end
		return arr, curr
	elseif tagType == TAG_LONG_ARRAY then
		const count = buffer.readu16(buf, offset + 1)
		const arr = table.create(count)
		local curr = offset + 3
		local item: unknown
		for i = 1, count do
			item, curr = read(buf, curr)
			arr[i] = item
		end
		return arr, curr
	elseif tagType == TAG_MAP then
		const count = buffer.readu16(buf, offset + 1)
		const map: { [unknown]: unknown } = {}
		local curr = offset + 3
		local k: unknown
		local v: unknown
		for _ = 1, count do
			k, curr = read(buf, curr)
			v, curr = read(buf, curr)
			map[k] = v
		end
		return map, curr
	end

	error(`[Burn] Corrupted packet: Unknown Auto tag type '{tagType}' at offset {offset}`)
end

@native
const function skip(buf: buffer, offset: number): number
	const tagByte = buffer.readu8(buf, offset)
	const tagType = bit32.rshift(tagByte, 4)
	const inlineData = bit32.band(tagByte, 0x0F)

	if tagType == TAG_NIL or tagType == TAG_BOOLEAN or tagType == TAG_SMALL_INT then
		return offset + 1
	elseif tagType == TAG_I8 then
		return offset + 2
	elseif tagType == TAG_I16 then
		return offset + 3
	elseif tagType == TAG_I32 then
		return offset + 5
	elseif tagType == TAG_F64 then
		return offset + 9
	elseif tagType == TAG_SHORT_STRING then
		return offset + 1 + inlineData
	elseif tagType == TAG_LONG_STRING or tagType == TAG_BUFFER then
		const len = buffer.readu16(buf, offset + 1)
		return offset + 3 + len
	elseif tagType == TAG_VECTOR3 then
		return offset + 1 + 12
	elseif tagType == TAG_CFRAME then
		return offset + 1 + 28
	elseif tagType == TAG_COLOR3 then
		return offset + 1 + 3
	elseif tagType == TAG_SHORT_ARRAY then
		local curr = offset + 1
		for _ = 1, inlineData do
			curr = skip(buf, curr)
		end
		return curr
	elseif tagType == TAG_LONG_ARRAY then
		const count = buffer.readu16(buf, offset + 1)
		local curr = offset + 3
		for _ = 1, count do
			curr = skip(buf, curr)
		end
		return curr
	elseif tagType == TAG_MAP then
		const count = buffer.readu16(buf, offset + 1)
		local curr = offset + 3
		for _ = 1, count do
			curr = skip(buf, curr)
			curr = skip(buf, curr)
		end
		return curr
	end

	error(`[Burn] Corrupted packet: Unknown Auto tag type '{tagType}' at offset {offset}`)
end

const Auto: Types.TypeDescriptor<unknown> = table.freeze({
	size = nil,
	write = write,
	read = read,
	skip = skip,
})

return Auto
