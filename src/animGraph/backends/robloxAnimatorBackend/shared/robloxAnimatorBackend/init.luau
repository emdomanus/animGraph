--!strict
--!optimize 2
--!native

local AnimPlaybackTypes = require(
	script.Parent.Parent.Parent.Parent.types.backends.robloxAnimatorBackend.shared.robloxAnimatorBackend.animPlayback
)
local RobloxPlaybackDefTypes =
	require(script.Parent.Parent.Parent.Parent.types.def.animationPlayback.shared.robloxPlayback)
local AnimPlayback = require(script.animPlayback)
local SampledAnimPlayback = require(script.sampledAnimPlayback)
local AnimationPosition = require(script.Parent.Parent.Parent.Parent.utils.animationPosition.shared.animationPosition)
local RequestValidation = require(script.Parent.Parent.Parent.Parent.utils.requestValidation.shared.requestValidation)
local BackendTypes = require(script.Parent.Parent.Parent.Parent.types.backends.animationBackend.shared.animationBackend)
local TrackMarkerSourceTypes =
	require(script.Parent.Parent.Parent.Parent.types.ports.backends.animationPlayback.shared.trackMarkerSource)
local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def.animation.shared.animation)
local MotionNodeTypes = require(script.Parent.Parent.Parent.Parent.types.motions.motionNode.shared.motionNode)
local Types =
	require(script.Parent.Parent.Parent.Parent.types.backends.robloxAnimatorBackend.shared.robloxAnimatorBackend)

type AssetId = RobloxPlaybackDefTypes.AssetId
type RobloxLayerBackend = RobloxPlaybackDefTypes.RobloxLayerBackend
type LogicalPriorityBand = RobloxPlaybackDefTypes.LogicalPriorityBand
type RobloxAnimatorBackendConfig<ClipT> = Types.RobloxAnimatorBackendConfig<ClipT>
type RobloxAnimatorBackend<LayerT, StateT, ClipT> = Types.RobloxAnimatorBackend<LayerT, StateT, ClipT>
type RobloxAnimatorBackendImpl<LayerT, StateT, ClipT> = Types.RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>

type TrackMarkerSource<LayerT, StateT, ClipT> = TrackMarkerSourceTypes.TrackMarkerSource<LayerT, StateT, ClipT>
type AnimationPosition = DefTypes.AnimationPosition
type TrackCompletedEvent<LayerT, StateT> = DefTypes.TrackCompletedEvent<LayerT, StateT>
type TrackMarkerListeners<LayerT, StateT, ClipT> = Types.TrackMarkerListeners<LayerT, StateT, ClipT>
type TrackMarkerListener<LayerT, StateT, ClipT> = Types.TrackMarkerListener<LayerT, StateT, ClipT>
type TrackMarkerBinding<LayerT, StateT, ClipT> = Types.TrackMarkerBinding<LayerT, StateT, ClipT>
type Playback<LayerT, StateT, ClipT> = AnimPlaybackTypes.AnimPlayback<LayerT, StateT, ClipT>

local DEFAULT_FADE_OUT = 0.2
local DEFAULT_PRIORITY = Enum.AnimationPriority.Movement

local DEFAULT_PRIORITY_BANDS: { LogicalPriorityBand } = {
	{ min = 200, priority = Enum.AnimationPriority.Action4 },
	{ min = 100, priority = Enum.AnimationPriority.Action3 },
	{ min = 50, priority = Enum.AnimationPriority.Action2 },
	{ min = 10, priority = Enum.AnimationPriority.Action },
	{ min = 0, priority = Enum.AnimationPriority.Movement },
}

local NATIVE_RATE: BackendTypes.BackendPositionMode = "nativeRate"
local SAMPLED_POSITION: BackendTypes.BackendPositionMode = "sampledPosition"

local function makeCapabilities(positionMode: BackendTypes.BackendPositionMode): BackendTypes.BackendCapabilities
	return {
		positionMode = positionMode,
		trackMarkers = positionMode == NATIVE_RATE,
		unlimitedPriority = false,
		perJointFallback = "priorityTier",
		customMasks = false,
	}
end

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

