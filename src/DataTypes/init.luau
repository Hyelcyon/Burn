--!strict

const u8 = require(script.u8)
const u16 = require(script.u16)
const u24 = require(script.u24)
const u32 = require(script.u32)
const i8 = require(script.i8)
const i16 = require(script.i16)
const i24 = require(script.i24)
const i32 = require(script.i32)
const f32 = require(script.f32)
const f48 = require(script.f48)
const f64 = require(script.f64)
const boolean = require(script.boolean)
const stringDesc = require(script.string)
const bufferDesc = require(script.buffer)
const Vector2 = require(script.Vector2)
const Vector3 = require(script.Vector3)
const Color3 = require(script.Color3)
const color2 = require(script.color2)
const CFrame = require(script.CFrame)
const EnumItem = require(script.EnumItem)
const Instance = require(script.Instance)
const Array = require(script.Array)
const Map = require(script.Map)
const Struct = require(script.Struct)
const Optional = require(script.Optional)

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
