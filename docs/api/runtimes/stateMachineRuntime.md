# StateMachineRuntime

Source: `src/animGraph/runtime/stateMachineRuntime/init.luau`

Create with `AnimGraph.stateMachine(config)` or
`AnimGraph.stateMachineRuntime.new(config)`. The runtime is a stateful motion
node with authored states, ordered transitions, conditions, event emission, and
debug state.

Transition progress consumes the selected layer activation's reader-derived
`MotionEvaluateContext.dt`. A held reader holds progress; native request speed
does not scale it. Create separate runtime instances for independent live graph
state.
