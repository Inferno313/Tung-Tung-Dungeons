--!strict
-- EnemyManager.lua (ModuleScript, required by GameManager)
-- Spawns, updates, and destroys Brainrot enemies.
-- Phase 3: status effects (Burn/Freeze/Shock/Bleed/Poison/Stun/Knockback)
--          and archetype-specific ability VFX.

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local TweenService       = game:GetService("TweenService")

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
    id:               string,
    def:              BrainrotData.BrainrotDef,
    model:            Model,
    humanoid:         Humanoid,
    rootPart:         BasePart,
    health:           number,
    maxHealth:        number,
    fsm:              StateMachine.StateMachineInstance,
    target:           Player?,
    abilityCooldowns: { [string]: number },
    pathUpdateTimer:  number,
    isAlive:          boolean,
    baseWalkSpeed:    number,    -- speed at spawn (floor-scaled); restored after freeze/stun
    originalColor:    BrickColor, -- rootPart colour at spawn; restored when effects clear
}

type ActiveEffect = {
    effectType: string,
    remaining:  number,  -- seconds left
    tickTimer:  number,  -- countdown to next DoT tick
    value:      number,  -- damage per tick (DoT) or ignored (freeze/stun)
    source:     Player?, -- who applied it (for XP credit on DoT kills)
}

-- ─── State ───────────────────────────────────────────────────────────────────

local EnemyManager = {}

local activeEnemies: { EnemyInstance } = {}
local activeEffects: { [any]: { [string]: ActiveEffect } } = {}
local roomKey: string = "0_0"
local lastBossDeathPosition: Vector3? = nil

local PROJECTILE_SPEED = 80  -- studs per second

-- ─── Status Effect Colours ───────────────────────────────────────────────────

local EFFECT_COLORS: { [string]: BrickColor } = {
    Burn      = BrickColor.new("Bright orange"),
    Freeze    = BrickColor.new("Light blue"),
    Shock     = BrickColor.new("Bright yellow"),
    Bleed     = BrickColor.new("CGA brown"),    -- dark red tint
    Poison    = BrickColor.new("Bright green"),
    Stun      = BrickColor.new("Bright yellow"),
}

-- Returns the highest-priority effect colour active on an enemy (or nil).
local function dominantEffectColor(effects: { [string]: ActiveEffect }): BrickColor?
    local priority = { "Freeze", "Shock", "Stun", "Burn", "Poison", "Bleed" }
    for _, effectType in priority do
        if effects[effectType] then
            return EFFECT_COLORS[effectType]
        end
    end
    return nil
end

-- ─── Private Helpers ─────────────────────────────────────────────────────────

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

local function scaleStatForFloor(base: number, scalePerFloor: number, floor: number): number
    return math.floor(base * (1 + scalePerFloor * (floor - 1)))
end

local function nearestPlayer(pos: Vector3): (Player?, number)
    local closest: Player? = nil
    local closestDist      = math.huge
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

local function broadcastHealth(enemy: EnemyInstance)
    Remotes.EnemyHealthUpdated:FireAllClients({
        enemyId   = enemy.id .. tostring(enemy.model),
        health    = enemy.health,
        maxHealth = enemy.maxHealth,
        position  = enemy.rootPart.Position,
    })
end

-- ─── Damage ──────────────────────────────────────────────────────────────────

local function damageEnemy(enemy: EnemyInstance, amount: number, attacker: Player?)
    if not enemy.isAlive then return end
    enemy.health = math.max(0, enemy.health - amount)
    broadcastHealth(enemy)

    if enemy.health <= 0 then
        enemy.isAlive = false
        enemy.humanoid.Health = 0

        if enemy.def.archetype == "Boss" then
            lastBossDeathPosition = enemy.rootPart.Position
        end

        -- Clean up status effects
        activeEffects[enemy] = nil

        if attacker then
            local gold = Util.randomInt(enemy.def.goldReward.min, enemy.def.goldReward.max)
            PlayerDataManager.awardKillRewards(attacker, enemy.def.xpReward, gold)
        end

        Remotes.EnemyKilled:FireAllClients({
            displayName = enemy.def.displayName,
            killedBy    = attacker and attacker.Name or "Unknown",
            xpReward    = enemy.def.xpReward,
        })

        task.delay(1.5, function()
            if enemy.model and enemy.model.Parent then
                enemy.model:Destroy()
            end
        end)
    end
