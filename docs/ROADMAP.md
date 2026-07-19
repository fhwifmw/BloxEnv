# Roadmap

## 0.1 — usable runtime shim

- Embedded Luau runtime
- Config-driven globals, services, methods, and properties
- `game`, `workspace`, `script`, `Instance`, `Enum`, `task`, and `typeof`
- Basic Instance hierarchy, signals, attributes, cloning, and destruction
- Deterministic scheduler
- `Vector2`, `Vector3`, and `Color3`
- Filesystem modules and `ModuleScript.SourcePath`
- Basic Players, RunService, HttpService, and CollectionService mocks

## 0.2 — better compatibility

- `CFrame`, `UDim`, `UDim2`, `BrickColor`, `Ray`, and sequence types
- JSON encode/decode implementation
- Better class inheritance and default properties
- BindableFunction
- More service presets
- Improved Roblox-style stack traces
- Config schema validation

## 0.3 — testing and debugging

- Call tracing
- Mock call history and assertions
- Snapshots of the Instance tree
- Coverage output
- Execution limits and configurable timeouts
- Test discovery and a `bloxenv test` command

## Later

- Rojo sourcemap/project import
- `.rbxlx`/`.rbxmx` model import where practical
- Plugin API mocks
- Optional native datatype implementations
- Editor/LSP integration
