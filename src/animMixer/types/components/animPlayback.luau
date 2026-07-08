--!strict
--!optimize 2
--!native

export type AssetId = number

export type AnimPlaybackPlayOptions = {
	fadeIn: number,
	weight: number,
	baseSpeed: number,
	effectiveSpeed: number,
	looped: boolean,
	priority: Enum.AnimationPriority,
	forceRestart: boolean,
}

export type AnimPlaybackConfig<RefT> = {
	ref: RefT,
	assetId: AssetId,
	animator: Animator,
	onStopped: (playback: AnimPlaybackImpl<RefT>) -> (),
}

export type AnimPlayback<RefT> = {
	getRef: (self: AnimPlayback<RefT>) -> RefT,
	getAssetId: (self: AnimPlayback<RefT>) -> AssetId,
	getTrack: (self: AnimPlayback<RefT>) -> AnimationTrack,
	isPlaying: (self: AnimPlayback<RefT>) -> boolean,
	getBaseSpeed: (self: AnimPlayback<RefT>) -> number,
	getSpeed: (self: AnimPlayback<RefT>) -> number,
	getTimePosition: (self: AnimPlayback<RefT>) -> number,
	play: (self: AnimPlayback<RefT>, options: AnimPlaybackPlayOptions) -> (),
	adjustWeight: (self: AnimPlayback<RefT>, weight: number, fadeTime: number) -> (),
	setBaseSpeed: (self: AnimPlayback<RefT>, speed: number) -> (),
	setEffectiveSpeed: (self: AnimPlayback<RefT>, speed: number) -> (),
	setTimePosition: (self: AnimPlayback<RefT>, timePosition: number) -> (),
	adjustTimePosition: (self: AnimPlayback<RefT>, deltaTime: number) -> (),
	stop: (self: AnimPlayback<RefT>, fadeOut: number) -> (),
	destroy: (self: AnimPlayback<RefT>) -> (),
}

export type AnimPlaybackImpl<RefT> = AnimPlayback<RefT> & {
	_ref: RefT,
	_assetId: AssetId,
	_animation: Animation,
	_track: AnimationTrack,
	_stoppedConnection: RBXScriptConnection,
	_onStopped: (playback: AnimPlaybackImpl<RefT>) -> (),
	_baseSpeed: number,
	_effectiveSpeed: number,
	_ignoredStoppedCount: number,
	_destroyed: boolean,

	_stopIgnoring: (self: AnimPlaybackImpl<RefT>, fadeOut: number) -> (),
	_handleStopped: (self: AnimPlaybackImpl<RefT>) -> (),
}

return {}
