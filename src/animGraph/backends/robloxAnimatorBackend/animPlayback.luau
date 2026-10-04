--!strict
--!optimize 2
--!native

local AnimationPosition = require(script.Parent.Parent.Parent.utils.animationPosition)
local DefTypes = require(script.Parent.Parent.Parent.types.def)
local MotionNodeTypes = require(script.Parent.Parent.Parent.types.motions.motionNode)
local RobloxAnimatorBackendTypes = require(script.Parent.Parent.Parent.types.backends.robloxAnimatorBackend)
local AnimationBackendTypes = require(script.Parent.Parent.Parent.types.backends.animationBackend)

type AnimationPosition = DefTypes.AnimationPosition
type RobloxLayerBackend = RobloxAnimatorBackendTypes.RobloxLayerBackend

type PlaybackLifecycle = RobloxAnimatorBackendTypes.PlaybackLifecycle
type AnimPlaybackConfig<ClipT> = RobloxAnimatorBackendTypes.AnimPlaybackConfig<ClipT>
type AnimPlayback<LayerT, StateT, ClipT> = RobloxAnimatorBackendTypes.AnimPlayback<LayerT, StateT, ClipT>
type AnimPlaybackImpl<LayerT, StateT, ClipT> = RobloxAnimatorBackendTypes.AnimPlaybackImpl<LayerT, StateT, ClipT>

local AnimPlayback = {}
AnimPlayback.__index = AnimPlayback

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

local function latchCompleted<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): boolean
	if self._lifecycle ~= "active" or self._looped then
		return false
	end

	self._lifecycle = "completed"
	self._pendingPosition = nil
	self._pendingOffsetSeconds = nil
	self._pendingReverseStart = false
	disconnect(self._stoppedConnection)
	self._stoppedConnection = nil
	return true
end

local function desiredNativeSpeed<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): number
	return self._speed * self._timeRate
end

local function requiresPendingReverseHold<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): boolean
	return (self._pendingPosition ~= nil or self._pendingOffsetSeconds ~= nil)
		and not self._looped
		and desiredNativeSpeed(self) < 0
		and self._track.Length <= 0
end

local function resolvePendingAddress<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): boolean
	local pendingPosition = self._pendingPosition
	local pendingOffsetSeconds = self._pendingOffsetSeconds
	if (pendingPosition == nil and pendingOffsetSeconds == nil) or self._lifecycle ~= "active" then
		return false
	end

	local length = self._track.Length
	if length <= 0 then
		return false
	end

	local resolvedSeconds: number
	local completed: boolean
	local desiredSpeed = desiredNativeSpeed(self)
	if pendingPosition ~= nil then
		resolvedSeconds, completed = AnimationPosition.resolve(pendingPosition, length, self._looped, desiredSpeed)
	else
		resolvedSeconds = self._track.TimePosition
		completed = false
	end
	if pendingOffsetSeconds ~= nil then
		resolvedSeconds, completed =
			AnimationPosition.resolveOffset(resolvedSeconds, pendingOffsetSeconds, length, self._looped, desiredSpeed)
	end
	self._pendingPosition = nil
	self._pendingOffsetSeconds = nil
	self._track.TimePosition = resolvedSeconds
	if self._pendingReverseStart then
		self._pendingReverseStart = false
		if self._nativeSpeed ~= desiredSpeed then
			self._nativeSpeed = desiredSpeed
			self._track:AdjustSpeed(desiredSpeed)
		end
	end
	if completed then
		latchCompleted(self)
	end
	return completed
end

