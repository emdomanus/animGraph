--!strict
--!optimize 2
--!native

local AnimPlayback = require(script.animPlayback)
local AnimationPosition = require(script.Parent.Parent.utils.animationPosition)
local RequestValidation = require(script.Parent.Parent.utils.requestValidation)
local BackendTypes = require(script.Parent.Parent.types.backends.animationBackend)
local DefTypes = require(script.Parent.Parent.types.def)
local MotionNodeTypes = require(script.Parent.Parent.types.motions.motionNode)
local Types = require(script.Parent.Parent.types.backends.robloxAnimatorBackend)

export type AssetId = Types.AssetId
export type RobloxLayerBackend = Types.RobloxLayerBackend
export type LogicalPriorityBand = Types.LogicalPriorityBand
export type RobloxAnimatorBackendConfig<ClipT> = Types.RobloxAnimatorBackendConfig<ClipT>
export type RobloxAnimatorBackend<LayerT, StateT, ClipT> = Types.RobloxAnimatorBackend<LayerT, StateT, ClipT>
export type RobloxAnimatorBackendImpl<LayerT, StateT, ClipT> = Types.RobloxAnimatorBackendImpl<
	LayerT,
	StateT,
	ClipT
>

type AnimationPosition = DefTypes.AnimationPosition
type TrackCompletedEvent<LayerT, StateT> = DefTypes.TrackCompletedEvent<LayerT, StateT>
type Playback<LayerT, StateT, ClipT> = AnimPlayback.AnimPlayback<LayerT, StateT, ClipT>

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

local function assertNonNegative(value: number, name: string): number
	assert(value == value and value < math.huge, name .. " must be finite")
	assert(value >= 0, name .. " must be non-negative")
	return value
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
	self._defaultFadeOut = assertNonNegative(optionNumber(config.defaultFadeOut, DEFAULT_FADE_OUT), "defaultFadeOut")
	self._defaultPriority = config.defaultPriority or DEFAULT_PRIORITY
	self._priorityBands = copyPriorityBands(config.priorityBands)
	self._active = {}
	self._physical = {}
	self._retiring = {}
	self._completed = {}
	self._completionListeners = {}
	self._pendingCompletions = {}
	self._nextGeneration = 0
	self._applyDepth = 0
	self._dispatchingCompletions = false
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

function RobloxAnimatorBackend._materialize<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>,
	robloxPriority: Enum.AnimationPriority
): Playback<LayerT, StateT, ClipT>
	local assetId = assertPositiveAssetId(self._resolveAssetId(request.clip))
	self._nextGeneration += 1
	local generation = self._nextGeneration
	local playback: Playback<LayerT, StateT, ClipT> = AnimPlayback.new({
		trackKey = request.trackKey,
		clip = request.clip,
		assetId = assetId,
		animator = self._animator,
		generation = generation,
		onStopped = function(stoppedGeneration)
			self:_handleStopped(stoppedGeneration)
		end,
		onEnded = function(endedGeneration)
			self:_handleEnded(endedGeneration)
		end,
	})

	self._active[request.trackKey] = playback
	self._physical[generation] = playback
	local completed = playback:start(request, robloxPriority)
	if completed then
		self:_complete(playback)
	end
	return playback
end

function RobloxAnimatorBackend._cleanupPhysical<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	generation: number
): ()
	local playback = self._physical[generation] :: Playback<LayerT, StateT, ClipT>?
	if playback == nil then
		return
	end

	self._physical[generation] = nil
	self._retiring[generation] = nil
	playback:cleanup()
end

function RobloxAnimatorBackend._retire<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	playback: Playback<LayerT, StateT, ClipT>,
	fadeTime: number
): ()
	local generation = playback:getGeneration()
	if self._physical[generation] ~= playback then
		return
	end

	local trackKey = playback:getTrackKey()
	if self._active[trackKey] == playback then
		self._active[trackKey] = nil
	end
	self._retiring[generation] = playback
	if playback:retire(fadeTime) then
		self:_cleanupPhysical(generation)
	end
end

