--!strict
-- EnemyManager.lua (ModuleScript, required by GameManager)
-- Spawns, updates, and destroys Brainrot enemies.
-- Each enemy runs an independent AI loop via a StateMachine.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService= game:GetService("PathfindingService")

local BrainrotData   = require(ReplicatedStorage.Data.BrainrotData)
local DungeonData    = require(ReplicatedStorage.Data.DungeonData)
local Constants      = require(ReplicatedStorage.Data.Constants)
local Util           = require(ReplicatedStorage.Modules.Util)
local StateMachine   = require(ReplicatedStorage.Modules.StateMachine)
local Remotes        = require(ReplicatedStorage.Remotes)
local DungeonManager = require(script.Parent.DungeonManager)

-- ─── Types ───────────────────────────────────────────────────────────────────

type EnemyInstance = {
    id:           string,
    def:          BrainrotData.BrainrotDef,
    model:        Model,
    humanoid:     Humanoid,
    rootPart:     BasePart,
    health:       number,
    maxHealth:    number,
    fsm:          StateMachine.StateMachineInstance,
    target:       Player?,
    abilityCooldowns: { [string]: number },
    pathUpdateTimer:  number,
    isAlive:      boolean,
}

-- ─── State ───────────────────────────────────────────────────────────────────

local EnemyManager = {}

local activeEnemies: { EnemyInstance } = {}
local roomKey: string = "0_0"   -- "floor_room"

-- ─── Private Helpers ─────────────────────────────────────────────────────────

-- Weighted random pick from the floor's spawn table.
local function pickBrainrotId(floorNumber: number): string
    local floorDef = DungeonData.getFloor(floorNumber)
    local entries  = {}
    for _, entry in floorDef.spawnTable do
        if floorNumber >= entry.minFloor then
            table.insert(entries, { item = entry.brainrotId, weight = entry.weight })
        end
    end
    if #entries == 0 then return "tung_tung_tung" end
    return Util.weightedRandom(entries)
end

-- Applies floor scaling to a base stat value.
local function scaleStatForFloor(base: number, scalePerFloor: number, floor: number): number
    return math.floor(base * (1 + scalePerFloor * (floor - 1)))
end

-- Finds the nearest alive player to a given position.
local function nearestPlayer(pos: Vector3): (Player?, number)
    local closest: Player?  = nil
    local closestDist       = math.huge
    for _, player in Players:GetPlayers() do
        local char = player.Character
        if not char then continue end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then continue end
        local dist = (root.Position - pos).Magnitude
        if dist < closestDist then
            closest     = player
            closestDist = dist
        end
    end
    return closest, closestDist
end

-- Broadcasts updated HP to all clients (shown on enemy health bars).
local function broadcastHealth(enemy: EnemyInstance)
    Remotes.EnemyHealthUpdated:FireAllClients({
        enemyId   = enemy.id .. tostring(enemy.model),
        health    = enemy.health,
        maxHealth = enemy.maxHealth,
        position  = enemy.rootPart.Position,
    })
end

-- Deals damage to an enemy and handles death.
local function damageEnemy(enemy: EnemyInstance, amount: number, attacker: Player?)
    if not enemy.isAlive then return end
    enemy.health = math.max(0, enemy.health - amount)
    broadcastHealth(enemy)

    -- Update health bar fill
    local hpFill = enemy.rootPart:FindFirstChild("BillboardGui") and
        enemy.rootPart.BillboardGui:FindFirstChild("HPBg") and
        enemy.rootPart.BillboardGui.HPBg:FindFirstChild("HPFill") :: Frame?
    if hpFill then
        hpFill.Size = UDim2.new(math.clamp(enemy.health / enemy.maxHealth, 0, 1), 0, 1, 0)
    end

    if enemy.health <= 0 then
        enemy.isAlive = false
        enemy.humanoid.Health = 0

        -- Award XP and gold
        if attacker then
            Remotes.PlayerStatsUpdated:FireClient(attacker, {
                xpGained   = enemy.def.xpReward,
                goldGained = Util.randomInt(enemy.def.goldReward.min, enemy.def.goldReward.max),
            })
        end

        -- Broadcast kill to all clients for kill feed
        Remotes.EnemyKilled:FireAllClients({
            displayName = enemy.def.displayName,
            killedBy    = attacker and attacker.Name or "Unknown",
            xpReward    = enemy.def.xpReward,
        })

        -- Brief death animation pause then destroy
        task.delay(1.5, function()
            if enemy.model and enemy.model.Parent then
                enemy.model:Destroy()
            end
        end)

        -- Check if this was the last enemy → broadcast RoomCleared
        local allDead = true
        for _, e in activeEnemies do
            if e.isAlive then
                allDead = false
                break
            end
        end
        if allDead then
            Remotes.RoomCleared:FireAllClients({})
        end
    end
