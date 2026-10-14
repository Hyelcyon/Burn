--!strict

const u8 = require("@datatypes/u8")
const u16 = require("@datatypes/u16")
const u24 = require("@datatypes/u24")
const u32 = require("@datatypes/u32")
const i8 = require("@datatypes/i8")
const i16 = require("@datatypes/i16")
const i24 = require("@datatypes/i24")
const i32 = require("@datatypes/i32")
const f32 = require("@datatypes/f32")
const f48 = require("@datatypes/f48")
const f64 = require("@datatypes/f64")
const boolean = require("@datatypes/boolean")
const stringDesc = require("@datatypes/string")
const bufferDesc = require("@datatypes/buffer")
const Vector2 = require("@datatypes/Vector2")
const Vector3 = require("@datatypes/Vector3")
const Color3 = require("@datatypes/Color3")
const color2 = require("@datatypes/color2")
const CFrame = require("@datatypes/CFrame")
const EnumItem = require("@datatypes/EnumItem")
const Instance = require("@datatypes/Instance")
const Array = require("@datatypes/Array")
const Map = require("@datatypes/Map")
const Struct = require("@datatypes/Struct")
const Optional = require("@datatypes/Optional")

return table.freeze({
	u8 = u8,
	u16 = u16,
	u24 = u24,
	u32 = u32,
	i8 = i8,
	i16 = i16,
	i24 = i24,
	i32 = i32,
	f32 = f32,
	f48 = f48,
	f64 = f64,
	boolean = boolean,
	string = stringDesc,
	buffer = bufferDesc,

	Vector2 = Vector2,
	Vector3 = Vector3,
	Color3 = Color3,
	color2 = color2,
	CFrame = CFrame,
	EnumItem = EnumItem,
	Instance = Instance,
	Array = Array,
	Map = Map,
	Struct = Struct,
	Optional = Optional,

	U8 = u8,
	U16 = u16,
	U24 = u24,
	U32 = u32,
	I8 = i8,
	I16 = i16,
	I24 = i24,
	I32 = i32,
	F32 = f32,
	F48 = f48,
	F64 = f64,
	Boolean = boolean,
	String = stringDesc,
	Buffer = bufferDesc,
	RawBuffer = bufferDesc,
	Color2 = color2,
	map = Map,
})