function AnimPlayback.new<LayerT, StateT, ClipT>(config: AnimPlaybackConfig<ClipT>): AnimPlayback<LayerT, StateT, ClipT>
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(config.assetId)

	local track = config.animator:LoadAnimation(animation)
	local self: AnimPlaybackImpl<LayerT, StateT, ClipT> = setmetatable({}, AnimPlayback) :: any

	self._trackKey = config.trackKey
	self._clip = config.clip
	self._generation = config.generation
	self._animation = animation
	self._track = track
	self._layer = nil
	self._state = nil
	self._weight = 0
	self._speed = 1
	self._timeRate = 1
	self._nativeSpeed = 1
	self._looped = false
	self._logicalPriority = 0
	self._priority = nil
	self._pendingPosition = nil
	self._pendingOffsetSeconds = nil
	self._pendingReverseStart = false
	self._lifecycle = "active"
	self._stoppedConnection = track.Stopped:Connect(function()
		config.onStopped(config.generation)
	end)
	self._endedConnection = track.Ended:Connect(function()
		config.onEnded(config.generation)
	end)

	return self
end

function AnimPlayback.bindToMarker<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>,
	markerName: string,
	callback: (value: string) -> ()
): DefTypes.Release
	local connection = self._track:GetMarkerReachedSignal(markerName):Connect(callback)
	return function()
		connection:Disconnect()
	end
end

function AnimPlayback.start<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>,
	_sampleTime: number,
	request: MotionNodeTypes.ClipRequest<
		LayerT,
		StateT,
		ClipT,
		RobloxLayerBackend
	>,
	robloxPriority: Enum.AnimationPriority
): boolean
	assert(self._lifecycle == "active", "cannot start an inactive playback generation")

	self._layer = request.layer
	self._state = request.state
	self._weight = math.max(request.weight, 0)
	self._speed = request.speed
	self._timeRate = request.timeRate
	self._looped = request.looped
	self._logicalPriority = request.logicalPriority
	self._priority = robloxPriority
	self._pendingPosition = copyPosition(request.initialPosition)

	local track = self._track
	track.Looped = self._looped
	track.Priority = robloxPriority
	local playSpeed = desiredNativeSpeed(self)
	if requiresPendingReverseHold(self) then
		playSpeed = 0
		self._pendingReverseStart = true
	end
	self._nativeSpeed = playSpeed
	track:Play(request.fadeTime, self._weight, playSpeed)
	return resolvePendingAddress(self)
end

function AnimPlayback.preflightApply<LayerT, StateT, ClipT>(
	_self: AnimPlaybackImpl<LayerT, StateT, ClipT>,
	_request: MotionNodeTypes.ClipRequest<
		LayerT,
		StateT,
		ClipT,
		RobloxLayerBackend
	>
): ()
end

function AnimPlayback.apply<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>,
	_sampleTime: number,
	request: MotionNodeTypes.ClipRequest<
		LayerT,
		StateT,
		ClipT,
		RobloxLayerBackend
	>,
	robloxPriority: Enum.AnimationPriority
): boolean
	if self._lifecycle ~= "active" then
		return false
	end

	self._layer = request.layer
	self._state = request.state
	self._logicalPriority = request.logicalPriority
	local track = self._track
	local weight = math.max(request.weight, 0)
	local previousDesiredSpeed = desiredNativeSpeed(self)
	self._speed = request.speed
	self._timeRate = request.timeRate
	local desiredSpeed = desiredNativeSpeed(self)
	local speedChanged = desiredSpeed ~= previousDesiredSpeed

	if request.looped ~= self._looped then
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
	if requiresPendingReverseHold(self) then
		self._pendingReverseStart = true
		if self._nativeSpeed ~= 0 then
			self._nativeSpeed = 0
			track:AdjustSpeed(0)
		end
	end
	local completed = resolvePendingAddress(self)
	if completed then
		return true
	end

	if not self._pendingReverseStart and self._nativeSpeed ~= desiredSpeed then
		self._nativeSpeed = desiredSpeed
		track:AdjustSpeed(desiredSpeed)
		local length = track.Length
		if
			speedChanged
			and not self._looped
			and length > 0
			and AnimationPosition.isComplete(track.TimePosition, length, desiredSpeed)
		then
			return latchCompleted(self)
		end
	end

	return false
