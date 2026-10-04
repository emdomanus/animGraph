--!strict
--!optimize 2

local AnimPlaybackTypes = require(script.Parent.animPlayback)
local DefTypes = require(script.Parent.Parent.Parent.Parent.Parent.def.animation.shared.animation)

type AnimPlayback<LayerT, StateT, ClipT> = AnimPlaybackTypes.AnimPlayback<LayerT, StateT, ClipT>
type PlaybackLifecycle = AnimPlaybackTypes.PlaybackLifecycle

export type SampledAnimPlaybackImpl<LayerT, StateT, ClipT> = AnimPlayback<LayerT, StateT, ClipT> & {
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
	_looped: boolean,
	_logicalPriority: number,
	_priority: Enum.AnimationPriority?,
	_pendingPosition: DefTypes.AnimationPosition?,
	_pendingOffsetSeconds: number,
	_positionAnchor: number?,
	_timePositionAnchor: number,
	_lastTimePosition: number?,
	_lifecycle: PlaybackLifecycle,
}

return {}