local function assertFiniteSampleTime(sampleTime: number): number
	assert(typeof(sampleTime) == "number", "sampleTime must be a number")
	assert(sampleTime == sampleTime and sampleTime > -math.huge and sampleTime < math.huge, "sampleTime must be finite")
	return sampleTime
end

local function copyPriorityBands(priorityBands: { LogicalPriorityBand }?): { LogicalPriorityBand }
	local source = priorityBands or DEFAULT_PRIORITY_BANDS
	local bands = table.create(#source) :: { LogicalPriorityBand }

	for index, band in source do
		bands[index] = {
			min = band.min,
			priority = band.priority,
		}
	end

	table.sort(bands, function(left: LogicalPriorityBand, right: LogicalPriorityBand)
		return left.min > right.min
	end)

	return bands
end

local function newMarkerListeners<LayerT, StateT, ClipT>(): TrackMarkerListeners<LayerT, StateT, ClipT>
	return { items = {}, count = 0, dispatchDepth = 0 }
end

local function compactMarkerListeners<LayerT, StateT, ClipT>(listeners: TrackMarkerListeners<LayerT, StateT, ClipT>): ()
	if listeners.dispatchDepth > 0 or #listeners.items == listeners.count then
		return
	end
	local kept = 0
	local length = #listeners.items
	for index = 1, length do
		local listener = listeners.items[index]
		if listener.connected then
			kept += 1
			listeners.items[kept] = listener
		end
	end
	for index = kept + 1, length do
		listeners.items[index] = nil
	end
end

local function markerBindingIsActive<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	binding: TrackMarkerBinding<LayerT, StateT, ClipT>
): boolean
	local playback = binding.playback
	return binding.connected
		and not self._destroyed
		and self._active[playback:getTrackKey()] == playback
		and playback:getLifecycle() == "active"
end

local function dispatchMarkerListeners<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	binding: TrackMarkerBinding<LayerT, StateT, ClipT>,
	value: string,
	listeners: TrackMarkerListeners<LayerT, StateT, ClipT>?,
	count: number
): ()
	if listeners == nil then
		return
	end
	for index = 1, count do
		if not markerBindingIsActive(self, binding) then
			break
		end
		local listener = listeners.items[index]
		if listener.connected then
			if listener.kind == "track" then
				listener.callback(value)
			else
				listener.callback(binding.playback, value)
			end
		end
	end
end

local function dispatchMarkerBatch<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	binding: TrackMarkerBinding<LayerT, StateT, ClipT>,
	value: string,
	trackListeners: TrackMarkerListeners<LayerT, StateT, ClipT>?,
	trackCount: number,
	allListeners: TrackMarkerListeners<LayerT, StateT, ClipT>?,
	allCount: number
): unknown
	dispatchMarkerListeners(self, binding, value, trackListeners, trackCount)
	dispatchMarkerListeners(self, binding, value, allListeners, allCount)
	return nil
end

local RobloxAnimatorBackend = {}
RobloxAnimatorBackend.__index = RobloxAnimatorBackend

function RobloxAnimatorBackend.new<LayerT, StateT, ClipT>(
	config: RobloxAnimatorBackendConfig<ClipT>
): RobloxAnimatorBackend<LayerT, StateT, ClipT>
	local self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT> = setmetatable({}, RobloxAnimatorBackend) :: any

	self._animator = config.animator
	self._resolveAssetId = config.resolveAssetId
	self._defaultFadeOut = assertNonNegative(optionNumber(config.defaultFadeOut, DEFAULT_FADE_OUT), "defaultFadeOut")
	self._defaultPriority = config.defaultPriority or DEFAULT_PRIORITY
	self._priorityBands = copyPriorityBands(config.priorityBands)
	local positionMode = config.positionMode or NATIVE_RATE
	assert(positionMode == NATIVE_RATE or positionMode == SAMPLED_POSITION, "invalid backend positionMode")
	self._positionMode = positionMode
	self._capabilities = makeCapabilities(positionMode)
	self._lastSampleTime = nil
	self._active = {}
	self._physical = {}
	self._retiring = {}
	self._completed = {}
	self._trackMarkerListeners = {}
	self._markerListeners = {}
	self._markerBindings = {}
	self._pendingMarkerBindings = {}
	self._pendingMarkerValues = {}
	self._markerQueueHead = 1
	self._markerQueueTail = 0
	self._dispatchingMarkers = false
	self._completionListeners = {}
	self._pendingCompletions = {}
	self._nextGeneration = 0
	self._applyDepth = 0
	self._spareTouched = {}
	self._dispatchingCompletions = false
	self._lifecycleEpoch = 0
	self._warnings = {}
	self._destroyed = false

	return self