end

-- ─── AI State Machine Builder ─────────────────────────────────────────────────

local function buildEnemyFSM(enemy: EnemyInstance): StateMachine.StateMachineInstance
    local fsm = StateMachine.new("Idle", {
        Idle    = {},
        Chase   = {},
        Attack  = {},
        Ability = {},
        Dead    = {},
    })

    -- ── Transitions ────────────────────────────────────────────────────────
    fsm:addTransition("Idle",    "playerInRange",     "Chase")
    fsm:addTransition("Chase",   "playerInAttack",    "Attack")
    fsm:addTransition("Chase",   "playerOutRange",    "Idle")
    fsm:addTransition("Attack",  "playerOutAttack",   "Chase")
    fsm:addTransition("Attack",  "playerOutRange",    "Idle")
    fsm:addTransition("Attack",  "abilityReady",      "Ability")
    fsm:addTransition("Ability", "abilityCast",       "Chase")
    fsm:addTransition("Chase",   "abilityReady",      "Ability")
    fsm:addTransition("Idle",    "died",              "Dead")
    fsm:addTransition("Chase",   "died",              "Dead")
    fsm:addTransition("Attack",  "died",              "Dead")
    fsm:addTransition("Ability", "died",              "Dead")

    -- ── Update Ticks ───────────────────────────────────────────────────────
    fsm:onUpdate("Idle", function(_, dt)
        if not enemy.isAlive then fsm:send("died") return end
        local target, dist = nearestPlayer(enemy.rootPart.Position)
        if target and dist <= Constants.ENEMY_AGGRO_RANGE then
            enemy.target = target
            fsm:send("playerInRange")
        end
    end)

    fsm:onUpdate("Chase", function(_, dt)
        if not enemy.isAlive then fsm:send("died") return end

        local target = enemy.target
        if not target or not target.Character then
            fsm:send("playerOutRange")
            return
        end

        local targetRoot = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not targetRoot then
            fsm:send("playerOutRange")
            return
        end

        local dist = (targetRoot.Position - enemy.rootPart.Position).Magnitude

        if dist > Constants.ENEMY_DEAGGRO_RANGE then
            enemy.target = nil
            fsm:send("playerOutRange")
            return
        end

        -- Check ability cooldowns
        for _, abilityDef in enemy.def.abilities do
            local cooldown = enemy.abilityCooldowns[abilityDef.name] or 0
            if cooldown <= 0 and dist <= abilityDef.range then
                fsm:send("abilityReady")
                return
            end
        end

        if dist <= enemy.def.attackRange then
            fsm:send("playerInAttack")
            return
        end

        -- Pathfind towards target
        enemy.pathUpdateTimer -= dt
        if enemy.pathUpdateTimer <= 0 then
            enemy.pathUpdateTimer = Constants.ENEMY_PATH_UPDATE_RATE
            local path = PathfindingService:CreatePath({
                AgentRadius     = 2,
                AgentHeight     = 5,
                AgentCanJump    = false,
                AgentJumpHeight = 0,
            })
            path:ComputeAsync(enemy.rootPart.Position, targetRoot.Position)
            if path.Status == Enum.PathStatus.Success then
                local waypoints = path:GetWaypoints()
                if #waypoints >= 2 then
                    enemy.humanoid:MoveTo(waypoints[2].Position)
                end
            else
                enemy.humanoid:MoveTo(targetRoot.Position)
            end
        end

        -- Decrement ability cooldowns
        for abilityName, cd in enemy.abilityCooldowns do
            enemy.abilityCooldowns[abilityName] = math.max(0, cd - dt)
        end
    end)

    fsm:onEnter("Attack", function(_)
        if not enemy.isAlive then return end
        local target = enemy.target
        if not target or not target.Character then return end

        -- Stop movement
        enemy.humanoid:MoveTo(enemy.rootPart.Position)

        -- Face the target
        local targetRoot = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if targetRoot then
            local lookAt = Vector3.new(targetRoot.Position.X, enemy.rootPart.Position.Y, targetRoot.Position.Z)
            enemy.rootPart.CFrame = CFrame.new(enemy.rootPart.Position, lookAt)
        end

        -- Deal damage
        local targetHum = target.Character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if targetHum and targetHum.Health > 0 then
            targetHum:TakeDamage(enemy.def.damage)
        end

        -- Return to chase after attack cooldown
        task.delay(1 / enemy.def.attackRate, function()
            if enemy.isAlive and fsm:is("Attack") then
                local _, dist = nearestPlayer(enemy.rootPart.Position)
                if dist > enemy.def.attackRange then
                    fsm:send("playerOutAttack")
                end
            end
        end)
    end)

    fsm:onEnter("Ability", function(_)
        if not enemy.isAlive then return end
        -- Find a ready ability with a target in range
        for _, abilityDef in enemy.def.abilities do
            local cooldown = enemy.abilityCooldowns[abilityDef.name] or 0
            local target   = enemy.target
            if cooldown > 0 or not target or not target.Character then continue end

            local targetRoot = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not targetRoot then continue end
            local dist = (targetRoot.Position - enemy.rootPart.Position).Magnitude
            if dist > abilityDef.range then continue end

            -- Cast the ability
            enemy.abilityCooldowns[abilityDef.name] = abilityDef.cooldown

            -- Apply ability damage
            if abilityDef.damage > 0 then
                local targetHum = target.Character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                if targetHum and targetHum.Health > 0 then
                    targetHum:TakeDamage(abilityDef.damage)
                end
            end

            -- TODO: archetype-specific ability VFX / movement (ChargeRush, BombBarrage, etc.)
            -- This is where per-ability logic is implemented in Phase 3.
            break
        end

        task.delay(0.8, function()
            if enemy.isAlive then
                fsm:send("abilityCast")
            end
        end)
    end)

    return fsm