function RobloxAnimatorBackend._complete<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	playback: Playback<LayerT, StateT, ClipT>
): ()
	local generation = playback:getGeneration()
	local trackKey = playback:getTrackKey()
	if self._physical[generation] ~= playback or self._active[trackKey] ~= playback then
		return
	end

	playback:latchNaturalCompletion()
	self._active[trackKey] = nil
	local event: TrackCompletedEvent<LayerT, StateT> = {
		name = "trackCompleted",
		trackKey = trackKey,
		layer = playback:getLayer(),
		state = playback:getState(),
	}
	self._completed[trackKey] = {
		trackKey = trackKey,
		layer = event.layer,
		state = event.state,
		clip = playback:getClip(),
		generation = generation,
	}
	self._pendingCompletions[#self._pendingCompletions + 1] = event
	self:_flushCompletions()
end

function RobloxAnimatorBackend._handleStopped<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	generation: number
): ()
	local playback = self._physical[generation] :: Playback<LayerT, StateT, ClipT>?
	if playback == nil or playback:isLooped() then
		return
	end

	local trackKey = playback:getTrackKey()
	if self._active[trackKey] ~= playback then
		return
	end

	playback:latchNaturalCompletion()
	self:_complete(playback)
end

function RobloxAnimatorBackend._handleEnded<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	generation: number
): ()
	local playback = self._physical[generation] :: Playback<LayerT, StateT, ClipT>?
	if playback == nil then
		return
	end

	local trackKey = playback:getTrackKey()
	if self._active[trackKey] == playback then
		if playback:isLooped() then
			self._active[trackKey] = nil
		else
			local completed, resultOrError = pcall(function(): unknown
				self:_complete(playback)
				return nil
			end)
			self:_cleanupPhysical(generation)
			if not completed then
				error(resultOrError, 0)
			end
			return
		end
	end
	self:_cleanupPhysical(generation)
end

function RobloxAnimatorBackend._flushCompletions<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>
): ()
	if self._applyDepth > 0 or self._dispatchingCompletions then
		return
	end

	self._dispatchingCompletions = true
	local dispatched, resultOrError = pcall(function(): unknown
		while #self._pendingCompletions > 0 do
			local event = table.remove(self._pendingCompletions, 1)
			assert(event ~= nil, "completion queue changed during dispatch")
			local listeners = table.clone(self._completionListeners)
			for _, callback in listeners do
				callback(event)
			end
		end
		return nil
	end)
	self._dispatchingCompletions = false
	if not dispatched then
		error(resultOrError, 0)
	end
end