end

function RobloxAnimatorBackend._mapPriority<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	request: MotionNodeTypes.ClipRequest<
		LayerT,
		StateT,
		ClipT,
		RobloxLayerBackend
	>
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
	sampleTime: number,
	request: MotionNodeTypes.ClipRequest<
		LayerT,
		StateT,
		ClipT,
		RobloxLayerBackend
	>,
	robloxPriority: Enum.AnimationPriority
): Playback<LayerT, StateT, ClipT>?
	local lifecycleEpoch = self._lifecycleEpoch
	local resolvedAssetId = self._resolveAssetId(request.clip)
	if self._destroyed or self._lifecycleEpoch ~= lifecycleEpoch then
		return nil
	end
	local assetId = assertPositiveAssetId(resolvedAssetId)
	self._nextGeneration += 1
	local generation = self._nextGeneration
	local playbackConfig: AnimPlaybackTypes.AnimPlaybackConfig<ClipT> = {
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
	}
	local playback: Playback<LayerT, StateT, ClipT>
	if self._positionMode == SAMPLED_POSITION then
		playback = SampledAnimPlayback.new(playbackConfig)
	else
		playback = AnimPlayback.new(playbackConfig)
	end

	self._active[request.trackKey] = playback
	self._physical[generation] = playback
	local trackMarkerListeners = self._trackMarkerListeners[request.trackKey]
	if trackMarkerListeners ~= nil then
		for markerName in trackMarkerListeners do
			self:_refreshMarker(playback, markerName)
		end
	end
	for markerName in self._markerListeners do
		self:_refreshMarker(playback, markerName)
	end
	local completed = playback:start(sampleTime, request, robloxPriority)
	if completed then
		self:_complete(playback)
	end
	return playback
end

function RobloxAnimatorBackend._cleanupPhysical<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<
		LayerT,
		StateT,
		ClipT
	>,
	generation: number
): ()
	local playback = self._physical[generation] :: Playback<LayerT, StateT, ClipT>?
	if playback == nil then
		return
	end

	self:_disconnectMarkers(playback)
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
	self:_disconnectMarkers(playback)
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
	self:_disconnectMarkers(playback)
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
	if playback:getPositionMode() == SAMPLED_POSITION then
		self:_cleanupPhysical(generation)
	end
	self:_flushCompletions()
end

function RobloxAnimatorBackend._handleStopped<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<
		LayerT,
		StateT,
		ClipT
	>,
	generation: number
): ()
	local playback = self._physical[generation] :: Playback<LayerT, StateT, ClipT>?
	if playback == nil or playback:isLooped() or playback:getPositionMode() == SAMPLED_POSITION then
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
		if playback:getPositionMode() == SAMPLED_POSITION then
			return
		end
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

