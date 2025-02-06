
------------------------------------------------------------------------------------------------

-- State variables
local Octree = loadstring(game:HttpGet("https://raw.githubusercontent.com/Sleitnick/rbxts-octo-tree/main/src/init.lua", true))()

local rt = {} -- Removable table
rt.__index = rt
rt.octree = Octree.new()

rt.RoundInProgress = false

rt.Players = game.Players
rt.player = game.Players.LocalPlayer

rt.coinContainer = nil
rt.radius = 200 :: number -- Radius to search for coins
rt.walkspeed = 30 :: number -- speed at which you will go to a coin measured in walkspeed
rt.touchedCoins = {} -- Table to track touched coins
rt.positionChangeConnections = setmetatable({}, { __mode = "v" }) -- Weak table for connections
rt.touchChangeConnections = setmetatable({}, { __mode = "v" }) -- Weak table for connections
rt.Added = nil :: RBXScriptConnection
rt.Removing = nil :: RBXScriptConnection

rt.UserDied = nil :: RBXScriptConnection

local State = {
    Action = "Action",
    StandStillWait = "StandStillWait",
    WaitingForRound = "WaitingForRound",
    WaitingForRoundEnd = "WaitingForRoundEnd",
    RespawnState = "RespawnState"
}

local CurrentState = State.WaitingForRound
local LastPosition = nil
local RoundInProgress = function()
    return rt.RoundInProgress
end
local BagIsFull = false

-- Constants
rt.RoleTracker1 = nil :: RBXScriptConnection
rt.RoleTracker2 = nil :: RBXScriptConnection
rt.InvalidPos = nil :: RBXScriptConnection
local IsMurderer = false
local Working = false
local ROUND_TIMER = workspace:WaitForChild("RoundTimerPart").SurfaceGui.Timer
local PLAYER_GUI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") 

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
function rt:Message(_Title, _Text, Time)
	return game:GetService("StarterGui"):SetCore("SendNotification", { Title = _Title, Text = _Text, Duration = Time })
end

function rt:Character () : (Model)
    return self.player.Character or self.player.CharacterAdded:Wait()
end

function rt:GetCharacterLoaded() : (Model)
    repeat
        task.wait(0.02)
    until self:Character() ~= nil
end

function rt:CheckIfPlayerIsInARound () : (boolean)
    --check if player is in a round
    --check by going to the players gui -> MainGui -> Game -> Timer.Visible
    if not PLAYER_GUI:WaitForChild("MainGUI") then return false end

    if PLAYER_GUI:WaitForChild("MainGUI").Game.Timer.Visible then
        return true
    end

    --check by going to the players gui -> MainGui -> Game -> EarnedXP.Visible
    if PLAYER_GUI:WaitForChild("MainGUI").Game.EarnedXP.Visible then
        return true
    end

    return false
end

function rt:MainGUI () : (ScreenGui)
    return self.player.PlayerGui.MainGUI or self.player.PlayerGui:WaitForChild("MainGUI")
end

function rt.Disconnect (connection:RBXScriptConnection)
    if connection and connection.Connected then
        connection:Disconnect()
    end
end

function rt:Map () : (Model | nil)
    for _, v in workspace:GetDescendants() do
        if v.Name == "Spawns" and v.Parent.Name ~= "Lobby"  then
            return v.Parent
        end
    end
    return nil
end

function rt:CheckIfGameInProgress () : (boolean)
    if rt:Map() then return true end
    return false
end

function rt:GetAlivePlayers (): (table | nil)
    --get all players that are alive
    local aliveplrs = setmetatable({}, {__mode = "v"})
    local OldPos = self:Character():GetPivot()
    local pos = CFrame.new(-121.995956, 134.462997, 46.4180717)
    
    if not rt:CheckIfGameInProgress() then return nil end

    local isAlive = rt:CheckIfPlayerIsInARound()

    if not isAlive then self:Character():PivotTo(pos) end

    for _, v in pairs(rt.Players:GetPlayers()) do
        local distance = (self:Character().PrimaryPart.Position - v.Character.PrimaryPart.Position).Magnitude
        if isAlive then
            if distance <= 500 then
                table.insert(aliveplrs, v)
            end
        else
            if distance > 500 then
                table.insert(aliveplrs, v)
            end
        end
    end

    if not isAlive then self:Character():PivotTo(OldPos) end
    
    return aliveplrs
