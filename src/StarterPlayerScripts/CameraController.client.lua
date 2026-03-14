--!strict
-- CameraController.client.lua
-- Maintains a fixed top-down isometric camera that follows the local player.
-- The camera is locked by CharacterSetup; this script drives its CFrame each frame.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local Constants  = require(game.ReplicatedStorage.Data.Constants)

local localPlayer = Players.LocalPlayer
local camera      = workspace.CurrentCamera

-- ─── Camera Settings ─────────────────────────────────────────────────────────

local HEIGHT      = Constants.CAMERA_HEIGHT   -- studs above player
local PITCH_DEG   = Constants.CAMERA_ANGLE    -- negative = looking down
local PITCH_RAD   = math.rad(PITCH_DEG)
local SMOOTH      = 0.12                      -- 0=instant, 1=never moves

-- Offset so the camera is slightly ahead of the player in the aim direction.
local LOOK_AHEAD  = 5  -- studs

-- ─── State ───────────────────────────────────────────────────────────────────

local currentPos = Vector3.zero

-- ─── Main Loop ───────────────────────────────────────────────────────────────

RunService.RenderStepped:Connect(function(dt: number)
    local character = localPlayer.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return end

    local targetPos = rootPart.Position

    -- Smooth lerp towards target
    currentPos = currentPos:Lerp(targetPos, SMOOTH)

    -- Build the camera CFrame: position above player, angled downward.
    local offset   = Vector3.new(0, HEIGHT, HEIGHT * math.tan(-PITCH_RAD))
    local camPos   = currentPos + offset
    local lookAt   = currentPos + Vector3.new(0, 0, LOOK_AHEAD)

    camera.CFrame  = CFrame.new(camPos, lookAt) * CFrame.Angles(PITCH_RAD, 0, 0)
end)
