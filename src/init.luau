--!strict

const RunService = game:GetService("RunService")

const Types = require("@src/Types")
const Constants = require("@src/Constants")
const Buffer = require("@buffer")
const DataTypes = require("@datatypes")
const Packet = require("@packet")
const Network = require("@network")

export type TypeDescriptor<T> = Types.TypeDescriptor<T>
export type AnyTypeDescriptor = Types.AnyTypeDescriptor
export type ErasedTypeDescriptor = Types.ErasedTypeDescriptor
export type PacketType = Types.PacketType
export type PacketPriority = Types.PacketPriority
export type PacketOptions = Types.PacketOptions
export type PacketDefinition<T> = Types.PacketDefinition<T>
export type AnyPacketDefinition = Types.AnyPacketDefinition
export type ErasedPacketDefinition = Types.ErasedPacketDefinition
export type Connection = Types.Connection
export type NetworkContext = Types.NetworkContext
export type ByteBuffer = Buffer.ByteBuffer
export type Cursor = Buffer.Cursor
export type StructDescriptor<F> = DataTypes.StructDescriptor<F>
export type InferStruct<F> = DataTypes.InferStruct<F>
export type BitfieldDescriptor<F> = DataTypes.BitfieldDescriptor<F>
export type InferBitfield<F> = DataTypes.InferBitfield<F>
export type ArrayDescriptor<T> = DataTypes.ArrayDescriptor<T>
export type MapDescriptor<K, V> = DataTypes.MapDescriptor<K, V>
export type OptionalDescriptor<T> = DataTypes.OptionalDescriptor<T>
export type EnumDescriptor<E> = DataTypes.EnumDescriptor<E>
export type InstanceDescriptor<T = Instance?> = DataTypes.InstanceDescriptor<T>
export type DataTypes = DataTypes.DataTypes
export type Infer<D> = Types.Infer<D>
export type TypeOf<D> = Types.TypeOf<D>
export type InferPacket<P> = Types.InferPacket<P>

--[=[
	@class Burn
	Compact binary networking library for Roblox built on Luau `buffer`.
]=]

const isServer = RunService:IsServer()
const isClient = RunService:IsClient()

export type ServerListener<T> = (Player, T) -> ()
export type ClientListener<T> = (T) -> ()
export type Listener<T> = ServerListener<T> | ClientListener<T>

--[=[
	Registers a persistent listener for incoming packets.
	On the server, listener receives `(player, data)`. On the client, listener receives `(data)`.
]=]
const on: Types.OnDispatcher = function<T>(packet, listener): Types.Connection
	if isServer then
		return Network.Server.on(packet, listener :: ServerListener<T>)
	else
		return Network.Client.on(packet, listener :: ClientListener<T>)
	end
end

--[=[
	Registers a one-shot listener that unregisters itself before invoking the callback.
]=]
const once: Types.OnceDispatcher = function<T>(packet, listener): Types.Connection
	if isServer then
		const serverListener = listener :: ServerListener<T>
		local conn: Types.Connection
		conn = Network.Server.on(packet, function(player: Player, data: T)
			conn:disconnect()
			serverListener(player, data)
		end)
		return conn
	else
		const clientListener = listener :: ClientListener<T>
		local conn: Types.Connection
		conn = Network.Client.on(packet, function(data: T)
			conn:disconnect()
			clientListener(data)
		end)
		return conn
	end
end

--[=[
	Yields the running thread until a matching packet arrives.
	Resumes with `(player, data)` on the server and `(data)` on the client.
	@yields
]=]
const wait: Types.WaitDispatcher = function<T>(packet): (Player?, T)
	const thread = coroutine.running()
	if isServer then
		local conn: Types.Connection
		conn = Network.Server.on(packet, function(player: Player, data: T)
			conn:disconnect()
			task.spawn(thread, player, data)
		end)
		local player: Player?, data: T = coroutine.yield()
		return player, data
	else
		local conn: Types.Connection
		conn = Network.Client.on(packet, function(data: T)
			conn:disconnect()
			task.spawn(thread, data)
		end)
		local data: T = coroutine.yield()
		return nil, data
	end
end

const function isPacketDefinition(value: unknown): boolean
	return typeof(value) == "table"
		and (value :: { id: unknown?, packetType: unknown? }).id ~= nil
		and (value :: { id: unknown?, packetType: unknown? }).packetType ~= nil
end