function RobloxAnimatorBackend._flushCompletions<LayerT, StateT, ClipT>(self: RobloxAnimatorBackendImpl<
	LayerT,
	StateT,
	ClipT
>): ()
	if self._applyDepth > 0 or self._dispatchingCompletions or #self._pendingCompletions == 0 then
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
	sampleTime: number,
	requests: {
		MotionNodeTypes.ClipRequest<
			LayerT,
			StateT,
			ClipT,
			RobloxLayerBackend
		>
	}
): ()
	assertFiniteSampleTime(sampleTime)
	local lastSampleTime = self._lastSampleTime
	assert(lastSampleTime == nil or sampleTime >= lastSampleTime, "sampleTime moved backward")
	RequestValidation.validate(requests)
	if self._destroyed then
		return
	end
	for _, request in requests do
		local playback = self._active[request.trackKey] :: Playback<LayerT, StateT, ClipT>?
		if playback ~= nil and playback:getClip() == request.clip and not request.forceRestart then
			playback:preflightApply(request)
		end
	end
	self._lastSampleTime = sampleTime

	self._applyDepth += 1
	local touched = self._spareTouched or {}
	self._spareTouched = nil
	local applied, resultOrError = pcall(function(): unknown
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
				local materialized = self:_materialize(sampleTime, request, robloxPriority)
				if materialized == nil then
					return nil
				end
			else
				local completed = playback:apply(sampleTime, request, robloxPriority)
				if completed then
					self:_complete(playback)
				end
			end
		end

		local absentActive: { Playback<LayerT, StateT, ClipT> }? = nil
		for trackKey, playback in self._active do
			if not touched[trackKey] then
				local absent: { Playback<LayerT, StateT, ClipT> } = absentActive or {}
				absent[#absent + 1] = playback
				absentActive = absent
			end
		end
		if absentActive ~= nil then
			for _, playback in absentActive do
				self:_retire(playback, self._defaultFadeOut)
			end
		end

		local absentTombstones: { Types.CompletedTombstone<LayerT, StateT, ClipT> }? = nil
		for trackKey, tombstone in self._completed do
			if not touched[trackKey] then
				local absent: { Types.CompletedTombstone<LayerT, StateT, ClipT> } = absentTombstones or {}
				absent[#absent + 1] = tombstone
				absentTombstones = absent
			end
		end
		if absentTombstones ~= nil then
			for _, tombstone in absentTombstones do
				self._completed[tombstone.trackKey] = nil
				local completedPhysical = self._physical[tombstone.generation] :: Playback<LayerT, StateT, ClipT>?
				if completedPhysical ~= nil then
					self:_retire(completedPhysical, self._defaultFadeOut)
				end
			end
		end
		return nil
	end)

	self._applyDepth -= 1
	table.clear(touched)
	if self._spareTouched == nil then
		self._spareTouched = touched
	end
	if not applied then
		self:_clearMarkerQueue()
		error(resultOrError, 0)
	end
	self:_flushCompletions()
	self:_flushMarkers()
end

function RobloxAnimatorBackend.setTrackPosition<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<
		LayerT,
		StateT,
		ClipT
	>,
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

function RobloxAnimatorBackend.offsetTrackPosition<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<
		LayerT,
		StateT,
		ClipT
	>,
	trackKey: string,
	deltaSeconds: number
): boolean
	AnimationPosition.assertFiniteSeconds(deltaSeconds, "deltaSeconds")
	if self._destroyed then
		return false
	end

	local playback = self._active[trackKey] :: Playback<LayerT, StateT, ClipT>?
	if playback == nil or playback:getLifecycle() ~= "active" then
		return false
	end

	local completed = playback:offsetPosition(deltaSeconds)
	if completed then
		self:_complete(playback)
	end
	return true
end

function RobloxAnimatorBackend._refreshMarker<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<
		LayerT,
		StateT,
		ClipT
	>,
	playback: Playback<LayerT, StateT, ClipT>,
	markerName: string
): ()
	local trackKey = playback:getTrackKey()
	local generation = playback:getGeneration()
	local trackListeners = self._trackMarkerListeners[trackKey]
	local wanted = self._markerListeners[markerName] ~= nil
		or (trackListeners ~= nil and trackListeners[markerName] ~= nil)
	local bindings = self._markerBindings[generation]
	local existing = if bindings ~= nil then bindings[markerName] else nil
	if not wanted then
		if existing ~= nil then
			existing.connected = false
			local releasePlayback = existing.releasePlayback
			existing.releasePlayback = nil
			if releasePlayback ~= nil then
				releasePlayback()
			end
			if bindings ~= nil then
				bindings[markerName] = nil
			end
		end
		return
	end
	if existing ~= nil or self._active[trackKey] ~= playback then
		return
	end
	if bindings == nil then
		bindings = {}
		self._markerBindings[generation] = bindings
	end
	local binding: TrackMarkerBinding<LayerT, StateT, ClipT> = {
		playback = playback,
		markerName = markerName,
		connected = true,
	}
	bindings[markerName] = binding
	binding.releasePlayback = playback:bindToMarker(markerName, function(value: string)
		if not markerBindingIsActive(self, binding) then
			return
		end
		local index = self._markerQueueTail + 1
		self._markerQueueTail = index
		self._pendingMarkerBindings[index] = binding
		self._pendingMarkerValues[index] = value
		self:_flushMarkers()
	end)
