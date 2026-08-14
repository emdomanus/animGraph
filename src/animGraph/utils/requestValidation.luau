--!strict
--!optimize 2
--!native

local AnimationPosition = require(script.Parent.animationPosition)
local MotionNodeTypes = require(script.Parent.Parent.types.motions.motionNode)

local RequestValidation = {}

function RequestValidation.validate<LayerT, StateT, ClipT, LayerBackendT>(
	requests: { MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, LayerBackendT> }
): ()
	local seenTrackKeys: { [string]: true } = {}

	for _, request in requests do
		assert(seenTrackKeys[request.trackKey] == nil, "duplicate trackKey in request batch: " .. request.trackKey)
		seenTrackKeys[request.trackKey] = true

		if request.initialPosition ~= nil then
			AnimationPosition.assertValid(request.initialPosition)
		end
	end
end

return RequestValidation
