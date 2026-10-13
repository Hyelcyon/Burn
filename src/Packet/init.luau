--!strict

const Definition = require(script.Definition)
const Registry = require(script.Registry)

export type PacketType = Definition.PacketType
export type PacketDefinition<T> = Definition.PacketDefinition<T>

return table.freeze({
	Definition = Definition,
	Registry = Registry,
})
