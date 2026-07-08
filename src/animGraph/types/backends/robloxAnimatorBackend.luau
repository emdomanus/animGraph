--!strict
--!optimize 2
--!native

local AnimationBackendTypes = require(script.Parent.animationBackend)
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

export type TrackDebugState<LayerT, StateT, ClipT> = {
	trackKey: string,
	layer: LayerT,
	state: StateT?,
	clip: ClipT,
	weight: number,
	speed: number,
	logicalPriority: number,
	robloxPriority: Enum.AnimationPriority,
	isPlaying: boolean,
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
		_playbacks: { [string]: any },
		_trackStates: { [string]: TrackDebugState<LayerT, StateT, ClipT> },
		_warnings: { string },
		_destroyed: boolean,

		_mapPriority: (
			self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
			request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, RobloxLayerBackend>
		) -> Enum.AnimationPriority,
		_getOrLoadPlayback: (
			self: RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>,
			trackKey: string,
			clip: ClipT
		) -> any,
	}

return {}
