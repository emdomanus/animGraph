--!strict
--!optimize 2
--!native

local AnimationPosition = require(script.Parent.Parent.Parent.utils.animationPosition)
local DefTypes = require(script.Parent.Parent.Parent.types.def)
local MotionNodeTypes = require(script.Parent.Parent.Parent.types.motions.motionNode)
local RobloxAnimatorBackendTypes = require(script.Parent.Parent.Parent.types.backends.robloxAnimatorBackend)

type AnimationPosition = DefTypes.AnimationPosition
type RobloxLayerBackend = RobloxAnimatorBackendTypes.RobloxLayerBackend

export type AssetId = number
export type PlaybackLifecycle = "active" | "retiring" | "completed" | "cleaned"

export type AnimPlaybackConfig<ClipT> = {
	trackKey: string,
	clip: ClipT,
	assetId: AssetId,
	animator: Animator,
	generation: number,
	onStopped: (generation: number) -> (),
	onEnded: (generation: number) -> (),
}

export type AnimPlayback<LayerT, StateT, ClipT> = {
	start: (
		self: AnimPlayback<LayerT, StateT, ClipT>,
		request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>,
		robloxPriority: Enum.AnimationPriority
	) -> boolean,
	apply: (
		self: AnimPlayback<LayerT, StateT, ClipT>,
		request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>,
		robloxPriority: Enum.AnimationPriority
	) -> boolean,
	setPosition: (self: AnimPlayback<LayerT, StateT, ClipT>, position: AnimationPosition) -> boolean,
	latchNaturalCompletion: (self: AnimPlayback<LayerT, StateT, ClipT>) -> boolean,
	retire: (self: AnimPlayback<LayerT, StateT, ClipT>, fadeTime: number) -> boolean,
	cleanup: (self: AnimPlayback<LayerT, StateT, ClipT>) -> (),
	getGeneration: (self: AnimPlayback<LayerT, StateT, ClipT>) -> number,
	getTrackKey: (self: AnimPlayback<LayerT, StateT, ClipT>) -> string,
	getClip: (self: AnimPlayback<LayerT, StateT, ClipT>) -> ClipT,
	getLayer: (self: AnimPlayback<LayerT, StateT, ClipT>) -> LayerT,
	getState: (self: AnimPlayback<LayerT, StateT, ClipT>) -> StateT?,
	getLifecycle: (self: AnimPlayback<LayerT, StateT, ClipT>) -> PlaybackLifecycle,
	isLooped: (self: AnimPlayback<LayerT, StateT, ClipT>) -> boolean,
	isPlaying: (self: AnimPlayback<LayerT, StateT, ClipT>) -> boolean,
	getWeight: (self: AnimPlayback<LayerT, StateT, ClipT>) -> number,
	getSpeed: (self: AnimPlayback<LayerT, StateT, ClipT>) -> number,
	getLogicalPriority: (self: AnimPlayback<LayerT, StateT, ClipT>) -> number,
	getRobloxPriority: (self: AnimPlayback<LayerT, StateT, ClipT>) -> Enum.AnimationPriority,
}

export type AnimPlaybackImpl<LayerT, StateT, ClipT> = AnimPlayback<LayerT, StateT, ClipT> & {
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
	_nativeSpeed: number,
	_looped: boolean,
	_logicalPriority: number,
	_priority: Enum.AnimationPriority?,
	_pendingPosition: AnimationPosition?,
	_pendingReverseStart: boolean,
	_lifecycle: PlaybackLifecycle,
}

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

local function latchCompleted<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): boolean
	if self._lifecycle ~= "active" or self._looped then
		return false
	end

	self._lifecycle = "completed"
	self._pendingPosition = nil
	self._pendingReverseStart = false
	disconnect(self._stoppedConnection)
	self._stoppedConnection = nil
	return true
end

local function requiresPendingReverseHold<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): boolean
	return self._pendingPosition ~= nil and not self._looped and self._speed < 0 and self._track.Length <= 0
