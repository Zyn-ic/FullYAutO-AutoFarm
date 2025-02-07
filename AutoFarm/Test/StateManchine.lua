local StateMachine = {}
StateMachine.__index = StateMachine

local Promise = require("Path.To.Promise")
local Trove = require("Path.To.Trove")

function StateMachine.new(player)
    local self = setmetatable({}, StateMachine)
    
    -- Core components
    self.Player = player
    self.States = {
        Action = "Action",
        StandStillWait = "StandStillWait",
        WaitingForRound = "WaitingForRound",
        WaitingForRoundEnd = "WaitingForRoundEnd",
        RespawnState = "RespawnState",
        Reboot = "Reboot"
    }
    -- State management
    self.CurrentState = nil
    self.StateTrove = Trove.new()
    self.GlobalTrove = Trove.new()
    self.LastPosition = nil
    self.RoundInProgress = false :: boolean
    self.IsMurderer = false :: boolean
    self.BagIsFull = false :: boolean
    
    -- Configuration
    self.TASK_TIMEOUT = 60
    self.REBOOT_DELAY = 5
    self.INITIAL_STATE = self.States.WaitingForRound

    -- Initialize global connections
    self:InitializeGlobalConnections()

    return self
end

function StateMachine:InitializeGlobalConnections()
    -- Permanent connections that survive state changes
    self.GlobalTrove:Add(self.player.CharacterRemoving:Connect(function()
        self.StateTrove:CleanAll()
        self:EmergencyReboot("Character removed unexpectedly")
    end))

    -- Round tracking
    local roundTimer = workspace:WaitForChild("RoundTimerPart").SurfaceGui.Timer
    self.GlobalTrove:Add(roundTimer:GetPropertyChangedSignal("Text"):Connect(function()
        if (self.RoundInProgress) then return end
        self.RoundInProgress = true
    end))
end


function StateMachine:Start()
    self:SetState(self.INITIAL_STATE)
end

function StateMachine:EmergencyReboot(reason)
    print("Emergency reboot triggered:", reason)
    
    -- Full cleanup
    self.StateTrove:CleanAll()
    self.GlobalTrove:CleanAll()
    
    -- Clear game state
    self.LastPosition = nil
    self.IsMurderer = false
    self.BagIsFull = false
    self.RoundInProgress = false
    
    -- Delay and restart
    Promise.delay(self.REBOOT_DELAY)
        :andThen(function()
            self:InitializeGlobalConnections()
            self:Start()
        end)
end

function StateMachine:SetState(newState)
    -- Validate state exists
    if not self.States[newState] then
        return self:EmergencyReboot(string.format("Invalid state transition attempt: %s", tostring(newState)))
    end

    -- Cleanup previous state resources
    self.StateTrove:CleanAll()

    -- Create fresh trove for new state
    local stateTrove = self.Trove.new()
    self.StateTrove = stateTrove

    -- State transition tracking
    local transitionId = tick()
    self._currentTransition = transitionId
    self.CurrentState = newState

    -- Get state handler (convention: StateName + "State" = handler function)
    local handlerName = newState .. "State"
    local handler = self[handlerName]
    if type(handler) ~= "function" then
        return self:EmergencyReboot(string.format("Missing handler for state: %s", handlerName))
    end

    -- Create state guard
    local guard = {
        isValid = function()
            return self._currentTransition == transitionId
        end
    }
    stateTrove:Add(function()
        guard.isValid = function() return false end
    end)

    -- Prepare state promise with timeout
    local statePromise = Promise.try(function()
        -- Add critical cleanup to trove first
        stateTrove:Add(function()
            if guard.isValid() then
                self:Message("StateCleanup", string.format("Cleaning up %s state", newState), 2)
            end
        end)

        return handler(self, stateTrove)
    end)

    -- Add timeout protection
    local timeoutPromise = Promise.delay(self.TASK_TIMEOUT)
        :andThen(function()
            if guard.isValid() then
                return Promise.reject(string.format("State timeout (%ss)", self.TASK_TIMEOUT))
            end
        end)

    -- Handle state completion
    Promise.race({statePromise, timeoutPromise})
        :andThen(function(nextState)
            if not guard.isValid() then
                self:Message("StateDebug", "Ignoring stale state transition", 1)
                return
            end

            if not self.States[nextState] then
                return Promise.reject("Invalid next state: " .. tostring(nextState))
            end

            self:SetState(nextState)
        end)
        :catch(function(err)
            if not guard.isValid() then return end
            local errMsg = string.format("State failure in %s: %s", newState, tostring(err))
            self:Message("CriticalError", errMsg, 5)
            self:EmergencyReboot(errMsg)
        end)

    -- Register state promise in trove
    stateTrove:Add(function()
        if statePromise:getStatus() == Promise.Status.Started then
            self:Message("StateDebug", "Canceling ongoing state operations", 2)
        end
    end)
