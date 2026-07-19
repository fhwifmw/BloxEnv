assert(script.Name == "smoke")
assert(script.ClassName == "Script")
assert(game.PlaceId == 123)
assert(game:GetService("RunService"):IsServer())
assert(customMock(21) == 42)
assert(game:GetService("CustomService"):Ping() == "pong")

local folder = Instance.new("Folder")
folder.Name = "Container"
folder.Parent = workspace
assert(workspace:FindFirstChild("Container") == folder)

local outer = require(game.ReplicatedStorage.Modules.Outer)
local outerScriptName, innerScriptName = outer()
assert(outerScriptName == "Outer")
assert(innerScriptName == "Inner")
assert(script.Name == "smoke")

local fired = false
task.delay(0.25, function()
    fired = true
    assert(script.Name == "smoke")
end)
task.wait(0.5)
assert(fired)

print("BloxEnv smoke test passed")
