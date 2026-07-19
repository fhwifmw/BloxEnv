local localPlayer = Instance.new("Player")
localPlayer.Name = "DebugPlayer"
localPlayer.DisplayName = "Debug Player"
localPlayer.UserId = 123456

return {
    context = "client",
    strict = false,

    game = {
        PlaceId = 123456789,
        GameId = 987654321,
        JobId = "bloxenv-example-session",
    },

    scheduler = {
        maxSteps = 25000,
    },

    services = {
        Players = {
            LocalPlayer = localPlayer,
        },

        ReplicatedStorage = {
            Children = {
                Modules = {
                    ClassName = "Folder",
                    Children = {
                        Greeting = {
                            ClassName = "ModuleScript",
                            SourcePath = "./Modules/Greeting.luau",
                        },
                    },
                },
            },
        },

        HttpService = {
            JSONDecode = function(_self, body)
                -- This is deliberately tiny: users can replace it with any JSON library.
                if body == [[{"enabled":true}]] then
                    return { enabled = true }
                end
                error("Example JSONDecode mock received unexpected input: " .. body)
            end,
        },
    },

    globals = {
        identifyexecutor = function()
            return "BloxEnv"
        end,
    },

    overrides = {
        ["game.Players.GetNameFromUserIdAsync"] = function(_self, userId)
            return "MockUser_" .. tostring(userId)
        end,
    },
}