end

function rt:CheckIfPlayerWasInARound () : (boolean)
    if self.player:GetAttribute("Alive") then
        return true
    end

    return false
end

function rt:IsElite() : (boolean)
    if self.player:GetAttribute("Elite") then
        return true
    end

    return false
end

local function AutoFarmCleanUp()
    if next(rt.positionChangeConnections) == nil or next(rt.touchChangeConnections) == nil then
        return rt:Message("Info", "Nothing to clean", 1)
    end

    -- Clean up all connections and cached data
    for _, connection in pairs(rt.positionChangeConnections) do
        rt.Disconnect(connection)
    end

    for _, connection in pairs(rt.touchChangeConnections) do
        rt.Disconnect(connection)   
    end

    rt.Disconnect(rt.Added)
    rt.Disconnect(rt.Removing)

    task.spawn(rt:Message("Info", "Autofarm CleanUp Success", 2))
    table.clear(rt.touchedCoins)
    table.clear(rt.touchChangeConnections)
    table.clear(rt.positionChangeConnections)
    rt.octree:ClearAllNodes()
end

-- Function to check if a coin has been touched
local function isCoinTouched(coin)
    return rt.touchedCoins[coin]
end

-- Function to mark a coin as touched
local function markCoinAsTouched(coin)
    if not rt then return end
    rt.touchedCoins[coin] = true
    local node = rt.octree:FindFirstNode(coin)
    if node then
        rt.octree:RemoveNode(node)
    end
end

-- Function to track touch interactions
local function setupTouchTracking(coin)
    
    local touchInterest = coin:FindFirstChildWhichIsA("TouchTransmitter")
    if touchInterest then
        local connection
        connection = touchInterest.AncestryChanged:Connect(function(_, parent)
            if not rt then connection:Disconnect() return end
            if parent == nil then
                -- TouchInterest removed; mark the coin as touched
                markCoinAsTouched(coin)
                rt.Disconnect(connection)
            end
        end)
        rt.touchChangeConnections[coin] = connection
    end
end

local function setupPositionTracking(coin: MeshPart, LastPositonY: number)
    local connection
    connection = coin:GetPropertyChangedSignal("Position"):Connect(function()
        -- Check if the Y position has changed
        local currentY = coin.Position.Y
        if LastPositonY and LastPositonY ~= currentY then

            -- Remove the coin from the octree as it has been moved
            markCoinAsTouched(coin)

            rt.Disconnect(connection)
            coin:Destroy()
            return
        end
    end)
    rt.positionChangeConnections[coin] = connection
end

local function moveToPositionSlowly(targetPosition: Vector3, duration: number)
    local startPosition = rt:Character().PrimaryPart.Position
    local startTime = tick()

    local nearestNode = rt.octree:GetNearest(rt:Character().PrimaryPart.Position, rt.radius, 1)[1]
    if nearestNode then
        local closestCoin = nearestNode.Object
        if not isCoinTouched(closestCoin) then
            local targetPosition2 = closestCoin.Position
            if targetPosition ~= targetPosition2 then 
                targetPosition = targetPosition2
            end
        end
    end
    
    while true do
        local elapsedTime = tick() - startTime
        local alpha = math.min(elapsedTime / duration, 1)

        if rt:Character() == nil then break end

        rt:Character():PivotTo(CFrame.new(startPosition:Lerp(targetPosition, alpha)))

        if alpha >= 1 then
            task.wait(0.2)
            break
        end

        task.wait() -- Small delay to make the movement smoother
    end
