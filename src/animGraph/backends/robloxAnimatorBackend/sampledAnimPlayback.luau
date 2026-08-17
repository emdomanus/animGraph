--!strict
--!optimize 2
--!native

local AnimationPosition = require(script.Parent.Parent.Parent.utils.animationPosition)
local NativeAnimPlayback = require(script.Parent.animPlayback)
local DefTypes = require(script.Parent.Parent.Parent.types.def)
local MotionNodeTypes = require(script.Parent.Parent.Parent.types.motions.motionNode)
local RobloxAnimatorBackendTypes = require(script.Parent.Parent.Parent.types.backends.robloxAnimatorBackend)
local AnimationBackendTypes = require(script.Parent.Parent.Parent.types.backends.animationBackend)

type AnimationPosition = DefTypes.AnimationPosition
type RobloxLayerBackend = RobloxAnimatorBackendTypes.RobloxLayerBackend
type PlaybackLifecycle = NativeAnimPlayback.PlaybackLifecycle

export type SampledAnimPlaybackImpl<LayerT, StateT, ClipT> = NativeAnimPlayback.AnimPlayback<LayerT, StateT, ClipT> & {
	_trackKey: string,
	_clip: ClipT,
	_generation: number,
	_animation: Animation,
	_track: AnimationTrack,
	_stoppedConnection: RBXScriptConnection?,
	_endedConnection: RBXScriptConnection?,
	_layer: LayerT?,
	_state: StateT?,
	_weight: number,
	_speed: number,
	_looped: boolean,
	_logicalPriority: number,
	_priority: Enum.AnimationPriority?,
	_pendingPosition: AnimationPosition?,
	_pendingOffsetSeconds: number,
	_positionAnchor: number?,
	_sampleTimeAnchor: number,
	_lastSampleTime: number?,
	_lifecycle: PlaybackLifecycle,
}

local SampledAnimPlayback = {}
SampledAnimPlayback.__index = SampledAnimPlayback

local function assertFinite(value: number, name: string): number
	assert(typeof(value) == "number", name .. " must be a number")
	assert(value == value and value > -math.huge and value < math.huge, name .. " must be finite")
	return value
end

local function copyPosition(position: AnimationPosition?): AnimationPosition?
	if position == nil then
		return nil
	end

	if position.kind == "seconds" then
		return { kind = "seconds", value = position.value }
	end

	return { kind = "normalized", value = position.value }
end

local function disconnect(connection: RBXScriptConnection?): ()
	if connection ~= nil then
		connection:Disconnect()
	end
end

local function latchCompleted<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): boolean
	if self._lifecycle ~= "active" or self._looped then
		return false
	end

	self._lifecycle = "completed"
	self._pendingPosition = nil
	self._pendingOffsetSeconds = 0
	disconnect(self._stoppedConnection)
	self._stoppedConnection = nil
	return true
end

local function phaseOffset<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>,
	sampleTime: number
): number
	local elapsed = assertFinite(sampleTime - self._sampleTimeAnchor, "sampled phase elapsed")
	assert(elapsed >= 0, "sampleTime moved backward within sampled playback")
	return assertFinite(self._speed * elapsed, "sampled phase offset")
end

local function resolveCurrent<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>,
	sampleTime: number
): (number?, boolean)
	local length = self._track.Length
	if length <= 0 then
		return nil, false
	end

	local basePosition = self._positionAnchor
	local pendingOffset = 0
	if basePosition == nil then
		local zeroPosition: AnimationPosition = { kind = "seconds", value = 0 }
		local pendingPosition: AnimationPosition = self._pendingPosition or zeroPosition
		basePosition = AnimationPosition.resolve(pendingPosition, length, self._looped, self._speed)
		pendingOffset = self._pendingOffsetSeconds
	end

	local totalOffset = assertFinite(pendingOffset + phaseOffset(self, sampleTime), "sampled total phase offset")
	local resolvedBasePosition = basePosition
	assert(resolvedBasePosition ~= nil, "sampled phase base did not resolve")
	return AnimationPosition.resolveOffset(resolvedBasePosition, totalOffset, length, self._looped, self._speed)
end

local function writeCurrent<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>,
	sampleTime: number,
	rebase: boolean
): boolean
	local resolved, completed = resolveCurrent(self, sampleTime)
	if resolved == nil then
		return false
	end

	self._track.TimePosition = resolved
	if rebase or self._positionAnchor == nil then
		self._positionAnchor = resolved
		self._pendingPosition = nil
		self._pendingOffsetSeconds = 0
		self._sampleTimeAnchor = sampleTime
	end
	if completed then
		return latchCompleted(self)
	end
	return false