end

function StateMachine:CreateStateGuard()
    local guard = { isValid = true }
    self.StateTrove:Add(function()
        guard.isValid = false
    end)
    return function()
        return guard.isValid
    end
end

function StateMachine:ActionState(trove)
    return Promise.new(function(resolve, reject)
        -- State initialization
        local isGuardValid = self:CreateStateGuard()
        trove:Add(AutoFarmCleanUp)

        -- Main logic
        Promise.try(function()
            -- Setup coin collection
            local coinContainer = self:Map():FindFirstChild("CoinContainer")
            if not coinContainer then
                return reject("Coin container not found")
            end

            populateOctree(coinContainer, trove)
            self.LastPosition = self:Character():GetPivot()

            -- Main collection loop
            while isGuardValid() and not self.BagIsFull do
                if not self:CheckIfGameInProgress() then
                    return reject("Game exited unexpectedly")
                end

                local nearestCoin = self.octree:GetNearest(self:Character().PrimaryPart.Position, self.radius, 1)[1]
                if nearestCoin then
                    moveToPositionSlowly(nearestCoin.Object.Position, trove)
                else
                    Promise.delay(1):await()
                end
            end

            return self.BagIsFull and self.States.WaitingForRoundEnd or self.States.WaitingForRound
        end)
        :andThen(resolve)
        :catch(reject)
    end)
end

function StateMachine:RespawnState(trove, kill: boolean)
    return Promise.new(function(resolve, reject)
        local isGuardValid = self:CreateStateGuard()
        
        Promise.try(function()
            -- Respawn logic
            if kill then self:Character():BreakJoints() end
            self:GetCharacterLoaded()
            
            if isGuardValid() and self.LastPosition then
                self:Character():PivotTo(self.LastPosition)
            end

            return self:CheckIfGameInProgress() 
                and self.States.Action 
                or self.States.WaitingForRound
        end)
        :andThen(resolve)
        :catch(reject)
    end)
end

function StateMachine:RebootState(trove)
    return Promise.new(function(resolve)
        -- Cleanup everything
        self.StateTrove:CleanAll()
        self.GlobalTrove:CleanAll()
        
        -- Wait before restarting
        Promise.delay(self.REBOOT_DELAY)
            :andThen(function()
                resolve(self.INITIAL_STATE)
            end)
    end)
end

function StateMachine:WaitingForRoundState(trove)
    return Promise.new(function(resolve)
        local isGuardValid = self:CreateStateGuard()
        
        self:Message("Info", "Waiting for round start...", 2)
        
        -- Wait for round start
        local connection
        connection = self.GlobalTrove:Add(function()
            connection:Disconnect()
        end)
        
        -- Check every 2 seconds
        while isGuardValid() do
            if self:CheckIfGameInProgress() then
                resolve(self.States.Action)
                return
            end
            Promise.delay(2):await()
        end
    end)
end

-- Utility functions (from original code)
function StateMachine:Message(_Title, _Text, Time)
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = _Title,
        Text = _Text,
        Duration = Time
    })
end

function StateMachine:Character()
    return self.player.Character or self.player.CharacterAdded:Wait()
end

function StateMachine:GetCharacterLoaded()
    repeat task.wait(0.1) until self:Character() and self:Character():FindFirstChild("HumanoidRootPart")
end

return StateMachine