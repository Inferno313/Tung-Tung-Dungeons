--!strict
-- EnemyManager.lua (ModuleScript, required by GameManager)
-- Spawns, updates, and destroys Brainrot enemies.
-- Each enemy runs an independent AI loop via a StateMachine.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService= game:GetService("PathfindingService")

local BrainrotData      = require(ReplicatedStorage.Data.BrainrotData)
local DungeonData       = require(ReplicatedStorage.Data.DungeonData)
local Constants         = require(ReplicatedStorage.Data.Constants)
local Util              = require(ReplicatedStorage.Modules.Util)
local StateMachine      = require(ReplicatedStorage.Modules.StateMachine)
local Remotes           = require(ReplicatedStorage.Remotes)
local DungeonManager    = require(script.Parent.DungeonManager)
local PlayerDataManager = require(script.Parent.PlayerDataManager)

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
local lastBossDeathPosition: Vector3? = nil

local PROJECTILE_SPEED = 80  -- studs per second

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

    if enemy.health <= 0 then
        enemy.isAlive = false
        enemy.humanoid.Health = 0

        -- Track boss death position for loot drop
        if enemy.def.archetype == "Boss" then
            lastBossDeathPosition = enemy.rootPart.Position
        end

        -- Award XP and gold through PlayerDataManager (persists to DataStore)
        if attacker then
            local gold = Util.randomInt(enemy.def.goldReward.min, enemy.def.goldReward.max)
            PlayerDataManager.awardKillRewards(attacker, enemy.def.xpReward, gold)
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
    rootPart.Size           = Vector3.new(2, 5, 2)
    rootPart.Position       = position
    rootPart.BrickColor     = BrickColor.new("Bright red")
    rootPart.Anchored       = false
    rootPart.Parent         = model

    local humanoid          = Instance.new("Humanoid")
    humanoid.MaxHealth      = scaledHealth
    humanoid.Health         = scaledHealth
    humanoid.WalkSpeed      = def.speed * floorDef.enemyModifiers.speedMultiplier
    humanoid.Parent         = model

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

-- ─── Projectile System ───────────────────────────────────────────────────────

local WeaponData = require(ReplicatedStorage.Data.WeaponData)

local PROJECTILE_COLORS: { [string]: Color3 } = {
    Fire     = Color3.fromRGB(255, 120,  20),
    Ice      = Color3.fromRGB(100, 210, 255),
    Electric = Color3.fromRGB(255, 240,  50),
    Chaos    = Color3.fromRGB(200,  80, 255),
    None     = Color3.fromRGB(200, 200, 200),
}

local function spawnProjectile(player: Player, weaponDef: WeaponData.WeaponDef, origin: Vector3, direction: Vector3)
    local proj           = Instance.new("Part")
    proj.Name            = "Projectile_" .. weaponDef.id
    proj.Shape           = Enum.PartType.Ball
    proj.Size            = Vector3.new(0.7, 0.7, 0.7)
    proj.CFrame          = CFrame.new(origin + Vector3.new(0, 1.2, 0))
    proj.Material        = Enum.Material.Neon
    proj.Color           = PROJECTILE_COLORS[weaponDef.element] or PROJECTILE_COLORS.None
    proj.CastShadow      = false
    proj.CanCollide      = false
    proj.Parent          = workspace

    local bv         = Instance.new("BodyVelocity")
    bv.Velocity      = direction.Unit * PROJECTILE_SPEED
    bv.MaxForce      = Vector3.new(1e5, 1e5, 1e5)
    bv.Parent        = proj

    local hitHandled = false

    proj.Touched:Connect(function(part: BasePart)
        if hitHandled then return end
        -- Ignore touches from parts not belonging to an enemy
        for _, enemy in activeEnemies do
            if not enemy.isAlive then continue end
            if part == enemy.rootPart or part:IsDescendantOf(enemy.model) then
                hitHandled = not weaponDef.isPiercing  -- piercing keeps going
                local hitPos = proj.Position

                if weaponDef.aoeRadius > 0 then
                    -- AoE explosion: damage all enemies in radius
                    for _, aoeEnemy in activeEnemies do
                        if not aoeEnemy.isAlive then continue end
                        if (aoeEnemy.rootPart.Position - hitPos).Magnitude <= weaponDef.aoeRadius then
                            damageEnemy(aoeEnemy, weaponDef.damage, player)
                        end
                    end
                else
                    damageEnemy(enemy, weaponDef.damage, player)
                end

                if hitHandled then
                    proj:Destroy()
                end
                return
            end
        end
    end)

    -- Auto-destroy after weapon range is exhausted
    task.delay(weaponDef.range / PROJECTILE_SPEED + 0.1, function()
        if proj and proj.Parent then proj:Destroy() end
    end)
end

-- ─── Player Attack Handler ────────────────────────────────────────────────────

-- Called by the attack remote to deal damage.
-- Melee: 120° arc in front of player, respects aoeRadius for wide swings.
-- Ranged / Magic: spawns a visible projectile.
function EnemyManager.handlePlayerAttack(player: Player, weaponId: string)
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return end

    local weaponDef = WeaponData[weaponId]
    if not weaponDef then return end

    -- ── Ranged / Magic → projectile ────────────────────────────────────────
    if weaponDef.class == "Ranged" or weaponDef.class == "Magic" then
        local aimDir = root.CFrame.LookVector
        if weaponDef.isHoming then
            -- Override direction: aim at nearest enemy
            local nearest, _ = nearestPlayer(root.Position)
            -- nearestPlayer finds players; we need nearest enemy instead
            local closestDist = math.huge
            for _, enemy in activeEnemies do
                if not enemy.isAlive then continue end
                local d = (enemy.rootPart.Position - root.Position).Magnitude
                if d < closestDist then
                    closestDist = d
                    aimDir = (enemy.rootPart.Position - root.Position).Unit
                end
            end
        end
        spawnProjectile(player, weaponDef, root.Position, aimDir)
        return
    end

    -- ── Melee → arc + optional AoE ─────────────────────────────────────────
    local lookDir    = root.CFrame.LookVector
    local flatLook   = Vector3.new(lookDir.X, 0, lookDir.Z)
    local hasAoE     = weaponDef.aoeRadius > 0
    local hitRange   = hasAoE and weaponDef.aoeRadius or weaponDef.range
    -- ARC_DOT: cos(60°) = 0.5 for 120° total cone; AoE ignores arc (hits all around)
    local ARC_DOT    = 0.5

    for _, enemy in activeEnemies do
        if not enemy.isAlive then continue end
        local offset = enemy.rootPart.Position - root.Position
        local dist   = offset.Magnitude
        if dist > hitRange then continue end

        if not hasAoE then
            -- Arc check: enemy must be within 60° of player's look direction
            local flatOffset = Vector3.new(offset.X, 0, offset.Z)
            if flatOffset.Magnitude > 0 and flatLook.Magnitude > 0 then
                local dot = flatOffset.Unit:Dot(flatLook.Unit)
                if dot < ARC_DOT then continue end
            end
        end

        damageEnemy(enemy, weaponDef.damage, player)
        if not weaponDef.isPiercing and not hasAoE then break end
    end
end

-- Returns the world position where the last boss died (for loot drop).
function EnemyManager.getLastBossPosition(): Vector3?
    return lastBossDeathPosition
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

Remotes.PlayerAttack.OnServerEvent:Connect(function(player: Player, weaponId: string)
    EnemyManager.handlePlayerAttack(player, weaponId)
end)

return EnemyManager
