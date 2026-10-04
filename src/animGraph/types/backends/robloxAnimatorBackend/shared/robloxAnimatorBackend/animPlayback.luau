--!strict
--!optimize 2

local AnimationBackendTypes = require(script.Parent.Parent.Parent.Parent.animationBackend.shared.animationBackend)
local TrackMarkerSourceTypes =
	require(script.Parent.Parent.Parent.Parent.Parent.ports.backends.animationPlayback.shared.trackMarkerSource)
local DefTypes = require(script.Parent.Parent.Parent.Parent.Parent.def.animation.shared.animation)
local MotionNodeTypes = require(script.Parent.Parent.Parent.Parent.Parent.motions.motionNode.shared.motionNode)
local RobloxPlaybackDefTypes =
	require(script.Parent.Parent.Parent.Parent.Parent.def.animationPlayback.shared.robloxPlayback)

type AssetId = RobloxPlaybackDefTypes.AssetId
type RobloxLayerBackend = RobloxPlaybackDefTypes.RobloxLayerBackend

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

export type AnimPlayback<LayerT, StateT, ClipT> = TrackMarkerSourceTypes.TrackMarkerSource<LayerT, StateT, ClipT> & {
	bindToMarker: (
		self: AnimPlayback<LayerT, StateT, ClipT>,
		markerName: string,
		callback: (value: string) -> ()
	) -> DefTypes.Release,
	start: (
		self: AnimPlayback<LayerT, StateT, ClipT>,
		sampleTime: number,
		request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>,
		robloxPriority: Enum.AnimationPriority
	) -> boolean,
	apply: (
		self: AnimPlayback<LayerT, StateT, ClipT>,
		sampleTime: number,
		request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>,
		robloxPriority: Enum.AnimationPriority
	) -> boolean,
	preflightApply: (
		self: AnimPlayback<LayerT, StateT, ClipT>,
		request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>
	) -> (),
	setPosition: (self: AnimPlayback<LayerT, StateT, ClipT>, position: DefTypes.AnimationPosition) -> boolean,
	offsetPosition: (self: AnimPlayback<LayerT, StateT, ClipT>, deltaSeconds: number) -> boolean,
	latchNaturalCompletion: (self: AnimPlayback<LayerT, StateT, ClipT>) -> boolean,
	retire: (self: AnimPlayback<LayerT, StateT, ClipT>, fadeTime: number) -> boolean,
	cleanup: (self: AnimPlayback<LayerT, StateT, ClipT>) -> (),
	getLifecycle: (self: AnimPlayback<LayerT, StateT, ClipT>) -> PlaybackLifecycle,
	isLooped: (self: AnimPlayback<LayerT, StateT, ClipT>) -> boolean,
	isPlaying: (self: AnimPlayback<LayerT, StateT, ClipT>) -> boolean,
	getWeight: (self: AnimPlayback<LayerT, StateT, ClipT>) -> number,
	getSpeed: (self: AnimPlayback<LayerT, StateT, ClipT>) -> number,
	getLogicalPriority: (self: AnimPlayback<LayerT, StateT, ClipT>) -> number,
	getRobloxPriority: (self: AnimPlayback<LayerT, StateT, ClipT>) -> Enum.AnimationPriority,
	getPositionMode: (self: AnimPlayback<LayerT, StateT, ClipT>) -> AnimationBackendTypes.BackendPositionMode,
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
	_timeRate: number,
	_nativeSpeed: number,
	_looped: boolean,
	_logicalPriority: number,
	_priority: Enum.AnimationPriority?,
	_pendingPosition: DefTypes.AnimationPosition?,
	_pendingOffsetSeconds: number?,
	_pendingReverseStart: boolean,
	_lifecycle: PlaybackLifecycle,
}

return {}
