return {
    context = "server",
    strict = true,

    game = {
        PlaceId = 123,
    },

    services = {
        ReplicatedStorage = {
            Children = {
                Modules = {
                    ClassName = "Folder",
                    Children = {
                        Outer = {
                            ClassName = "ModuleScript",
                            SourcePath = "./Modules/Outer.luau",
                        },
                    },
                },
            },
        },

        CustomService = {
            Ping = function()
                return "pong"
            end,
        },
    },

    globals = {
        customMock = function(value)
            return value * 2
        end,
    },
}
