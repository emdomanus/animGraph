--!strict
--!optimize 2
--!native

local MotionNodeTypes = require(script.Parent.Parent.motions.motionNode)
local DefTypes = require(script.Parent.Parent.def)

export type PerJointFallbackMode = "full" | "priorityTier" | "none"
export type BackendPositionMode = "nativeRate" | "sampledPosition"

export type BackendCapabilities = {
	positionMode: BackendPositionMode,
	unlimitedPriority: boolean,
	perJointFallback: PerJointFallbackMode,
	customMasks: boolean,
}

export type BackendDebugTrack = {
	trackKey: string,
	layer: any,
	state: any?,
	clip: any,
	weight: number,
	speed: number,
	logicalPriority: number,
	isPlaying: boolean,
	details: { [string]: any }?,
}

export type BackendDebugSnapshot = {
	name: string,
	capabilities: BackendCapabilities,
	tracks: { BackendDebugTrack },
	warnings: { string },
}

export type AnimationBackend<LayerT, StateT, ClipT, LayerBackendT> = {
	read apply: (
		self: AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>,
		sampleTime: number,
		requests: { MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, LayerBackendT> }
	) -> (),
	read setTrackPosition: (
		self: AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>,
		trackKey: string,
		position: DefTypes.AnimationPosition
	) -> boolean,
	read offsetTrackPosition: (
		self: AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>,
		trackKey: string,
		deltaSeconds: number
	) -> boolean,
	read bindToTrackCompleted: (
		self: AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>,
		callback: (event: DefTypes.TrackCompletedEvent<LayerT, StateT>) -> ()
	) -> DefTypes.Release,
	read stopLayer: (
		self: AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>,
		layer: LayerT,
		fadeTime: number?
	) -> (),
	read clear: (self: AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>) -> (),
	read destroy: (self: AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>) -> (),
	read getCapabilities: (self: AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>) -> BackendCapabilities,
	read getDebugSnapshot: (self: AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>) -> BackendDebugSnapshot,
}

return {}
