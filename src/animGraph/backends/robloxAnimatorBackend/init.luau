--!strict
--!optimize 2
--!native

local AnimPlayback = require(script.animPlayback)
local RequestValidation = require(script.Parent.Parent.utils.requestValidation)
local Types = require(script.Parent.Parent.types.backends.robloxAnimatorBackend)
local BackendTypes = require(script.Parent.Parent.types.backends.animationBackend)
local MotionNodeTypes = require(script.Parent.Parent.types.motions.motionNode)

export type AssetId = Types.AssetId
export type RobloxLayerBackend = Types.RobloxLayerBackend
export type LogicalPriorityBand = Types.LogicalPriorityBand
export type RobloxAnimatorBackendConfig<ClipT> = Types.RobloxAnimatorBackendConfig<ClipT>
export type RobloxAnimatorBackend<LayerT, StateT, ClipT> = Types.RobloxAnimatorBackend<
	LayerT,
	StateT,
	ClipT
>
export type RobloxAnimatorBackendImpl<LayerT, StateT, ClipT> = Types.RobloxAnimatorBackendImpl<
	LayerT,
	StateT,
	ClipT
>

local DEFAULT_FADE_OUT = 0.2
local DEFAULT_PRIORITY = Enum.AnimationPriority.Movement

local DEFAULT_PRIORITY_BANDS: { LogicalPriorityBand } = {
	{ min = 200, priority = Enum.AnimationPriority.Action4 },
	{ min = 100, priority = Enum.AnimationPriority.Action3 },
	{ min = 50, priority = Enum.AnimationPriority.Action2 },
	{ min = 10, priority = Enum.AnimationPriority.Action },
	{ min = 0, priority = Enum.AnimationPriority.Movement },
}

local CAPABILITIES: BackendTypes.BackendCapabilities = {
	unlimitedPriority = false,
	perJointFallback = "priorityTier",
	customMasks = false,
}

local function optionNumber(value: number?, fallback: number): number
	return if value ~= nil then value else fallback
end

local function assertPositiveAssetId(assetId: AssetId): AssetId
	assert(assetId > 0, "resolved animation asset id must be a positive number")
	return assetId
end

local function copyPriorityBands(priorityBands: { LogicalPriorityBand }?): { LogicalPriorityBand }
	local source = priorityBands or DEFAULT_PRIORITY_BANDS
	local bands = table.create(#source)

	for index, band in source do
		bands[index] = {
			min = band.min,
			priority = band.priority,
		}
	end

	table.sort(bands, function(left, right)
		return left.min > right.min
	end)

	return bands
end

local RobloxAnimatorBackend = {}
RobloxAnimatorBackend.__index = RobloxAnimatorBackend

function RobloxAnimatorBackend.new<LayerT, StateT, ClipT>(
	config: RobloxAnimatorBackendConfig<ClipT>
): RobloxAnimatorBackend<LayerT, StateT, ClipT>
	local self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT> = setmetatable(
		{},
		RobloxAnimatorBackend
	) :: any

	self._animator = config.animator
	self._resolveAssetId = config.resolveAssetId
	self._defaultFadeOut = optionNumber(config.defaultFadeOut, DEFAULT_FADE_OUT)
	self._defaultPriority = config.defaultPriority or DEFAULT_PRIORITY
	self._priorityBands = copyPriorityBands(config.priorityBands)
	self._playbacks = {}
	self._trackStates = {}
	self._warnings = {}
	self._destroyed = false

	return self
end

function RobloxAnimatorBackend._mapPriority<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>
): Enum.AnimationPriority
	local layerBackend = request.layerBackend
	if layerBackend ~= nil and layerBackend.robloxPriority ~= nil then
		return layerBackend.robloxPriority
	end

	for _, band in self._priorityBands do
		if request.logicalPriority >= band.min then
			return band.priority
		end
	end

	return self._defaultPriority
end

function RobloxAnimatorBackend._getOrLoadPlayback<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	trackKey: string,
	clip: ClipT
): any
	local playback = self._playbacks[trackKey]
	if playback ~= nil then
		return playback
	end

	local assetId = assertPositiveAssetId(self._resolveAssetId(clip))
	playback = AnimPlayback.new({
		trackKey = trackKey,
		clip = clip,
		assetId = assetId,
		animator = self._animator,
	})
	self._playbacks[trackKey] = playback

	return playback
end

function RobloxAnimatorBackend.apply<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	requests: { MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend> }
): ()
	if self._destroyed then
		return
	end

	RequestValidation.validate(requests)
	local touched: { [string]: true } = {}

	for _, request in requests do
		local robloxPriority = self:_mapPriority(request)
		local playback = self:_getOrLoadPlayback(request.trackKey, request.clip)
		playback:apply(request, robloxPriority)
		touched[request.trackKey] = true

		self._trackStates[request.trackKey] = {
			trackKey = request.trackKey,
			layer = request.layer,
			state = request.state,
			clip = request.clip,
			weight = playback:getWeight(),
			speed = playback:getSpeed(),
			logicalPriority = request.logicalPriority,
			robloxPriority = robloxPriority,
			isPlaying = playback:isPlaying(),
		}
	end

	for trackKey, playback in self._playbacks do
		if not touched[trackKey] then
			playback:markAbsent()
			playback:fadeToZero(self._defaultFadeOut)
			local state = self._trackStates[trackKey]
			if state ~= nil then
				state.weight = 0
				state.isPlaying = playback:isPlaying()
			end
		end
	end
end

function RobloxAnimatorBackend.stopLayer<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	layer: LayerT,
	fadeTime: number?
): ()
	if self._destroyed then
		return
	end

	local resolvedFadeTime = optionNumber(fadeTime, self._defaultFadeOut)
	for trackKey, state in self._trackStates do
		if state.layer == layer then
			local playback = self._playbacks[trackKey]
			if playback ~= nil then
				playback:fadeToZero(resolvedFadeTime)
			end
			state.weight = 0
		end
	end
end

function RobloxAnimatorBackend.clear<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>
): ()
	for _, playback in self._playbacks do
		playback:destroy()
	end

	self._playbacks = {}
	self._trackStates = {}
	self._warnings = {}
end

function RobloxAnimatorBackend.destroy<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>
): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	self:clear()
end

function RobloxAnimatorBackend.getCapabilities<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>
): BackendTypes.BackendCapabilities
	local _self = self
	return CAPABILITIES
end

function RobloxAnimatorBackend.getDebugSnapshot<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>
): BackendTypes.BackendDebugSnapshot
	local tracks: { BackendTypes.BackendDebugTrack } = {}
	for _, state in self._trackStates do
		tracks[#tracks + 1] = {
			trackKey = state.trackKey,
			layer = state.layer,
			state = state.state,
			clip = state.clip,
			weight = state.weight,
			speed = state.speed,
			logicalPriority = state.logicalPriority,
			isPlaying = state.isPlaying,
			details = {
				robloxPriority = state.robloxPriority,
			},
		}
	end

	return {
		name = "RobloxAnimatorBackend",
		capabilities = CAPABILITIES,
		tracks = tracks,
		warnings = self._warnings,
	}
end

return RobloxAnimatorBackend