end

function RobloxAnimatorBackend._disconnectMarkers<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<
		LayerT,
		StateT,
		ClipT
	>,
	playback: Playback<LayerT, StateT, ClipT>
): ()
	local generation = playback:getGeneration()
	local bindings = self._markerBindings[generation]
	if bindings == nil then
		return
	end
	self._markerBindings[generation] = nil
	for _, binding in bindings do
		binding.connected = false
		local releasePlayback = binding.releasePlayback
		binding.releasePlayback = nil
		if releasePlayback ~= nil then
			releasePlayback()
		end
	end
end

function RobloxAnimatorBackend._clearMarkerQueue<LayerT, StateT, ClipT>(self: RobloxAnimatorBackendImpl<
	LayerT,
	StateT,
	ClipT
>): ()
	table.clear(self._pendingMarkerBindings)
	table.clear(self._pendingMarkerValues)
	self._markerQueueHead = 1
	self._markerQueueTail = 0
end

function RobloxAnimatorBackend._drainMarkers<LayerT, StateT, ClipT>(self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>): unknown
	while self._markerQueueHead <= self._markerQueueTail do
		local index = self._markerQueueHead
		local binding = self._pendingMarkerBindings[index]
		local value = self._pendingMarkerValues[index]
		self._pendingMarkerBindings[index] = nil
		self._pendingMarkerValues[index] = nil
		self._markerQueueHead = index + 1
		if not markerBindingIsActive(self, binding) then
			continue
		end
		local byTrack = self._trackMarkerListeners[binding.playback:getTrackKey()]
		local trackListeners = if byTrack ~= nil then byTrack[binding.markerName] else nil
		local allListeners = self._markerListeners[binding.markerName]
		-- Capture both lengths before any callback. Defer removals while either list is in use.
		local trackCount = if trackListeners ~= nil then #trackListeners.items else 0
		local allCount = if allListeners ~= nil then #allListeners.items else 0
		if trackListeners ~= nil then
			trackListeners.dispatchDepth += 1
		end
		if allListeners ~= nil then
			allListeners.dispatchDepth += 1
		end
		local dispatched, failure =
			pcall(dispatchMarkerBatch, self, binding, value, trackListeners, trackCount, allListeners, allCount)
		if trackListeners ~= nil then
			trackListeners.dispatchDepth -= 1
			compactMarkerListeners(trackListeners)
		end
		if allListeners ~= nil then
			allListeners.dispatchDepth -= 1
			compactMarkerListeners(allListeners)
		end
		if not dispatched then
			error(failure, 0)
		end
	end
	return nil
end

function RobloxAnimatorBackend._flushMarkers<LayerT, StateT, ClipT>(self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>): ()
	if self._applyDepth > 0 or self._dispatchingMarkers or self._markerQueueHead > self._markerQueueTail then
		return
	end
	self._dispatchingMarkers = true
	local dispatched, failure = pcall(self._drainMarkers, self)
	self._dispatchingMarkers = false
	self:_clearMarkerQueue()
	if not dispatched then
		error(failure, 0)
	end
end

