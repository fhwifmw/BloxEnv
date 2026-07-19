local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local greeting = require(ReplicatedStorage.Modules.Greeting)

print("Executor:", identifyexecutor())
print("PlaceId:", game.PlaceId)
print("Context is client:", game:GetService("RunService"):IsClient())
print(greeting(Players.LocalPlayer.Name))
print("Mock username:", Players:GetNameFromUserIdAsync(42))
print("Decoded enabled:", HttpService:JSONDecode([[{"enabled":true}]]).enabled)

Players.PlayerAdded:Connect(function(player)
    print("PlayerAdded:", player.Name, "at simulated time", time())
end)

task.delay(0.5, function()
    BloxEnv.addPlayer({
        Name = "SecondPlayer",
        DisplayName = "Second Player",
        UserId = 654321,
    }, false)
end)

print("Waiting one simulated second...")
task.wait(1)
print("Finished at simulated time:", time())