end

-- ─── Spawn ───────────────────────────────────────────────────────────────────

-- Creates and registers a single enemy at the given world position.
local function spawnEnemy(brainrotId: string, position: Vector3, floorNumber: number)
    local def = BrainrotData[brainrotId]
    if not def then
        warn("[EnemyManager] Unknown brainrot id:", brainrotId)
        return
    end

    local floorDef = DungeonData.getFloor(floorNumber)
    local scaledHealth = scaleStatForFloor(
        def.health,
        Constants.ENEMY_HEALTH_SCALE_PER_FLOOR,
        floorNumber
    ) * floorDef.enemyModifiers.healthMultiplier

    -- Build a simple placeholder model (artists replace via Roblox Studio)
    local model = Instance.new("Model")
    model.Name  = def.displayName

    local rootPart          = Instance.new("Part")
    rootPart.Name           = "HumanoidRootPart"
    rootPart.Size           = Vector3.new(4, 6, 4)
    rootPart.Position       = position
    rootPart.BrickColor     = BrickColor.new("Bright red")
    rootPart.Material       = Enum.Material.Neon
    rootPart.Anchored       = false
    rootPart.Parent         = model

    local humanoid          = Instance.new("Humanoid")
    humanoid.MaxHealth      = scaledHealth
    humanoid.Health         = scaledHealth
    humanoid.WalkSpeed      = def.speed * floorDef.enemyModifiers.speedMultiplier
    humanoid.Parent         = model

    -- Billboard health bar above enemy
    local billboard         = Instance.new("BillboardGui")
    billboard.Size          = UDim2.new(0, 100, 0, 28)
    billboard.StudsOffset   = Vector3.new(0, 5, 0)
    billboard.AlwaysOnTop   = false
    billboard.Parent        = rootPart

    local nameLabel         = Instance.new("TextLabel")
    nameLabel.Size          = UDim2.new(1, 0, 0.45, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3    = Color3.new(1, 0.2, 0.2)
    nameLabel.Font          = Enum.Font.GothamBold
    nameLabel.TextSize      = 11
    nameLabel.Text          = def.displayName
    nameLabel.Parent        = billboard

    local hpBg              = Instance.new("Frame")
    hpBg.Name               = "HPBg"
    hpBg.Size               = UDim2.new(1, 0, 0.45, 0)
    hpBg.Position           = UDim2.new(0, 0, 0.55, 0)
    hpBg.BackgroundColor3   = Color3.fromRGB(40, 0, 0)
    hpBg.BorderSizePixel    = 0
    hpBg.Parent             = billboard

    local hpFill            = Instance.new("Frame")
    hpFill.Name             = "HPFill"
    hpFill.Size             = UDim2.new(1, 0, 1, 0)
    hpFill.BackgroundColor3 = Color3.fromRGB(220, 30, 30)
    hpFill.BorderSizePixel  = 0
    hpFill.Parent           = hpBg

    model.PrimaryPart       = rootPart
    model.Parent            = workspace

    -- Build ability cooldown table (all start at 0)
    local abilityCooldowns: { [string]: number } = {}
    for _, abilityDef in def.abilities do
        abilityCooldowns[abilityDef.name] = 0
    end

    local enemy: EnemyInstance = {
        id               = brainrotId,
        def              = def,
        model            = model,
        humanoid         = humanoid,
        rootPart         = rootPart,
        health           = scaledHealth,
        maxHealth        = scaledHealth,
        fsm              = nil :: any,
        target           = nil,
        abilityCooldowns = abilityCooldowns,
        pathUpdateTimer  = 0,
        isAlive          = true,
    }

    enemy.fsm = buildEnemyFSM(enemy)

    -- Wire Humanoid.Died to our damage system
    humanoid.Died:Connect(function()
        enemy.isAlive = false
    end)

    table.insert(activeEnemies, enemy)
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Spawns all enemies for the given room using the floor's spawn table.
function EnemyManager.spawnRoomEnemies(floorNumber: number, roomIndex: number)
    roomKey = string.format("%d_%d", floorNumber, roomIndex)

    local spawnPoints = DungeonManager.getRoomSpawnPoints(roomIndex)
    if #spawnPoints == 0 then return end

    local floorDef   = DungeonData.getFloor(floorNumber)
    local baseCount  = math.random(3, Constants.MAX_ENEMIES_PER_ROOM)
    local scaledCount= math.floor(baseCount * (1 + Constants.ENEMY_COUNT_SCALE_PER_FLOOR * (floorNumber - 1)))
    local count      = math.min(scaledCount, #spawnPoints)

    -- Boss room: spawn boss only
    if DungeonManager.isBossRoom(floorNumber, roomIndex) and floorDef.bossId then
        local bossPoint = spawnPoints[1]
        spawnEnemy(floorDef.bossId, bossPoint, floorNumber)
        return
    end

    local shuffled = Util.shuffle(Util.shallowCopy(spawnPoints))
    for i = 1, count do
        local brainrotId = pickBrainrotId(floorNumber)
        spawnEnemy(brainrotId, shuffled[i] or spawnPoints[1], floorNumber)
    end
end

-- Returns true if all enemies in the current room are dead.
function EnemyManager.isRoomCleared(_floor: number, _room: number): boolean
    for _, enemy in activeEnemies do
        if enemy.isAlive then return false end
    end
    return true
end

-- Destroys all active enemies (e.g., on floor unload).
function EnemyManager.despawnAll()
    for _, enemy in activeEnemies do
        if enemy.model and enemy.model.Parent then
            enemy.model:Destroy()
        end
    end
    activeEnemies = {}
end

-- Called by the attack remote to deal damage to the nearest enemy.
function EnemyManager.handlePlayerAttack(player: Player, weaponId: string)
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return end

    local WeaponData = require(ReplicatedStorage.Data.WeaponData)
    local weaponDef  = WeaponData[weaponId]
    if not weaponDef then return end

    -- Find enemies within weapon range
    for _, enemy in activeEnemies do
        if not enemy.isAlive then continue end
        local dist = (enemy.rootPart.Position - root.Position).Magnitude
        if dist <= weaponDef.range then
            damageEnemy(enemy, weaponDef.damage, player)
            if not weaponDef.isPiercing then break end  -- single-target stops at first hit
        end
    end
end

-- ─── Heartbeat Loop ──────────────────────────────────────────────────────────

RunService.Heartbeat:Connect(function(dt: number)
    for _, enemy in activeEnemies do
        if enemy.isAlive then
            enemy.fsm:update(dt)
        end
    end
end)

-- ─── Remote Wiring ───────────────────────────────────────────────────────────

local Remotes2 = require(ReplicatedStorage.Remotes)
Remotes2.PlayerAttack.OnServerEvent:Connect(function(player: Player, weaponId: string)
    EnemyManager.handlePlayerAttack(player, weaponId)
end)

return EnemyManager
