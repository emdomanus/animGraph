--!strict
--!optimize 2
--!native

local MotionNodeTypes = require(script.Parent.Parent.Parent.types.motions.motionNode)
local RobloxAnimatorBackendTypes = require(script.Parent.Parent.Parent.types.backends.robloxAnimatorBackend)

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
	self._destroyed = false

	return self
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
	self._weight = math.max(request.weight, 0)
	self._speed = request.speed

	track.Looped = request.looped
	track.Priority = robloxPriority

	if track.IsPlaying then
		track:AdjustWeight(self._weight, request.fadeTime)
		track:AdjustSpeed(self._speed)
	else
		track:Play(request.fadeTime, self._weight, self._speed)
	end

	if request.normalizedTime ~= nil and track.Length > 0 then
		track.TimePosition = math.max(request.normalizedTime, 0) * track.Length
	elseif request.timePosition ~= nil then
		track.TimePosition = math.max(request.timePosition, 0)
	elseif request.forceRestart then
		track.TimePosition = 0
	end
end

function AnimPlayback.fadeToZero<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>,
	fadeTime: number
): ()
	if self._destroyed or not self._track.IsPlaying then
		return
	end

	self._weight = 0
	self._track:AdjustWeight(0, fadeTime)
end

function AnimPlayback.isPlaying<LayerT, StateT, ClipT>(
	self: AnimPlaybackImpl<LayerT, StateT, ClipT>
): boolean
	return not self._destroyed and self._track.IsPlaying
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
