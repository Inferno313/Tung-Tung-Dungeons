--!strict
-- PlayerController.client.lua
-- Handles all player input: movement (WASD), sprint (Shift), dodge (Space),
-- attack (LMB), and interact (E). Sends relevant actions to the server.

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Constants        = require(game.ReplicatedStorage.Data.Constants)
local Remotes          = require(game.ReplicatedStorage.Remotes)

local localPlayer = Players.LocalPlayer
local camera      = workspace.CurrentCamera

-- ─── State ───────────────────────────────────────────────────────────────────

local moveVector      = Vector3.zero
local isSprinting     = false
local dodgeCooldown   = 0
local attackCooldown  = 0
local equippedWeapon  = "wooden_club"  -- updated by UIController when player equips

-- ─── Input Vectors ───────────────────────────────────────────────────────────

local MOVE_KEYS = {
    [Enum.KeyCode.W] = Vector3.new( 0, 0, -1),
    [Enum.KeyCode.S] = Vector3.new( 0, 0,  1),
    [Enum.KeyCode.A] = Vector3.new(-1, 0,  0),
    [Enum.KeyCode.D] = Vector3.new( 1, 0,  0),
    -- Arrow key support
    [Enum.KeyCode.Up]    = Vector3.new( 0, 0, -1),
    [Enum.KeyCode.Down]  = Vector3.new( 0, 0,  1),
    [Enum.KeyCode.Left]  = Vector3.new(-1, 0,  0),
    [Enum.KeyCode.Right] = Vector3.new( 1, 0,  0),
}

local heldKeys: { [Enum.KeyCode]: boolean } = {}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

-- Projects a world-space direction onto the camera's flat plane so WASD
-- always moves relative to the camera yaw (not world axes).
local function cameraRelativeDirection(dir: Vector3): Vector3
    local camCF  = camera.CFrame
    local flat   = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z).Unit
    local right  = Vector3.new(0, 1, 0):Cross(flat)   -- up × forward = correct right
    return (right * dir.X + flat * -dir.Z).Unit
end

local function getMoveInput(): Vector3
    local total = Vector3.zero
    for key, dir in MOVE_KEYS do
        if heldKeys[key] then
            total += dir
        end
    end
    if total.Magnitude > 1 then
        total = total.Unit
    end
    return total
end

-- Rotates the character to face the mouse cursor position on a flat plane.
local function faceMouseTarget()
    local character = localPlayer.Character
    if not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return end

    local unitRay = camera:ScreenPointToRay(
        UserInputService:GetMouseLocation().X,
        UserInputService:GetMouseLocation().Y
    )
    -- Intersect with the floor plane (Y = rootPart.Position.Y)
    local t      = (rootPart.Position.Y - unitRay.Origin.Y) / unitRay.Direction.Y
    if t < 0 then return end
    local hitPos = unitRay.Origin + unitRay.Direction * t

    local lookDir = Vector3.new(hitPos.X, rootPart.Position.Y, hitPos.Z)
    rootPart.CFrame = CFrame.new(rootPart.Position, lookDir)
end

-- ─── Movement Loop ───────────────────────────────────────────────────────────

RunService.Heartbeat:Connect(function(dt: number)
    local character = localPlayer.Character
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not humanoid or not rootPart then return end
    if humanoid.Health <= 0 then return end

    -- Decrement cooldowns
    if dodgeCooldown > 0 then
        dodgeCooldown = math.max(0, dodgeCooldown - dt)
    end
    if attackCooldown > 0 then
        attackCooldown = math.max(0, attackCooldown - dt)
    end

    -- Sprint stamina drain
    local staminaValue = character:FindFirstChild("Stamina") :: NumberValue?
    if staminaValue then
        if isSprinting and staminaValue.Value > 0 then
            staminaValue.Value = math.max(0, staminaValue.Value - Constants.STAMINA_SPRINT_COST * dt)
            if staminaValue.Value <= 0 then
                isSprinting = false
                local sprintFlag = character:FindFirstChild("IsSprinting") :: BoolValue?
                if sprintFlag then sprintFlag.Value = false end
            end
        end
    end

    -- Apply movement
    local raw = getMoveInput()
    if raw.Magnitude > 0 then
        local dir = cameraRelativeDirection(raw)
        humanoid:Move(dir, false)
    else
        humanoid:Move(Vector3.zero, false)
    end

    -- Face mouse
    faceMouseTarget()
end)

