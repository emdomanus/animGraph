--!strict
--!optimize 2
--!native

local Types = require(script.Parent.Parent.Parent.Parent.types.motions.blend1DNode.shared.blend1DNode)
local MotionNodeTypes = require(script.Parent.Parent.Parent.Parent.types.motions.motionNode.shared.motionNode)

type Blend1DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.Blend1DSample<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
type Blend1DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.Blend1DNodeConfig<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
type Blend1DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.Blend1DNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
type Blend1DNodeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.Blend1DNodeImpl<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>

local EPSILON = 1e-5

local function readNumber(value: any, fallback: number): number
	return if typeof(value) == "number" then value else fallback
end

local function computeWeights<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	samples: {
		Blend1DSample<
			LayerT,
			StateT,
			ParamT,
			ClipT,
			LayerBackendT
		>
	},
	value: number,
	weights: { number }
): { number }
	local count = #samples
	for index = 1, count do
		weights[index] = 0
	end

	if count == 0 then
		return weights
	end
	if count == 1 or value <= samples[1].threshold then
		weights[1] = 1
		return weights
	end
	if value >= samples[count].threshold then
		weights[count] = 1
		return weights
	end

	for index = 1, count - 1 do
		local left = samples[index]
		local right = samples[index + 1]
		if value >= left.threshold and value <= right.threshold then
			local span = right.threshold - left.threshold
			if math.abs(span) <= EPSILON then
				weights[index + 1] = 1
			else
				local alpha = math.clamp((value - left.threshold) / span, 0, 1)
				weights[index] = 1 - alpha
				weights[index + 1] = alpha
			end
			return weights
		end
	end

	weights[count] = 1
	return weights
end

local Blend1DNode = {}
Blend1DNode.__index = Blend1DNode

function Blend1DNode.new<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	parameter: ParamT,
	config: Blend1DNodeConfig<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>
): Blend1DNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
	assert(#config.samples > 0, "Blend1DNode requires at least one sample")

	local samples = table.clone(config.samples)
	table.sort(
		samples,
		function(
			left: Blend1DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
			right: Blend1DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT>
		)
			return left.threshold < right.threshold
		end
	)

	local self: Blend1DNodeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = setmetatable({}, Blend1DNode) :: any
	self._parameter = parameter
	self._name = config.name or "Blend1D"
	self._defaultValue = config.defaultValue or 0
	self._samples = samples
	self._lastValue = self._defaultValue
	self._lastWeights = table.create(#samples, 0)
	self._spareWeights = self._lastWeights

	return self
end

function Blend1DNode.evaluate<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: Blend1DNodeImpl<
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
	local value = readNumber(context.getParameter(self._parameter), self._defaultValue)
	local weights = self._spareWeights or table.create(#self._samples, 0)
	-- Lease the array before calling children; nested evaluation needs its own weights.
	self._spareWeights = nil
	computeWeights(self._samples, value, weights)
	local requests: { MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, LayerBackendT> } = {}

	self._lastValue = value
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

	if self._spareWeights == nil then
		self._spareWeights = weights
	end
	return requests
end

function Blend1DNode.getDebugSnapshot<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: Blend1DNodeImpl<
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
		details.threshold = sample.threshold
		details.weight = self._lastWeights[index] or 0
		children[index] = child
	end

	return {
		kind = "Blend1D",
		name = self._name,
		details = {
			parameter = tostring(self._parameter),
			value = self._lastValue,
		},
		children = children,
	}
end

return { new = Blend1DNode.new }
