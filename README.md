# BloxEnv

**Run Roblox-oriented Luau outside Roblox Studio with a configurable local environment.**

BloxEnv loads Roblox-like globals, services, datatypes, and user-defined overrides before running a Luau script.

## Installation

### macOS and Linux

```bash
curl -fsSL https://raw.githubusercontent.com/fhwifmw/BloxEnv/main/install.sh | bash
```

### Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/fhwifmw/BloxEnv/main/install.ps1 | iex
```

The installer builds BloxEnv from source and adds it to your user `PATH`. It requires Git, CMake, and a C++ compiler.

## Usage

```bash
bloxenv path/to/script.luau
```

Place a `bloxenv.config.luau` beside your project to replace globals, services, properties, and functions with ordinary Luau code. Without `--config`, BloxEnv searches upward from the target script for the nearest config file.

```text
bloxenv [options] <script.luau> [-- script arguments...]

--config <path>       Use a specific config file
--no-config           Disable config discovery
--strict              Error on unsupported services
--allow-outside-root  Permit require() outside the project root
-h, --help            Show help
-v, --version         Show version
```

Arguments after `--` are available through `BloxEnv.args`:

```bash
bloxenv main.luau -- first second
```

```luau
print(BloxEnv.args[1]) -- first
```

## Features

- Embedded Luau compiler and VM
- Configurable `game`, `script`, services, globals, methods, and properties
- Roblox-like `Instance`, `Enum`, signals, attributes, and parenting
- Deterministic `task.spawn`, `task.defer`, `task.delay`, and `task.wait`
- `Players`, `RunService`, `HttpService`, and `CollectionService` mocks
- `Vector2`, `Vector3`, and `Color3`
- Filesystem modules and configurable `ModuleScript` paths
- Server, client, and Studio contexts
- Project-root confinement for module reads

See the [configuration documentation](docs/CONFIG.md) and [roadmap](docs/ROADMAP.md).

## Configuration

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

## ModuleScripts

Map a mocked `ModuleScript` to a local source file:

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

Then require it normally:

```luau
local Utility = require(game.ReplicatedStorage.Utility)
```

Filesystem paths also work:

```luau
local Utility = require("./src/Utility")
```

## Build from source

### macOS and Linux

```bash
git clone https://github.com/fhwifmw/BloxEnv.git
cd BloxEnv
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --target bloxenv --parallel
```

### Windows

```powershell
git clone https://github.com/fhwifmw/BloxEnv.git
cd BloxEnv
cmake -S . -B build
cmake --build build --config Release --target bloxenv --parallel
```

## Example

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

A complete example project is available in [`examples/basic`](examples/basic).

## License

BloxEnv is released under the MIT License and embeds [Luau](https://luau.org/), which is also distributed under the MIT License.
