# Public Type Index

The package root `src/init.luau` re-exports public types from
`src/animGraph/types/init.luau`. Consumers should name types through the package
namespace instead of requiring implementation modules.

## Shared Definitions

- `AnimationPosition`
- `TimeSource`
- `LogicalPositionReader`
- `Release`
- `TrackCompletedEvent<LayerT, StateT>`

See [Definitions](/api/types/definitions).

## Controller and Events

- `AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>`
- `AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT>`
- `AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>`
- `AnimationEventName`
- `AnimationEvent<LayerT, StateT>`
- `AnimationEventCallback<LayerT, StateT>`
- `ParameterValue`

## Layers and Motions

- `LayerDefinition<LayerT, LayerBackendT>`
- `LayerPlayOptions<StateT, LayerBackendT>`
- `MotionRequestOverrides<LayerBackendT>`
- `ClipRequest<LayerT, StateT, ClipT, LayerBackendT>`
- `MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>`
- `ClipNodeConfig<LayerBackendT>`
- `ClipNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>`
- `Blend1DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT>`
- `Blend1DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>`
- `Blend1DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>`
- `Blend2DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT>`
- `Blend2DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>`
- `Blend2DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>`

`MotionEvaluateContext`, implementation shapes, and layer/debug helper types are
available from the internal type barrel for package implementation, but are not
re-exported as root consumer types.

## State Machines

- `TransitionConditionOp`
- `TransitionCondition<ParamT>`
- `TransitionDefinition<StateT, ParamT>`
- `StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT>`
- `StateMachineConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>`
- `StateMachineRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>`

## Backends

- `AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>`
- `BackendCapabilities`
- `BackendDebugSnapshot`
- `AssetId`
- `RobloxLayerBackend`
- `LogicalPriorityBand`
- `RobloxAnimatorBackendConfig<ClipT>`
- `RobloxAnimatorBackend<LayerT, StateT, ClipT>`

## Components

- `SpeedModifierMode`
- `SpeedModifierOptions`
- `StackModifier`