end

local function rebaseAt<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>,
	sampleTime: number
): ()
	local resolved = resolveCurrent(self, sampleTime)
	if resolved ~= nil then
		self._positionAnchor = resolved
		self._pendingPosition = nil
		self._pendingOffsetSeconds = 0
	else
		self._pendingOffsetSeconds = assertFinite(
			self._pendingOffsetSeconds + phaseOffset(self, sampleTime),
			"pending sampled phase offset"
		)
	end
	self._sampleTimeAnchor = sampleTime
end

local function ensurePlaying<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): ()
	if self._track.IsPlaying then
		return
	end

	self._track:Play(0, self._weight, 0)
	self._track.Looped = self._looped
	local priority = self._priority
	if priority ~= nil then
		self._track.Priority = priority
	end
end

function SampledAnimPlayback.new<LayerT, StateT, ClipT>(
	config: NativeAnimPlayback.AnimPlaybackConfig<ClipT>
): NativeAnimPlayback.AnimPlayback<LayerT, StateT, ClipT>
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(config.assetId)

	local track = config.animator:LoadAnimation(animation)
	local self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT> = setmetatable({}, SampledAnimPlayback) :: any

	self._trackKey = config.trackKey
	self._clip = config.clip
	self._generation = config.generation
	self._animation = animation
	self._track = track
	self._layer = nil
	self._state = nil
	self._weight = 0
	self._speed = 1
	self._looped = false
	self._logicalPriority = 0
	self._priority = nil
	self._pendingPosition = nil
	self._pendingOffsetSeconds = 0
	self._positionAnchor = nil
	self._sampleTimeAnchor = 0
	self._lastSampleTime = nil
	self._lifecycle = "active"
	self._stoppedConnection = track.Stopped:Connect(function()
		config.onStopped(config.generation)
	end)
	self._endedConnection = track.Ended:Connect(function()
		config.onEnded(config.generation)
	end)

	return self
end

function SampledAnimPlayback.start<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>,
	sampleTime: number,
	request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>,
	robloxPriority: Enum.AnimationPriority
): boolean
	assert(self._lifecycle == "active", "cannot start an inactive playback generation")
	assertFinite(sampleTime, "sampleTime")

	self._layer = request.layer
	self._state = request.state
	self._weight = math.max(request.weight, 0)
	self._speed = request.speed
	self._looped = request.looped
	self._logicalPriority = request.logicalPriority
	self._priority = robloxPriority
	self._pendingPosition = copyPosition(request.initialPosition) or { kind = "seconds", value = 0 }
	self._pendingOffsetSeconds = 0
	self._positionAnchor = nil
	self._sampleTimeAnchor = sampleTime
	self._lastSampleTime = sampleTime

	local track = self._track
	track.Looped = self._looped
	track.Priority = robloxPriority
	track:Play(request.fadeTime, self._weight, 0)
	return writeCurrent(self, sampleTime, true)
end

function SampledAnimPlayback.apply<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>,
	sampleTime: number,
	request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>,
	robloxPriority: Enum.AnimationPriority
): boolean
	if self._lifecycle ~= "active" then
		return false
	end
	assertFinite(sampleTime, "sampleTime")
	local lastSampleTime = self._lastSampleTime
	assert(lastSampleTime == nil or sampleTime >= lastSampleTime, "sampleTime moved backward within sampled playback")

	self._layer = request.layer
	self._state = request.state
	self._logicalPriority = request.logicalPriority
	local track = self._track
	local weight = math.max(request.weight, 0)
	local speedChanged = request.speed ~= self._speed
	local loopedChanged = request.looped ~= self._looped
	if speedChanged or loopedChanged then
		rebaseAt(self, sampleTime)
	end

	self._speed = request.speed
	if loopedChanged then
		self._looped = request.looped
		track.Looped = request.looped
	end
	if robloxPriority ~= self._priority then
		self._priority = robloxPriority
		track.Priority = robloxPriority
	end
	if weight ~= self._weight then
		self._weight = weight
		track:AdjustWeight(weight, request.fadeTime)
	end

	ensurePlaying(self)
	self._lastSampleTime = sampleTime
	return writeCurrent(self, sampleTime, false)
