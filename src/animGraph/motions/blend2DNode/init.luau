--!strict
--!optimize 2
--!native

local Types = require(script.Parent.Parent.types.motions.blend2DNode)
local MotionNodeTypes = require(script.Parent.Parent.types.motions.motionNode)

export type Blend2DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.Blend2DSample<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type Blend2DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.Blend2DNodeConfig<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type Blend2DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.Blend2DNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type Blend2DNodeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.Blend2DNodeImpl<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>

type Blend2DCandidate = Types.Blend2DCandidate
type Blend2DEvaluationScratch = Types.Blend2DEvaluationScratch

local EPSILON = 1e-6
local DEFAULT_MAX_INFLUENCES = 4

local function readNumber(value: any, fallback: number): number
	return if typeof(value) == "number" then value else fallback
end

local function computeWeights<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	samples: {
		Blend2DSample<
			LayerT,
			StateT,
			ParamT,
			ClipT,
			LayerBackendT
		>
	},
	x: number,
	y: number,
	maxInfluences: number,
	scratch: Blend2DEvaluationScratch
): { number }
	local count = #samples
	local weights = scratch.weights
	for index = 1, count do
		weights[index] = 0
	end
	if count == 0 then
		return weights
	end

	local candidates = scratch.candidates
	for index, sample in samples do
		local dx = x - sample.x
		local dy = y - sample.y
		local distanceSquared = dx * dx + dy * dy
		if distanceSquared <= EPSILON then
			weights[index] = 1
			return weights
		end

		-- Reset sample order before sorting, including after exact-hit early returns.
		local candidate = candidates[index]
		if candidate == nil then
			candidates[index] = { index = index, distanceSquared = distanceSquared }
		else
			candidate.index = index
			candidate.distanceSquared = distanceSquared
		end
	end

	table.sort(candidates, function(left: Blend2DCandidate, right: Blend2DCandidate)
		return left.distanceSquared < right.distanceSquared
	end)

	local total = 0
	local influenceCount = math.min(math.max(maxInfluences, 1), #candidates)
	for index = 1, influenceCount do
		local candidate = candidates[index]
		local influence = 1 / candidate.distanceSquared
		weights[candidate.index] = influence
		total += influence
	end

	if total > 0 then
		for index = 1, count do
			weights[index] /= total
		end
	end

	return weights
end

local Blend2DNode = {}
Blend2DNode.__index = Blend2DNode

function Blend2DNode.new<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	parameterX: ParamT,
	parameterY: ParamT,
	config: Blend2DNodeConfig<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>
): Blend2DNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
	assert(#config.samples > 0, "Blend2DNode requires at least one sample")

	local self: Blend2DNodeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = setmetatable({}, Blend2DNode) :: any
	self._parameterX = parameterX
	self._parameterY = parameterY
	self._name = config.name or "Blend2D"
	self._defaultX = config.defaultX or 0
	self._defaultY = config.defaultY or 0
	self._maxInfluences = config.maxInfluences or DEFAULT_MAX_INFLUENCES
	self._samples = table.clone(config.samples)
	self._lastX = self._defaultX
	self._lastY = self._defaultY
	self._lastWeights = table.create(#self._samples, 0)
	self._spareEvaluationScratch = { weights = self._lastWeights, candidates = {} }

	return self
end

function Blend2DNode.evaluate<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: Blend2DNodeImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	context: MotionNodeTypes.MotionEvaluateContext<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>
): {
	MotionNodeTypes.ClipRequest<
		LayerT,
		StateT,
		ClipT,
		LayerBackendT
	>
}
	local x = readNumber(context.getParameter(self._parameterX), self._defaultX)
	local y = readNumber(context.getParameter(self._parameterY), self._defaultY)
	local scratch = self._spareEvaluationScratch or { weights = table.create(#self._samples, 0), candidates = {} }
	-- Child callbacks may re-enter this node. Never share an in-flight workspace.
	self._spareEvaluationScratch = nil
	local weights = computeWeights(self._samples, x, y, self._maxInfluences, scratch)
	local requests: { MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, LayerBackendT> } = {}

	self._lastX = x
	self._lastY = y
	self._lastWeights = weights

	for index, sample in self._samples do
		local weight = weights[index]
		if weight > 0 then
			local sampleRequests = sample.motion:evaluate(context)
			for _, request in sampleRequests do
				request.weight *= weight
				requests[#requests + 1] = request
			end
		end
	end

	if self._spareEvaluationScratch == nil then
		self._spareEvaluationScratch = scratch
	end
	return requests
end

function Blend2DNode.getDebugSnapshot<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: Blend2DNodeImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>
): MotionNodeTypes.MotionDebugSnapshot
	local children = table.create(#self._samples) :: { MotionNodeTypes.MotionDebugSnapshot }
	for index, sample in self._samples do
		local child = sample.motion:getDebugSnapshot()
		local details: { [string]: any } = child.details or {}
		child.details = details
		details.x = sample.x
		details.y = sample.y
		details.weight = self._lastWeights[index] or 0
		children[index] = child
	end

	return {
		kind = "Blend2D",
		name = self._name,
		details = {
			parameterX = tostring(self._parameterX),
			parameterY = tostring(self._parameterY),
			x = self._lastX,
			y = self._lastY,
		},
		children = children,
	}
end

return Blend2DNode
