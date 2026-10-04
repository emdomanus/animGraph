--!strict
--!optimize 2
--!native

local AnimationPosition = require(script.Parent.Parent.Parent.animationPosition.shared.animationPosition)
local MotionNodeTypes = require(script.Parent.Parent.Parent.Parent.types.motions.motionNode.shared.motionNode)

local RequestValidation = {}

local spareSeenTrackKeys: { [string]: true }? = {}

local function assertFinite(value: number, name: string): ()
	assert(typeof(value) == "number", name .. " must be a number")
	assert(value == value and value > -math.huge and value < math.huge, name .. " must be finite")
end

function RequestValidation.validate<LayerT, StateT, ClipT, LayerBackendT>(requests: {
	MotionNodeTypes.ClipRequest<
		LayerT,
		StateT,
		ClipT,
		LayerBackendT
	>
}): ()
	local seenTrackKeys = spareSeenTrackKeys or {}
	-- A rejected or re-entrant validation must not expose a partially filled map.
	spareSeenTrackKeys = nil

	for _, request in requests do
		assert(seenTrackKeys[request.trackKey] == nil, "duplicate trackKey in request batch: " .. request.trackKey)
		seenTrackKeys[request.trackKey] = true
		assertFinite(request.weight, "request weight")
		assertFinite(request.speed, "request speed")
		assertFinite(request.timePosition, "request timePosition")
		assertFinite(request.timeRate, "request timeRate")
		assertFinite(request.speed * request.timeRate, "request composed speed")
		assertFinite(request.logicalPriority, "request logicalPriority")
		assertFinite(request.fadeTime, "request fadeTime")
		assert(request.fadeTime >= 0, "request fadeTime must be non-negative")

		if request.initialPosition ~= nil then
			AnimationPosition.assertValid(request.initialPosition)
		end
	end
	table.clear(seenTrackKeys)
	if spareSeenTrackKeys == nil then
		spareSeenTrackKeys = seenTrackKeys
	end
end

return RequestValidation
