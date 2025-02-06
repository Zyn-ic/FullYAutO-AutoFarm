-- StateMachine module
local StateMachine = {}
StateMachine.__index = StateMachine

-- Dependencies
local Promise = require("Path.To.Promise") 
local Trove = require("Path.To.Trove")

function StateMachine.new()
    local self = setmetatable({}, StateMachine)
    
    -- State tracking
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
    self.StateTrove = Trove.new() -- For state-specific cleanup
    self.GlobalTrove = Trove.new() -- For permanent connections
    
    -- Timeout constants
    self.TASK_TIMEOUT = 60
    self.REBOOT_DELAY = 5
    
    return self
end

--[[
State transition flow:
1. Normal flow: States transition based on game conditions
2. Error flow: Any state error → ErrorHandler -> Normal Flow ? Reboot state
3. Timeout flow: Task timeout → ErrorHandler -> Reboot state ? Normal Flow
4. Reboot flow: Cleanup → Wait → Restart state machine
]]

function StateMachine:RegisterState(name, handler)
    --[[
    Register a state with:
    - Name: State identifier
    - Handler: async function(trove) that returns nextState
    ]]
    self.States[name] = name
end

function StateMachine:SetState(newState)
    --[[
    Transition to new state:
    1. Cleanup previous state resources
    2. Start new state task with timeout
    3. Handle completion/errors
    ]]
end

function StateMachine:Start(initialState)
    --[[
    Start the state machine:
    1. Initialize global connections
    2. Begin state transitions
    ]]
end

function StateMachine:EmergencyReboot(reason)
    --[[
    Full system reboot:
    1. Kill all current operations
    2. Clear cached data
    3. Full resource cleanup
    4. Restart state machine after delay
    ]]
end

function StateMachine:CreateStateGuard()
    --[[
    Create a promise-based guard that:
    - Automatically rejects if state changes
    - Helps cancel ongoing operations
    ]]
end

-- Example state handler structure
function StateMachine:ActionState(trove)
    return Promise.new(function(resolve, reject)
        -- 1. Add all state-specific resources to trove
        -- 2. Implement state logic with proper error handling
        -- 3. Return appropriate next state
        
        trove:Add(function()
            -- Cleanup code for this state
        end)
        
        -- State implementation here
    end)
end

function StateMachine:RespawnState(trove)
    return Promise.new(function(resolve, reject)
        -- Similar structure to ActionState
    end)
end

function StateMachine:RebootState(trove)
    return Promise.new(function(resolve, reject)
        -- 1. Full cleanup
        -- 2. Delay before restart
        -- 3. Resolve to initial state
    end)
end

return StateMachine