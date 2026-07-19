# BloxEnv

**Run and debug Roblox-oriented Luau outside Roblox Studio with a configurable local environment.**

BloxEnv is a small Luau host that installs Roblox-like globals before running a script:

```bash
bloxenv path/to/main.server.luau
```

Place a `bloxenv.config.luau` beside your project and replace any property, service, method, or global with ordinary Luau code.

> BloxEnv is a compatibility and testing runtime, not a Roblox engine emulator. It does not render, simulate Roblox physics, connect to Roblox servers, or reproduce every engine API.

## Example

```luau
-- bloxenv.config.luau
return {
    context = "client",

    game = {
        PlaceId = 123456789,
    },

    services = {
        Players = {
            GetNameFromUserIdAsync = function(_self, userId)
                return "MockUser_" .. tostring(userId)
            end,
        },
    },

    globals = {
        identifyexecutor = function()
            return "BloxEnv"
        end,
    },
}
```

```luau
-- main.client.luau
local Players = game:GetService("Players")

print(game.PlaceId)
print(Players:GetNameFromUserIdAsync(42))
print(identifyexecutor())
```

```text
123456789
MockUser_42
BloxEnv
```

## Current MVP features

- Embedded official Luau compiler and VM
- Nearest-config discovery (`bloxenv.config.luau`)
- Configurable `game`, target `script`, services, globals, methods, and properties
- `game`, `workspace`, `script`, `Instance`, `Enum`, `task`, `typeof`, `time`, and `tick`
- Instance parenting, children, signals, attributes, cloning, and destruction
- Deterministic `task.spawn`, `task.defer`, `task.delay`, and `task.wait`
- Basic `Players`, `RunService`, `HttpService`, and `CollectionService`
- Basic `Vector2`, `Vector3`, and `Color3`
- Filesystem `require("./Module")`
- Mock `ModuleScript` support through `SourcePath`
- Server, client, and Studio contexts
- Project-root confinement for module reads

See [configuration documentation](docs/CONFIG.md) and the [roadmap](docs/ROADMAP.md).

## Build

BloxEnv uses CMake and fetches the pinned Luau `0.730` source automatically.

### macOS and Linux

```bash
git clone https://github.com/YOUR_USERNAME/BloxEnv.git
cd BloxEnv
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
./build/bloxenv examples/basic/main.client.luau
```

Install it onto your `PATH`:

```bash
sudo cmake --install build
```

### Windows

```powershell
git clone https://github.com/YOUR_USERNAME/BloxEnv.git
cd BloxEnv
cmake -S . -B build
cmake --build build --config Release --parallel
.\build\Release\bloxenv.exe examples\basic\main.client.luau
```

## CLI

```text
bloxenv [options] <script.luau> [-- script arguments...]

--config <path>       Use a specific config file
--no-config           Disable config discovery
--strict              Error on unsupported services
--allow-outside-root  Permit require() outside the project root
-h, --help            Show help
-v, --version         Show version
```

Without `--config`, BloxEnv starts in the target script's directory and walks upward until it finds the nearest `bloxenv.config.luau`.

Arguments after `--` are available through `BloxEnv.args`:

```bash
bloxenv main.luau -- first second
```

```luau
print(BloxEnv.args[1]) -- first
```

## ModuleScripts

A mocked `ModuleScript` needs a source path:

```luau
return {
    services = {
        ReplicatedStorage = {
            Children = {
                Utility = {
                    ClassName = "ModuleScript",
                    SourcePath = "./src/Utility.luau",
                },
            },
        },
    },
}
```

Then normal Roblox-style code works:

```luau
local Utility = require(game.ReplicatedStorage.Utility)
```

String paths also work:

```luau
local Utility = require("./src/Utility")
```

Module paths are restricted to the detected project root unless `--allow-outside-root` is supplied.

## Deterministic time

BloxEnv does not sleep in real time. It advances a simulated clock to the next scheduled task:

```luau
task.delay(10, function()
    print("ten seconds")
end)

task.wait(5)
print(time()) -- 5
```

The whole script can still finish almost instantly on the host machine.

## Status and limitations

This repository is an early MVP. Current limitations include:

- Partial Roblox API coverage
- No rendering, physics, networking, DataStore backend, or engine security contexts
- Approximate Instance/class behavior
- No `CFrame`, `UDim2`, or JSON implementation yet
- Mutable configurable base globals with per-script `script` environments; v0.1 is for trusted local code, not hostile-code sandboxing
- No audited hostile-code resource limits yet
- Config files are expected to run synchronously

Unsupported functions are meant to be replaced in `bloxenv.config.luau` until native mocks are added.

## Smoke test

After building:

```bash
./build/bloxenv tests/smoke.server.luau
```

Expected output:

```text
BloxEnv smoke test passed
```

## Luau attribution

BloxEnv embeds [Luau](https://luau.org/), distributed under the MIT License. Luau is developed by Roblox and open-source contributors.

## License

BloxEnv is released under the MIT License.
