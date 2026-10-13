--!strict

const Constants = table.freeze({
	DEFAULT_BUFFER_CAPACITY = 4096,
	MAX_PACKET_ID = 255,
	REMOTE_FOLDER_NAME = "_BurnNetwork",
	RELIABLE_EVENT_NAME = "ReliableEvent",
	UNRELIABLE_EVENT_NAME = "UnreliableEvent",
	REQUEST_FUNCTION_NAME = "RequestFunction",
	HEADER_SIZE = 3,
	MAX_PACKET_SIZE = 65536,
	RATE_LIMIT_BYTES_PER_SEC = 65536,
})

return Constants