end

local function resolvePendingPosition<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): boolean
	local pending = self._pendingPosition
	if pending == nil or self._lifecycle ~= "active" then
		return false
	end

	local length = self._track.Length
	if length <= 0 then
		return false
	end

	local resolvedSeconds, completed = AnimationPosition.resolve(pending, length, self._looped, self._speed)
	self._pendingPosition = nil
	self._track.TimePosition = resolvedSeconds
	if self._pendingReverseStart then
		self._pendingReverseStart = false
		if self._nativeSpeed ~= self._speed then
			self._nativeSpeed = self._speed
			self._track:AdjustSpeed(self._speed)
		end
	end
	if completed then
		latchCompleted(self)
	end
	return completed
end

function AnimPlayback.new<LayerT, StateT, ClipT>(
	config: AnimPlaybackConfig<ClipT>
): AnimPlayback<LayerT, StateT, ClipT>
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
	self._nativeSpeed = 1
	self._looped = false
	self._logicalPriority = 0
	self._priority = nil
	self._pendingPosition = nil
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

function AnimPlayback.start<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>,
	request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>,
	robloxPriority: Enum.AnimationPriority
): boolean
	assert(self._lifecycle == "active", "cannot start an inactive playback generation")

	self._layer = request.layer
	self._state = request.state
	self._weight = math.max(request.weight, 0)
	self._speed = request.speed
	self._looped = request.looped
	self._logicalPriority = request.logicalPriority
	self._priority = robloxPriority
	self._pendingPosition = copyPosition(request.initialPosition)

	local track = self._track
	track.Looped = self._looped
	track.Priority = robloxPriority
	local playSpeed = self._speed
	if requiresPendingReverseHold(self) then
		playSpeed = 0
		self._pendingReverseStart = true
	end
	self._nativeSpeed = playSpeed
	track:Play(request.fadeTime, self._weight, playSpeed)
	return resolvePendingPosition(self)
end

function AnimPlayback.apply<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>,
	request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>,
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
	local speedChanged = request.speed ~= self._speed
	self._speed = request.speed

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
	local completed = resolvePendingPosition(self)
	if completed then
		return true
	end

	if not self._pendingReverseStart and self._nativeSpeed ~= self._speed then
		self._nativeSpeed = self._speed
		track:AdjustSpeed(self._speed)
		local length = track.Length
		if
			speedChanged
			and not self._looped
			and length > 0
			and AnimationPosition.isComplete(track.TimePosition, length, self._speed)
		then
			return latchCompleted(self)
		end
	end

	return false
end

function AnimPlayback.setPosition<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>,
	position: AnimationPosition
): boolean
	assert(self._lifecycle == "active", "cannot position an inactive playback generation")
	self._pendingPosition = copyPosition(position)
	if requiresPendingReverseHold(self) then
		self._pendingReverseStart = true
		if self._nativeSpeed ~= 0 then
			self._nativeSpeed = 0
			self._track:AdjustSpeed(0)
		end
	end
	return resolvePendingPosition(self)
end

function AnimPlayback.latchNaturalCompletion<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): boolean
	return latchCompleted(self)
end

function AnimPlayback.retire<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>,
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
	self._pendingReverseStart = false
	disconnect(self._stoppedConnection)
	self._stoppedConnection = nil
	if wasPlaying then
		self._track:Stop(fadeTime)
	end

	return fadeTime <= 0 or not wasPlaying
end

function AnimPlayback.cleanup<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): ()
	if self._lifecycle == "cleaned" then
		return
	end

	self._lifecycle = "cleaned"
	self._pendingPosition = nil
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

function AnimPlayback.getLifecycle<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): PlaybackLifecycle
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

function AnimPlayback.getLogicalPriority<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): number
	return self._logicalPriority
end

function AnimPlayback.getRobloxPriority<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): Enum.AnimationPriority
	local priority = self._priority
	assert(priority ~= nil, "playback generation has not started")
	return priority
end

return AnimPlayback
