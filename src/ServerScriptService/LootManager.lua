--!strict
-- LootManager.lua (ModuleScript, required by GameManager)
-- Handles loot drops after room clears: weapons, gold pickups, health orbs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local WeaponData     = require(ReplicatedStorage.Data.WeaponData)
local Constants      = require(ReplicatedStorage.Data.Constants)
local Util           = require(ReplicatedStorage.Modules.Util)
local Remotes        = require(ReplicatedStorage.Remotes)
local DungeonManager = require(script.Parent.DungeonManager)

local LootManager = {}

-- ─── Rarity Roll ─────────────────────────────────────────────────────────────

local RARITY_TABLE = {
    { item = "Legendary", weight = Constants.LEGENDARY_WEAPON_CHANCE },
    { item = "Epic",      weight = Constants.EPIC_WEAPON_CHANCE },
    { item = "Rare",      weight = Constants.RARE_WEAPON_CHANCE },
    { item = "Uncommon",  weight = 0.15 },
    { item = "Common",    weight = 0.78 },  -- fills remainder
}

local function rollRarity(): string
    return Util.weightedRandom(RARITY_TABLE)
end

-- Picks a random weapon of a given rarity. Returns nil if none found.
local function pickWeaponByRarity(rarity: string): string?
    local options = WeaponData.getByRarity(rarity)
    if #options == 0 then return nil end
    return options[math.random(#options)]
end

-- ─── Pickup Spawning ─────────────────────────────────────────────────────────

-- Spawns a glowing weapon pickup orb at the given position.
local function spawnWeaponPickup(weaponId: string, position: Vector3, players: { Player })
    local weaponDef = WeaponData[weaponId]
    if not weaponDef then return end

    local orb          = Instance.new("Part")
    orb.Name           = "WeaponPickup_" .. weaponId
    orb.Shape          = Enum.PartType.Ball
    orb.Size           = Vector3.new(2, 2, 2)
    orb.Position       = position + Vector3.new(0, 1.5, 0)
    orb.Anchored       = true
    orb.CanCollide     = false
    orb.Material       = Enum.Material.Neon
    orb.Color          = Constants.RARITY_COLORS[weaponDef.rarity] or Color3.new(1, 1, 1)
    orb.Parent         = workspace

    -- Bob animation
    local tweenUp = TweenService:Create(orb, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
        Position = position + Vector3.new(0, 2.5, 0)
    })
    tweenUp:Play()

    -- Proximity pickup detection
    local touched = false
    orb.Touched:Connect(function(hit: BasePart)
        if touched then return end
        local char = hit.Parent
        if not char then return end
        local player = game:GetService("Players"):GetPlayerFromCharacter(char :: Model)
        if not player then return end
        if not Util.contains(players, player) then return end

        touched = true
        tweenUp:Cancel()
        orb:Destroy()

        -- Notify client to open weapon-choice UI (if multiple weapons offered)
        Remotes.LootDropped:FireClient(player, {
            type     = "Weapon",
            weaponId = weaponId,
        })
    end)

    -- Auto-despawn after 30s
    task.delay(30, function()
        if orb and orb.Parent then
            orb:Destroy()
        end
    end)
end

-- Spawns a gold coin pickup.
local function spawnGoldPickup(amount: number, position: Vector3, players: { Player })
    local coin          = Instance.new("Part")
    coin.Name           = "GoldPickup"
    coin.Shape          = Enum.PartType.Cylinder
    coin.Size           = Vector3.new(0.3, 1.5, 1.5)
    coin.Position       = position + Vector3.new(0, 1, 0)
    coin.Anchored       = false
    coin.CanCollide     = true
    coin.Material       = Enum.Material.SmoothPlastic
    coin.Color          = Color3.fromRGB(255, 215, 0)
    coin.Parent         = workspace

    local touched = false
    coin.Touched:Connect(function(hit: BasePart)
        if touched then return end
        local char = hit.Parent
        if not char then return end
        local player = game:GetService("Players"):GetPlayerFromCharacter(char :: Model)
        if not player then return end

        touched = true
        coin:Destroy()

        Remotes.PlayerStatsUpdated:FireClient(player, {
            goldGained = amount,
        })
    end)

    task.delay(20, function()
        if coin and coin.Parent then coin:Destroy() end
    end)
end

-- Spawns a health orb pickup (restores 25% max HP).
local function spawnHealthOrb(position: Vector3, players: { Player })
    local orb          = Instance.new("Part")
    orb.Name           = "HealthOrb"
    orb.Shape          = Enum.PartType.Ball
    orb.Size           = Vector3.new(1.5, 1.5, 1.5)
    orb.Position       = position + Vector3.new(0, 1.5, 0)
    orb.Anchored       = true
    orb.CanCollide     = false
    orb.Material       = Enum.Material.Neon
    orb.Color          = Color3.fromRGB(255, 80, 80)
    orb.Parent         = workspace

    local touched = false
    orb.Touched:Connect(function(hit: BasePart)
        if touched then return end
        local char = hit.Parent
        if not char then return end
        local player = game:GetService("Players"):GetPlayerFromCharacter(char :: Model)
        if not player or not Util.contains(players, player) then return end

        local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if hum and hum.Health < hum.MaxHealth then
            touched = true
            orb:Destroy()
            hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * 0.25)
        end
    end)

    task.delay(20, function()
        if orb and orb.Parent then orb:Destroy() end
    end)
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Drops loot at the end of a combat room.
function LootManager.dropRoomLoot(floorNumber: number, players: { Player }, roomIndex: number)
    local lootPoints = DungeonManager.getRoomLootPoints(roomIndex)
    if #lootPoints == 0 then
        -- Fall back to random points near room centre
        lootPoints = {
            Vector3.new(math.random(-10, 10), 1, math.random(-10, 10)),
        }
    end

    -- Weapon drop (chance check)
    if math.random() < Constants.LOOT_DROP_CHANCE then
        local rarity   = rollRarity()
        local weaponId = pickWeaponByRarity(rarity)
        if weaponId then
            local pos = lootPoints[math.random(#lootPoints)]
            spawnWeaponPickup(weaponId, pos, players)
        end
    end

    -- Gold drop
    local goldAmount = Util.randomInt(
        Constants.GOLD_DROP_MIN * floorNumber,
        Constants.GOLD_DROP_MAX * floorNumber
    )
    local goldPos = lootPoints[math.random(#lootPoints)]
    spawnGoldPickup(goldAmount, goldPos + Vector3.new(2, 0, 0), players)

    -- Health orb (30% chance per room clear)
    if math.random() < 0.30 then
        local healthPos = lootPoints[math.random(#lootPoints)]
        spawnHealthOrb(healthPos + Vector3.new(-2, 0, 2), players)
    end
end

-- Drops guaranteed high-quality loot for boss kills.
function LootManager.dropBossLoot(bossId: string, position: Vector3, players: { Player })
    -- Guaranteed epic or legendary weapon
    local rarity   = math.random() < 0.35 and "Legendary" or "Epic"
    local weaponId = pickWeaponByRarity(rarity) or pickWeaponByRarity("Rare")
    if weaponId then
        spawnWeaponPickup(weaponId, position, players)
    end

    -- Big gold dump
    local goldAmount = Util.randomInt(150, 300)
    spawnGoldPickup(goldAmount, position + Vector3.new(3, 0, 0), players)

    -- Full health orb
    spawnHealthOrb(position + Vector3.new(-3, 0, 0), players)
end

return LootManager
