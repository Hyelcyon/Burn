--!strict

const Types = require("@src/Types")
const vec3 = require("@datatypes/Vector3")
const cf = require("@datatypes/CFrame")
const color3 = require("@datatypes/Color3")

--[=[
	@within DataTypes
	Self-describing dynamic serializer for untyped or heterogeneous values.

	Wire header: 1 byte where upper 4 bits encode the type tag (0x0-0xF) and lower 4 bits
	encode inline payload metadata (boolean flag, 0-15 small integer, or length <= 14).
]=]
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

-- Pre-shifted 1-byte wire header tags (upper 4 bits) to eliminate runtime bit32.lshift operations.
const HDR_NIL = 0x00
const HDR_BOOLEAN = 0x10
const HDR_SMALL_INT = 0x20
const HDR_I8 = 0x30
const HDR_I16 = 0x40
const HDR_I32 = 0x50
const HDR_F64 = 0x60
const HDR_SHORT_STRING = 0x70
const HDR_LONG_STRING = 0x80
const HDR_BUFFER = 0x90
const HDR_VECTOR3 = 0xA0
const HDR_CFRAME = 0xB0
const HDR_COLOR3 = 0xC0
const HDR_SHORT_ARRAY = 0xD0
const HDR_LONG_ARRAY = 0xE0
const HDR_MAP = 0xF0