end
-- Function to populate the Octree with coins
local function populateOctree()
    rt.octree:ClearAllNodes() -- Clear previous nodes

    for _, descendant in pairs(rt.coinContainer:GetDescendants()) do
        if descendant:IsA("TouchTransmitter") then --and descendant.Material == rt.Material then
            local parentCoin = descendant.Parent
            if not isCoinTouched(parentCoin) then
                rt.octree:CreateNode(parentCoin.Position, parentCoin)
                setupTouchTracking(parentCoin)
            end
            setupPositionTracking(parentCoin, parentCoin.Position.Y)
        end
    end

    rt.Added = rt.coinContainer.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("TouchTransmitter") then --and descendant.Material == rt.Material then
            local parentCoin = descendant.Parent
            if not isCoinTouched(parentCoin) then
                rt.octree:CreateNode(parentCoin.Position, parentCoin)
                setupTouchTracking(parentCoin)
                setupPositionTracking(parentCoin, parentCoin.Position.Y)
            end
        end
    end)

    rt.Removing = rt.coinContainer.DescendantRemoving:Connect(function(descendant)
        if descendant:IsA("TouchTransmitter") and descendant.Parent.Name == "Coin_Server" then
            local parentCoin = descendant.Parent
            if isCoinTouched(parentCoin) then
                markCoinAsTouched(parentCoin)
            end
        end
    end)
end

local function ChangeState(State)
    CurrentState = State
end
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

-- Helper Functions

local function CheckMurderer()
    return IsMurderer
end

local function IsBagFull()
    local playerGui = PLAYER_GUI:WaitForChild("MainGUI")
    local coinText = playerGui.Game.CoinBags.Container.SnowToken.CurrencyFrame.Icon.Coins.Text
    return tonumber(coinText) >= (rt:IsElite() and 50 or 40)
end

local function RespawnAndTeleportBack()
    LastPosition = LastPosition ~= nil and LastPosition or rt:Character():GetPivot()
    rt:Character():FindFirstChildWhichIsA("Humanoid"):ChangeState(Enum.HumanoidStateType.Dead)
    rt:GetCharacterLoaded()
    task.wait(1)
    
    if rt:Character() then
        if not RoundInProgress() then rt:GetCharacterLoaded() return ChangeState(State.WaitingForRound) end
        rt:GetCharacterLoaded()
        rt:Character():PivotTo(LastPosition)
    end
end

local function CollectCoins()
    Working = true
    rt.coinContainer = rt:Map():FindFirstChild("CoinContainer")
    populateOctree()
    while CurrentState == State.Action do
        if IsBagFull() then
            rt:Message("Alert", "Bag is full!", 2)
            BagIsFull = true
            break
        end

        if rt:Character() == nil then
            break
        end

        -- Find nearest coin
        local nearestNode = rt.octree:GetNearest(rt:Character().PrimaryPart.Position, rt.radius, 1)[1]
        if nearestNode then
            local closestCoin = nearestNode.Object
            if not isCoinTouched(closestCoin) then
                local targetPosition = closestCoin.Position
                local duration = (rt:Character().PrimaryPart.Position - targetPosition).Magnitude / rt.walkspeed
                moveToPositionSlowly(targetPosition, duration)
                markCoinAsTouched(closestCoin)
                task.wait(0.2)
            end
        else
            task.wait(1)
        end
    end
    AutoFarmCleanUp()
end

local function RespawnState()
    rt:Message("Info", "Respawning...", 2)
    rt:GetCharacterLoaded()
    task.wait(1)
    if LastPosition == nil then LastPosition = rt:GetAlivePlayers()[1] end
    if rt:Character() then
        rt:GetCharacterLoaded()
        rt:Character():PivotTo(LastPosition)
    end
    rt:Message("Info", "Respawned!", 2)

    if not RoundInProgress() then
        rt:Message("Info", "Round ended during respawn!", 2)
        ChangeState(State.WaitingForRound)
        return
    end

    ChangeState(State.Action)
end

-- Waiting State Logic
local function WaitingForRound()
    rt:Message("Info", "Waiting for round to start...", 2)
    Working = false
    --rt:Character():FindFirstChildWhichIsA("Humanoid"):ChangeState(Enum.HumanoidStateType.Seated)
   -- Monitor round start
    repeat
        task.wait(0.5)
    until RoundInProgress() and rt:CheckIfPlayerWasInARound()

    rt:Message("Alert", "Round started!", 2)
    ChangeState(State.Action)
end

