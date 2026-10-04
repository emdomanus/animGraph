--!strict
--!optimize 2

local AnimationBackendTypes = require(script.Parent.Parent.Parent.animationBackend.shared.animationBackend)
local TrackMarkerSourceTypes =
	require(script.Parent.Parent.Parent.Parent.ports.backends.animationPlayback.shared.trackMarkerSource)
local DefTypes = require(script.Parent.Parent.Parent.Parent.def.animation.shared.animation)
local MotionNodeTypes = require(script.Parent.Parent.Parent.Parent.motions.motionNode.shared.motionNode)

local AnimPlaybackTypes = require(script.animPlayback)
local RobloxPlaybackDefTypes = require(script.Parent.Parent.Parent.Parent.def.animationPlayback.shared.robloxPlayback)

type AssetId = RobloxPlaybackDefTypes.AssetId
type RobloxLayerBackend = RobloxPlaybackDefTypes.RobloxLayerBackend
type LogicalPriorityBand = RobloxPlaybackDefTypes.LogicalPriorityBand
type AnimPlayback<LayerT, StateT, ClipT> = AnimPlaybackTypes.AnimPlayback<LayerT, StateT, ClipT>

export type RobloxAnimatorBackendConfig<ClipT> = {
	animator: Animator,
	resolveAssetId: (clip: ClipT) -> AssetId,
	positionMode: AnimationBackendTypes.BackendPositionMode?,
	defaultFadeOut: number?,
	defaultPriority: Enum.AnimationPriority?,
	priorityBands: { LogicalPriorityBand }?,
}

export type CompletedTombstone<LayerT, StateT, ClipT> = {
	trackKey: string,
	layer: LayerT,
	state: StateT?,
	clip: ClipT,
	generation: number,
}

export type RobloxAnimatorBackend<LayerT, StateT, ClipT> = AnimationBackendTypes.AnimationBackend<
	LayerT,
	StateT,
	ClipT,
	RobloxLayerBackend
>

export type TrackMarkerListener<LayerT, StateT, ClipT> = ({
	kind: "track",
	callback: (value: string) -> (),
} | {
	kind: "all",
	callback: (track: TrackMarkerSourceTypes.TrackMarkerSource<LayerT, StateT, ClipT>, value: string) -> (),
}) & { connected: boolean }

export type TrackMarkerListeners<LayerT, StateT, ClipT> = {
	items: { TrackMarkerListener<LayerT, StateT, ClipT> },
	count: number,
	dispatchDepth: number,
}

export type TrackMarkerBinding<LayerT, StateT, ClipT> = {
	playback: AnimPlayback<LayerT, StateT, ClipT>,
	markerName: string,
	connected: boolean,
	releasePlayback: DefTypes.Release?,
}

export type RobloxAnimatorBackendImpl<LayerT, StateT, ClipT> = RobloxAnimatorBackend<LayerT, StateT, ClipT> & {
	_animator: Animator,
	_resolveAssetId: (clip: ClipT) -> AssetId,
	_defaultFadeOut: number,
	_defaultPriority: Enum.AnimationPriority,
	_priorityBands: { LogicalPriorityBand },
	_positionMode: AnimationBackendTypes.BackendPositionMode,
	_capabilities: AnimationBackendTypes.BackendCapabilities,
	_lastSampleTime: number?,
	_active: { [string]: any },
	_physical: { [number]: any },
	_retiring: { [number]: any },
	_completed: { [string]: CompletedTombstone<LayerT, StateT, ClipT> },
	_trackMarkerListeners: { [string]: { [string]: TrackMarkerListeners<LayerT, StateT, ClipT> } },
	_markerListeners: { [string]: TrackMarkerListeners<LayerT, StateT, ClipT> },
	_markerBindings: { [number]: { [string]: TrackMarkerBinding<LayerT, StateT, ClipT> } },
	_pendingMarkerBindings: { TrackMarkerBinding<LayerT, StateT, ClipT> },
	_pendingMarkerValues: { string },
	_markerQueueHead: number,
	_markerQueueTail: number,
	_dispatchingMarkers: boolean,
	_refreshMarker: (
		self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
		playback: AnimPlayback<LayerT, StateT, ClipT>,
		markerName: string
	) -> (),
	_disconnectMarkers: (
		self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
		playback: AnimPlayback<LayerT, StateT, ClipT>
	) -> (),
	_clearMarkerQueue: (self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>) -> (),
	_flushMarkers: (self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>) -> (),
	_drainMarkers: (self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>) -> unknown,
	_completionListeners: { (event: DefTypes.TrackCompletedEvent<LayerT, StateT>) -> () },
	_pendingCompletions: { DefTypes.TrackCompletedEvent<LayerT, StateT> },
	_nextGeneration: number,
	_applyDepth: number,
	_spareTouched: { [string]: true }?,
	_dispatchingCompletions: boolean,
	_lifecycleEpoch: number,
	_warnings: { string },
	_destroyed: boolean,

	_mapPriority: (
		self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
		request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>
	) -> Enum.AnimationPriority,
	_materialize: (
		self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
		sampleTime: number,
		request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>,
		robloxPriority: Enum.AnimationPriority
	) -> any,
	_retire: (self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>, playback: any, fadeTime: number) -> (),
	_complete: (self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>, playback: any) -> (),
	_handleStopped: (self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>, generation: number) -> (),
	_handleEnded: (self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>, generation: number) -> (),
	_cleanupPhysical: (self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>, generation: number) -> (),
	_clearPhysical: (self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>) -> (),
	_flushCompletions: (self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>) -> (),
}

return {}
