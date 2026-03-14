--!strict
-- StateMachine.lua
-- Generic finite state machine used by both enemies and the game loop.
-- Usage:
--   local fsm = StateMachine.new("Idle", { Idle = {}, Chase = {}, Attack = {} })
--   fsm:addTransition("Idle",   "playerInRange",  "Chase")
--   fsm:addTransition("Chase",  "playerInAttack", "Attack")
--   fsm:addTransition("Attack", "playerOutRange", "Idle")
--   fsm:onEnter("Chase", function(fsm) print("began chasing!") end)
--   fsm:update()   -- call each heartbeat; processes queued events

export type StateMachineInstance = {
    current: string,
    addTransition: (self: StateMachineInstance, from: string, event: string, to: string) -> (),
    onEnter:       (self: StateMachineInstance, state: string, fn: (StateMachineInstance) -> ()) -> (),
    onExit:        (self: StateMachineInstance, state: string, fn: (StateMachineInstance) -> ()) -> (),
    onUpdate:      (self: StateMachineInstance, state: string, fn: (StateMachineInstance, number) -> ()) -> (),
    send:          (self: StateMachineInstance, event: string) -> (),
    update:        (self: StateMachineInstance, dt: number) -> (),
    is:            (self: StateMachineInstance, state: string) -> boolean,
}

local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(initialState: string, states: { [string]: any }): StateMachineInstance
    local self = setmetatable({}, StateMachine) :: any
    self.current      = initialState
    self._states      = states
    self._transitions = {} :: { [string]: { [string]: string } }
    self._onEnter     = {} :: { [string]: (any) -> () }
    self._onExit      = {} :: { [string]: (any) -> () }
    self._onUpdate    = {} :: { [string]: (any, number) -> () }
    self._eventQueue  = {} :: { string }
    return self :: StateMachineInstance
end

function StateMachine:addTransition(from: string, event: string, to: string)
    if not self._transitions[from] then
        self._transitions[from] = {}
    end
    self._transitions[from][event] = to
end

function StateMachine:onEnter(state: string, fn: (any) -> ())
    self._onEnter[state] = fn
end

function StateMachine:onExit(state: string, fn: (any) -> ())
    self._onExit[state] = fn
end

function StateMachine:onUpdate(state: string, fn: (any, number) -> ())
    self._onUpdate[state] = fn
end

function StateMachine:send(event: string)
    table.insert(self._eventQueue, event)
end

function StateMachine:_transition(to: string)
    local exitFn = self._onExit[self.current]
    if exitFn then exitFn(self) end

    self.current = to

    local enterFn = self._onEnter[to]
    if enterFn then enterFn(self) end
end

function StateMachine:update(dt: number)
    -- Process all queued events first
    local queue = self._eventQueue
    self._eventQueue = {}

    for _, event in queue do
        local trans = self._transitions[self.current]
        if trans then
            local nextState = trans[event]
            if nextState then
                self:_transition(nextState)
            end
        end
    end

    -- Run the current state's update tick
    local updateFn = self._onUpdate[self.current]
    if updateFn then
        updateFn(self, dt)
    end
end

function StateMachine:is(state: string): boolean
    return self.current == state
end

return StateMachine