end

function SampledAnimPlayback.setPosition<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>,
	position: AnimationPosition
): boolean
	assert(self._lifecycle == "active", "cannot position an inactive playback generation")
	local sampleTime = self._lastSampleTime
	assert(sampleTime ~= nil, "sampled playback generation has not started")

	self._pendingPosition = copyPosition(position)
	self._pendingOffsetSeconds = 0
	self._positionAnchor = nil
	self._sampleTimeAnchor = sampleTime
	return writeCurrent(self, sampleTime, true)
end

function SampledAnimPlayback.offsetPosition<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>,
	deltaSeconds: number
): boolean
	assert(self._lifecycle == "active", "cannot position an inactive playback generation")
	AnimationPosition.assertFiniteSeconds(deltaSeconds, "deltaSeconds")
	local sampleTime = self._lastSampleTime
	assert(sampleTime ~= nil, "sampled playback generation has not started")
	rebaseAt(self, sampleTime)

	local length = self._track.Length
	local positionAnchor = self._positionAnchor
	if length > 0 and positionAnchor ~= nil then
		local resolved, completed = AnimationPosition.resolveOffset(
			positionAnchor,
			deltaSeconds,
			length,
			self._looped,
			self._speed
		)
		self._positionAnchor = resolved
		self._track.TimePosition = resolved
		if completed then
			return latchCompleted(self)
		end
	else
		self._pendingOffsetSeconds = assertFinite(
			self._pendingOffsetSeconds + deltaSeconds,
			"accumulated pending offset"
		)
	end
	return false
end

function SampledAnimPlayback.latchNaturalCompletion<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): boolean
	return latchCompleted(self)
end

function SampledAnimPlayback.retire<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>,
	fadeTime: number
): boolean
	if self._lifecycle == "cleaned" then
		return true
	end
	if self._lifecycle == "retiring" then
		if fadeTime <= 0 then
			if self._track.IsPlaying then
				self._track:Stop(0)
			end
			return true
		end
		return false
	end

	local wasPlaying = self._track.IsPlaying
	self._lifecycle = "retiring"
	self._pendingPosition = nil
	self._pendingOffsetSeconds = 0
	disconnect(self._stoppedConnection)
	self._stoppedConnection = nil
	if wasPlaying then
		self._track:Stop(fadeTime)
	end

	return fadeTime <= 0 or not wasPlaying
end

function SampledAnimPlayback.cleanup<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): ()
	if self._lifecycle == "cleaned" then
		return
	end

	self._lifecycle = "cleaned"
	self._pendingPosition = nil
	self._pendingOffsetSeconds = 0
	disconnect(self._stoppedConnection)
	disconnect(self._endedConnection)
	self._stoppedConnection = nil
	self._endedConnection = nil
	self._track:Destroy()
	self._animation:Destroy()
end

function SampledAnimPlayback.getGeneration<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): number
	return self._generation
end

function SampledAnimPlayback.getTrackKey<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): string
	return self._trackKey
end

function SampledAnimPlayback.getClip<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): ClipT
	return self._clip
end

function SampledAnimPlayback.getLayer<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): LayerT
	local layer = self._layer
	assert(layer ~= nil, "playback generation has not started")
	return layer
end

function SampledAnimPlayback.getState<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): StateT?
	return self._state
end

function SampledAnimPlayback.getLifecycle<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): PlaybackLifecycle
	return self._lifecycle
end

function SampledAnimPlayback.isLooped<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): boolean
	return self._looped
end

function SampledAnimPlayback.isPlaying<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): boolean
	return self._lifecycle == "active" and self._track.IsPlaying
end

function SampledAnimPlayback.getWeight<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): number
	return self._weight
end

function SampledAnimPlayback.getSpeed<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): number
	return self._speed
end

function SampledAnimPlayback.getLogicalPriority<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): number
	return self._logicalPriority
end

function SampledAnimPlayback.getRobloxPriority<LayerT, StateT, ClipT>(
	self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): Enum.AnimationPriority
	local priority = self._priority
	assert(priority ~= nil, "playback generation has not started")
	return priority
end

function SampledAnimPlayback.getPositionMode<LayerT, StateT, ClipT>(
	_self: SampledAnimPlaybackImpl<LayerT, StateT, ClipT>
): AnimationBackendTypes.BackendPositionMode
	return "sampledPosition"
end

return SampledAnimPlayback
