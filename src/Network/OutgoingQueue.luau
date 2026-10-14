--!strict

const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const Constants = require(script.Parent.Parent.Constants)
const Types = require(script.Parent.Parent.Types)
const ByteBuffer = require(script.Parent.Parent.Buffer.ByteBuffer)
const Channel = require(script.Parent.Channel)

const OutgoingQueue = {}

local clientReliable = ByteBuffer.create(Constants.DEFAULT_BUFFER_CAPACITY)
local clientUnreliable = ByteBuffer.create(Constants.DEFAULT_BUFFER_CAPACITY)

local playerReliable: { [Player]: ByteBuffer.ByteBuffer? } = {}
local playerUnreliable: { [Player]: ByteBuffer.ByteBuffer? } = {}
local broadcastReliable = ByteBuffer.create(Constants.DEFAULT_BUFFER_CAPACITY)
local broadcastUnreliable = ByteBuffer.create(Constants.DEFAULT_BUFFER_CAPACITY)

local activeReliablePlayers: { Player } = {}
local isReliablePlayerDirty: { [Player]: boolean? } = {}
local activeUnreliablePlayers: { Player } = {}
local isUnreliablePlayerDirty: { [Player]: boolean? } = {}

local removingPlayers: { [Player]: boolean? } = setmetatable({}, { __mode = "k" })
local isInitialized = false
local isClientChannelReady = false

const function isPlayerActive(player: Player): boolean
	return not removingPlayers[player] and player.Parent == Players
end

@native
const function serializeToScratch(packetDef: Types.PacketDefinition<any>, data: any): (buffer, number)
	if packetDef.packetType ~= "Reliable" and packetDef.packetType ~= "Unreliable" then
		error(`Packet '{packetDef.name}' has type '{packetDef.packetType}' and cannot be sent as an event`)
	end

	const scratch = ByteBuffer.getScratch()
	const schemaSize = packetDef.schema.size
	const capacity = if typeof(schemaSize) == "number" then schemaSize else Constants.MAX_PACKET_SIZE
	ByteBuffer.ensureCapacity(scratch, capacity)

	const payloadLen = packetDef.schema.write(scratch.raw, 0, data)
	if payloadLen < 0 or payloadLen > Constants.MAX_PAYLOAD_SIZE then
		error(
			`Packet '{packetDef.name}' payload ({payloadLen} bytes) exceeds limit ({Constants.MAX_PAYLOAD_SIZE} bytes)`
		)
	end
	if typeof(schemaSize) == "number" and payloadLen ~= schemaSize then
		error(`Packet '{packetDef.name}' wrote {payloadLen} bytes, expected fixed size {schemaSize}`)
	end

	return scratch.raw, payloadLen
end

@native
const function writeSerializedToBuffer(
	target: ByteBuffer.ByteBuffer,
	packetId: number,
	payloadBuf: buffer,
	payloadLen: number
)
	const packetTotal = Constants.HEADER_SIZE + payloadLen
	const totalNeeded = target.size + packetTotal
	ByteBuffer.ensureCapacity(target, totalNeeded)

	buffer.writeu8(target.raw, target.size, packetId)
	buffer.writeu16(target.raw, target.size + 1, payloadLen)
	if payloadLen > 0 then
		buffer.copy(target.raw, target.size + Constants.HEADER_SIZE, payloadBuf, 0, payloadLen)
	end

	target.size = totalNeeded
end

@native
const function buildImmediateBuffer(packetDef: Types.PacketDefinition<any>, data: any): buffer
	const scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	const packetTotal = Constants.HEADER_SIZE + payloadLen
	if packetDef.packetType == "Unreliable" and packetTotal > Constants.MAX_UNRELIABLE_BYTES then
		error(
			`Unreliable packet '{packetDef.name}' ({packetTotal} bytes) exceeds {Constants.MAX_UNRELIABLE_BYTES} bytes`
		)
	end

	const out = buffer.create(packetTotal)
	buffer.writeu8(out, 0, packetDef.id)
	buffer.writeu16(out, 1, payloadLen)
	if payloadLen > 0 then
		buffer.copy(out, Constants.HEADER_SIZE, scratchRaw, 0, payloadLen)
	end
	return out
end

const function getPlayerBuffer(dict: { [Player]: ByteBuffer.ByteBuffer? }, player: Player): ByteBuffer.ByteBuffer
	const existing = dict[player]
	if existing ~= nil then
		return existing
	end
	const created = ByteBuffer.create(Constants.DEFAULT_BUFFER_CAPACITY)
	dict[player] = created
	return created
end

