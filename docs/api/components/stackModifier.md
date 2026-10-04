# StackModifier

Source: `src/animGraph/components/stackModifier/shared/stackModifier.luau`

Construct with `AnimGraph.stackModifier.new(config?)`. It is a small reusable
numeric modifier stack that returns release callbacks for pushed entries. It
does not own controller timing, time readers, or backend materialization.
