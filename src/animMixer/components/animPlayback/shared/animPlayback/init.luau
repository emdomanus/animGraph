--!strict
--!optimize 2
--!native

local Types = require(script.Parent.Parent.Parent.Parent.types.components.animPlayback)

export type AssetId = Types.AssetId
export type AnimPlaybackPlayOptions = Types.AnimPlaybackPlayOptions
export type AnimPlaybackConfig<RefT> = Types.AnimPlaybackConfig<RefT>
export type AnimPlayback<RefT> = Types.AnimPlayback<RefT>
export type AnimPlaybackImpl<RefT> = Types.AnimPlaybackImpl<RefT>

local AnimPlayback = {}
AnimPlayback.__index = AnimPlayback

function AnimPlayback.new<RefT>(config: AnimPlaybackConfig<RefT>): AnimPlayback<RefT>
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(config.assetId)

	local track = config.animator:LoadAnimation(animation)
	local self: AnimPlaybackImpl<RefT> = setmetatable({}, AnimPlayback) :: any

	self._ref = config.ref
	self._assetId = config.assetId
	self._animation = animation
	self._track = track
	self._onStopped = config.onStopped
	self._baseSpeed = 1
	self._effectiveSpeed = 1
	self._ignoredStoppedCount = 0
	self._destroyed = false

	self._stoppedConnection = track.Stopped:Connect(function()
		self:_handleStopped()
	end)

	return self
end

function AnimPlayback.getRef<RefT>(self: AnimPlaybackImpl<RefT>): RefT
	return self._ref
end

function AnimPlayback.getAssetId<RefT>(self: AnimPlaybackImpl<RefT>): AssetId
	return self._assetId
end

function AnimPlayback.getTrack<RefT>(self: AnimPlaybackImpl<RefT>): AnimationTrack
	return self._track
end

function AnimPlayback.isPlaying<RefT>(self: AnimPlaybackImpl<RefT>): boolean
	return self._track.IsPlaying
end

function AnimPlayback.getBaseSpeed<RefT>(self: AnimPlaybackImpl<RefT>): number
	return self._baseSpeed
end

function AnimPlayback.getSpeed<RefT>(self: AnimPlaybackImpl<RefT>): number
	return self._track.Speed
end

function AnimPlayback.getTimePosition<RefT>(self: AnimPlaybackImpl<RefT>): number
	return self._track.TimePosition
end

function AnimPlayback.play<RefT>(
	self: AnimPlaybackImpl<RefT>,
	options: AnimPlaybackPlayOptions
): ()
	if self._destroyed then
		return
	end

	local track = self._track
	if track.IsPlaying and options.forceRestart then
		self:_stopIgnoring(0)
	end

	self._baseSpeed = options.baseSpeed
	self._effectiveSpeed = options.effectiveSpeed
	track.Looped = options.looped
	track.Priority = options.priority

	if track.IsPlaying then
		track:AdjustWeight(options.weight, options.fadeIn)
		track:AdjustSpeed(options.effectiveSpeed)
	else
		track:Play(options.fadeIn, options.weight, options.effectiveSpeed)
	end
end

function AnimPlayback.adjustWeight<RefT>(
	self: AnimPlaybackImpl<RefT>,
	weight: number,
	fadeTime: number
): ()
	if not self._destroyed and self._track.IsPlaying then
		self._track:AdjustWeight(weight, fadeTime)
	end
end

function AnimPlayback.setBaseSpeed<RefT>(self: AnimPlaybackImpl<RefT>, speed: number): ()
	self._baseSpeed = speed
end

function AnimPlayback.setEffectiveSpeed<RefT>(
	self: AnimPlaybackImpl<RefT>,
	speed: number
): ()
	self._effectiveSpeed = speed
	if not self._destroyed and self._track.IsPlaying then
		self._track:AdjustSpeed(speed)
	end
end

function AnimPlayback.setTimePosition<RefT>(
	self: AnimPlaybackImpl<RefT>,
	timePosition: number
): ()
	self._track.TimePosition = math.max(timePosition, 0)
end

function AnimPlayback.adjustTimePosition<RefT>(
	self: AnimPlaybackImpl<RefT>,
	deltaTime: number
): ()
	self:setTimePosition(self._track.TimePosition + deltaTime)
end

function AnimPlayback.stop<RefT>(self: AnimPlaybackImpl<RefT>, fadeOut: number): ()
	if not self._destroyed and self._track.IsPlaying then
		self._track:Stop(fadeOut)
	end
end

function AnimPlayback.destroy<RefT>(self: AnimPlaybackImpl<RefT>): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	self._stoppedConnection:Disconnect()
	if self._track.IsPlaying then
		self._track:Stop(0)
	end
	self._track:Destroy()
	self._animation:Destroy()
end

function AnimPlayback._stopIgnoring<RefT>(
	self: AnimPlaybackImpl<RefT>,
	fadeOut: number
): ()
	if self._track.IsPlaying then
		self._ignoredStoppedCount += 1
		self._track:Stop(fadeOut)
	end
end

function AnimPlayback._handleStopped<RefT>(self: AnimPlaybackImpl<RefT>): ()
	if self._destroyed or self._track.IsPlaying then
		return
	end

	if self._ignoredStoppedCount > 0 then
		self._ignoredStoppedCount -= 1
		return
	end

	self._onStopped(self)
end

return AnimPlayback
