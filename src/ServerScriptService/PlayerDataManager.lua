--!strict
-- PlayerDataManager.lua (ModuleScript, required by GameManager)
-- Manages persistent player data (levels, gold, unlocked weapons, best runs)
-- using Roblox DataStoreService. Also tracks per-run transient state.

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Data.Constants)
local Util      = require(ReplicatedStorage.Modules.Util)
local Remotes   = require(ReplicatedStorage.Remotes)

-- ─── Types ───────────────────────────────────────────────────────────────────

type PersistentData = {
    level:           number,
    xp:              number,
    gold:            number,
    totalRuns:       number,
    bestFloor:       number,
    unlockedWeapons: { string },
    equippedWeapon:  string,
    settings: {
        musicVolume: number,
        sfxVolume:   number,
    },
}

type RunData = {
    currentXp:      number,
    currentGold:    number,
    equippedWeapon: string,
    weaponLevel:    number,
}

-- ─── Constants ───────────────────────────────────────────────────────────────

local DATA_STORE_NAME = "TungTungDungeons_v1"
local DATA_STORE_KEY_PREFIX = "Player_"

local DEFAULT_DATA: PersistentData = {
    level           = 1,
    xp              = 0,
    gold            = 0,
    totalRuns       = 0,
    bestFloor       = 0,
    unlockedWeapons = { "wooden_club" },
    equippedWeapon  = "wooden_club",
    settings = {
        musicVolume = 0.5,
        sfxVolume   = 0.8,
    },
}

-- ─── State ───────────────────────────────────────────────────────────────────

local PlayerDataManager = {}

local dataStore: DataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)

-- Persistent data (loaded from DataStore)
local persistentData: { [number]: PersistentData } = {}

-- Transient run data (only for current run, lost on game over)
local runData: { [number]: RunData } = {}

-- ─── DataStore Helpers ────────────────────────────────────────────────────────

local function loadData(player: Player): PersistentData
    local key  = DATA_STORE_KEY_PREFIX .. player.UserId
    local success, data = pcall(function()
        return dataStore:GetAsync(key)
    end)

    if not success or not data then
        warn("[PlayerDataManager] Failed to load data for", player.Name, "— using defaults")
        return Util.shallowCopy(DEFAULT_DATA) :: PersistentData
    end

    -- Merge saved data over defaults (handles missing keys on schema updates)
    local merged = Util.shallowCopy(DEFAULT_DATA) :: any
    for k, v in data do
        merged[k] = v
    end
    return merged :: PersistentData
end

local function saveData(player: Player)
    local pData = persistentData[player.UserId]
    if not pData then return end

    local key = DATA_STORE_KEY_PREFIX .. player.UserId
    local success, err = pcall(function()
        dataStore:SetAsync(key, pData)
    end)

    if not success then
        warn("[PlayerDataManager] Failed to save data for", player.Name, ":", err)
    end
end

-- ─── XP / Levelling ──────────────────────────────────────────────────────────

local function checkLevelUp(player: Player)
    local pData = persistentData[player.UserId]
    if not pData then return end

    local xpNeeded = Util.xpForLevel(pData.level + 1, Constants.XP_PER_LEVEL_BASE, Constants.XP_PER_LEVEL_EXPONENT)
    while pData.xp >= xpNeeded and pData.level < Constants.MAX_PLAYER_LEVEL do
        pData.xp    -= xpNeeded
        pData.level += 1
        xpNeeded     = Util.xpForLevel(pData.level + 1, Constants.XP_PER_LEVEL_BASE, Constants.XP_PER_LEVEL_EXPONENT)
        -- TODO: unlock abilities / passive bonuses on level up
    end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Called when a player joins. Loads their data from the DataStore.
function PlayerDataManager.onPlayerAdded(player: Player)
    local pData               = loadData(player)
    persistentData[player.UserId] = pData

    -- Push initial stats to client
    Remotes.PlayerStatsUpdated:FireClient(player, {
        level          = pData.level,
        xp             = pData.xp,
        gold           = pData.gold,
        equippedWeapon = pData.equippedWeapon,
    })
