--!strict
-- UIController.client.lua
-- Drives all HUD elements and overlay screens (GameOver, FloorComplete, Inventory).
-- Listens to Remotes from the server and updates the UI reactively.

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Data.Constants)
local Remotes   = require(ReplicatedStorage.Remotes)

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ─── Types ───────────────────────────────────────────────────────────────────

type HUDRefs = {
    screenGui:    ScreenGui,
    healthBar:    Frame,
    healthFill:   Frame,
    staminaBar:   Frame,
    staminaFill:  Frame,
    xpBar:        Frame,
    xpFill:       Frame,
    levelLabel:   TextLabel,
    goldLabel:    TextLabel,
    floorLabel:   TextLabel,
    weaponIcon:   ImageLabel,
    killFeed:     ScrollingFrame,
    bossHealthBar:Frame,
    bossHealthFill:Frame,
    bossNameLabel: TextLabel,
}

-- ─── HUD Builder ─────────────────────────────────────────────────────────────
-- Creates the HUD ScreenGui programmatically so no Studio setup is required.
-- In production, this would be replaced by a designed ScreenGui from StarterGui.

local function createBar(parent: GuiObject, name: string, color: Color3, yPos: UDim2): (Frame, Frame)
    local bg            = Instance.new("Frame")
    bg.Name             = name .. "Bar"
    bg.Size             = UDim2.new(0.25, 0, 0, 18)
    bg.Position         = yPos
    bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    bg.BorderSizePixel  = 0
    bg.Parent           = parent

    local corner        = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent       = bg

    local fill          = Instance.new("Frame")
    fill.Name           = name .. "Fill"
    fill.Size           = UDim2.new(1, 0, 1, 0)
    fill.BackgroundColor3 = color
    fill.BorderSizePixel= 0
    fill.Parent         = bg

    local fillCorner    = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 4)
    fillCorner.Parent   = fill

    return bg, fill
end