function OutgoingQueue.init()
	if isInitialized then
		return
	end
	isInitialized = true

	if RunService:IsServer() then
		Channel.init()

		Players.PlayerRemoving:Connect(function(player)
			removingPlayers[player] = true
			playerReliable[player] = nil
			playerUnreliable[player] = nil
			isReliablePlayerDirty[player] = nil
			isUnreliablePlayerDirty[player] = nil
		end)

		RunService.Heartbeat:Connect(function()
			if broadcastReliable.size > 0 then
				const buf = ByteBuffer.compact(broadcastReliable)
				ByteBuffer.reset(broadcastReliable)
				Channel.getReliableEvent():FireAllClients(buf)
			end

			if broadcastUnreliable.size > 0 then
				const buf = ByteBuffer.compact(broadcastUnreliable)
				ByteBuffer.reset(broadcastUnreliable)
				Channel.getUnreliableEvent():FireAllClients(buf)
			end

			for _, player in activeReliablePlayers do
				const buf = playerReliable[player]
				if not isPlayerActive(player) then
					playerReliable[player] = nil
				elseif buf ~= nil and buf.size > 0 then
					const compacted = ByteBuffer.compact(buf)
					ByteBuffer.reset(buf)
					Channel.getReliableEvent():FireClient(player, compacted)
				end
				isReliablePlayerDirty[player] = nil
			end
			table.clear(activeReliablePlayers)

			for _, player in activeUnreliablePlayers do
				const buf = playerUnreliable[player]
				if not isPlayerActive(player) then
					playerUnreliable[player] = nil
				elseif buf ~= nil and buf.size > 0 then
					const compacted = ByteBuffer.compact(buf)
					ByteBuffer.reset(buf)
					Channel.getUnreliableEvent():FireClient(player, compacted)
				end
				isUnreliablePlayerDirty[player] = nil
			end
			table.clear(activeUnreliablePlayers)
		end)
	else
		task.spawn(function()
			Channel.getReliableEvent()
			Channel.getUnreliableEvent()
			isClientChannelReady = true
		end)

		RunService.Heartbeat:Connect(function()
			if not isClientChannelReady then
				return
			end

			if clientReliable.size > 0 then
				const buf = ByteBuffer.compact(clientReliable)
				ByteBuffer.reset(clientReliable)
				Channel.getReliableEvent():FireServer(buf)
			end

			if clientUnreliable.size > 0 then
				const buf = ByteBuffer.compact(clientUnreliable)
				ByteBuffer.reset(clientUnreliable)
				Channel.getUnreliableEvent():FireServer(buf)
			end
		end)
	end
end