function RobloxAnimatorBackend.apply<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	requests: { MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend> }
): ()
	RequestValidation.validate(requests)
	if self._destroyed then
		return
	end

	self._applyDepth += 1
	local touched: { [string]: true } = {}

	for _, request in requests do
		local trackKey = request.trackKey
		touched[trackKey] = true
		local tombstone = self._completed[trackKey]
		if tombstone ~= nil then
			if tombstone.clip == request.clip and not request.forceRestart then
				continue
			end

			local completedPhysical = self._physical[tombstone.generation] :: Playback<LayerT, StateT, ClipT>?
			self._completed[trackKey] = nil
			if completedPhysical ~= nil then
				self:_retire(completedPhysical, request.fadeTime)
			end
		end

		local playback = self._active[trackKey] :: Playback<LayerT, StateT, ClipT>?
		if playback ~= nil and (playback:getClip() ~= request.clip or request.forceRestart) then
			self:_retire(playback, request.fadeTime)
			playback = nil
		end

		local robloxPriority = self:_mapPriority(request)
		if playback == nil then
			self:_materialize(request, robloxPriority)
		else
			local completed = playback:apply(request, robloxPriority)
			if completed then
				self:_complete(playback)
			end
		end
	end

	local absentActive: { Playback<LayerT, StateT, ClipT> } = {}
	for trackKey, playback in self._active do
		if not touched[trackKey] then
			absentActive[#absentActive + 1] = playback
		end
	end
	for _, playback in absentActive do
		self:_retire(playback, self._defaultFadeOut)
	end

	local absentTombstones: { Types.CompletedTombstone<LayerT, StateT, ClipT> } = {}
	for trackKey, tombstone in self._completed do
		if not touched[trackKey] then
			absentTombstones[#absentTombstones + 1] = tombstone
		end
	end
	for _, tombstone in absentTombstones do
		self._completed[tombstone.trackKey] = nil
		local completedPhysical = self._physical[tombstone.generation] :: Playback<LayerT, StateT, ClipT>?
		if completedPhysical ~= nil then
			self:_retire(completedPhysical, self._defaultFadeOut)
		end
	end

	self._applyDepth -= 1
	self:_flushCompletions()
end

function RobloxAnimatorBackend.setTrackPosition<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	trackKey: string,
	position: AnimationPosition
): boolean
	AnimationPosition.assertValid(position)
	if self._destroyed then
		return false
	end

	local playback = self._active[trackKey] :: Playback<LayerT, StateT, ClipT>?
	if playback == nil or playback:getLifecycle() ~= "active" then
		return false
	end

	local completed = playback:setPosition(position)
	if completed then
		self:_complete(playback)
	end
	return true
end

function RobloxAnimatorBackend.bindToTrackCompleted<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	callback: (event: TrackCompletedEvent<LayerT, StateT>) -> ()
): DefTypes.Release
	assert(typeof(callback) == "function", "track completion callback must be a function")
	if self._destroyed then
		return function() end
	end

	self._completionListeners[#self._completionListeners + 1] = callback
	local released = false
	return function()
		if released then
			return
		end
		released = true

		for index = #self._completionListeners, 1, -1 do
			if self._completionListeners[index] == callback then
				table.remove(self._completionListeners, index)
				break
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

	local resolvedFadeTime = assertNonNegative(optionNumber(fadeTime, self._defaultFadeOut), "fadeTime")
	local selected: { Playback<LayerT, StateT, ClipT> } = {}
	for _, playback in self._active do
		if playback:getLayer() == layer then
			selected[#selected + 1] = playback
		end
	end
	for _, playback in selected do
		self:_retire(playback, resolvedFadeTime)
	end
end

function RobloxAnimatorBackend._clearPhysical<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>
): ()
	local physical: { Playback<LayerT, StateT, ClipT> } = {}
	for _, playback in self._physical do
		physical[#physical + 1] = playback
	end

	self._active = {}
	self._completed = {}
	for _, playback in physical do
		self:_retire(playback, 0)
	end
	self._retiring = {}
	self._physical = {}
	self._warnings = {}
end

function RobloxAnimatorBackend.clear<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>
): ()
	self:_clearPhysical()
end

function RobloxAnimatorBackend.destroy<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>
): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	self:_clearPhysical()
	self._completionListeners = {}
end

function RobloxAnimatorBackend.getCapabilities<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>
): BackendTypes.BackendCapabilities
	local _self = self
	return CAPABILITIES
end

local function appendPlaybackDebug<LayerT, StateT, ClipT>(
	tracks: { BackendTypes.BackendDebugTrack },
	playback: Playback<LayerT, StateT, ClipT>,
	lifecycle: "active" | "retiring"
): ()
	tracks[#tracks + 1] = {
		trackKey = playback:getTrackKey(),
		layer = playback:getLayer(),
		state = playback:getState(),
		clip = playback:getClip(),
		weight = playback:getWeight(),
		speed = playback:getSpeed(),
		logicalPriority = playback:getLogicalPriority(),
		isPlaying = playback:isPlaying(),
		details = {
			robloxPriority = playback:getRobloxPriority(),
			generation = playback:getGeneration(),
			lifecycle = lifecycle,
			physicalPresent = true,
		},
	}
end

function RobloxAnimatorBackend.getDebugSnapshot<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>
): BackendTypes.BackendDebugSnapshot
	local tracks: { BackendTypes.BackendDebugTrack } = {}
	for _, playback in self._active do
		appendPlaybackDebug(tracks, playback, "active")
	end
	for _, playback in self._retiring do
		appendPlaybackDebug(tracks, playback, "retiring")
	end
	for _, tombstone in self._completed do
		tracks[#tracks + 1] = {
			trackKey = tombstone.trackKey,
			layer = tombstone.layer,
			state = tombstone.state,
			clip = tombstone.clip,
			weight = 0,
			speed = 0,
			logicalPriority = 0,
			isPlaying = false,
			details = {
				generation = tombstone.generation,
				lifecycle = "completed",
				physicalPresent = self._physical[tombstone.generation] ~= nil,
			},
		}
	end

	table.sort(tracks, function(left, right)
		local leftDetails = left.details :: any
		local rightDetails = right.details :: any
		return leftDetails.generation < rightDetails.generation
	end)

	return {
		name = "RobloxAnimatorBackend",
		capabilities = CAPABILITIES,
		tracks = tracks,
		warnings = self._warnings,
	}
end

return RobloxAnimatorBackend
