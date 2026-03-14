--!strict
-- Remotes/init.lua
-- Creates and exposes all RemoteEvents and RemoteFunctions.
-- Required by both server and client:
--   local Remotes = require(game.ReplicatedStorage.Remotes)
--   Remotes.PlayerAttack:FireServer(...)

local Constants = require(script.Parent.Data.Constants)

-- On the server this module creates the remotes; on the client it waits for them.
local isServer = game:GetService("RunService"):IsServer()

local Remotes = {}

local function getOrCreate(name: string, className: string): Instance
    local existing = script:FindFirstChild(name)
    if existing then return existing end

    if isServer then
        local remote = Instance.new(className) :: any
        remote.Name   = name
        remote.Parent = script
        return remote
    else
        -- Client waits for the server to create the remote
        return script:WaitForChild(name, 10)
    end
end

-- ─── RemoteEvents ────────────────────────────────────────────────────────────
-- Player → Server
Remotes.PlayerAttack    = getOrCreate(Constants.Remotes.PlayerAttack,    "RemoteEvent") :: RemoteEvent
Remotes.PlayerDodge     = getOrCreate(Constants.Remotes.PlayerDodge,     "RemoteEvent") :: RemoteEvent
Remotes.PlayerInteract  = getOrCreate(Constants.Remotes.PlayerInteract,  "RemoteEvent") :: RemoteEvent
Remotes.EquipWeapon     = getOrCreate(Constants.Remotes.EquipWeapon,     "RemoteEvent") :: RemoteEvent
Remotes.RequestNextRoom = getOrCreate(Constants.Remotes.RequestNextRoom,  "RemoteEvent") :: RemoteEvent

-- Server → Player
Remotes.DungeonRoomLoaded    = getOrCreate(Constants.Remotes.DungeonRoomLoaded,    "RemoteEvent") :: RemoteEvent
Remotes.EnemyHealthUpdated   = getOrCreate(Constants.Remotes.EnemyHealthUpdated,   "RemoteEvent") :: RemoteEvent
Remotes.PlayerStatsUpdated   = getOrCreate(Constants.Remotes.PlayerStatsUpdated,   "RemoteEvent") :: RemoteEvent
Remotes.LootDropped          = getOrCreate(Constants.Remotes.LootDropped,          "RemoteEvent") :: RemoteEvent
Remotes.FloorCompleted       = getOrCreate(Constants.Remotes.FloorCompleted,       "RemoteEvent") :: RemoteEvent
Remotes.GameOver             = getOrCreate(Constants.Remotes.GameOver,             "RemoteEvent") :: RemoteEvent
Remotes.BossSpawned          = getOrCreate(Constants.Remotes.BossSpawned,          "RemoteEvent") :: RemoteEvent
Remotes.EnemyKilled          = getOrCreate(Constants.Remotes.EnemyKilled,          "RemoteEvent") :: RemoteEvent

return Remotes