--[=[
	Enqueues a packet into the outgoing priority queue for frame-batched transmission on Heartbeat.
]=]
const send: Types.SendDispatcher = function<T>(target, packetOrData, maybeData)
	if isServer then
		if isPacketDefinition(target) then
			const packet = target :: Types.PacketDefinition<T>
			const data = packetOrData :: T
			Network.Server.broadcast(packet, data)
		else
			const playerTarget = target :: Player | { Player }
			const packet = packetOrData :: Types.PacketDefinition<T>
			const data = maybeData :: T
			Network.Server.send(playerTarget, packet, data)
		end
	else
		if isPacketDefinition(target) then
			const packet = target :: Types.PacketDefinition<T>
			const data = packetOrData :: T
			Network.Client.send(packet, data)
		else
			const packet = packetOrData :: Types.PacketDefinition<T>
			const data = maybeData :: T
			Network.Client.send(packet, data)
		end
	end
end

--[=[
	Serializes and sends a packet immediately, bypassing frame batching.
]=]
const sendImmediate: Types.SendImmediateDispatcher = function<T>(target, packetOrData, maybeData)
	if isServer then
		if isPacketDefinition(target) then
			const packet = target :: Types.PacketDefinition<T>
			const data = packetOrData :: T
			Network.Server.broadcastImmediate(packet, data)
		else
			const playerTarget = target :: Player | { Player }
			const packet = packetOrData :: Types.PacketDefinition<T>
			const data = maybeData :: T
			Network.Server.sendImmediate(playerTarget, packet, data)
		end
	else
		if isPacketDefinition(target) then
			const packet = target :: Types.PacketDefinition<T>
			const data = packetOrData :: T
			Network.Client.sendImmediate(packet, data)
		else
			const packet = packetOrData :: Types.PacketDefinition<T>
			const data = maybeData :: T
			Network.Client.sendImmediate(packet, data)
		end
	end
end

--[=[
	Enqueues a packet to be sent to all connected clients on next Heartbeat flush.
	@server
]=]
const broadcast: Types.BroadcastDispatcher = function<T>(packet, data)
	assert(isServer, "Burn.broadcast can only be called on the server")
	Network.Server.broadcast(packet, data)
end

--[=[
	Enqueues a packet to all connected clients except `excludedPlayer`.
	@server
]=]
const broadcastExcept: Types.BroadcastExceptDispatcher = function<T>(excludedPlayer, packet, data)
	assert(isServer, "Burn.broadcastExcept can only be called on the server")
	Network.Server.broadcastExcept(excludedPlayer, packet, data)
end

--[=[
	Sends an immediate packet to all connected clients without frame batching.
	@server
]=]
const broadcastImmediate: Types.BroadcastImmediateDispatcher = function<T>(packet, data)
	assert(isServer, "Burn.broadcastImmediate can only be called on the server")
	Network.Server.broadcastImmediate(packet, data)
end

--[=[
	Invokes the server synchronously and yields until response is returned or rejected.
	@client
	@yields
]=]
const invoke: Types.InvokeDispatcher = function<Req, Res>(packet, responseSchema, data): Res?
	assert(isClient, "Burn.invoke can only be called on the client")
	return Network.Client.invoke(packet, responseSchema, data)
end

--[=[
	Registers a server-side request handler for two-way client invocations.
	@server
]=]
const handleRequest: Types.HandleRequestDispatcher = function<Req, Res>(packet, responseSchema, handler)
	assert(isServer, "Burn.handleRequest can only be called on the server")
	Network.Server.handleRequest(packet, responseSchema, handler)
end

--[=[
	Registers a network packet with a schema, transport type, and optional ID/priority.
]=]
const function definePacket<T>(
	name: string,
	packetType: Types.PacketType,
	schema: Types.TypeDescriptor<T>,
	optionsOrId: (number | PacketOptions | Types.PacketPriority)?,
	maybePriority: Types.PacketPriority?
): Types.PacketDefinition<T>
	return Packet.Registry.register(name, packetType, schema, optionsOrId, maybePriority)
end

Packet.Definition.setNetworkBindings({
	send = send,
	sendImmediate = sendImmediate,
	broadcast = broadcast,
	broadcastExcept = broadcastExcept,
	broadcastImmediate = broadcastImmediate,
	on = on,
	once = once,
	wait = wait,
	invoke = invoke,
	handleRequest = handleRequest,
})