-- ─── Key Press / Release ─────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end

    -- Track held keys for movement
    if MOVE_KEYS[input.KeyCode] then
        heldKeys[input.KeyCode] = true
    end

    -- Sprint
    if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
        local character   = localPlayer.Character
        if not character then return end
        local staminaValue = character:FindFirstChild("Stamina") :: NumberValue?
        if staminaValue and staminaValue.Value > 10 then
            isSprinting = true
            local sprintFlag = character:FindFirstChild("IsSprinting") :: BoolValue?
            if sprintFlag then sprintFlag.Value = true end
        end
    end

    -- Dodge roll
    if input.KeyCode == Enum.KeyCode.Space and dodgeCooldown <= 0 then
        local character    = localPlayer.Character
        if not character then return end
        local humanoid     = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local rootPart     = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        local staminaValue = character:FindFirstChild("Stamina") :: NumberValue?

        if not humanoid or not rootPart or not staminaValue then return end
        if staminaValue.Value < Constants.DODGE_STAMINA_COST then return end
        if humanoid.Health <= 0 then return end

        dodgeCooldown  = Constants.DODGE_COOLDOWN
        staminaValue.Value = staminaValue.Value - Constants.DODGE_STAMINA_COST

        -- Impulse the character in move direction (or face direction if idle)
        local raw  = getMoveInput()
        local dir  = raw.Magnitude > 0 and cameraRelativeDirection(raw) or rootPart.CFrame.LookVector
        local body = Instance.new("BodyVelocity")
        body.Velocity      = dir * Constants.DODGE_DISTANCE / 0.3
        body.MaxForce      = Vector3.new(1e5, 0, 1e5)
        body.Parent        = rootPart

        Remotes.PlayerDodge:FireServer()

        task.delay(0.3, function()
            if body and body.Parent then body:Destroy() end
        end)
    end

    -- Interact
    if input.KeyCode == Enum.KeyCode.E then
        Remotes.PlayerInteract:FireServer()
    end
end)

UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
    if MOVE_KEYS[input.KeyCode] then
        heldKeys[input.KeyCode] = nil
    end

    if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
        isSprinting = false
        local character  = localPlayer.Character
        if character then
            local sprintFlag = character:FindFirstChild("IsSprinting") :: BoolValue?
            if sprintFlag then sprintFlag.Value = false end
        end
    end
end)

-- ─── Attack (Mouse Button 1) ─────────────────────────────────────────────────

local WeaponData = require(game.ReplicatedStorage.Data.WeaponData)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if attackCooldown > 0 then return end
        local weaponDef = WeaponData[equippedWeapon]
        local cooldown  = weaponDef and (1 / weaponDef.attackSpeed) or 0.5
        attackCooldown  = cooldown
        Remotes.PlayerAttack:FireServer(equippedWeapon)
    end
end)

-- ─── Weapon Equip Listener ───────────────────────────────────────────────────
-- UIController fires this binding when the player selects a weapon from inventory.

ContextActionService:BindAction("EquipWeapon", function(_name, _state, _input)
    -- Handled via UIController → Remotes.EquipWeapon
    return Enum.ContextActionResult.Sink
end, false)

-- Listen for weapon-equipped confirmation from server
Remotes.PlayerStatsUpdated.OnClientEvent:Connect(function(data: { [string]: any })
    if data.equippedWeapon then
        equippedWeapon = data.equippedWeapon
    end
end)
