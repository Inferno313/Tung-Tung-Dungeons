--!strict
-- CharacterSetup.client.lua
-- Runs each time the local player's character spawns.
-- Configures the Humanoid, disables default Roblox jump (top-down game),
-- and applies initial visual polish.

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(game.ReplicatedStorage.Data.Constants)

local localPlayer = Players.LocalPlayer
local character   = script.Parent  -- StarterCharacterScripts parent = character model
local humanoid    = character:WaitForChild("Humanoid") :: Humanoid
local rootPart    = character:WaitForChild("HumanoidRootPart") :: BasePart

-- ─── Humanoid Settings ───────────────────────────────────────────────────────

humanoid.WalkSpeed       = Constants.BASE_PLAYER_SPEED
humanoid.JumpPower       = 0          -- no jumping in a top-down dungeon
humanoid.AutoJumpEnabled = false
humanoid.MaxHealth       = Constants.BASE_PLAYER_HEALTH
humanoid.Health          = Constants.BASE_PLAYER_HEALTH
humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None  -- hide nametag overhead

-- Disable Roblox's default character animations (we use custom ones)
for _, animTrack in humanoid:GetPlayingAnimationTracks() do
    animTrack:Stop(0)
end

local animController = character:FindFirstChildOfClass("Animator")
if animController then
    for _, track in animController:GetPlayingAnimationTracks() do
        track:Stop(0)
    end
end

-- ─── Camera Lock ─────────────────────────────────────────────────────────────
-- Lock the camera so CameraController can take full control.
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable

-- ─── Mouse Lock ──────────────────────────────────────────────────────────────
-- Capture mouse for aim direction.
UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

-- Expose stamina value on the character for the HUD to read.
local staminaValue      = Instance.new("NumberValue")
staminaValue.Name       = "Stamina"
staminaValue.Value      = Constants.BASE_PLAYER_STAMINA
staminaValue.Parent     = character

-- Stamina regen loop
local isSprinting = false
RunService.Heartbeat:Connect(function(dt: number)
    if not isSprinting and staminaValue.Value < Constants.BASE_PLAYER_STAMINA then
        staminaValue.Value = math.min(
            Constants.BASE_PLAYER_STAMINA,
            staminaValue.Value + Constants.STAMINA_REGEN_RATE * dt
        )
    end
end)

-- Expose sprint state to PlayerController via a BoolValue
local sprintingValue      = Instance.new("BoolValue")
sprintingValue.Name       = "IsSprinting"
sprintingValue.Value      = false
sprintingValue.Parent     = character

sprintingValue:GetPropertyChangedSignal("Value"):Connect(function()
    isSprinting = sprintingValue.Value
    humanoid.WalkSpeed = isSprinting
        and Constants.BASE_PLAYER_SPEED * 1.6
        or  Constants.BASE_PLAYER_SPEED
end)