const Burn = table.freeze({
	Types = DataTypes,

	u8 = DataTypes.u8 :: Types.TypeDescriptor<number>,
	u16 = DataTypes.u16 :: Types.TypeDescriptor<number>,
	u24 = DataTypes.u24 :: Types.TypeDescriptor<number>,
	u32 = DataTypes.u32 :: Types.TypeDescriptor<number>,
	i8 = DataTypes.i8 :: Types.TypeDescriptor<number>,
	i16 = DataTypes.i16 :: Types.TypeDescriptor<number>,
	i24 = DataTypes.i24 :: Types.TypeDescriptor<number>,
	i32 = DataTypes.i32 :: Types.TypeDescriptor<number>,
	f32 = DataTypes.f32 :: Types.TypeDescriptor<number>,
	f48 = DataTypes.f48 :: Types.TypeDescriptor<number>,
	f64 = DataTypes.f64 :: Types.TypeDescriptor<number>,
	boolean = DataTypes.boolean :: Types.TypeDescriptor<boolean>,
	string = DataTypes.string :: Types.TypeDescriptor<string>,
	buffer = DataTypes.buffer :: Types.TypeDescriptor<buffer>,
	varu32 = DataTypes.varu32 :: Types.TypeDescriptor<number>,
	vari32 = DataTypes.vari32 :: Types.TypeDescriptor<number>,

	Vector2 = DataTypes.Vector2 :: Types.TypeDescriptor<Vector2>,
	Vector3 = DataTypes.Vector3 :: Types.TypeDescriptor<Vector3>,
	Color2 = DataTypes.Color2 :: Types.TypeDescriptor<Color3>,
	Color3 = DataTypes.Color3 :: Types.TypeDescriptor<Color3>,
	CFrame = DataTypes.CFrame :: Types.TypeDescriptor<CFrame>,
	EnumItem = DataTypes.EnumItem,
	Instance = DataTypes.Instance :: InstanceDescriptor<Instance?>,

	Struct = DataTypes.Struct,
	Array = DataTypes.Array,
	Map = DataTypes.Map,
	Optional = DataTypes.Optional,
	Bitfield = DataTypes.Bitfield,
	Auto = DataTypes.Auto,

	U8 = DataTypes.U8 :: Types.TypeDescriptor<number>,
	U16 = DataTypes.U16 :: Types.TypeDescriptor<number>,
	U24 = DataTypes.U24 :: Types.TypeDescriptor<number>,
	U32 = DataTypes.U32 :: Types.TypeDescriptor<number>,
	I8 = DataTypes.I8 :: Types.TypeDescriptor<number>,
	I16 = DataTypes.I16 :: Types.TypeDescriptor<number>,
	I24 = DataTypes.I24 :: Types.TypeDescriptor<number>,
	I32 = DataTypes.I32 :: Types.TypeDescriptor<number>,
	F32 = DataTypes.F32 :: Types.TypeDescriptor<number>,
	F48 = DataTypes.F48 :: Types.TypeDescriptor<number>,
	F64 = DataTypes.F64 :: Types.TypeDescriptor<number>,
	Boolean = DataTypes.Boolean :: Types.TypeDescriptor<boolean>,
	String = DataTypes.String :: Types.TypeDescriptor<string>,
	Buffer = Buffer.ByteBuffer,
	RawBuffer = DataTypes.RawBuffer :: Types.TypeDescriptor<buffer>,
	VarU32 = DataTypes.VarU32 :: Types.TypeDescriptor<number>,
	VarI32 = DataTypes.VarI32 :: Types.TypeDescriptor<number>,
	varint = DataTypes.varint :: Types.TypeDescriptor<number>,
	VarInt = DataTypes.VarInt,
	color2 = DataTypes.color2 :: Types.TypeDescriptor<Color3>,
	vector2 = DataTypes.vector2 :: Types.TypeDescriptor<Vector2>,
	vector3 = DataTypes.vector3 :: Types.TypeDescriptor<Vector3>,
	color3 = DataTypes.color3 :: Types.TypeDescriptor<Color3>,
	cframe = DataTypes.cframe :: Types.TypeDescriptor<CFrame>,
	enumItem = DataTypes.enumItem,
	instance = DataTypes.instance :: InstanceDescriptor<Instance?>,
	struct = DataTypes.struct,
	array = DataTypes.array,
	map = DataTypes.map,
	optional = DataTypes.optional,
	bitfield = DataTypes.bitfield,
	auto = DataTypes.auto,

	-- Packet API
	definePacket = definePacket,
	getPacketById = Packet.Registry.getById,
	getPacketByName = Packet.Registry.getByName,

	-- Networking API
	on = on,
	once = once,
	wait = wait,
	send = send,
	sendImmediate = sendImmediate,
	broadcast = broadcast,
	broadcastExcept = broadcastExcept,
	broadcastImmediate = broadcastImmediate,
	invoke = invoke,
	handleRequest = handleRequest,

	Cursor = Buffer.Cursor,
	Server = Network.Server,
	Client = Network.Client,
	isServer = isServer,
	isClient = isClient,
	Constants = Constants,
})

export type Burn = typeof(Burn)

return Burn
