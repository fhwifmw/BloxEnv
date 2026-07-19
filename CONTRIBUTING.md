# Contributing

BloxEnv is split into two layers:

- `src/main.cpp` handles the Luau host, CLI, source loading, and filesystem boundary.
- `runtime/bootstrap.luau` implements the Roblox-like environment.

Prefer implementing mock behavior in Luau unless it requires host access or a native datatype for correctness or performance.

## Development

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build --target bloxenv --parallel
./build/bloxenv examples/basic/main.client.luau
```

Keep changes focused and include a clear example when adding user-facing behavior.
