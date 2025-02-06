local GoodSignal = require(script.GoodSignal)
local Octree = nil -- loadstring(httpget("https://raw.githubusercontent.com/Sleitnick/rbxts-octo-tree/main/src/init.lua", true))()
local rt = {}

rt.__index = rt

-- Custom metatable to handle RoundInProgress

rt.octree = Octree
rt.RoundInProgress = false
rt.Players = game.Players
rt.player = game.Players.LocalPlayer

rt.coinContainer = nil
rt.radius = 200 -- Radius to search for coins
rt.walkspeed = 30 -- Speed at which you will go to a coin measured in walkspeed
rt.touchedCoins = {} -- Table to track touched coins
rt.positionChangeConnections = setmetatable({}, { __mode = "v" }) -- Weak table for connections
rt.Added = nil -- :: RBXScriptConnection
rt.Removing = nil -- :: RBXScriptConnection

rt.UserDied = nil -- :: RBXScriptConnection
rt.RoleTracker1 = nil -- :: RBXScriptConnection
rt.RoleTracker2 = nil -- :: RBXScriptConnection
rt.InvalidPos = nil -- :: RBXScriptConnection

rt.ConnectToPlayerIsMurderer = GoodSignal.new()

-- States and variables
local State = {
	Action = "Action",
	StandStillWait = "StandStillWait",
	WaitingForRound = "WaitingForRound",
	WaitingForRoundEnd = "WaitingForRoundEnd",
	RespawnState = "RespawnState"
}

local CurrentState = State.WaitingForRound
local LastPosition = nil
local BagIsFull = false

local IsMurderer = false
local Working = false
local ROUND_TIMER = nil --workspace:WaitForChild("RoundTimerPart").SurfaceGui.Timer
local PLAYER_GUI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

local proxy = setmetatable({}, {
	__index = rt,
	__newindex = function(tbl, key, value)
		local old_value = rt[key]
		if value ~= old_value then
			if key == "RoundInProgress" then rt.ConnectToPlayerIsMurderer:Fire("Info", value and "Round In Progress" or "Round Not in Progress", 2) end
		end
		rawset(rt, key, value)
	end
})

-- Methods
function rt:Message(_Title, _Text, Time)
	game:GetService("StarterGui"):SetCore("SendNotification", { Title = _Title, Text = _Text, Duration = Time })
end

function rt:checkMurderer()
	return IsMurderer
end

function rt:ChangeRIPVal(value)
	proxy.RoundInProgress = value
	print(self.RoundInProgress)
end

-- Connect GoodSignal
rt.ConnectToPlayerIsMurderer:Connect(function(Title:string, Text:string, Time:number)
	print("GoodSignal fired!")
	rt:Message(Title, Text, Time)
end)


-- Simulate runtime
task.wait(5)

print("Starting")
rt:ChangeRIPVal(true) -- Should trigger __newindex

task.wait(5)
print("Ending")
rt:ChangeRIPVal(false)
