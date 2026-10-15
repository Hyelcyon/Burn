--!strict

--[=[
	@class Burn
	High-performance buffer-oriented networking library for Roblox.

	Burn provides zero-copy binary serialization, 4-tier priority queues,
	batched network transmission with MTU auto-flushing, and compile-time
	Luau New Type Solver schema synthesis.

	```lua
	local Burn = require(ReplicatedStorage.Packages.Burn)

	-- Define schema and packet
	local PositionPacket = Burn.definePacket("UpdatePosition", "Unreliable", Burn.Types.Vector3, {
		priority = "High"
	})

	-- Send packet (Client -> Server or Server -> Client)
	Burn.send(player, PositionPacket, Vector3.new(0, 10, 0))

	-- Listen for packet
	Burn.on(PositionPacket, function(player, position)
		print(`Received position from {player.Name}: {position}`)
	end)
	```
]=]

const RunService = game:GetService("RunService")

const Types = require("@src/Types")
const Constants = require("@src/Constants")
const Buffer = require("@buffer")
const DataTypes = require("@datatypes")
const Packet = require("@packet")
const Network = require("@network")

export type TypeDescriptor<T> = Types.TypeDescriptor<T>
export type PacketType = Types.PacketType
export type PacketPriority = Types.PacketPriority
export type PacketOptions = Types.PacketOptions
export type PacketDefinition<T> = Types.PacketDefinition<T>
export type Connection = Types.Connection
export type ByteBuffer = Buffer.ByteBuffer
export type Cursor = Buffer.Cursor

const isServer = RunService:IsServer()
const isClient = RunService:IsClient()

export type ServerListener<T> = (Player, T) -> ()
export type ClientListener<T> = (T) -> ()
export type Listener<T> = ServerListener<T> | ClientListener<T>

--[=[
	@function on
	@within Burn
	@param packet PacketDefinition<T> -- The packet definition to listen for
	@param listener Listener<T> -- Callback invoked when packet is received
	@return Connection -- Connection object with :disconnect() method

	Connects a listener callback to incoming network packets.
	- On the **server**, the listener receives `(player: Player, data: T)`.
	- On the **client**, the listener receives `(data: T)`.

	:::note
	Multiple listeners can be attached to the same packet. Listeners are dispatched
	using `task.spawn` to isolate errors and prevent blocking the batch decoder.
	:::
]=]
const function on<T>(packet: Types.PacketDefinition<T>, listener: Listener<T>): Types.Connection
	if isServer then
		return Network.Server.on(packet, listener :: ServerListener<T>)
	else
		return Network.Client.on(packet, listener :: ClientListener<T>)
	end
end

--[=[
	@function once
	@within Burn
	@param packet PacketDefinition<T> -- The packet definition to listen for
	@param listener Listener<T> -- Callback invoked once when packet is received
	@return Connection -- Connection object with :disconnect() method

	Connects a one-time listener that automatically disconnects after receiving its first packet.
]=]
const function once<T>(packet: Types.PacketDefinition<T>, listener: Listener<T>): Types.Connection
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
	@function wait
	@within Burn
	@param packet PacketDefinition<T> -- The packet definition to wait for
	@return ... -- Returns `(Player, T)` on the server, or `T` on the client

	Yields the calling thread until the specified packet is received, then resumes with the payload.
]=]
const function wait<T>(packet: Types.PacketDefinition<T>)
	const thread = coroutine.running()
	if isServer then
		local conn: Types.Connection
		conn = Network.Server.on(packet, function(player: Player, data: T)
			conn:disconnect()
			task.spawn(thread, player, data)
		end)
		return coroutine.yield()
	else
		local conn: Types.Connection
		conn = Network.Client.on(packet, function(data: T)
			conn:disconnect()
			task.spawn(thread, data)
		end)
		return coroutine.yield()
	end
end

--[=[
	@function send
	@within Burn
	@param target Player | { Player } | PacketDefinition<T> -- Target player(s) on server, or packet definition on client
	@param packetOrData PacketDefinition<T> | T -- Packet definition on server, or payload data on client
	@param maybeData T? -- Payload data on server (when target is player/players)

	Enqueues a packet to be transmitted in the next frame's batched network flush.

	**Signatures**:
	- **Server Target**: `Burn.send(player, packet, data)` or `Burn.send({ p1, p2 }, packet, data)`
	- **Server Broadcast**: `Burn.send(packet, data)` (broadcasts to all active players)
	- **Client**: `Burn.send(packet, data)` (sends to server)

	:::note
	For fixed-size schemas, `send` writes directly into the outgoing priority buffer
	with zero intermediate scratch-buffer copying.
	:::
]=]
const function send<T>(
	target: Player | { Player } | Types.PacketDefinition<T>,
	packetOrData: Types.PacketDefinition<T> | T,
	maybeData: T?
)
	if isServer then
		if maybeData ~= nil then
			Network.Server.send(target :: Player | { Player }, packetOrData :: Types.PacketDefinition<T>, maybeData)
		else
			Network.Server.broadcast(target :: Types.PacketDefinition<T>, packetOrData :: T)
		end
	else
		Network.Client.send(target :: Types.PacketDefinition<T>, packetOrData :: T)
	end
end

