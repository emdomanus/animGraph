--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.types.def)

type AnimationPosition = DefTypes.AnimationPosition

local AnimationPosition = {}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function AnimationPosition.assertFiniteSeconds(value: number, name: string): number
	assert(typeof(value) == "number", name .. " must be a number")
	assert(isFinite(value), name .. " must be finite")
	return value
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

function AnimationPosition.resolveOffset(
	basePosition: number,
	deltaSeconds: number,
	length: number,
	looped: boolean,
	speed: number
): (number, boolean)
	AnimationPosition.assertFiniteSeconds(basePosition, "basePosition")
	AnimationPosition.assertFiniteSeconds(deltaSeconds, "deltaSeconds")
	assert(isFinite(length) and length > 0, "animation length must be finite and positive")

	if looped then
		local wrappedBase = basePosition % length
		local wrappedDelta = deltaSeconds % length
		local distanceToEnd = length - wrappedBase
		local resolved = if wrappedDelta >= distanceToEnd
			then wrappedDelta - distanceToEnd
			else wrappedBase + wrappedDelta
		return resolved, false
	end

	local resolved: number
	if deltaSeconds > 0 then
		resolved = if basePosition >= length - deltaSeconds
			then length
			else math.max(basePosition + deltaSeconds, 0)
	elseif deltaSeconds < 0 then
		resolved = if basePosition <= -deltaSeconds
			then 0
			else math.min(basePosition + deltaSeconds, length)
	else
		resolved = math.clamp(basePosition, 0, length)
	end

	return resolved, AnimationPosition.isComplete(resolved, length, speed)
end

return AnimationPosition
