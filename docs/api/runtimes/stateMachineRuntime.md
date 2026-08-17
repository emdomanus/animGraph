# StateMachineRuntime

Source: `src/animGraph/runtime/stateMachineRuntime/init.luau`

Create with `AnimGraph.stateMachine(config)` or
`AnimGraph.stateMachineRuntime.new(config)`. The runtime is a stateful motion
node with authored states, ordered transitions, conditions, event emission, and
debug state.

Transition progress derives from `MotionEvaluateContext.logicalPosition`. Each
transition stores its start-position anchor and computes elapsed from the
current absolute graph phase. Held or equal-coordinate evaluation holds
progress; native request speed does not scale or rewind it. Create separate
runtime instances for independent live graph state.