end

-- ─── Status Effects ───────────────────────────────────────────────────────────

local WeaponData = require(ReplicatedStorage.Data.WeaponData)

-- Applies all effect rolls from a weapon hit to the target enemy.
local function applyStatusEffects(
    enemy: EnemyInstance,
    effects: { WeaponData.WeaponEffect },
    attacker: Player?
)
    if not enemy.isAlive then return end
    if #effects == 0 then return end

    local enemyFx = activeEffects[enemy]
    if not enemyFx then
        enemyFx = {}
        activeEffects[enemy] = enemyFx
    end

    for _, effect in effects do
        if math.random() >= effect.chance then continue end

        if effect.type == "Knockback" then
            -- Immediate impulse, no duration tracking needed
            if attacker and attacker.Character then
                local aRoot = attacker.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if aRoot then
                    local dir = Vector3.new(
                        enemy.rootPart.Position.X - aRoot.Position.X,
                        0,
                        enemy.rootPart.Position.Z - aRoot.Position.Z
                    ).Unit
                    local bv        = Instance.new("BodyVelocity")
                    bv.Velocity     = dir * effect.value * 2
                    bv.MaxForce     = Vector3.new(1e5, 0, 1e5)
                    bv.Parent       = enemy.rootPart
                    task.delay(0.35, function()
                        if bv.Parent then bv:Destroy() end
                    end)
                end
            end
            continue
        end

        -- Refresh or start the effect
        enemyFx[effect.type] = {
            effectType = effect.type,
            remaining  = effect.duration,
            tickTimer  = (effect.type == "Shock" or effect.type == "Poison") and 0.5 or 1.0,
            value      = effect.value,
            source     = attacker,
        }

        -- Immediate stat changes on first application
        if effect.type == "Freeze" then
            enemy.humanoid.WalkSpeed = math.max(0, enemy.baseWalkSpeed * 0.4)
        elseif effect.type == "Stun" or effect.type == "Shock" then
            enemy.humanoid.WalkSpeed = 0
        end

        -- Tint the enemy the dominant effect colour
        local newColor = dominantEffectColor(enemyFx)
        if newColor then
            enemy.rootPart.BrickColor = newColor
        end
    end
end

-- ─── AI State Machine ─────────────────────────────────────────────────────────