-- Numbers are dynamically packed into the narrowest lossless representation:
-- small int 0-15 (1 byte total), i8 (2 bytes), i16 (3 bytes), i32 (5 bytes), or f64 (9 bytes).
@native
const function write(buf: buffer, offset: number, value: unknown): number
	if value == nil then
		buffer.writeu8(buf, offset, HDR_NIL)
		return offset + 1
	end

	const valType = typeof(value)

	if valType == "boolean" then
		buffer.writeu8(buf, offset, if value then HDR_BOOLEAN + 1 else HDR_BOOLEAN)
		return offset + 1
	elseif valType == "number" then
		const num = value :: number
		if num % 1 == 0 then
			if num >= 0 and num <= 15 then
				buffer.writeu8(buf, offset, HDR_SMALL_INT + num)
				return offset + 1
			elseif num >= -128 and num <= 127 then
				buffer.writeu8(buf, offset, HDR_I8)
				buffer.writei8(buf, offset + 1, num)
				return offset + 2
			elseif num >= -32768 and num <= 32767 then
				buffer.writeu8(buf, offset, HDR_I16)
				buffer.writei16(buf, offset + 1, num)
				return offset + 3
			elseif num >= -2147483648 and num <= 2147483647 then
				buffer.writeu8(buf, offset, HDR_I32)
				buffer.writei32(buf, offset + 1, num)
				return offset + 5
			end
		end
		buffer.writeu8(buf, offset, HDR_F64)
		buffer.writef64(buf, offset + 1, num)
		return offset + 9
	elseif valType == "string" then
		const str = value :: string
		const len = #str
		if len <= 14 then
			buffer.writeu8(buf, offset, HDR_SHORT_STRING + len)
			if len > 0 then
				buffer.writestring(buf, offset + 1, str, len)
			end
			return offset + 1 + len
		else
			if len > 65535 then
				error(`[Burn] String length {len} exceeds u16 limit (65535) in Auto serializer`)
			end
			buffer.writeu8(buf, offset, HDR_LONG_STRING)
			buffer.writeu16(buf, offset + 1, len)
			buffer.writestring(buf, offset + 3, str, len)
			return offset + 3 + len
		end
	elseif valType == "buffer" then
		const raw = value :: buffer
		const len = buffer.len(raw)
		if len > 65535 then
			error(`[Burn] Buffer length {len} exceeds u16 limit (65535) in Auto serializer`)
		end
		buffer.writeu8(buf, offset, HDR_BUFFER)
		buffer.writeu16(buf, offset + 1, len)
		if len > 0 then
			buffer.copy(buf, offset + 3, raw, 0, len)
		end
		return offset + 3 + len
	elseif valType == "Vector3" then
		buffer.writeu8(buf, offset, HDR_VECTOR3)
		return vec3.write(buf, offset + 1, value :: Vector3)
	elseif valType == "CFrame" then
		buffer.writeu8(buf, offset, HDR_CFRAME)
		return cf.write(buf, offset + 1, value :: CFrame)
	elseif valType == "Color3" then
		buffer.writeu8(buf, offset, HDR_COLOR3)
		return color3.write(buf, offset + 1, value :: Color3)
	elseif valType == "table" then
		const tbl = value :: { [unknown]: unknown }
		const arrLen = #tbl
		const isArray = (arrLen > 0 or tbl[1] ~= nil or next(tbl) == nil)
			and next(tbl, if arrLen > 0 then arrLen else nil) == nil

		if isArray then
			if arrLen <= 14 then
				buffer.writeu8(buf, offset, HDR_SHORT_ARRAY + arrLen)
				local curr = offset + 1
				for i = 1, arrLen do
					curr = write(buf, curr, tbl[i])
				end
				return curr
			else
				if arrLen > 65535 then
					error(`[Burn] Array element count {arrLen} exceeds u16 limit (65535) in Auto serializer`)
				end
				buffer.writeu8(buf, offset, HDR_LONG_ARRAY)
				buffer.writeu16(buf, offset + 1, arrLen)
				local curr = offset + 3
				for i = 1, arrLen do
					curr = write(buf, curr, tbl[i])
				end
				return curr
			end
		else
			buffer.writeu8(buf, offset, HDR_MAP)
			local count = 0
			local curr = offset + 3
			for k, v in tbl do
				count += 1
				if count > 65535 then
					error(`[Burn] Map entry count exceeds u16 limit (65535) in Auto serializer`)
				end
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
	const bufLen = buffer.len(buf)
	if offset >= bufLen then
		error(`[Burn] Buffer underflow: cannot read Auto tag at offset {offset} (bufLen {bufLen})`)
	end
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
		if offset + 2 > bufLen then
			error(`[Burn] Buffer underflow: cannot read i8 at offset {offset + 1} (bufLen {bufLen})`)
		end
		return buffer.readi8(buf, offset + 1), offset + 2
	elseif tagType == TAG_I16 then
		if offset + 3 > bufLen then
			error(`[Burn] Buffer underflow: cannot read i16 at offset {offset + 1} (bufLen {bufLen})`)
		end
		return buffer.readi16(buf, offset + 1), offset + 3
	elseif tagType == TAG_I32 then
		if offset + 5 > bufLen then
			error(`[Burn] Buffer underflow: cannot read i32 at offset {offset + 1} (bufLen {bufLen})`)
		end
		return buffer.readi32(buf, offset + 1), offset + 5
	elseif tagType == TAG_F64 then
		if offset + 9 > bufLen then
			error(`[Burn] Buffer underflow: cannot read f64 at offset {offset + 1} (bufLen {bufLen})`)
		end
		return buffer.readf64(buf, offset + 1), offset + 9
	elseif tagType == TAG_SHORT_STRING then
		if inlineData == 0 then
			return "", offset + 1
		end
		if offset + 1 + inlineData > bufLen then
			error(`[Burn] Buffer underflow: short string payload exceeds buffer size {bufLen}`)
		end
		return buffer.readstring(buf, offset + 1, inlineData), offset + 1 + inlineData
	elseif tagType == TAG_LONG_STRING then
		if offset + 3 > bufLen then
			error(`[Burn] Buffer underflow: cannot read long string length at offset {offset + 1} (bufLen {bufLen})`)
		end
		const len = buffer.readu16(buf, offset + 1)
		if offset + 3 + len > bufLen then
			error(`[Burn] Buffer underflow: long string payload exceeds buffer size {bufLen}`)
		end
		if len == 0 then
			return "", offset + 3
		end
		return buffer.readstring(buf, offset + 3, len), offset + 3 + len
	elseif tagType == TAG_BUFFER then
		if offset + 3 > bufLen then
			error(`[Burn] Buffer underflow: cannot read buffer length at offset {offset + 1} (bufLen {bufLen})`)
		end
		const len = buffer.readu16(buf, offset + 1)
		if offset + 3 + len > bufLen then
			error(`[Burn] Buffer underflow: buffer payload exceeds buffer size {bufLen}`)
		end
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
		if offset + 1 + count > bufLen then
			error(`[Burn] Buffer underflow: short array of {count} items exceeds buffer size {bufLen}`)
		end
		const arr = table.create(count)
		local curr = offset + 1
		local item: unknown
		for i = 1, count do
			item, curr = read(buf, curr)
			arr[i] = item
		end
		return arr, curr
	elseif tagType == TAG_LONG_ARRAY then
		if offset + 3 > bufLen then
			error(`[Burn] Buffer underflow: cannot read array count at offset {offset + 1} (bufLen {bufLen})`)
		end
		const count = buffer.readu16(buf, offset + 1)
		if offset + 3 + count > bufLen then
			error(`[Burn] Buffer underflow: long array of {count} items exceeds buffer size {bufLen}`)
		end
		const arr = table.create(count)
		local curr = offset + 3
		local item: unknown
		for i = 1, count do
			item, curr = read(buf, curr)
			arr[i] = item
		end
		return arr, curr
	elseif tagType == TAG_MAP then
		if offset + 3 > bufLen then
			error(`[Burn] Buffer underflow: cannot read map count at offset {offset + 1} (bufLen {bufLen})`)
		end
		const count = buffer.readu16(buf, offset + 1)
		if offset + 3 + count * 2 > bufLen then
			error(`[Burn] Buffer underflow: map of {count} entries exceeds buffer size {bufLen}`)
		end
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
	const bufLen = buffer.len(buf)
	if offset >= bufLen then
		error(`[Burn] Buffer underflow: cannot read Auto tag at offset {offset} (bufLen {bufLen})`)
	end
	const tagByte = buffer.readu8(buf, offset)
	const tagType = bit32.rshift(tagByte, 4)
	const inlineData = bit32.band(tagByte, 0x0F)

	if tagType == TAG_NIL or tagType == TAG_BOOLEAN or tagType == TAG_SMALL_INT then
		return offset + 1
	elseif tagType == TAG_I8 then
		if offset + 2 > bufLen then
			error(`[Burn] Buffer underflow: cannot skip i8 at offset {offset + 1} (bufLen {bufLen})`)
		end
		return offset + 2
	elseif tagType == TAG_I16 then
		if offset + 3 > bufLen then
			error(`[Burn] Buffer underflow: cannot skip i16 at offset {offset + 1} (bufLen {bufLen})`)
		end
		return offset + 3
	elseif tagType == TAG_I32 then
		if offset + 5 > bufLen then
			error(`[Burn] Buffer underflow: cannot skip i32 at offset {offset + 1} (bufLen {bufLen})`)
		end
		return offset + 5
	elseif tagType == TAG_F64 then
		if offset + 9 > bufLen then
			error(`[Burn] Buffer underflow: cannot skip f64 at offset {offset + 1} (bufLen {bufLen})`)
		end
		return offset + 9
	elseif tagType == TAG_SHORT_STRING then
		if offset + 1 + inlineData > bufLen then
			error(`[Burn] Buffer underflow: short string payload exceeds buffer size {bufLen}`)
		end
		return offset + 1 + inlineData
	elseif tagType == TAG_LONG_STRING or tagType == TAG_BUFFER then
		if offset + 3 > bufLen then
			error(`[Burn] Buffer underflow: cannot read length at offset {offset + 1} (bufLen {bufLen})`)
		end
		const len = buffer.readu16(buf, offset + 1)
		if offset + 3 + len > bufLen then
			error(`[Burn] Buffer underflow: payload exceeds buffer size {bufLen}`)
		end
		return offset + 3 + len
	elseif tagType == TAG_VECTOR3 then
		if offset + 13 > bufLen then
			error(`[Burn] Buffer underflow: cannot skip Vector3 at offset {offset + 1} (bufLen {bufLen})`)
		end
		return offset + 1 + 12
	elseif tagType == TAG_CFRAME then
		if offset + 29 > bufLen then
			error(`[Burn] Buffer underflow: cannot skip CFrame at offset {offset + 1} (bufLen {bufLen})`)
		end
		return offset + 1 + 28
	elseif tagType == TAG_COLOR3 then
		if offset + 4 > bufLen then
			error(`[Burn] Buffer underflow: cannot skip Color3 at offset {offset + 1} (bufLen {bufLen})`)
		end
		return offset + 1 + 3
	elseif tagType == TAG_SHORT_ARRAY then
		if offset + 1 + inlineData > bufLen then
			error(`[Burn] Buffer underflow: short array of {inlineData} items exceeds buffer size {bufLen}`)
		end
		local curr = offset + 1
		for _ = 1, inlineData do
			curr = skip(buf, curr)
		end
		return curr
	elseif tagType == TAG_LONG_ARRAY then
		if offset + 3 > bufLen then
			error(`[Burn] Buffer underflow: cannot read array count at offset {offset + 1} (bufLen {bufLen})`)
		end
		const count = buffer.readu16(buf, offset + 1)
		if offset + 3 + count > bufLen then
			error(`[Burn] Buffer underflow: long array of {count} items exceeds buffer size {bufLen}`)
		end
		local curr = offset + 3
		for _ = 1, count do
			curr = skip(buf, curr)
		end
		return curr
	elseif tagType == TAG_MAP then
		if offset + 3 > bufLen then
			error(`[Burn] Buffer underflow: cannot read map count at offset {offset + 1} (bufLen {bufLen})`)
		end
		const count = buffer.readu16(buf, offset + 1)
		if offset + 3 + count * 2 > bufLen then
			error(`[Burn] Buffer underflow: map of {count} entries exceeds buffer size {bufLen}`)
		end
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
