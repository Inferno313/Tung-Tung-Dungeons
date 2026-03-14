--!strict
-- GameManager.server.lua
-- Root game loop. Manages game states (Lobby → InGame → GameOver → Lobby)
-- and coordinates between DungeonManager, EnemyManager, LootManager,
-- and PlayerDataManager.

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants       = require(ReplicatedStorage.Data.Constants)
local Remotes         = require(ReplicatedStorage.Remotes)
local DungeonManager  = require(script.Parent.DungeonManager)
local EnemyManager    = require(script.Parent.EnemyManager)
local LootManager     = require(script.Parent.LootManager)
local PlayerDataManager = require(script.Parent.PlayerDataManager)

-- ─── Types ───────────────────────────────────────────────────────────────────

type GameState = "Lobby" | "Loading" | "InGame" | "BossRoom" | "GameOver"

type Session = {
    state: GameState,
    currentFloor: number,
    currentRoom: number,
    players: { Player },
    roomsCleared: number,
}

-- ─── State ───────────────────────────────────────────────────────────────────

local session: Session = {
    state        = "Lobby",
    currentFloor = 1,
    currentRoom  = 1,
    players      = {},
    roomsCleared = 0,
}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function broadcastToAll(remote: RemoteEvent, ...)
    for _, player in session.players do
        remote:FireClient(player, ...)
    end
end

local function allPlayersAlive(): boolean
    for _, player in session.players do
        local char = player.Character
        if not char then return false end
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return false end
    end
    return #session.players > 0
end

-- ─── State Transitions ───────────────────────────────────────────────────────

local function startGame()
    session.state        = "Loading"
    session.currentFloor = 1
    session.currentRoom  = 1
    session.roomsCleared = 0
    session.players      = Players:GetPlayers()

    -- Initialise player data for the run
    for _, player in session.players do
        PlayerDataManager.initRun(player)
    end

    -- Load the first dungeon floor
    DungeonManager.loadFloor(session.currentFloor, function()
        session.state = "InGame"
        broadcastToAll(Remotes.DungeonRoomLoaded, {
            floor = session.currentFloor,
            room  = session.currentRoom,
        })
        EnemyManager.spawnRoomEnemies(session.currentFloor, session.currentRoom)
    end)
end

local function advanceRoom()
    session.currentRoom  += 1
    session.roomsCleared += 1

    -- Notify clients
    broadcastToAll(Remotes.DungeonRoomLoaded, {
        floor = session.currentFloor,
        room  = session.currentRoom,
    })

    DungeonManager.loadRoom(session.currentFloor, session.currentRoom, function()
        local isBoss = DungeonManager.isBossRoom(session.currentFloor, session.currentRoom)
        if isBoss then
            session.state = "BossRoom"
            broadcastToAll(Remotes.BossSpawned, {
                floor = session.currentFloor,
            })
        end
        EnemyManager.spawnRoomEnemies(session.currentFloor, session.currentRoom)
    end)
end

local function advanceFloor()
    session.currentFloor += 1
    session.currentRoom   = 1

    broadcastToAll(Remotes.FloorCompleted, {
        floor = session.currentFloor - 1,
    })

    task.wait(3) -- brief pause between floors

    DungeonManager.loadFloor(session.currentFloor, function()
        session.state = "InGame"
        broadcastToAll(Remotes.DungeonRoomLoaded, {
            floor = session.currentFloor,
            room  = session.currentRoom,
        })
        EnemyManager.spawnRoomEnemies(session.currentFloor, session.currentRoom)
    end)
end

local function triggerGameOver(reason: string)
    session.state = "GameOver"
    broadcastToAll(Remotes.GameOver, {
        reason       = reason,
        floorReached = session.currentFloor,
        roomsCleared = session.roomsCleared,
    })

    -- Save run stats for all players
    for _, player in session.players do
        PlayerDataManager.saveRunStats(player, {
            floorReached = session.currentFloor,
            roomsCleared = session.roomsCleared,
        })
    end

    -- Reset after lobby delay
    task.wait(10)
    session.state = "Lobby"
end

-- ─── Remote Handlers ─────────────────────────────────────────────────────────

Remotes.RequestNextRoom.OnServerEvent:Connect(function(player: Player)
    if session.state ~= "InGame" and session.state ~= "BossRoom" then return end

    -- Only advance if all enemies in the room are defeated
    if not EnemyManager.isRoomCleared(session.currentFloor, session.currentRoom) then
        return
    end

    -- Drop loot for the cleared room
    LootManager.dropRoomLoot(session.currentFloor, session.players)

    local isLastRoom = DungeonManager.isLastRoom(session.currentFloor, session.currentRoom)
    if isLastRoom then
        advanceFloor()
    else
        advanceRoom()
    end
end)

-- ─── Death / GameOver Watcher ─────────────────────────────────────────────────

Players.PlayerAdded:Connect(function(player: Player)
    player.CharacterAdded:Connect(function(char: Model)
        local hum = char:WaitForChild("Humanoid") :: Humanoid
        hum.Died:Connect(function()
            if session.state == "InGame" or session.state == "BossRoom" then
                if not allPlayersAlive() then
                    triggerGameOver("All players defeated")
                end
            end
        end)
    end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
    -- Remove from active session
    for i, p in session.players do
        if p == player then
            table.remove(session.players, i)
            break
        end
    end
    if #session.players == 0 and session.state ~= "Lobby" then
        session.state = "Lobby"
        EnemyManager.despawnAll()
        DungeonManager.unload()
    end
end)

-- ─── Auto-Start When Enough Players ──────────────────────────────────────────

Players.PlayerAdded:Connect(function()
    if session.state == "Lobby" and #Players:GetPlayers() >= 1 then
        task.wait(5) -- brief countdown
        if session.state == "Lobby" then
            startGame()
        end
    end
end)

-- Also start immediately if a player is already in the game at script load
if #Players:GetPlayers() >= 1 then
    task.delay(5, function()
        if session.state == "Lobby" then
            startGame()
        end
    end)
end

print("[GameManager] Initialised — waiting for players.")
