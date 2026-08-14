--!strict
--!optimize 2
--!native

local MotionNodeTypes = require(script.Parent.Parent.Parent.types.motions.motionNode)
local RobloxAnimatorBackendTypes = require(script.Parent.Parent.Parent.types.backends.robloxAnimatorBackend)
local AnimationPosition = require(script.Parent.Parent.Parent.utils.animationPosition)
local DefTypes = require(script.Parent.Parent.Parent.types.def)

export type AssetId = number
export type RobloxLayerBackend = RobloxAnimatorBackendTypes.RobloxLayerBackend

export type AnimPlaybackConfig<ClipT> = {
	trackKey: string,
	clip: ClipT,
	assetId: AssetId,
	animator: Animator,
}

export type AnimPlayback<LayerT, StateT, ClipT> = {
	apply: (
		self: AnimPlayback<LayerT, StateT, ClipT>,
		request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>,
		robloxPriority: Enum.AnimationPriority
	) -> (),
	markAbsent: (self: AnimPlayback<LayerT, StateT, ClipT>) -> (),
	fadeToZero: (self: AnimPlayback<LayerT, StateT, ClipT>, fadeTime: number) -> (),
	isPlaying: (self: AnimPlayback<LayerT, StateT, ClipT>) -> boolean,
	getTrack: (self: AnimPlayback<LayerT, StateT, ClipT>) -> AnimationTrack,
	getWeight: (self: AnimPlayback<LayerT, StateT, ClipT>) -> number,
	getSpeed: (self: AnimPlayback<LayerT, StateT, ClipT>) -> number,
	destroy: (self: AnimPlayback<LayerT, StateT, ClipT>) -> (),
}

export type AnimPlaybackImpl<LayerT, StateT, ClipT> = AnimPlayback<LayerT, StateT, ClipT> & {
	_trackKey: string,
	_clip: ClipT,
	_assetId: AssetId,
	_animation: Animation,
	_track: AnimationTrack,
	_weight: number,
	_speed: number,
	_looped: boolean,
	_priority: Enum.AnimationPriority?,
	_started: boolean,
	_completed: boolean,
	_requestedLastApply: boolean,
	_pendingInitialPosition: DefTypes.AnimationPosition?,
	_generation: number,
	_destroyed: boolean,
}

local AnimPlayback = {}
AnimPlayback.__index = AnimPlayback

function AnimPlayback.new<LayerT, StateT, ClipT>(
	config: AnimPlaybackConfig<ClipT>
): AnimPlayback<LayerT, StateT, ClipT>
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(config.assetId)

	local track = config.animator:LoadAnimation(animation)
	local self: AnimPlaybackImpl<LayerT, StateT, ClipT> = setmetatable({}, AnimPlayback) :: any

	self._trackKey = config.trackKey
	self._clip = config.clip
	self._assetId = config.assetId
	self._animation = animation
	self._track = track
	self._weight = 0
	self._speed = 1
	self._looped = false
	self._priority = nil
	self._started = false
	self._completed = false
	self._requestedLastApply = false
	self._pendingInitialPosition = nil
	self._generation = 0
	self._destroyed = false

	return self
end

local function copyPosition(
	position: DefTypes.AnimationPosition?
): DefTypes.AnimationPosition?
	if position == nil then
		return nil
	end

	if position.kind == "seconds" then
		return { kind = "seconds", value = position.value }
	end

	return { kind = "normalized", value = position.value }
end

local function applyPendingInitialPosition<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): ()
	local pending = self._pendingInitialPosition
	if pending == nil or self._completed then
		return
	end

	local length = self._track.Length
	if length <= 0 then
		return
	end

	local resolvedSeconds, completed = AnimationPosition.resolve(pending, length, self._looped)
	self._pendingInitialPosition = nil
	self._track.TimePosition = resolvedSeconds
	if completed then
		self._completed = true
	end
end

local function startGeneration<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>,
	request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>,
	robloxPriority: Enum.AnimationPriority
): ()
	local track = self._track
	local restarting = self._started
	if restarting and track.IsPlaying then
		track:Stop(0)
	end

	self._generation += 1
	self._completed = false
	self._pendingInitialPosition = copyPosition(request.initialPosition)
	self._weight = math.max(request.weight, 0)
	self._speed = request.speed
	self._looped = request.looped
	self._priority = robloxPriority
	track.Looped = request.looped
	track.Priority = robloxPriority
	track:Play(request.fadeTime, self._weight, self._speed)
	self._started = true

	if restarting and request.initialPosition == nil then
		track.TimePosition = 0
	end
	applyPendingInitialPosition(self)
end

function AnimPlayback.apply<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>,
	request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>,
	robloxPriority: Enum.AnimationPriority
): ()
	if self._destroyed then
		return
	end

	local track = self._track
	local wasRequested = self._requestedLastApply
	self._requestedLastApply = true

	if self._started and not self._completed and not self._looped and not track.IsPlaying then
		self._completed = true
	end

	if not self._started or request.forceRestart or (self._completed and not wasRequested) then
		startGeneration(self, request, robloxPriority)
		return
	end

	if self._completed then
		return
	end

	local weight = math.max(request.weight, 0)
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
	if request.speed ~= self._speed then
		self._speed = request.speed
		track:AdjustSpeed(request.speed)
	end

	applyPendingInitialPosition(self)
end

function AnimPlayback.markAbsent<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): ()
	self._requestedLastApply = false
end

function AnimPlayback.fadeToZero<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>,
	fadeTime: number
): ()
	if self._destroyed or self._completed or not self._track.IsPlaying or self._weight == 0 then
		return
	end

	self._weight = 0
	self._track:AdjustWeight(0, fadeTime)
end

function AnimPlayback.isPlaying<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): boolean
	return not self._destroyed and not self._completed and self._track.IsPlaying
end

function AnimPlayback.getTrack<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): AnimationTrack
	return self._track
end

function AnimPlayback.getWeight<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): number
	return self._weight
end

function AnimPlayback.getSpeed<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): number
	return self._speed
end

function AnimPlayback.destroy<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	if self._track.IsPlaying then
		self._track:Stop(0)
	end
	self._track:Destroy()
	self._animation:Destroy()
end

return AnimPlayback
