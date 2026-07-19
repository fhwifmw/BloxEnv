# Contributing

BloxEnv is intentionally split into two layers:

- `src/main.cpp` owns the Luau host, CLI, source loading, and filesystem boundary.
- `runtime/bootstrap.luau` implements the Roblox-like environment.

Prefer implementing mock behavior in Luau unless it requires host access or a native datatype for correctness/performance.

## Development

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build --parallel
./build/bloxenv tests/smoke.server.luau
```

Please include a focused test or example for new behavior. Avoid claiming exact Roblox compatibility where behavior is only approximate.
