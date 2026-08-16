--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.types.def)

type AnimationPosition = DefTypes.AnimationPosition

local AnimationPosition = {}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function AnimationPosition.assertValid(position: AnimationPosition): AnimationPosition
	assert(typeof(position) == "table", "AnimationPosition must be a table")
	assert(
		position.kind == "seconds" or position.kind == "normalized",
		'AnimationPosition.kind must be "seconds" or "normalized"'
	)
	assert(typeof(position.value) == "number", "AnimationPosition.value must be a number")
	assert(isFinite(position.value), "AnimationPosition.value must be finite")

	if position.kind == "seconds" then
		assert(position.value >= 0, "seconds AnimationPosition.value must be non-negative")
	else
		assert(
			position.value >= 0 and position.value <= 1,
			"normalized AnimationPosition.value must be within [0, 1]"
		)
	end

	return position
end

function AnimationPosition.isComplete(position: number, length: number, speed: number): boolean
	if position >= length then
		return speed > 0
	end

	return position <= 0 and speed < 0
end

function AnimationPosition.resolve(
	position: AnimationPosition,
	length: number,
	looped: boolean,
	speed: number
): (number, boolean)
	AnimationPosition.assertValid(position)
	assert(isFinite(length) and length > 0, "animation length must be finite and positive")

	if looped then
		if position.kind == "normalized" then
			local normalized = if position.value == 1 then 0 else position.value
			return normalized * length, false
		end

		return position.value % length, false
	end

	local resolved = if position.kind == "normalized"
		then position.value * length
		else math.min(position.value, length)
	return resolved, AnimationPosition.isComplete(resolved, length, speed)
end

return AnimationPosition
