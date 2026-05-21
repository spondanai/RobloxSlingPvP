-- Server entry point: boots all Knit Services
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerStorage       = game:GetService("ServerStorage")

-- Wally packages
local Packages       = ReplicatedStorage:WaitForChild("Packages")
local ServerPackages = ServerStorage:WaitForChild("ServerPackages")
local Knit           = require(Packages.Knit)

-- Services
local Server = script.Parent
Knit.AddServicesDeep(Server.Services)

-- Boot
Knit.Start():andThen(function()
    print("[SlingSiege] Server started — all services online.")
end):catch(warn)