end

function AnimPlayback.setPosition<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>, position: AnimationPosition): boolean
	assert(self._lifecycle == "active", "cannot position an inactive playback generation")
	self._pendingOffsetSeconds = nil
	self._pendingPosition = copyPosition(position)
	if requiresPendingReverseHold(self) then
		self._pendingReverseStart = true
		if self._nativeSpeed ~= 0 then
			self._nativeSpeed = 0
			self._track:AdjustSpeed(0)
		end
	end
	return resolvePendingAddress(self)
end

function AnimPlayback.offsetPosition<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>, deltaSeconds: number): boolean
	assert(self._lifecycle == "active", "cannot position an inactive playback generation")
	AnimationPosition.assertFiniteSeconds(deltaSeconds, "deltaSeconds")
	local pendingOffsetSeconds = self._pendingOffsetSeconds
	local accumulatedOffsetSeconds = if pendingOffsetSeconds == nil
		then deltaSeconds
		else pendingOffsetSeconds + deltaSeconds
	AnimationPosition.assertFiniteSeconds(accumulatedOffsetSeconds, "accumulated pending offset")
	self._pendingOffsetSeconds = accumulatedOffsetSeconds
	if requiresPendingReverseHold(self) then
		self._pendingReverseStart = true
		if self._nativeSpeed ~= 0 then
			self._nativeSpeed = 0
			self._track:AdjustSpeed(0)
		end
	end
	return resolvePendingAddress(self)
end

function AnimPlayback.latchNaturalCompletion<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): boolean
	return latchCompleted(self)
end

function AnimPlayback.retire<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>, fadeTime: number): boolean
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
	self._pendingOffsetSeconds = nil
	self._pendingReverseStart = false
	disconnect(self._stoppedConnection)
	self._stoppedConnection = nil
	if wasPlaying then
		self._track:Stop(fadeTime)
	end

	return fadeTime <= 0 or not wasPlaying
end

function AnimPlayback.cleanup<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): ()
	if self._lifecycle == "cleaned" then
		return
	end

	self._lifecycle = "cleaned"
	self._pendingPosition = nil
	self._pendingOffsetSeconds = nil
	self._pendingReverseStart = false
	disconnect(self._stoppedConnection)
	disconnect(self._endedConnection)
	self._stoppedConnection = nil
	self._endedConnection = nil
	self._track:Destroy()
	self._animation:Destroy()
end

function AnimPlayback.getGeneration<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): number
	return self._generation
end

function AnimPlayback.getTrackKey<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): string
	return self._trackKey
end

function AnimPlayback.getClip<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): ClipT
	return self._clip
end

function AnimPlayback.getLayer<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): LayerT
	local layer = self._layer
	assert(layer ~= nil, "playback generation has not started")
	return layer
end

function AnimPlayback.getState<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): StateT?
	return self._state
end

function AnimPlayback.getLifecycle<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): PlaybackLifecycle
	return self._lifecycle
end

function AnimPlayback.isLooped<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): boolean
	return self._looped
end

function AnimPlayback.isPlaying<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): boolean
	return self._lifecycle == "active" and self._track.IsPlaying
end

function AnimPlayback.getWeight<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): number
	return self._weight
end

function AnimPlayback.getSpeed<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): number
	return self._speed
end

function AnimPlayback.getLogicalPriority<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): number
	return self._logicalPriority
end

function AnimPlayback.getRobloxPriority<LayerT, StateT, ClipT>(self: AnimPlaybackImpl<LayerT, StateT, ClipT>): Enum.AnimationPriority
	local priority = self._priority
	assert(priority ~= nil, "playback generation has not started")
	return priority
end

function AnimPlayback.getPositionMode<LayerT, StateT, ClipT>(
	_self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): AnimationBackendTypes.BackendPositionMode
	return "nativeRate"
end

return AnimPlayback
