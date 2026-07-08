# Changelog

## 0.1.0

- Added the initial `animMixer` package.
- Added raw asset-id animation refs, required ref-to-asset-id resolution,
  category/layer playback, pushed overrides, crossfade, speed modifiers, and
  category query primitives.
- Moved runtime/private types into dedicated type modules and exposed the
  `AnimMixer` / `AnimMixerImpl` type split.
- Added `AnimPlayback` for one-ref track ownership and `StackModifier` for
  deterministic `"set"`, `"add"`, and `"multiply"` speed modifier stacks.
