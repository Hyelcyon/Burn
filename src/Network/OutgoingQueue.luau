--!strict

const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const Constants = require(script.Parent.Parent.Constants)
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

local isInitialized = false

@native
const function appendPacket(target: ByteBuffer.ByteBuffer, packetDef, data)
	const scratch = ByteBuffer.getScratch()
	const schemaSize = packetDef.schema.size
	const capacity = if typeof(schemaSize) == "number" then schemaSize else 256
	ByteBuffer.ensureCapacity(scratch, capacity)
	const payloadLen = packetDef.schema.write(scratch.raw, 0, data)

	const totalNeeded = target.size + Constants.HEADER_SIZE + payloadLen
	ByteBuffer.ensureCapacity(target, totalNeeded)

	buffer.writeu8(target.raw, target.size, packetDef.id)
	buffer.writeu16(target.raw, target.size + 1, payloadLen)
	if payloadLen > 0 then
		buffer.copy(target.raw, target.size + Constants.HEADER_SIZE, scratch.raw, 0, payloadLen)
	end

	target.size += Constants.HEADER_SIZE + payloadLen
end

@native
const function buildImmediateBuffer(packetDef, data): buffer
	const scratch = ByteBuffer.getScratch()
	const schemaSize = packetDef.schema.size
	const capacity = if typeof(schemaSize) == "number" then schemaSize else 256
	ByteBuffer.ensureCapacity(scratch, capacity)
	const payloadLen = packetDef.schema.write(scratch.raw, 0, data)

	const out = buffer.create(Constants.HEADER_SIZE + payloadLen)
	buffer.writeu8(out, 0, packetDef.id)
	buffer.writeu16(out, 1, payloadLen)
	if payloadLen > 0 then
		buffer.copy(out, Constants.HEADER_SIZE, scratch.raw, 0, payloadLen)
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
		Players.PlayerRemoving:Connect(function(player)
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
				if buf ~= nil and buf.size > 0 and player.Parent ~= nil then
					const compacted = ByteBuffer.compact(buf)
					ByteBuffer.reset(buf)
					Channel.getReliableEvent():FireClient(player, compacted)
				end
				isReliablePlayerDirty[player] = nil
			end
			table.clear(activeReliablePlayers)

			for _, player in activeUnreliablePlayers do
				const buf = playerUnreliable[player]
				if buf ~= nil and buf.size > 0 and player.Parent ~= nil then
					const compacted = ByteBuffer.compact(buf)
					ByteBuffer.reset(buf)
					Channel.getUnreliableEvent():FireClient(player, compacted)
				end
				isUnreliablePlayerDirty[player] = nil
			end
			table.clear(activeUnreliablePlayers)
		end)
	else
		RunService.Heartbeat:Connect(function()
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

function OutgoingQueue.clientEnqueue(packetDef, data)
	OutgoingQueue.init()
	if packetDef.packetType == "Unreliable" then
		appendPacket(clientUnreliable, packetDef, data)
	else
		appendPacket(clientReliable, packetDef, data)
	end
end

function OutgoingQueue.clientSendImmediate(packetDef, data)
	const buf = buildImmediateBuffer(packetDef, data)
	if packetDef.packetType == "Unreliable" then
		Channel.getUnreliableEvent():FireServer(buf)
	else
		Channel.getReliableEvent():FireServer(buf)
	end
end

function OutgoingQueue.serverEnqueue(player: Player, packetDef, data)
	OutgoingQueue.init()
	if packetDef.packetType == "Unreliable" then
		const buf = getPlayerBuffer(playerUnreliable, player)
		appendPacket(buf, packetDef, data)
		if not isUnreliablePlayerDirty[player] then
			isUnreliablePlayerDirty[player] = true
			table.insert(activeUnreliablePlayers, player)
		end
	else
		const buf = getPlayerBuffer(playerReliable, player)
		appendPacket(buf, packetDef, data)
		if not isReliablePlayerDirty[player] then
			isReliablePlayerDirty[player] = true
			table.insert(activeReliablePlayers, player)
		end
	end
end

function OutgoingQueue.serverBroadcast(packetDef, data)
	OutgoingQueue.init()
	if packetDef.packetType == "Unreliable" then
		appendPacket(broadcastUnreliable, packetDef, data)
	else
		appendPacket(broadcastReliable, packetDef, data)
	end
end

function OutgoingQueue.serverBroadcastExcept(excludedPlayer: Player, packetDef, data)
	OutgoingQueue.init()
	for _, player in Players:GetPlayers() do
		if player ~= excludedPlayer then
			OutgoingQueue.serverEnqueue(player, packetDef, data)
		end
	end
end

function OutgoingQueue.serverSendImmediate(player: Player, packetDef, data)
	const buf = buildImmediateBuffer(packetDef, data)
	if packetDef.packetType == "Unreliable" then
		Channel.getUnreliableEvent():FireClient(player, buf)
	else
		Channel.getReliableEvent():FireClient(player, buf)
	end
end

function OutgoingQueue.serverBroadcastImmediate(packetDef, data)
	const buf = buildImmediateBuffer(packetDef, data)
	if packetDef.packetType == "Unreliable" then
		Channel.getUnreliableEvent():FireAllClients(buf)
	else
		Channel.getReliableEvent():FireAllClients(buf)
	end
end

return OutgoingQueue
