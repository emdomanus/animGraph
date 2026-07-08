# animMixer

animMixer is a Roblox/pesde package for playing and mixing `AnimationTrack`
instances by caller-defined category or layer keys.

It is meant to sit below character visualizers, combat systems, emote systems,
preview tools, and animation state machines. animMixer owns track loading,
track caching, category reconciliation, pushed overrides, fades, speed changes,
time seeking, and global or category speed modifiers. Callers own movement
policy, state replication, skills, VFX, species and variant lookup, and gameplay
animation selection.

## Install

```sh
pesde install
```

The package entrypoint is `src/init.luau`, which re-exports `src/animMixer`.

## Concepts

- A category is any caller-owned key, such as `"idle"`, `"action"`, or a typed
  layer enum.
- A ref is the caller's animation identity. It can be a raw numeric Roblox asset
  id, string key, enum value, or other stable caller-owned key.
- `resolveAssetId` is required in the constructor config. For raw numeric asset
  ids, pass an identity resolver.
- Category priorities map caller categories to Roblox `Enum.AnimationPriority`.
- Category defaults configure fades, speed, looping, force restart, and priority.
- Pushed entries are temporary category overrides. Higher `localPriority` wins;
  later pushes win when priority is tied.
- Speed modifiers are ordered stacks. Each entry has a `mode` of `"multiply"`,
  `"add"`, or `"set"`, plus optional `priority` and `duration`.
- Global speed modifiers are evaluated before category speed modifiers. Inside
  each stack, lower priority and older entries apply first.

One `Animation` and one `AnimationTrack` are cached per ref. If the same ref is
used in multiple categories, stopping one category does not stop the track while
another category still references it.

## Example

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimMixer = require(ReplicatedStorage.packages.animMixer)

type Layer = "idle" | "movement" | "action"

local mixer: AnimMixer.AnimMixer<Layer, number> = AnimMixer.new({
	animator = animator,
	resolveAssetId = function(assetId: number): number
		return assetId
	end,
	defaultFadeIn = 0.15,
	defaultFadeOut = 0.15,
	categoryPriorities = {
		idle = Enum.AnimationPriority.Idle,
		movement = Enum.AnimationPriority.Movement,
		action = Enum.AnimationPriority.Action3,
	},
	categoryDefaults = {
		action = {
			fadeIn = 0.08,
			fadeOut = 0.12,
			forceRestart = true,
		},
	},
})

mixer:play("idle", 1234567890, {
	looped = true,
})

mixer:play("movement", 2345678901, {
	looped = true,
	preserveTimePosition = true,
	speed = 1.2,
})

local releaseAttack = mixer:push("action", 3456789012, {
	localPriority = 10,
	forceRestart = true,
})

local releaseSlow = mixer:pushGlobalSpeedModifier(0.5, {
	mode = "multiply",
	duration = 0.4,
})
local releaseFreeze = mixer:pushCategorySpeedModifier("action", 0, {
	mode = "set",
	priority = 100,
	duration = 0.12,
})

releaseAttack()
releaseSlow()
releaseFreeze()
```

For string or key refs:

```luau
type AnimRef = string

local mixer = AnimMixer.new({
	animator = animator,
	resolveAssetId = function(ref: AnimRef): number
		return animationIdsByKey[ref]
	end,
})
```

## API

- `AnimMixer.new(config)`
- `mixer:play(category, ref, options)`
- `mixer:push(category, ref, options) -> release`
- `mixer:stop(category, fadeOut)`
- `mixer:stopIfRef(category, ref, fadeOut) -> boolean`
- `mixer:getCategoryTrack(category) -> AnimationTrack?`
- `mixer:getCategoryRef(category) -> RefT?`
- `mixer:isCategoryPlaying(category) -> boolean`
- `mixer:getCategoryTimePosition(category) -> number?`
- `mixer:getCategorySpeed(category) -> number?`
- `mixer:setCategorySpeed(category, speed)`
- `mixer:setCategoryTimePosition(category, timePosition)`
- `mixer:adjustCategoryTimePosition(category, deltaTime)`
- `mixer:adjustAllTimePositions(deltaTime)`
- `mixer:pushGlobalSpeedModifier(value, options?) -> release`
- `mixer:pushCategorySpeedModifier(category, value, options?) -> release`
- `mixer:clear()`
- `mixer:destroy()`

Speed modifier options:

```luau
{
	mode = "multiply", -- "multiply", "add", or "set"; default "multiply"
	priority = 0, -- default 0
	duration = 0.25, -- optional auto-release
}
```

## Boundaries

animMixer owns generic `AnimationTrack` playback and mixing. It does not own:

- character movement policy;
- replicated character state;
- skills or ability selection;
- VFX lifetime rules;
- hitstop, freeze-frame, slow-motion, or other gameplay semantics;
- species, variant, weapon, or loadout lookup;
- animation dictionaries;
- procedural locomotion solvers;
- gameplay animation selection.

Those systems should resolve the appropriate raw asset id or ref, then pass it
to animMixer with the category and playback options they want.

## Development

Run static and formatting checks when the local tools are available:

```sh
selene src
stylua --check src
rojo sourcemap default.project.json --output sourcemap.json
```
