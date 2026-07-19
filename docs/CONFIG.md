# BloxEnv configuration

BloxEnv searches upward from the target script for the nearest `bloxenv.config.luau`. The file runs after the default environment has been created, so the config itself can use values such as `Instance`, `Vector3`, `Color3`, and `Enum`.


> BloxEnv 0.1 uses an intentionally mutable base environment so the config can replace values at runtime; each loaded script still receives its own `script` global. Run trusted local scripts only; it is not an operating-system or hostile-code sandbox.

The config must return one table:

```luau
return {
    context = "client", -- "server", "client", or "studio"
    strict = false,

    game = {
        PlaceId = 123,
    },

    services = {
        Players = {
            GetPlayers = function(self)
                return { self.LocalPlayer }
            end,
        },
    },

    globals = {
        identifyexecutor = function()
            return "BloxEnv"
        end,
    },

    overrides = {
        ["game.HttpService.JSONDecode"] = function(_self, body)
            return { originalBody = body }
        end,
    },
}
```

## Fields

### `context`

Controls `RunService:IsServer()`, `RunService:IsClient()`, and `RunService:IsStudio()`.

### `strict`

When true, `game:GetService()` errors for services that BloxEnv has not created. When false, BloxEnv creates a generic mock service and prints a warning.

The CLI `--strict` flag also enables strict behavior.

### `game`

Properties and functions merged directly into the mock `DataModel`.

### `script`

Properties merged into the target script's mock `Script` or `LocalScript` immediately before execution:

```luau
return {
    script = {
        Name = "DebugMain",
        Parent = workspace,
    },
}
```

### `services`

Each key is passed through `game:GetService()`, then its table is merged into that service. Functions are ordinary Luau functions, so every method can be replaced.

### `globals`

Values copied into the target script's global environment after default globals are installed.

### `overrides`

Flat dot-separated paths for precise replacements:

```luau
return {
    overrides = {
        ["game.Players.GetUserIdFromNameAsync"] = function(_self, name)
            return 1000 + #name
        end,
    },
}
```

### `scheduler.maxSteps`

Maximum number of deterministic scheduler resumptions before BloxEnv assumes the script is stuck in an infinite task loop.

### `beforeRun` and `afterRun`

Optional hooks:

```luau
return {
    beforeRun = function(env)
        env.addPlayer({ Name = "TestPlayer", UserId = 1 }, true)
    end,

    afterRun = function(env)
        print("Finished at", env.time())
    end,
}
```

## Creating an Instance tree

Use `Children` descriptors inside any service or Instance patch:

```luau
return {
    services = {
        ReplicatedStorage = {
            Children = {
                Shared = {
                    ClassName = "Folder",
                    Children = {
                        Config = {
                            ClassName = "ModuleScript",
                            SourcePath = "./src/Config.luau",
                        },
                    },
                },
            },
        },
    },
}
```

A `ModuleScript` must have a `SourcePath` so BloxEnv can locate its source file. Relative paths resolve from the script performing the `require()`.