local function buildEnemyFSM(enemy: EnemyInstance): StateMachine.StateMachineInstance
    local fsm = StateMachine.new("Idle", {
        Idle    = {},
        Chase   = {},
        Attack  = {},
        Ability = {},
        Dead    = {},
    })

    fsm:addTransition("Idle",    "playerInRange",  "Chase")
    fsm:addTransition("Chase",   "playerInAttack", "Attack")
    fsm:addTransition("Chase",   "playerOutRange", "Idle")
    fsm:addTransition("Attack",  "playerOutAttack","Chase")
    fsm:addTransition("Attack",  "playerOutRange", "Idle")
    fsm:addTransition("Attack",  "abilityReady",   "Ability")
    fsm:addTransition("Ability", "abilityCast",    "Chase")
    fsm:addTransition("Chase",   "abilityReady",   "Ability")
    fsm:addTransition("Idle",    "died",           "Dead")
    fsm:addTransition("Chase",   "died",           "Dead")
    fsm:addTransition("Attack",  "died",           "Dead")
    fsm:addTransition("Ability", "died",           "Dead")

    fsm:onUpdate("Idle", function(_, _dt)
        if not enemy.isAlive then fsm:send("died") return end
        local _, dist = nearestPlayer(enemy.rootPart.Position)
        local target = nil
        for _, p in Players:GetPlayers() do
            local char = p.Character
            if not char then continue end
            local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
            if root and (root.Position - enemy.rootPart.Position).Magnitude <= Constants.ENEMY_AGGRO_RANGE then
                target = p
                break
            end
        end
        if target then
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

        for _, abilityDef in enemy.def.abilities do
            local cd = enemy.abilityCooldowns[abilityDef.name] or 0
            if cd <= 0 and dist <= abilityDef.range then
                fsm:send("abilityReady")
                return
            end
        end

        if dist <= enemy.def.attackRange then
            fsm:send("playerInAttack")
            return
        end

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
                local wps = path:GetWaypoints()
                if #wps >= 2 then
                    enemy.humanoid:MoveTo(wps[2].Position)
                end
            else
                enemy.humanoid:MoveTo(targetRoot.Position)
            end
        end

        for abilityName, cd in enemy.abilityCooldowns do
            enemy.abilityCooldowns[abilityName] = math.max(0, cd - dt)
        end
    end)

    fsm:onEnter("Attack", function(_)
        if not enemy.isAlive then return end
        local target = enemy.target
        if not target or not target.Character then return end

        enemy.humanoid:MoveTo(enemy.rootPart.Position)

        local targetRoot = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if targetRoot then
            local lookAt = Vector3.new(targetRoot.Position.X, enemy.rootPart.Position.Y, targetRoot.Position.Z)
            enemy.rootPart.CFrame = CFrame.new(enemy.rootPart.Position, lookAt)
        end

        local targetHum = target.Character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if targetHum and targetHum.Health > 0 then
            targetHum:TakeDamage(enemy.def.damage)
        end

        task.delay(1 / enemy.def.attackRate, function()
            if enemy.isAlive and fsm:is("Attack") then
                local _, dist = nearestPlayer(enemy.rootPart.Position)
                if dist > enemy.def.attackRange then
                    fsm:send("playerOutAttack")
                end
            end
        end)
    end)

    -- ── Archetype-specific ability VFX ────────────────────────────────────────
    fsm:onEnter("Ability", function(_)
        if not enemy.isAlive then return end

        local chosenAbility: BrainrotData.AbilityDef? = nil
        for _, abilityDef in enemy.def.abilities do
            local cd     = enemy.abilityCooldowns[abilityDef.name] or 0
            local target = enemy.target
            if cd > 0 or not target or not target.Character then continue end
            local targetRoot = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not targetRoot then continue end
            if (targetRoot.Position - enemy.rootPart.Position).Magnitude > abilityDef.range then continue end
            chosenAbility = abilityDef
            enemy.abilityCooldowns[abilityDef.name] = abilityDef.cooldown
            break
        end

        if chosenAbility then
            local abilityDef = chosenAbility
            local archetype  = enemy.def.archetype
            local target     = enemy.target

            -- ── Charger: dash toward player ─────────────────────────────────
            if archetype == "Charger" then
                if target and target.Character then
                    local tRoot = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if tRoot then
                        local dir = Vector3.new(
                            tRoot.Position.X - enemy.rootPart.Position.X,
                            0,
                            tRoot.Position.Z - enemy.rootPart.Position.Z
                        ).Unit
                        local bv    = Instance.new("BodyVelocity")
                        bv.Velocity = dir * 70
                        bv.MaxForce = Vector3.new(1e5, 0, 1e5)
                        bv.Parent   = enemy.rootPart
                        -- Brief orange flash to signal the dash
                        enemy.rootPart.BrickColor = BrickColor.new("Bright orange")
                        task.delay(0.35, function()
                            if bv.Parent then bv:Destroy() end
                            -- Damage any player we're close to at end of dash
                            if not enemy.isAlive then return end
                            local _, d = nearestPlayer(enemy.rootPart.Position)
                            if d <= enemy.def.attackRange + 3 then
                                local tgt = enemy.target
                                if tgt and tgt.Character then
                                    local tHum = tgt.Character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                                    if tHum and tHum.Health > 0 then
                                        tHum:TakeDamage(abilityDef.damage)
                                    end
                                end
                            end
                            if not activeEffects[enemy] then
                                enemy.rootPart.BrickColor = enemy.originalColor
                            end
                        end)
                    end
                end

            -- ── Ranged: fire a projectile at the player ──────────────────────
            elseif archetype == "Ranged" then
                if target and target.Character then
                    local tRoot = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if tRoot then
                        local dir  = (tRoot.Position - enemy.rootPart.Position).Unit
                        local proj = Instance.new("Part")
                        proj.Name         = "EnemyProjectile"
                        proj.Shape        = Enum.PartType.Ball
                        proj.Size         = Vector3.new(0.8, 0.8, 0.8)
                        proj.CFrame       = CFrame.new(enemy.rootPart.Position + Vector3.new(0, 1, 0))
                        proj.Material     = Enum.Material.Neon
                        proj.Color        = Color3.fromRGB(255, 80, 0)
                        proj.CanCollide   = false
                        proj.CastShadow   = false
                        proj.Parent       = workspace
                        local bv          = Instance.new("BodyVelocity")
                        bv.Velocity       = dir * 55
                        bv.MaxForce       = Vector3.new(1e5, 1e5, 1e5)
                        bv.Parent         = proj
                        local hitHandled  = false
                        proj.Touched:Connect(function(part: BasePart)
                            if hitHandled then return end
                            local char = part.Parent :: Model?
                            if not char then return end
                            local hum    = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
                            local player = Players:GetPlayerFromCharacter(char)
                            if player and hum and hum.Health > 0 then
                                hitHandled = true
                                hum:TakeDamage(abilityDef.damage)
                                proj:Destroy()
                            end
                        end)
                        task.delay(4, function()
                            if proj and proj.Parent then proj:Destroy() end
                        end)
                    end
                end

            -- ── Boss: shockwave AoE centered on the boss ─────────────────────
            elseif archetype == "Boss" then
                for _, p in Players:GetPlayers() do
                    if not p.Character then continue end
                    local pRoot = p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if not pRoot then continue end
                    if (pRoot.Position - enemy.rootPart.Position).Magnitude <= abilityDef.range then
                        local pHum = p.Character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                        if pHum and pHum.Health > 0 then
                            pHum:TakeDamage(abilityDef.damage)
                        end
                    end
                end
                -- Expanding ring VFX
                local ring         = Instance.new("Part")
                ring.Shape         = Enum.PartType.Cylinder
                ring.Size          = Vector3.new(0.4, 2, 2)
                ring.CFrame        = CFrame.new(enemy.rootPart.Position) * CFrame.Angles(0, 0, math.pi / 2)
                ring.Anchored      = true
                ring.CanCollide    = false
                ring.Material      = Enum.Material.Neon
                ring.Color         = Color3.fromRGB(200, 80, 255)
                ring.Transparency  = 0.2
                ring.Parent        = workspace
                local targetSize   = abilityDef.range * 2 + 4
                TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                    Size         = Vector3.new(0.2, targetSize, targetSize),
                    Transparency = 1,
                }):Play()
                task.delay(0.5, function()
                    if ring.Parent then ring:Destroy() end
                end)

            -- ── Tank: temporary damage reduction (visual only for now) ────────
            elseif archetype == "Tank" then
                enemy.rootPart.BrickColor = BrickColor.new("Dark stone grey")
                task.delay(3, function()
                    if enemy.isAlive and not activeEffects[enemy] then
                        enemy.rootPart.BrickColor = enemy.originalColor
                    end
                end)

            -- ── Stealth: briefly go semi-transparent ─────────────────────────
            elseif archetype == "Stealth" then
                enemy.rootPart.Transparency = 0.75
                task.delay(2, function()
                    if enemy.isAlive then
                        enemy.rootPart.Transparency = 0
                    end
                end)
            end
        end

        task.delay(0.8, function()
            if enemy.isAlive then fsm:send("abilityCast") end
        end)
    end)

    return fsm