local function buildHUD(): HUDRefs
    local screenGui             = Instance.new("ScreenGui")
    screenGui.Name              = "TungTungHUD"
    screenGui.ResetOnSpawn      = false
    screenGui.IgnoreGuiInset    = true
    screenGui.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
    screenGui.Parent            = playerGui

    -- ── Status bars (top-left) ───────────────────────────────────────────
    local _, healthFill  = createBar(screenGui, "Health",  Constants.HUD_HEALTH_BAR_COLOR,  UDim2.new(0.02, 0, 0.02, 0))
    local _, staminaFill = createBar(screenGui, "Stamina", Constants.HUD_STAMINA_BAR_COLOR, UDim2.new(0.02, 0, 0.06, 0))
    local _, xpFill      = createBar(screenGui, "XP",      Constants.HUD_XP_BAR_COLOR,      UDim2.new(0.02, 0, 0.10, 0))

    local healthBar  = healthFill.Parent  :: Frame
    local staminaBar = staminaFill.Parent :: Frame
    local xpBar      = xpFill.Parent      :: Frame

    -- ── Level label ──────────────────────────────────────────────────────
    local levelLabel            = Instance.new("TextLabel")
    levelLabel.Name             = "LevelLabel"
    levelLabel.Size             = UDim2.new(0, 80, 0, 20)
    levelLabel.Position         = UDim2.new(0.02, 0, 0.14, 0)
    levelLabel.BackgroundTransparency = 1
    levelLabel.TextColor3       = Color3.new(1, 1, 1)
    levelLabel.Font             = Enum.Font.GothamBold
    levelLabel.TextSize         = 14
    levelLabel.Text             = "Lv. 1"
    levelLabel.TextXAlignment   = Enum.TextXAlignment.Left
    levelLabel.Parent           = screenGui

    -- ── Gold label ───────────────────────────────────────────────────────
    local goldLabel             = Instance.new("TextLabel")
    goldLabel.Name              = "GoldLabel"
    goldLabel.Size              = UDim2.new(0, 100, 0, 20)
    goldLabel.Position          = UDim2.new(0.02, 0, 0.18, 0)
    goldLabel.BackgroundTransparency = 1
    goldLabel.TextColor3        = Color3.fromRGB(255, 215, 0)
    goldLabel.Font              = Enum.Font.GothamBold
    goldLabel.TextSize          = 14
    goldLabel.Text              = "Gold: 0"
    goldLabel.TextXAlignment    = Enum.TextXAlignment.Left
    goldLabel.Parent            = screenGui

    -- ── Floor label (top-center) ─────────────────────────────────────────
    local floorLabel            = Instance.new("TextLabel")
    floorLabel.Name             = "FloorLabel"
    floorLabel.Size             = UDim2.new(0.2, 0, 0, 30)
    floorLabel.Position         = UDim2.new(0.4, 0, 0.02, 0)
    floorLabel.BackgroundTransparency = 1
    floorLabel.TextColor3       = Color3.new(1, 1, 1)
    floorLabel.Font             = Enum.Font.GothamBlack
    floorLabel.TextSize         = 18
    floorLabel.Text             = "Floor 1"
    floorLabel.TextXAlignment   = Enum.TextXAlignment.Center
    floorLabel.Parent           = screenGui

    -- ── Weapon icon (bottom-center) ─────────────────────────────────────
    local weaponIcon            = Instance.new("ImageLabel")
    weaponIcon.Name             = "WeaponIcon"
    weaponIcon.Size             = UDim2.new(0, 60, 0, 60)
    weaponIcon.Position         = UDim2.new(0.47, 0, 0.88, 0)
    weaponIcon.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    weaponIcon.BorderSizePixel  = 0
    weaponIcon.Image            = ""   -- set dynamically when weapon changes
    weaponIcon.Parent           = screenGui

    -- ── Boss health bar (bottom-center, hidden by default) ──────────────
    local bossBar               = Instance.new("Frame")
    bossBar.Name                = "BossHealthBar"
    bossBar.Size                = UDim2.new(0.5, 0, 0, 24)
    bossBar.Position            = UDim2.new(0.25, 0, 0.94, 0)
    bossBar.BackgroundColor3    = Color3.fromRGB(30, 0, 0)
    bossBar.BorderSizePixel     = 0
    bossBar.Visible             = false
    bossBar.Parent              = screenGui

    local bossFill              = Instance.new("Frame")
    bossFill.Name               = "BossHealthFill"
    bossFill.Size               = UDim2.new(1, 0, 1, 0)
    bossFill.BackgroundColor3   = Color3.fromRGB(200, 0, 0)
    bossFill.BorderSizePixel    = 0
    bossFill.Parent             = bossBar

    local bossNameLabel         = Instance.new("TextLabel")
    bossNameLabel.Name          = "BossNameLabel"
    bossNameLabel.Size          = UDim2.new(1, 0, 0, 20)
    bossNameLabel.Position      = UDim2.new(0, 0, -1, 0)
    bossNameLabel.BackgroundTransparency = 1
    bossNameLabel.TextColor3    = Color3.fromRGB(220, 0, 0)
    bossNameLabel.Font          = Enum.Font.GothamBlack
    bossNameLabel.TextSize      = 16
    bossNameLabel.Text          = ""
    bossNameLabel.Parent        = bossBar

    -- ── Kill feed (right side) ────────────────────────────────────────
    local killFeed              = Instance.new("ScrollingFrame")
    killFeed.Name               = "KillFeed"
    killFeed.Size               = UDim2.new(0.2, 0, 0.3, 0)
    killFeed.Position           = UDim2.new(0.78, 0, 0.02, 0)
    killFeed.BackgroundTransparency = 1
    killFeed.ScrollBarThickness = 0
    killFeed.CanvasSize         = UDim2.new(0, 0, 0, 0)
    killFeed.Parent             = screenGui

    return {
        screenGui    = screenGui,
        healthBar    = healthBar,
        healthFill   = healthFill,
        staminaBar   = staminaBar,
        staminaFill  = staminaFill,
        xpBar        = xpBar,
        xpFill       = xpFill,
        levelLabel   = levelLabel,
        goldLabel    = goldLabel,
        floorLabel   = floorLabel,
        weaponIcon   = weaponIcon,
        killFeed     = killFeed,
        bossHealthBar  = bossBar,
        bossHealthFill = bossFill,
        bossNameLabel  = bossNameLabel,
    }
end

-- ─── HUD Update Helpers ──────────────────────────────────────────────────────

local hud: HUDRefs = buildHUD()

local function tweenBarFill(fill: Frame, ratio: number)
    TweenService:Create(fill, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
        Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0)
    }):Play()
end

-- Polls character stats each frame (health / stamina).
local function startStatPoll()
    game:GetService("RunService").RenderStepped:Connect(function()
        local char = localPlayer.Character
        if not char then return end

        local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if hum then
            tweenBarFill(hud.healthFill, hum.Health / hum.MaxHealth)
        end

        local stamina = char:FindFirstChild("Stamina") :: NumberValue?
        if stamina then
            tweenBarFill(hud.staminaFill, stamina.Value / Constants.BASE_PLAYER_STAMINA)
        end
    end)
end

startStatPoll()

-- ─── Remote Listeners ────────────────────────────────────────────────────────

-- Player stats update (XP, level, gold, equipped weapon)
Remotes.PlayerStatsUpdated.OnClientEvent:Connect(function(data: { [string]: any })
    if data.level then
        hud.levelLabel.Text = string.format("Lv. %d", data.level)
    end
    if data.gold then
        hud.goldLabel.Text = string.format("Gold: %s", tostring(data.gold))
    end
    if data.xp and data.level then
        local xpForNext = math.floor(Constants.XP_PER_LEVEL_BASE * ((data.level + 1) ^ Constants.XP_PER_LEVEL_EXPONENT))
        tweenBarFill(hud.xpFill, data.xp / xpForNext)
    end
    -- TODO: update weapon icon image when equippedWeapon changes
end)