--[=[
	@function sendImmediate
	@within Burn
	@param target Player | { Player } | PacketDefinition<T>
	@param packetOrData PacketDefinition<T> | T
	@param maybeData T?

	Serializes and transmits the packet over the network immediately, bypassing
	the end-of-frame batch queue.

	:::warning
	Frequent calls to `sendImmediate` can saturate Roblox RemoteEvent network frames.
	Use `send` for general gameplay and reserve `sendImmediate` for critical low-latency events.
	:::
]=]
const function sendImmediate<T>(
	target: Player | { Player } | Types.PacketDefinition<T>,
	packetOrData: Types.PacketDefinition<T> | T,
	maybeData: T?
)
	if isServer then
		if maybeData ~= nil then
			Network.Server.sendImmediate(
				target :: Player | { Player },
				packetOrData :: Types.PacketDefinition<T>,
				maybeData
			)
		else
			Network.Server.broadcastImmediate(target :: Types.PacketDefinition<T>, packetOrData :: T)
		end
	else
		Network.Client.sendImmediate(target :: Types.PacketDefinition<T>, packetOrData :: T)
	end
end

--[=[
	@function broadcast
	@within Burn
	@param packet PacketDefinition<T> -- The packet to broadcast
	@param data T -- Payload data

	Enqueues a packet to be broadcast to all connected players on the next network frame.
	Server-only.
]=]
const function broadcast<T>(packet: Types.PacketDefinition<T>, data: T)
	assert(isServer, "Burn.broadcast can only be called on the server")
	Network.Server.broadcast(packet, data)
end

--[=[
	@function broadcastExcept
	@within Burn
	@param excludedPlayer Player -- Player to exclude from the broadcast
	@param packet PacketDefinition<T> -- The packet to broadcast
	@param data T -- Payload data

	Enqueues a packet to be broadcast to all connected players except `excludedPlayer`.
	Server-only.
]=]
const function broadcastExcept<T>(excludedPlayer: Player, packet: Types.PacketDefinition<T>, data: T)
	assert(isServer, "Burn.broadcastExcept can only be called on the server")
	Network.Server.broadcastExcept(excludedPlayer, packet, data)
end

--[=[
	@function broadcastImmediate
	@within Burn
	@param packet PacketDefinition<T> -- The packet to broadcast
	@param data T -- Payload data

	Immediately broadcasts a packet to all connected players without queuing.
	Server-only.
]=]
const function broadcastImmediate<T>(packet: Types.PacketDefinition<T>, data: T)
	assert(isServer, "Burn.broadcastImmediate can only be called on the server")
	Network.Server.broadcastImmediate(packet, data)
end

--[=[
	@function invoke
	@within Burn
	@param packet PacketDefinition<Req> -- Request packet definition (must be "Request" type)
	@param responseSchema TypeDescriptor<Res> -- Serialization schema for expected response
	@param data Req -- Request payload data
	@return Res? -- Response received from server, or nil if invocation failed

	Sends a two-way RPC request to the server and yields until a response is received.
	Client-only.
]=]
const function invoke<Req, Res>(packet: Types.PacketDefinition<Req>, responseSchema: Types.TypeDescriptor<Res>, data: Req): Res?
	assert(isClient, "Burn.invoke can only be called on the client")
	return Network.Client.invoke(packet, responseSchema, data)
end

--[=[
	@function handleRequest
	@within Burn
	@param packet PacketDefinition<Req> -- Request packet definition
	@param responseSchema TypeDescriptor<Res> -- Serialization schema for response payload
	@param handler (Player, Req) -> Res -- Server callback invoked to process the request

	Registers a server-side request handler for two-way client RPC invocations.
	Server-only.
]=]
const function handleRequest<Req, Res>(
	packet: Types.PacketDefinition<Req>,
	responseSchema: Types.TypeDescriptor<Res>,
	handler: (Player, Req) -> Res
)
	assert(isServer, "Burn.handleRequest can only be called on the server")
	Network.Server.handleRequest(packet, responseSchema, handler)
end

--[=[
	@function definePacket
	@within Burn
	@param name string -- Unique network packet identifier
	@param packetType PacketType -- Reliability mode ("Reliable" | "Unreliable" | "Request")
	@param schema TypeDescriptor<T> -- Binary serialization descriptor for payload
	@param optionsOrId (number | PacketOptions)? -- Optional ID override (0..255) or PacketOptions table
	@param maybePriority PacketPriority? -- Optional priority override ("Low" | "Medium" | "High" | "Max")
	@return PacketDefinition<T>

	Registers a packet schema with the global registry.
	Precomputes priority indices (1..4) and schema byte sizes for O(1) buffer queue routing.

	```lua
	local FireWeapon = Burn.definePacket("FireWeapon", "Reliable", Burn.Types.Struct({
		weaponId = Burn.Types.varu32,
		origin = Burn.Types.Vector3,
		direction = Burn.Types.Vector3,
	}), {
		priority = "High"
	})
	```
]=]
const function definePacket<T>(
	name: string,
	packetType: Types.PacketType,
	schema: Types.TypeDescriptor<T>,
	optionsOrId: (number | PacketOptions)?,
	maybePriority: Types.PacketPriority?
): Types.PacketDefinition<T>
	return Packet.Registry.register(name, packetType, schema, optionsOrId, maybePriority)
end

const Burn = table.freeze({
	Types = DataTypes,

	definePacket = definePacket,
	getPacketById = Packet.Registry.getById,
	getPacketByName = Packet.Registry.getByName,

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

	Buffer = Buffer.ByteBuffer,
	Cursor = Buffer.Cursor,

	Server = Network.Server,
	Client = Network.Client,

	isServer = isServer,
	isClient = isClient,

	Constants = Constants,
})

return Burn
