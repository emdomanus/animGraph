--!strict
--!optimize 2
--!native

local AnimationBackendTypes = require(script.Parent.animationBackend)
local DefTypes = require(script.Parent.Parent.def)
local MotionNodeTypes = require(script.Parent.Parent.motions.motionNode)

export type AssetId = number

export type RobloxLayerBackend = {
	robloxPriority: Enum.AnimationPriority?,
}

export type LogicalPriorityBand = {
	min: number,
	priority: Enum.AnimationPriority,
}

export type RobloxAnimatorBackendConfig<ClipT> = {
	animator: Animator,
	resolveAssetId: (clip: ClipT) -> AssetId,
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

export type RobloxAnimatorBackend<LayerT, StateT, ClipT> =
	AnimationBackendTypes.AnimationBackend<LayerT, StateT, ClipT, RobloxLayerBackend>

export type RobloxAnimatorBackendImpl<LayerT, StateT, ClipT> =
	RobloxAnimatorBackend<LayerT, StateT, ClipT> & {
		_animator: Animator,
		_resolveAssetId: (clip: ClipT) -> AssetId,
		_defaultFadeOut: number,
		_defaultPriority: Enum.AnimationPriority,
		_priorityBands: { LogicalPriorityBand },
		_active: { [string]: any },
		_physical: { [number]: any },
		_retiring: { [number]: any },
		_completed: { [string]: CompletedTombstone<LayerT, StateT, ClipT> },
		_completionListeners: { (event: DefTypes.TrackCompletedEvent<LayerT, StateT>) -> () },
		_pendingCompletions: { DefTypes.TrackCompletedEvent<LayerT, StateT> },
		_nextGeneration: number,
		_applyDepth: number,
		_dispatchingCompletions: boolean,
		_warnings: { string },
		_destroyed: boolean,

		_mapPriority: (
			self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
			request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>
		) -> Enum.AnimationPriority,
		_materialize: (
			self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
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