-- Room / floor loaded
Remotes.DungeonRoomLoaded.OnClientEvent:Connect(function(info: { floor: number, room: number })
    hud.floorLabel.Text = string.format("Floor %d  ·  Room %d", info.floor, info.room)
    hud.bossHealthBar.Visible = false
end)

-- Boss spawned: reveal boss health bar
Remotes.BossSpawned.OnClientEvent:Connect(function(info: { floor: number })
    hud.bossHealthBar.Visible = true
    hud.bossNameLabel.Text    = string.format("Floor %d BOSS", info.floor)
end)

-- Enemy health updates (only shown for boss enemies)
Remotes.EnemyHealthUpdated.OnClientEvent:Connect(function(info: {
    enemyId: string, health: number, maxHealth: number, position: Vector3
})
    -- Simple boss bar update: if boss bar is visible, reflect HP
    if hud.bossHealthBar.Visible then
        tweenBarFill(hud.bossHealthFill, info.health / info.maxHealth)
        if info.health <= 0 then
            hud.bossHealthBar.Visible = false
        end
    end
end)

-- Floor completed: show a brief banner
Remotes.FloorCompleted.OnClientEvent:Connect(function(info: { floor: number })
    local banner            = Instance.new("TextLabel")
    banner.Size             = UDim2.new(0.6, 0, 0, 60)
    banner.Position         = UDim2.new(0.2, 0, 0.4, 0)
    banner.BackgroundTransparency = 0.3
    banner.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    banner.TextColor3       = Color3.fromRGB(255, 215, 0)
    banner.Font             = Enum.Font.GothamBlack
    banner.TextSize         = 28
    banner.Text             = string.format("FLOOR %d CLEARED!", info.floor)
    banner.TextXAlignment   = Enum.TextXAlignment.Center
    banner.ZIndex           = 10
    banner.Parent           = hud.screenGui

    task.delay(3, function()
        TweenService:Create(banner, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
        task.delay(0.6, function() banner:Destroy() end)
    end)
end)

-- Game over screen
Remotes.GameOver.OnClientEvent:Connect(function(info: { reason: string, floorReached: number, roomsCleared: number })
    local overlay               = Instance.new("Frame")
    overlay.Name                = "GameOverOverlay"
    overlay.Size                = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3    = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.4
    overlay.ZIndex              = 20
    overlay.Parent              = hud.screenGui

    local title                 = Instance.new("TextLabel")
    title.Size                  = UDim2.new(0.5, 0, 0, 70)
    title.Position              = UDim2.new(0.25, 0, 0.3, 0)
    title.BackgroundTransparency= 1
    title.TextColor3            = Color3.fromRGB(220, 0, 0)
    title.Font                  = Enum.Font.GothamBlack
    title.TextSize              = 48
    title.Text                  = "YOU DIED"
    title.TextXAlignment        = Enum.TextXAlignment.Center
    title.ZIndex                = 21
    title.Parent                = overlay

    local stats                 = Instance.new("TextLabel")
    stats.Size                  = UDim2.new(0.5, 0, 0, 40)
    stats.Position              = UDim2.new(0.25, 0, 0.45, 0)
    stats.BackgroundTransparency= 1
    stats.TextColor3            = Color3.new(1, 1, 1)
    stats.Font                  = Enum.Font.Gotham
    stats.TextSize              = 18
    stats.Text                  = string.format(
        "Reached Floor %d  ·  %d Rooms Cleared",
        info.floorReached, info.roomsCleared
    )
    stats.TextXAlignment        = Enum.TextXAlignment.Center
    stats.ZIndex                = 21
    stats.Parent                = overlay

    -- Auto-dismiss after 8 seconds (server will reset the game)
    task.delay(8, function()
        TweenService:Create(overlay, TweenInfo.new(1), { BackgroundTransparency = 1 }):Play()
        task.delay(1.1, function() overlay:Destroy() end)
    end)
end)

-- Loot dropped: show pick-up prompt / weapon selection
Remotes.LootDropped.OnClientEvent:Connect(function(info: { type: string, weaponId: string? })
    if info.type == "Weapon" and info.weaponId then
        local WeaponData = require(ReplicatedStorage.Data.WeaponData)
        local def        = WeaponData[info.weaponId]
        if not def then return end

        -- TODO: Phase 3 — replace with a proper weapon-choice panel (keep vs swap)
        -- For now, automatically equip the new weapon.
        Remotes.EquipWeapon:FireServer(info.weaponId)
    end
end)