end

-- ─── Spawn ───────────────────────────────────────────────────────────────────

local function spawnEnemy(brainrotId: string, position: Vector3, floorNumber: number)
    local def = BrainrotData[brainrotId]
    if not def then
        warn("[EnemyManager] Unknown brainrot id:", brainrotId)
        return
    end

    local floorDef     = DungeonData.getFloor(floorNumber)
    local scaledHealth = scaleStatForFloor(
        def.health,
        Constants.ENEMY_HEALTH_SCALE_PER_FLOOR,
        floorNumber
    ) * floorDef.enemyModifiers.healthMultiplier

    local scaledSpeed  = def.speed * floorDef.enemyModifiers.speedMultiplier

    local model        = Instance.new("Model")
    model.Name         = def.displayName

    local rootPart         = Instance.new("Part")
    rootPart.Name          = "HumanoidRootPart"
    rootPart.Size          = Vector3.new(2, 5, 2)
    rootPart.Position      = position
    rootPart.BrickColor    = BrickColor.new("Bright red")
    rootPart.Anchored      = false
    rootPart.Parent        = model

    local humanoid         = Instance.new("Humanoid")
    humanoid.MaxHealth     = scaledHealth
    humanoid.Health        = scaledHealth
    humanoid.WalkSpeed     = scaledSpeed
    humanoid.Parent        = model

    model.PrimaryPart      = rootPart
    model.Parent           = workspace

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
        baseWalkSpeed    = scaledSpeed,
        originalColor    = BrickColor.new("Bright red"),
    }

    enemy.fsm = buildEnemyFSM(enemy)

    humanoid.Died:Connect(function()
        enemy.isAlive = false
    end)

    table.insert(activeEnemies, enemy)
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function EnemyManager.spawnRoomEnemies(floorNumber: number, roomIndex: number)
    roomKey = string.format("%d_%d", floorNumber, roomIndex)

    local spawnPoints = DungeonManager.getRoomSpawnPoints(roomIndex)
    if #spawnPoints == 0 then return end

    local floorDef    = DungeonData.getFloor(floorNumber)
    local baseCount   = math.random(3, Constants.MAX_ENEMIES_PER_ROOM)
    local scaledCount = math.floor(baseCount * (1 + Constants.ENEMY_COUNT_SCALE_PER_FLOOR * (floorNumber - 1)))
    local count       = math.min(scaledCount, #spawnPoints)

    if DungeonManager.isBossRoom(floorNumber, roomIndex) and floorDef.bossId then
        spawnEnemy(floorDef.bossId, spawnPoints[1], floorNumber)
        return
    end

    local shuffled = Util.shuffle(Util.shallowCopy(spawnPoints))
    for i = 1, count do
        local brainrotId = pickBrainrotId(floorNumber)
        spawnEnemy(brainrotId, shuffled[i] or spawnPoints[1], floorNumber)
    end
end

function EnemyManager.isRoomCleared(_floor: number, _room: number): boolean
    for _, enemy in activeEnemies do
        if enemy.isAlive then return false end
    end
    return true
end

function EnemyManager.despawnAll()
    for _, enemy in activeEnemies do
        if enemy.model and enemy.model.Parent then
            enemy.model:Destroy()
        end
    end
    activeEnemies = {}
    activeEffects = {}
end

function EnemyManager.getLastBossPosition(): Vector3?
    return lastBossDeathPosition
end

-- ─── Projectile System ───────────────────────────────────────────────────────

local PROJECTILE_COLORS: { [string]: Color3 } = {
    Fire     = Color3.fromRGB(255, 120,  20),
    Ice      = Color3.fromRGB(100, 210, 255),
    Electric = Color3.fromRGB(255, 240,  50),
    Chaos    = Color3.fromRGB(200,  80, 255),
    None     = Color3.fromRGB(200, 200, 200),
}

local function spawnProjectile(player: Player, weaponDef: WeaponData.WeaponDef, origin: Vector3, direction: Vector3)
    local proj         = Instance.new("Part")
    proj.Name          = "Projectile_" .. weaponDef.id
    proj.Shape         = Enum.PartType.Ball
    proj.Size          = Vector3.new(0.7, 0.7, 0.7)
    proj.CFrame        = CFrame.new(origin + Vector3.new(0, 1.2, 0))
    proj.Material      = Enum.Material.Neon
    proj.Color         = PROJECTILE_COLORS[weaponDef.element] or PROJECTILE_COLORS.None
    proj.CastShadow    = false
    proj.CanCollide    = false
    proj.Parent        = workspace

    local bv           = Instance.new("BodyVelocity")
    bv.Velocity        = direction.Unit * PROJECTILE_SPEED
    bv.MaxForce        = Vector3.new(1e5, 1e5, 1e5)
    bv.Parent          = proj

    local hitHandled   = false

    proj.Touched:Connect(function(part: BasePart)
        if hitHandled then return end
        for _, enemy in activeEnemies do
            if not enemy.isAlive then continue end
            if part == enemy.rootPart or part:IsDescendantOf(enemy.model) then
                hitHandled = not weaponDef.isPiercing
                local hitPos = proj.Position

                if weaponDef.aoeRadius > 0 then
                    for _, aoeEnemy in activeEnemies do
                        if not aoeEnemy.isAlive then continue end
                        if (aoeEnemy.rootPart.Position - hitPos).Magnitude <= weaponDef.aoeRadius then
                            damageEnemy(aoeEnemy, weaponDef.damage, player)
                            applyStatusEffects(aoeEnemy, weaponDef.effects, player)
                        end
                    end
                else
                    damageEnemy(enemy, weaponDef.damage, player)
                    applyStatusEffects(enemy, weaponDef.effects, player)
                end

                if hitHandled then proj:Destroy() end
                return
            end
        end
    end)

    task.delay(weaponDef.range / PROJECTILE_SPEED + 0.1, function()
        if proj and proj.Parent then proj:Destroy() end
    end)
end

-- ─── Player Attack Handler ────────────────────────────────────────────────────

function EnemyManager.handlePlayerAttack(player: Player, weaponId: string)
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return end

    local weaponDef = WeaponData[weaponId]
    if not weaponDef then return end

    -- Ranged / Magic → projectile
    if weaponDef.class == "Ranged" or weaponDef.class == "Magic" then
        local aimDir = root.CFrame.LookVector
        if weaponDef.isHoming then
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

    -- Melee → 120° arc cone + optional AoE
    local lookDir  = root.CFrame.LookVector
    local flatLook = Vector3.new(lookDir.X, 0, lookDir.Z)
    local hasAoE   = weaponDef.aoeRadius > 0
    local hitRange = hasAoE and weaponDef.aoeRadius or weaponDef.range
    local ARC_DOT  = 0.5  -- cos(60°)

    for _, enemy in activeEnemies do
        if not enemy.isAlive then continue end
        local offset = enemy.rootPart.Position - root.Position
        local dist   = offset.Magnitude
        if dist > hitRange then continue end

        if not hasAoE then
            local flatOffset = Vector3.new(offset.X, 0, offset.Z)
            if flatOffset.Magnitude > 0 and flatLook.Magnitude > 0 then
                if flatOffset.Unit:Dot(flatLook.Unit) < ARC_DOT then continue end
            end
        end

        damageEnemy(enemy, weaponDef.damage, player)
        applyStatusEffects(enemy, weaponDef.effects, player)
        if not weaponDef.isPiercing and not hasAoE then break end
    end
end

-- ─── Heartbeat Loop ──────────────────────────────────────────────────────────

RunService.Heartbeat:Connect(function(dt: number)
    -- AI update
    for _, enemy in activeEnemies do
        if enemy.isAlive then
            enemy.fsm:update(dt)
        end
    end

    -- Status effect processing
    for enemy, effects in activeEffects do
        if not enemy.isAlive then
            activeEffects[enemy] = nil
            continue
        end

        local anyActive = false
        for effectType, effect in effects do
            effect.remaining -= dt

            -- DoT tick
            if effectType == "Burn" or effectType == "Bleed" or
               effectType == "Shock" or effectType == "Poison" then
                effect.tickTimer -= dt
                if effect.tickTimer <= 0 then
                    local interval = (effectType == "Shock" or effectType == "Poison") and 0.5 or 1.0
                    effect.tickTimer = interval
                    damageEnemy(enemy, effect.value, effect.source)
                end
            end

            if effect.remaining <= 0 then
                effects[effectType] = nil
                -- Restore speed if movement-impeding effect expired
                if effectType == "Freeze" or effectType == "Stun" or effectType == "Shock" then
                    if enemy.isAlive then
                        enemy.humanoid.WalkSpeed = enemy.baseWalkSpeed
                    end
                end
            else
                anyActive = true
            end
        end

        if not anyActive then
            -- All effects expired — restore original colour
            if enemy.isAlive then
                enemy.rootPart.BrickColor = enemy.originalColor
            end
            activeEffects[enemy] = nil
        else
            -- Keep the dominant effect colour up to date
            local newColor = dominantEffectColor(effects)
            if newColor and enemy.isAlive then
                enemy.rootPart.BrickColor = newColor
            end
        end
    end
end)

-- ─── Remote Wiring ───────────────────────────────────────────────────────────

Remotes.PlayerAttack.OnServerEvent:Connect(function(player: Player, weaponId: string)
    EnemyManager.handlePlayerAttack(player, weaponId)
end)

return EnemyManager
