--!strict

--[=[
	@class Constants
	@within Burn
	Fixed protocol limits, wire framing dimensions, and network rate-limiting parameters.
]=]
const Constants = table.freeze({
	DEFAULT_BUFFER_CAPACITY = 4096,

	-- Packet identifiers are encoded as a single byte (u8) in the wire header.
	MAX_PACKET_ID = 255,

	REMOTE_FOLDER_NAME = "_BurnNetwork",
	RELIABLE_EVENT_NAME = "ReliableEvent",
	UNRELIABLE_EVENT_NAME = "UnreliableEvent",
	REQUEST_FUNCTION_NAME = "RequestFunction",

	-- Wire header layout: 1 byte packet ID (u8) + 2 bytes payload length (u16).
	HEADER_SIZE = 3,

	-- Maximum byte budget for a single batched reliable payload.
	MAX_PACKET_SIZE = 65536,

	-- Maximum payload size: MAX_PACKET_SIZE - HEADER_SIZE.
	MAX_PAYLOAD_SIZE = 65533,

	-- Roblox drops UnreliableRemoteEvent payloads exceeding 900 bytes (MTU threshold).
	MAX_UNRELIABLE_BYTES = 900,

	-- Upper bound on packets decoded per batch to prevent CPU starvation attacks.
	MAX_PACKETS_PER_BATCH = 256,

	-- Minimum token cost charged against rate limit to penalize malformed or 0-byte packet spam.
	MIN_PACKET_COST_BYTES = 32,

	-- Per-player token bucket replenishment rate (64 KB/sec).
	RATE_LIMIT_BYTES_PER_SEC = 65536,
})

return Constants