function RobloxAnimatorBackend.bindToTrackMarker<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<
		LayerT,
		StateT,
		ClipT
	>,
	trackKey: string,
	markerName: string,
	callback: (value: string) -> ()
): DefTypes.Release
	assert(not self._destroyed, "cannot subscribe to markers on a destroyed backend")
	assert(self._capabilities.trackMarkers, "sampledPosition does not support track markers")
	assert(typeof(trackKey) == "string" and #trackKey > 0, "trackKey must be a non-empty string")
	assert(typeof(markerName) == "string" and #markerName > 0, "markerName must be a non-empty string")
	assert(typeof(callback) == "function", "track marker callback must be a function")
	local byTrack = self._trackMarkerListeners[trackKey]
	if byTrack == nil then
		byTrack = {}
		self._trackMarkerListeners[trackKey] = byTrack
	end
	local listeners = byTrack[markerName]
	if listeners == nil then
		listeners = newMarkerListeners()
		byTrack[markerName] = listeners
	end
	local listener: TrackMarkerListener<LayerT, StateT, ClipT> = {
		kind = "track",
		callback = callback,
		connected = true,
	}
	listeners.items[#listeners.items + 1] = listener
	listeners.count += 1
	local playback = self._active[trackKey] :: Playback<LayerT, StateT, ClipT>?
	if playback ~= nil then
		self:_refreshMarker(playback, markerName)
	end
	return function()
		if not listener.connected then
			return
		end
		listener.connected = false
		listeners.count -= 1
		compactMarkerListeners(listeners)
		if listeners.count == 0 then
			byTrack[markerName] = nil
			if next(byTrack) == nil and self._trackMarkerListeners[trackKey] == byTrack then
				self._trackMarkerListeners[trackKey] = nil
			end
			local active = self._active[trackKey] :: Playback<LayerT, StateT, ClipT>?
			if active ~= nil then
				self:_refreshMarker(active, markerName)
			end
		end
	end
end

function RobloxAnimatorBackend.bindToMarker<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
	markerName: string,
	callback: (
		track: TrackMarkerSource<LayerT, StateT, ClipT>,
		value: string
	) -> ()
): DefTypes.Release
	assert(not self._destroyed, "cannot subscribe to markers on a destroyed backend")
	assert(self._capabilities.trackMarkers, "sampledPosition does not support track markers")
	assert(typeof(markerName) == "string" and #markerName > 0, "markerName must be a non-empty string")
	assert(typeof(callback) == "function", "track marker callback must be a function")
	local listeners = self._markerListeners[markerName]
	if listeners == nil then
		listeners = newMarkerListeners()
		self._markerListeners[markerName] = listeners
	end
	local listener: TrackMarkerListener<LayerT, StateT, ClipT> = {
		kind = "all",
		callback = callback,
		connected = true,
	}
	listeners.items[#listeners.items + 1] = listener
	listeners.count += 1
	for _, playback in self._active do
		self:_refreshMarker(playback, markerName)
	end
	return function()
		if not listener.connected then
			return
		end
		listener.connected = false
		listeners.count -= 1
		compactMarkerListeners(listeners)
		if listeners.count == 0 then
			if self._markerListeners[markerName] == listeners then
				self._markerListeners[markerName] = nil
			end
			for _, playback in self._active do
				self:_refreshMarker(playback, markerName)
			end
		end
	end
end

function RobloxAnimatorBackend.bindToTrackCompleted<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<
		LayerT,
		StateT,
		ClipT
	>,
	callback: (
		event: TrackCompletedEvent<LayerT, StateT>
	) -> ()
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

function RobloxAnimatorBackend._clearPhysical<LayerT, StateT, ClipT>(self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>): ()
	local physical: { Playback<LayerT, StateT, ClipT> } = {}
	for _, playback in self._physical do
		physical[#physical + 1] = playback
	end

	self:_clearMarkerQueue()
	self._active = {}
	self._completed = {}
	for _, playback in physical do
		self:_retire(playback, 0)
	end
	self._retiring = {}
	self._physical = {}
	self._warnings = {}
end

function RobloxAnimatorBackend.clear<LayerT, StateT, ClipT>(self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>): ()
	self._lifecycleEpoch += 1
	self:_clearPhysical()
end

function RobloxAnimatorBackend.destroy<LayerT, StateT, ClipT>(self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	self._lifecycleEpoch += 1
	self:_clearPhysical()
	self._completionListeners = {}
	table.clear(self._trackMarkerListeners)
	table.clear(self._markerListeners)
end

function RobloxAnimatorBackend.getCapabilities<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<
		LayerT,
		StateT,
		ClipT
	>
): BackendTypes.BackendCapabilities
	return self._capabilities
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
			positionMode = playback:getPositionMode(),
			generation = playback:getGeneration(),
			lifecycle = lifecycle,
			physicalPresent = true,
		},
	}
end

function RobloxAnimatorBackend.getDebugSnapshot<LayerT, StateT, ClipT>(
	self: RobloxAnimatorBackendImpl<
		LayerT,
		StateT,
		ClipT
	>
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
				positionMode = self._positionMode,
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
		capabilities = self._capabilities,
		tracks = tracks,
		warnings = self._warnings,
	}
end

return { new = RobloxAnimatorBackend.new }
