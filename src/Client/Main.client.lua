-- Client entry point: boots all Knit Controllers
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit     = require(Packages.Knit)

-- Controllers
local Client = script.Parent
Knit.AddControllersDeep(Client.Controllers)

-- Boot
Knit.Start():andThen(function()
    print("[SlingSiege] Client started — all controllers online.")
end):catch(warn)
