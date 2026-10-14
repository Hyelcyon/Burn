--!strict

const Definition = require("@packet/Definition")
const Registry = require("@packet/Registry")

export type PacketType = Definition.PacketType
export type PacketDefinition<T> = Definition.PacketDefinition<T>

return table.freeze({
	Definition = Definition,
	Registry = Registry,
})
