--!strict
-- GameManager.server.lua
-- Root game loop. Manages game states (Lobby → InGame → GameOver → Lobby)
-- and coordinates between DungeonManager, EnemyManager, LootManager,
-- and PlayerDataManager.
-- Phase 2: door locking, room-clear detection, upgrade station interaction, boss loot.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants         = require(ReplicatedStorage.Data.Constants)
local DungeonData       = require(ReplicatedStorage.Data.DungeonData)
local BrainrotData      = require(ReplicatedStorage.Data.BrainrotData)
local Remotes           = require(ReplicatedStorage.Remotes)
local DungeonManager    = require(script.Parent.DungeonManager)
local EnemyManager      = require(script.Parent.EnemyManager)
local LootManager       = require(script.Parent.LootManager)
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

-- Lock doors if the current room is a combat/boss room.
local function lockCurrentRoomDoors()
    if DungeonManager.isRoomLockable(session.currentFloor, session.currentRoom) then
        DungeonManager.lockRoomDoors(session.currentRoom)
    end
end

-- ─── State Transitions ───────────────────────────────────────────────────────

local function startGame()
    session.state        = "Loading"
    session.currentFloor = 1
    session.currentRoom  = 1
    session.roomsCleared = 0
    session.players      = Players:GetPlayers()

    for _, player in session.players do
        PlayerDataManager.initRun(player)
    end

    DungeonManager.loadFloor(session.currentFloor, function()
        session.state = "InGame"
        broadcastToAll(Remotes.DungeonRoomLoaded, {
            floor      = session.currentFloor,
            room       = session.currentRoom,
            roomTypes  = DungeonManager.getFloorRoomTypes(),
            totalRooms = #DungeonManager.getFloorRoomTypes(),
        })
        EnemyManager.spawnRoomEnemies(session.currentFloor, session.currentRoom)
        lockCurrentRoomDoors()
    end)
end

local function advanceRoom()
    session.currentRoom  += 1
    session.roomsCleared += 1

    broadcastToAll(Remotes.DungeonRoomLoaded, {
        floor      = session.currentFloor,
        room       = session.currentRoom,
        roomTypes  = DungeonManager.getFloorRoomTypes(),
        totalRooms = #DungeonManager.getFloorRoomTypes(),
    })

    DungeonManager.loadRoom(session.currentFloor, session.currentRoom, function()
        local isBoss = DungeonManager.isBossRoom(session.currentFloor, session.currentRoom)
        if isBoss then
            session.state = "BossRoom"
            local floorDef  = DungeonData.getFloor(session.currentFloor)
            local bossDef   = floorDef.bossId and BrainrotData[floorDef.bossId]
            broadcastToAll(Remotes.BossSpawned, {
                floor    = session.currentFloor,
                bossName = bossDef and bossDef.displayName or "???",
            })
        end
        EnemyManager.spawnRoomEnemies(session.currentFloor, session.currentRoom)
        lockCurrentRoomDoors()
    end)
end

local function advanceFloor()
    session.currentFloor += 1
    session.currentRoom   = 1

    broadcastToAll(Remotes.FloorCompleted, {
        floor = session.currentFloor - 1,
    })

    task.wait(3)

    DungeonManager.loadFloor(session.currentFloor, function()
        session.state = "InGame"
        broadcastToAll(Remotes.DungeonRoomLoaded, {
            floor      = session.currentFloor,
            room       = session.currentRoom,
            roomTypes  = DungeonManager.getFloorRoomTypes(),
            totalRooms = #DungeonManager.getFloorRoomTypes(),
        })
        EnemyManager.spawnRoomEnemies(session.currentFloor, session.currentRoom)
        lockCurrentRoomDoors()
    end)
end

local function triggerGameOver(reason: string)
    session.state = "GameOver"
    broadcastToAll(Remotes.GameOver, {
        reason       = reason,
        floorReached = session.currentFloor,
        roomsCleared = session.roomsCleared,
    })

    for _, player in session.players do
        PlayerDataManager.saveRunStats(player, {
            floorReached = session.currentFloor,
            roomsCleared = session.roomsCleared,
        })
    end

    task.wait(10)
    session.state = "Lobby"
end

-- ─── Room-Clear Heartbeat ─────────────────────────────────────────────────────
-- Polls for room clears every 0.5 s, unlocks doors, and fires boss loot.

local roomClearTimer      = 0
local roomClearHandled    = false

RunService.Heartbeat:Connect(function(dt: number)
    if session.state ~= "InGame" and session.state ~= "BossRoom" then return end

    roomClearTimer -= dt
    if roomClearTimer > 0 then return end
    roomClearTimer = 0.5

    if roomClearHandled then return end
    if not EnemyManager.isRoomCleared(session.currentFloor, session.currentRoom) then return end

    roomClearHandled = true

    -- Unlock doors
    DungeonManager.unlockRoomDoors(session.currentRoom)

    -- Drop boss loot automatically when the boss room is cleared
    if session.state == "BossRoom" then
        local bossPos = EnemyManager.getLastBossPosition()
        if bossPos then
            LootManager.dropBossLoot("boss", bossPos, session.players)
        end
        session.state = "InGame"  -- allow RequestNextRoom
    end

    -- Notify clients the room is clear
    broadcastToAll(Remotes.RoomCleared, {
        floor = session.currentFloor,
        room  = session.currentRoom,
    })
end)

-- ─── Remote Handlers ─────────────────────────────────────────────────────────

Remotes.RequestNextRoom.OnServerEvent:Connect(function(_player: Player)
    if session.state ~= "InGame" and session.state ~= "BossRoom" then return end
    if not EnemyManager.isRoomCleared(session.currentFloor, session.currentRoom) then return end

    -- Reset the room-clear flag for the next room
    roomClearHandled = false

    LootManager.dropRoomLoot(session.currentFloor, session.players, session.currentRoom)

    local isLastRoom = DungeonManager.isLastRoom(session.currentFloor, session.currentRoom)
    if isLastRoom then
        advanceFloor()
    else
        advanceRoom()
    end
end)

-- Player presses E: check if they're near an upgrade station.
Remotes.PlayerInteract.OnServerEvent:Connect(function(player: Player)
    if session.state ~= "InGame" and session.state ~= "BossRoom" then return end

    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return end

    local stations = DungeonManager.getRoomUpgradeStations(session.currentRoom)
    for _, stationPos in stations do
        if (stationPos - root.Position).Magnitude <= 8 then
            local weaponId    = PlayerDataManager.getEquippedWeapon(player)
            local weaponLevel = PlayerDataManager.getWeaponLevel(player)
            local upgradeCost = Constants.WEAPON_UPGRADE_COST_BASE * weaponLevel
            Remotes.UpgradeStationNearby:FireClient(player, {
                weaponId    = weaponId,
                weaponLevel = weaponLevel,
                upgradeCost = upgradeCost,
            })
            return
        end
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

-- ─── Auto-Start ───────────────────────────────────────────────────────────────

Players.PlayerAdded:Connect(function()
    if session.state == "Lobby" and #Players:GetPlayers() >= 1 then
        task.wait(5)
        if session.state == "Lobby" then
            startGame()
        end
    end
end)

if #Players:GetPlayers() >= 1 then
    task.delay(5, function()
        if session.state == "Lobby" then
            startGame()
        end
    end)
end

print("[GameManager] Initialised — waiting for players.")