function OutgoingQueue.clientEnqueue<T>(packetDef: Types.PacketDefinition<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end
	const scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	const packetTotal = Constants.HEADER_SIZE + payloadLen

	if packetDef.packetType == "Unreliable" then
		if packetTotal > Constants.MAX_UNRELIABLE_BYTES then
			error(
				`Unreliable packet '{packetDef.name}' ({packetTotal} bytes) exceeds {Constants.MAX_UNRELIABLE_BYTES} bytes`
			)
		end
		if
			isClientChannelReady
			and clientUnreliable.size > 0
			and clientUnreliable.size + packetTotal > Constants.MAX_UNRELIABLE_BYTES
		then
			const flushed = ByteBuffer.compact(clientUnreliable)
			ByteBuffer.reset(clientUnreliable)
			Channel.getUnreliableEvent():FireServer(flushed)
		end
		writeSerializedToBuffer(clientUnreliable, packetDef.id, scratchRaw, payloadLen)
	else
		if
			isClientChannelReady
			and clientReliable.size > 0
			and clientReliable.size + packetTotal > Constants.MAX_PACKET_SIZE
		then
			const flushed = ByteBuffer.compact(clientReliable)
			ByteBuffer.reset(clientReliable)
			Channel.getReliableEvent():FireServer(flushed)
		end
		writeSerializedToBuffer(clientReliable, packetDef.id, scratchRaw, payloadLen)
	end
end

function OutgoingQueue.clientSendImmediate<T>(packetDef: Types.PacketDefinition<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end
	const buf = buildImmediateBuffer(packetDef, data)
	if packetDef.packetType == "Unreliable" then
		Channel.getUnreliableEvent():FireServer(buf)
	else
		Channel.getReliableEvent():FireServer(buf)
	end
end

@native
const function enqueuePreSerializedVerified(
	player: Player,
	packetDef: Types.PacketDefinition<any>,
	scratchRaw: buffer,
	payloadLen: number
)
	const packetTotal = Constants.HEADER_SIZE + payloadLen
	if packetDef.packetType == "Unreliable" then
		if packetTotal > Constants.MAX_UNRELIABLE_BYTES then
			error(
				`Unreliable packet '{packetDef.name}' ({packetTotal} bytes) exceeds {Constants.MAX_UNRELIABLE_BYTES} bytes`
			)
		end
		const buf = getPlayerBuffer(playerUnreliable, player)
		if buf.size > 0 and buf.size + packetTotal > Constants.MAX_UNRELIABLE_BYTES then
			const flushed = ByteBuffer.compact(buf)
			ByteBuffer.reset(buf)
			Channel.getUnreliableEvent():FireClient(player, flushed)
		end
		writeSerializedToBuffer(buf, packetDef.id, scratchRaw, payloadLen)
		if not isUnreliablePlayerDirty[player] then
			isUnreliablePlayerDirty[player] = true
			table.insert(activeUnreliablePlayers, player)
		end
	else
		const buf = getPlayerBuffer(playerReliable, player)
		if buf.size > 0 and buf.size + packetTotal > Constants.MAX_PACKET_SIZE then
			const flushed = ByteBuffer.compact(buf)
			ByteBuffer.reset(buf)
			Channel.getReliableEvent():FireClient(player, flushed)
		end
		writeSerializedToBuffer(buf, packetDef.id, scratchRaw, payloadLen)
		if not isReliablePlayerDirty[player] then
			isReliablePlayerDirty[player] = true
			table.insert(activeReliablePlayers, player)
		end
	end
end

function OutgoingQueue.serverEnqueue<T>(player: Player, packetDef: Types.PacketDefinition<T>, data: T)
	if not isPlayerActive(player) then
		return
	end
	if not isInitialized then
		OutgoingQueue.init()
	end
	const scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	enqueuePreSerializedVerified(player, packetDef, scratchRaw, payloadLen)
end

function OutgoingQueue.serverEnqueueList<T>(players: { Player }, packetDef: Types.PacketDefinition<T>, data: T)
	if #players == 0 then
		return
	end
	if not isInitialized then
		OutgoingQueue.init()
	end
	const scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	for _, player in players do
		if isPlayerActive(player) then
			enqueuePreSerializedVerified(player, packetDef, scratchRaw, payloadLen)
		end
	end
end

function OutgoingQueue.serverBroadcast<T>(packetDef: Types.PacketDefinition<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end
	const scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	const packetTotal = Constants.HEADER_SIZE + payloadLen

	if packetDef.packetType == "Unreliable" then
		if packetTotal > Constants.MAX_UNRELIABLE_BYTES then
			error(
				`Unreliable packet '{packetDef.name}' ({packetTotal} bytes) exceeds {Constants.MAX_UNRELIABLE_BYTES} bytes`
			)
		end
		if broadcastUnreliable.size > 0 and broadcastUnreliable.size + packetTotal > Constants.MAX_UNRELIABLE_BYTES then
			const flushed = ByteBuffer.compact(broadcastUnreliable)
			ByteBuffer.reset(broadcastUnreliable)
			Channel.getUnreliableEvent():FireAllClients(flushed)
		end
		writeSerializedToBuffer(broadcastUnreliable, packetDef.id, scratchRaw, payloadLen)
	else
		if broadcastReliable.size > 0 and broadcastReliable.size + packetTotal > Constants.MAX_PACKET_SIZE then
			const flushed = ByteBuffer.compact(broadcastReliable)
			ByteBuffer.reset(broadcastReliable)
			Channel.getReliableEvent():FireAllClients(flushed)
		end
		writeSerializedToBuffer(broadcastReliable, packetDef.id, scratchRaw, payloadLen)
	end
end

function OutgoingQueue.serverBroadcastExcept<T>(excludedPlayer: Player, packetDef: Types.PacketDefinition<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end
	const scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	for _, player in Players:GetPlayers() do
		if player ~= excludedPlayer and not removingPlayers[player] then
			enqueuePreSerializedVerified(player, packetDef, scratchRaw, payloadLen)
		end
	end
end

function OutgoingQueue.serverSendImmediate<T>(player: Player, packetDef: Types.PacketDefinition<T>, data: T)
	if not isPlayerActive(player) then
		return
	end
	if not isInitialized then
		OutgoingQueue.init()
	end
	const buf = buildImmediateBuffer(packetDef, data)
	if packetDef.packetType == "Unreliable" then
		Channel.getUnreliableEvent():FireClient(player, buf)
	else
		Channel.getReliableEvent():FireClient(player, buf)
	end
end

function OutgoingQueue.serverSendImmediateList<T>(players: { Player }, packetDef: Types.PacketDefinition<T>, data: T)
	if #players == 0 then
		return
	end
	if not isInitialized then
		OutgoingQueue.init()
	end
	const buf = buildImmediateBuffer(packetDef, data)
	if packetDef.packetType == "Unreliable" then
		const event = Channel.getUnreliableEvent()
		for _, player in players do
			if isPlayerActive(player) then
				event:FireClient(player, buf)
			end
		end
	else
		const event = Channel.getReliableEvent()
		for _, player in players do
			if isPlayerActive(player) then
				event:FireClient(player, buf)
			end
		end
	end
end

function OutgoingQueue.serverBroadcastImmediate<T>(packetDef: Types.PacketDefinition<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end
	const buf = buildImmediateBuffer(packetDef, data)
	if packetDef.packetType == "Unreliable" then
		Channel.getUnreliableEvent():FireAllClients(buf)
	else
		Channel.getReliableEvent():FireAllClients(buf)
	end
end

return OutgoingQueue
