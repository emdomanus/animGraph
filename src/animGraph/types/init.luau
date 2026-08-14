--!strict
--!optimize 2
--!native

local AnimationControllerTypes = require(script.controller.animationController)
local DefTypes = require(script.def)
local EventBusTypes = require(script.controller.eventBus)
local ParameterStoreTypes = require(script.controller.parameterStore)
local LayerRuntimeTypes = require(script.runtime.layerRuntime)
local StateMachineRuntimeTypes = require(script.runtime.stateMachineRuntime)
local TransitionRuntimeTypes = require(script.runtime.transitionRuntime)
local MotionNodeTypes = require(script.motions.motionNode)
local ClipNodeTypes = require(script.motions.clipNode)
local Blend1DNodeTypes = require(script.motions.blend1DNode)
local Blend2DNodeTypes = require(script.motions.blend2DNode)
local AnimationBackendTypes = require(script.backends.animationBackend)
local RobloxAnimatorBackendTypes = require(script.backends.robloxAnimatorBackend)
local StackModifierTypes = require(script.components.stackModifier)

export type AnimationPosition = DefTypes.AnimationPosition
export type TimeSource = DefTypes.TimeSource
export type LogicalTimeReader = DefTypes.LogicalTimeReader

export type ParameterValue = ParameterStoreTypes.ParameterValue
export type ParameterStore<ParamT> = ParameterStoreTypes.ParameterStore<ParamT>
export type ParameterStoreImpl<ParamT> = ParameterStoreTypes.ParameterStoreImpl<ParamT>
export type AnimationEventName = EventBusTypes.AnimationEventName
export type AnimationEvent<LayerT, StateT> = EventBusTypes.AnimationEvent<LayerT, StateT>
export type AnimationEventCallback<LayerT, StateT> = EventBusTypes.AnimationEventCallback<LayerT, StateT>

export type AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	AnimationControllerTypes.AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT> =
	AnimationControllerTypes.AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT>
export type AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	AnimationControllerTypes.AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	AnimationControllerTypes.AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>

export type LayerDefinition<LayerT, LayerBackendT> = LayerRuntimeTypes.LayerDefinition<LayerT, LayerBackendT>
export type LayerPlayOptions<StateT, LayerBackendT> = LayerRuntimeTypes.LayerPlayOptions<StateT, LayerBackendT>
export type LayerDebugSnapshot<LayerT, StateT, LayerBackendT> =
	LayerRuntimeTypes.LayerDebugSnapshot<LayerT, StateT, LayerBackendT>
export type LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	LayerRuntimeTypes.LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	LayerRuntimeTypes.LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>

export type TransitionConditionOp = TransitionRuntimeTypes.TransitionConditionOp
export type TransitionCondition<ParamT> = TransitionRuntimeTypes.TransitionCondition<ParamT>
export type TransitionDefinition<StateT, ParamT> =
	TransitionRuntimeTypes.TransitionDefinition<StateT, ParamT>
export type TransitionDebugSnapshot<StateT> = TransitionRuntimeTypes.TransitionDebugSnapshot<StateT>
export type TransitionRuntime<StateT, ParamT> = TransitionRuntimeTypes.TransitionRuntime<StateT, ParamT>

export type StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	StateMachineRuntimeTypes.StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type StateMachineConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	StateMachineRuntimeTypes.StateMachineConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type StateMachineRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	StateMachineRuntimeTypes.StateMachineRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>

export type MotionRequestOverrides<LayerBackendT> = MotionNodeTypes.MotionRequestOverrides<LayerBackendT>
export type MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	MotionNodeTypes.MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type ClipRequest<LayerT, StateT, ClipT, LayerBackendT> =
	MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, LayerBackendT>
export type MotionDebugSnapshot = MotionNodeTypes.MotionDebugSnapshot
export type MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	MotionNodeTypes.MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>

export type ClipNodeConfig<LayerBackendT> = ClipNodeTypes.ClipNodeConfig<LayerBackendT>
export type ClipNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> = ClipNodeTypes.ClipNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type ClipNodeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = ClipNodeTypes.ClipNodeImpl<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>

export type Blend1DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Blend1DNodeTypes.Blend1DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type Blend1DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Blend1DNodeTypes.Blend1DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type Blend1DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Blend1DNodeTypes.Blend1DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>

export type Blend2DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Blend2DNodeTypes.Blend2DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type Blend2DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Blend2DNodeTypes.Blend2DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type Blend2DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Blend2DNodeTypes.Blend2DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>

export type PerJointFallbackMode = AnimationBackendTypes.PerJointFallbackMode
export type BackendCapabilities = AnimationBackendTypes.BackendCapabilities
export type BackendDebugTrack = AnimationBackendTypes.BackendDebugTrack
export type BackendDebugSnapshot = AnimationBackendTypes.BackendDebugSnapshot
export type AnimationBackend<LayerT, StateT, ClipT, LayerBackendT> =
	AnimationBackendTypes.AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>

export type AssetId = RobloxAnimatorBackendTypes.AssetId
export type RobloxLayerBackend = RobloxAnimatorBackendTypes.RobloxLayerBackend
export type LogicalPriorityBand = RobloxAnimatorBackendTypes.LogicalPriorityBand
export type RobloxAnimatorBackendConfig<ClipT> =
	RobloxAnimatorBackendTypes.RobloxAnimatorBackendConfig<ClipT>
export type TrackDebugState<LayerT, StateT, ClipT> =
	RobloxAnimatorBackendTypes.TrackDebugState<LayerT, StateT, ClipT>
export type RobloxAnimatorBackend<LayerT, StateT, ClipT> =
	RobloxAnimatorBackendTypes.RobloxAnimatorBackend<LayerT, StateT, ClipT>
export type RobloxAnimatorBackendImpl<LayerT, StateT, ClipT> =
	RobloxAnimatorBackendTypes.RobloxAnimatorBackendImpl<LayerT, StateT, ClipT>

export type Release = StackModifierTypes.Release
export type SpeedModifierMode = StackModifierTypes.SpeedModifierMode
export type SpeedModifierOptions = StackModifierTypes.SpeedModifierOptions
export type StackModifierConfig = StackModifierTypes.StackModifierConfig
export type StackModifierEntry = StackModifierTypes.StackModifierEntry
export type StackModifier = StackModifierTypes.StackModifier
export type StackModifierImpl = StackModifierTypes.StackModifierImpl

return {}