end

-- Called when a player leaves. Saves their data.
function PlayerDataManager.onPlayerRemoving(player: Player)
    saveData(player)
    persistentData[player.UserId] = nil
    runData[player.UserId]        = nil
end

-- Initialises transient run data at the start of a new dungeon run.
function PlayerDataManager.initRun(player: Player)
    local pData = persistentData[player.UserId]
    if not pData then return end

    runData[player.UserId] = {
        currentXp      = 0,
        currentGold    = 0,
        equippedWeapon = pData.equippedWeapon,
        weaponLevel    = 1,
    }
end

-- Awards XP and gold from a kill; called by EnemyManager via remote.
function PlayerDataManager.awardKillRewards(player: Player, xp: number, gold: number)
    local pData = persistentData[player.UserId]
    local rData = runData[player.UserId]
    if not pData or not rData then return end

    pData.xp             += xp
    pData.gold           += gold
    rData.currentXp      += xp
    rData.currentGold    += gold

    checkLevelUp(player)

    Remotes.PlayerStatsUpdated:FireClient(player, {
        level     = pData.level,
        xp        = pData.xp,
        gold      = pData.gold,
        xpGained  = xp,
        goldGained= gold,
    })
end

-- Saves end-of-run statistics (called on GameOver or floor completion).
function PlayerDataManager.saveRunStats(player: Player, stats: { floorReached: number, roomsCleared: number })
    local pData = persistentData[player.UserId]
    if not pData then return end

    pData.totalRuns += 1
    if stats.floorReached > pData.bestFloor then
        pData.bestFloor = stats.floorReached
    end

    saveData(player)
end

-- Equips a weapon for the player (validates ownership).
function PlayerDataManager.equipWeapon(player: Player, weaponId: string)
    local pData = persistentData[player.UserId]
    if not pData then return end

    if not Util.contains(pData.unlockedWeapons, weaponId) then
        warn("[PlayerDataManager]", player.Name, "tried to equip locked weapon:", weaponId)
        return
    end

    pData.equippedWeapon = weaponId
    local rData = runData[player.UserId]
    if rData then
        rData.equippedWeapon = weaponId
    end

    Remotes.PlayerStatsUpdated:FireClient(player, {
        equippedWeapon = weaponId,
    })
end

-- Unlocks a weapon for the player (e.g., after picking up a drop).
function PlayerDataManager.unlockWeapon(player: Player, weaponId: string)
    local pData = persistentData[player.UserId]
    if not pData then return end

    if not Util.contains(pData.unlockedWeapons, weaponId) then
        table.insert(pData.unlockedWeapons, weaponId)
    end
end

-- Returns the player's currently equipped weapon ID (for combat validation).
function PlayerDataManager.getEquippedWeapon(player: Player): string
    local rData = runData[player.UserId]
    if rData then return rData.equippedWeapon end
    local pData = persistentData[player.UserId]
    if pData then return pData.equippedWeapon end
    return "wooden_club"
end

-- ─── Hook into Player Events ─────────────────────────────────────────────────

Players.PlayerAdded:Connect(PlayerDataManager.onPlayerAdded)
Players.PlayerRemoving:Connect(PlayerDataManager.onPlayerRemoving)

-- Load data for any players already in the game when this script runs
for _, player in Players:GetPlayers() do
    PlayerDataManager.onPlayerAdded(player)
end

-- ─── Remote Handlers ─────────────────────────────────────────────────────────

Remotes.EquipWeapon.OnServerEvent:Connect(function(player: Player, weaponId: string)
    PlayerDataManager.equipWeapon(player, weaponId)
end)

-- Award kill rewards triggered by EnemyManager via PlayerStatsUpdated remote
Remotes.PlayerStatsUpdated.OnServerEvent = nil  -- One-way (server→client only)

return PlayerDataManager
