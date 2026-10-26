--!strict

const Types = require("@src/Types")

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
const str = require("@datatypes/string")
const buff = require("@datatypes/buffer")
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
const Auto = require("@datatypes/Auto")
const Bitfield = require("@datatypes/Bitfield")
const VarInt = require("@datatypes/VarInt")

export type StructDescriptor<F> = Struct.StructDescriptor<F>
export type InferStruct<F> = Struct.InferStruct<F>
export type BitfieldDescriptor<F> = Bitfield.BitfieldDescriptor<F>
export type InferBitfield<F> = Bitfield.InferBitfield<F>
export type ArrayDescriptor<T> = Array.ArrayDescriptor<T>
export type MapDescriptor<K, V> = Map.MapDescriptor<K, V>
export type OptionalDescriptor<T> = Optional.OptionalDescriptor<T>
export type EnumDescriptor<E> = EnumItem.EnumDescriptor<E>
export type InstanceDescriptor<T = Instance?> = Instance.InstanceDescriptor<T>

--[=[
	@class DataTypes
	@within Burn
	Registry of primitive types, Roblox engine types, composite structures, and collections
	for binary serialization and deserialization.
]=]
const DataTypes = table.freeze({
	u8 = u8 :: Types.TypeDescriptor<number>,
	u16 = u16 :: Types.TypeDescriptor<number>,
	u24 = u24 :: Types.TypeDescriptor<number>,
	u32 = u32 :: Types.TypeDescriptor<number>,
	i8 = i8 :: Types.TypeDescriptor<number>,
	i16 = i16 :: Types.TypeDescriptor<number>,
	i24 = i24 :: Types.TypeDescriptor<number>,
	i32 = i32 :: Types.TypeDescriptor<number>,
	f32 = f32 :: Types.TypeDescriptor<number>,
	f48 = f48 :: Types.TypeDescriptor<number>,
	f64 = f64 :: Types.TypeDescriptor<number>,
	boolean = boolean :: Types.TypeDescriptor<boolean>,
	string = str :: Types.TypeDescriptor<string>,
	buffer = buff :: Types.TypeDescriptor<buffer>,
	varu32 = VarInt.VarU32 :: Types.TypeDescriptor<number>,
	vari32 = VarInt.VarI32 :: Types.TypeDescriptor<number>,

	Vector2 = Vector2 :: Types.TypeDescriptor<Vector2>,
	Vector3 = Vector3 :: Types.TypeDescriptor<Vector3>,
	Color2 = color2 :: Types.TypeDescriptor<Color3>,
	Color3 = Color3 :: Types.TypeDescriptor<Color3>,
	CFrame = CFrame :: Types.TypeDescriptor<CFrame>,
	EnumItem = EnumItem,
	Instance = Instance :: InstanceDescriptor<Instance?>,

	Struct = Struct,
	Array = Array,
	Map = Map,
	Optional = Optional,
	Bitfield = Bitfield,
	Auto = Auto,

	U8 = u8 :: Types.TypeDescriptor<number>,
	U16 = u16 :: Types.TypeDescriptor<number>,
	U24 = u24 :: Types.TypeDescriptor<number>,
	U32 = u32 :: Types.TypeDescriptor<number>,
	I8 = i8 :: Types.TypeDescriptor<number>,
	I16 = i16 :: Types.TypeDescriptor<number>,
	I24 = i24 :: Types.TypeDescriptor<number>,
	I32 = i32 :: Types.TypeDescriptor<number>,
	F32 = f32 :: Types.TypeDescriptor<number>,
	F48 = f48 :: Types.TypeDescriptor<number>,
	F64 = f64 :: Types.TypeDescriptor<number>,
	Boolean = boolean :: Types.TypeDescriptor<boolean>,
	String = str :: Types.TypeDescriptor<string>,
	Buffer = buff :: Types.TypeDescriptor<buffer>,
	RawBuffer = buff :: Types.TypeDescriptor<buffer>,
	VarU32 = VarInt.VarU32 :: Types.TypeDescriptor<number>,
	VarI32 = VarInt.VarI32 :: Types.TypeDescriptor<number>,
	varint = VarInt.VarU32 :: Types.TypeDescriptor<number>,
	VarInt = VarInt,
	color2 = color2 :: Types.TypeDescriptor<Color3>,
	vector2 = Vector2 :: Types.TypeDescriptor<Vector2>,
	vector3 = Vector3 :: Types.TypeDescriptor<Vector3>,
	color3 = Color3 :: Types.TypeDescriptor<Color3>,
	cframe = CFrame :: Types.TypeDescriptor<CFrame>,
	enumItem = EnumItem,
	instance = Instance :: InstanceDescriptor<Instance?>,
	struct = Struct,
	array = Array,
	map = Map,
	optional = Optional,
	bitfield = Bitfield,
	auto = Auto,
})

export type DataTypes = typeof(DataTypes)

return DataTypes