local function waitForRoundEnd()
    rt:Message("Info", "Waiting for round to end...", 2)
    Working = false
    --rt:Character():FindFirstChildWhichIsA("Humanoid"):ChangeState(Enum.HumanoidStateType.Seated)
    -- Monitor round end
    repeat
        task.wait(1)
    until not RoundInProgress()

    rt:Message("Alert", "Round ended!", 2)
    ChangeState(State.WaitingForRound) 
end

local function StandStillWait()
    rt:Message("Info", "Waiting for murderer to respawn", 2)
    ChangeState("Nothing")
    rt:GetCharacterLoaded()
    task.wait(2)
    ChangeState(State.WaitingForRound)
end

-- Action State Logic
local function ActionState()
    LastPosition = nil
    if CheckMurderer() then
        rt:Message("Info", "You are the Murderer! Collecting coins...", 2)
        CollectCoins()
    else
        rt:Message("Info", "Logging position and respawning...", 2)
        --if #game.Players:GetChildren() > 2 then RespawnAndTeleportBack(); CollectCoins() else CollectCoins() end
        CollectCoins()
    end

    -- After collecting coins or if the round ends, return to waiting state
    if BagIsFull or not RoundInProgress() then
        if CheckMurderer() then
            rt:Message("Info", "Returning to Waiting State...", 2)
            BagIsFull, Working, rt.RoundInProgress = false, false, false
            rt:Character():FindFirstChildWhichIsA("Humanoid"):ChangeState(Enum.HumanoidStateType.Dead)
        else
            rt:Message("Info", "Returning to Waiting State...", 2)
            BagIsFull, Working = false, false
            rt:Character():FindFirstChildWhichIsA("Humanoid"):ChangeState(Enum.HumanoidStateType.Dead)
            ChangeState(State.WaitingForRoundEnd)
        end
    end
    
end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
rt.RoleTracker1 = rt.player.DescendantAdded:Connect(function(descendant)
    if descendant:IsA("Tool") then
        if descendant.Name == "Knife" then
            IsMurderer = true
        end
    end
end)

rt.InvalidPos = workspace.DescendantAdded:Connect(function(descendant)
    if descendant:IsA("Model") then
        if string.match(descendant.Name, "Glitch") and descendant.Parent.Name ~= "Lobby" then
            descendant:Destroy()
        end

        if string.match(descendant.Name, "Invis") and descendant.Parent.Name ~= "Lobby" then
            descendant:Destroy()
        end
    end
end)

 -- Monitor round start
local LastText
ROUND_TIMER:GetPropertyChangedSignal("Text"):Connect(function()
    rt.RoundInProgress = true
end)

PLAYER_GUI.ChildAdded:Connect(function(child)
    if child:IsA("Sound") then
        rt.RoundInProgress = false
        Working = false
        ChangeState(State.WaitingForRound)
    end
end)

rt.UserDied = rt.player.CharacterRemoving:Connect(function(character)
    AutoFarmCleanUp()
    LastText = ROUND_TIMER.Text
    if CheckMurderer() then IsMurderer = false; LastPosition = nil; Working = false; rt.RoundInProgress = false return ChangeState(State.StandStillWait) end
    
    if not RoundInProgress() then IsMurderer = false; LastPosition = nil; Working = false; return ChangeState(State.WaitingForRound) end

    task.wait(2)
    if LastText == ROUND_TIMER.Text then LastPosition = nil; IsMurderer = false; rt.RoundInProgress = false; Working = false return ChangeState(State.WaitingForRound) end

    if Working then
        Working = false
        IsMurderer = false
        LastPosition = nil
        ChangeState(State.RespawnState)
    end
end)

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

IsMurderer = rt.player.Backpack:FindFirstChild("Knife") and true or false   


-- Main Loop
while true do
    if CurrentState == State.WaitingForRound then
        WaitingForRound()
    elseif CurrentState == State.Action then
        ActionState()
    elseif CurrentState == State.WaitingForRoundEnd then
        waitForRoundEnd()
    elseif CurrentState == State.RespawnState then
        RespawnState()
    elseif CurrentState == State.StandStillWait then
        StandStillWait()
    end
    task.wait()
end


---------------------------------------------------------------------------------------------------------
--if the sound doesnt play when the murderer dies run getgenv().RoundInProgress = false
