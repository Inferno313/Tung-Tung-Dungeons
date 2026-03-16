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

-- Loot dropped: show weapon choice panel (keep current vs swap)
Remotes.LootDropped.OnClientEvent:Connect(function(info: { type: string, weaponId: string? })
    if info.type ~= "Weapon" or not info.weaponId then return end

    local WeaponData = require(ReplicatedStorage.Data.WeaponData)
    local newDef     = WeaponData[info.weaponId]
    if not newDef then return end

    -- Build choice panel
    local panel                 = Instance.new("Frame")
    panel.Name                  = "WeaponChoicePanel"
    panel.Size                  = UDim2.new(0, 420, 0, 200)
    panel.Position              = UDim2.new(0.5, -210, 0.5, -100)
    panel.BackgroundColor3      = Color3.fromRGB(20, 20, 20)
    panel.BorderSizePixel       = 0
    panel.ZIndex                = 30
    panel.Parent                = hud.screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = panel

    -- Title
    local title                 = Instance.new("TextLabel")
    title.Size                  = UDim2.new(1, 0, 0, 36)
    title.Position              = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency= 1
    title.TextColor3            = Constants.RARITY_COLORS[newDef.rarity] or Color3.new(1,1,1)
    title.Font                  = Enum.Font.GothamBlack
    title.TextSize              = 18
    title.Text                  = string.format("WEAPON FOUND: %s", newDef.displayName)
    title.TextXAlignment        = Enum.TextXAlignment.Center
    title.ZIndex                = 31
    title.Parent                = panel

    -- Stats line
    local stats                 = Instance.new("TextLabel")
    stats.Size                  = UDim2.new(1, -20, 0, 24)
    stats.Position              = UDim2.new(0, 10, 0, 40)
    stats.BackgroundTransparency= 1
    stats.TextColor3            = Color3.fromRGB(200, 200, 200)
    stats.Font                  = Enum.Font.Gotham
    stats.TextSize              = 14
    stats.Text                  = string.format(
        "%s  ·  DMG: %d  ·  SPD: %.1f  ·  Range: %d  ·  %s",
        newDef.class, newDef.damage, newDef.attackSpeed, newDef.range, newDef.rarity
    )
    stats.TextXAlignment        = Enum.TextXAlignment.Center
    stats.ZIndex                = 31
    stats.Parent                = panel

    -- Description
    local desc                  = Instance.new("TextLabel")
    desc.Size                   = UDim2.new(1, -20, 0, 40)
    desc.Position               = UDim2.new(0, 10, 0, 68)
    desc.BackgroundTransparency = 1
    desc.TextColor3             = Color3.fromRGB(160, 160, 160)
    desc.Font                   = Enum.Font.Gotham
    desc.TextSize               = 13
    desc.Text                   = newDef.description
    desc.TextXAlignment         = Enum.TextXAlignment.Center
    desc.TextWrapped            = true
    desc.ZIndex                 = 31
    desc.Parent                 = panel

    local function makeButton(label: string, xPos: number, color: Color3): TextButton
        local btn               = Instance.new("TextButton")
        btn.Size                = UDim2.new(0, 180, 0, 44)
        btn.Position            = UDim2.new(0, xPos, 0, 140)
        btn.BackgroundColor3    = color
        btn.BorderSizePixel     = 0
        btn.TextColor3          = Color3.new(1, 1, 1)
        btn.Font                = Enum.Font.GothamBold
        btn.TextSize            = 16
        btn.Text                = label
        btn.ZIndex              = 31
        btn.Parent              = panel
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = btn
        return btn
    end

    local swapBtn = makeButton("SWAP  ↑", 20,  Color3.fromRGB(40, 140, 40))
    local keepBtn = makeButton("KEEP  →", 220, Color3.fromRGB(100, 40, 40))

    -- Auto-dismiss after 12s with no input
    local dismissed = false
    local function dismiss()
        if dismissed then return end
        dismissed = true
        panel:Destroy()
    end

    swapBtn.MouseButton1Click:Connect(function()
        Remotes.EquipWeapon:FireServer(info.weaponId)
        dismiss()
    end)

    keepBtn.MouseButton1Click:Connect(function()
        dismiss()
    end)

    task.delay(12, dismiss)
end)

-- Room cleared notification
Remotes.RoomCleared.OnClientEvent:Connect(function(_info: { floor: number, room: number })
    local banner            = Instance.new("TextLabel")
    banner.Size             = UDim2.new(0.4, 0, 0, 40)
    banner.Position         = UDim2.new(0.3, 0, 0.55, 0)
    banner.BackgroundTransparency = 0.3
    banner.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    banner.TextColor3       = Color3.fromRGB(80, 255, 80)
    banner.Font             = Enum.Font.GothamBlack
    banner.TextSize         = 20
    banner.Text             = "ROOM CLEARED  —  Press E to advance"
    banner.TextXAlignment   = Enum.TextXAlignment.Center
    banner.ZIndex           = 10
    banner.Parent           = hud.screenGui

    task.delay(4, function()
        TweenService:Create(banner, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
        task.delay(0.6, function() banner:Destroy() end)
    end)
end)

-- Upgrade station panel: shown when the player presses E near an anvil.
Remotes.UpgradeStationNearby.OnClientEvent:Connect(function(info: {
    weaponId: string, weaponLevel: number, upgradeCost: number
})
    -- Avoid duplicate panels
    if hud.screenGui:FindFirstChild("UpgradePanel") then return end

    local WeaponData = require(ReplicatedStorage.Data.WeaponData)
    local weaponDef  = WeaponData[info.weaponId]
    if not weaponDef then return end

    local panel             = Instance.new("Frame")
    panel.Name              = "UpgradePanel"
    panel.Size              = UDim2.new(0, 380, 0, 160)
    panel.Position          = UDim2.new(0.5, -190, 0.5, -80)
    panel.BackgroundColor3  = Color3.fromRGB(20, 20, 20)
    panel.BorderSizePixel   = 0
    panel.ZIndex            = 30
    panel.Parent            = hud.screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = panel

    local title             = Instance.new("TextLabel")
    title.Size              = UDim2.new(1, 0, 0, 36)
    title.Position          = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.TextColor3        = Constants.RARITY_COLORS[weaponDef.rarity] or Color3.new(1, 1, 1)
    title.Font              = Enum.Font.GothamBlack
    title.TextSize          = 16
    title.Text              = string.format("⚒  UPGRADE STATION  —  %s", weaponDef.displayName)
    title.TextXAlignment    = Enum.TextXAlignment.Center
    title.ZIndex            = 31
    title.Parent            = panel

    local info_label        = Instance.new("TextLabel")
    info_label.Size         = UDim2.new(1, -20, 0, 28)
    info_label.Position     = UDim2.new(0, 10, 0, 40)
    info_label.BackgroundTransparency = 1
    info_label.TextColor3   = Color3.fromRGB(200, 200, 200)
    info_label.Font         = Enum.Font.Gotham
    info_label.TextSize     = 14
    info_label.Text         = string.format(
        "Level %d  →  Level %d     Cost: %d gold",
        info.weaponLevel, info.weaponLevel + 1, info.upgradeCost
    )
    info_label.TextXAlignment = Enum.TextXAlignment.Center
    info_label.ZIndex       = 31
    info_label.Parent       = panel

    local bonus_label       = Instance.new("TextLabel")
    bonus_label.Size        = UDim2.new(1, -20, 0, 22)
    bonus_label.Position    = UDim2.new(0, 10, 0, 70)
    bonus_label.BackgroundTransparency = 1
    bonus_label.TextColor3  = Color3.fromRGB(160, 160, 160)
    bonus_label.Font        = Enum.Font.Gotham
    bonus_label.TextSize    = 13
    bonus_label.Text        = string.format(
        "+%d damage  +%.2f atk speed per upgrade",
        weaponDef.upgradeScaling.damage, weaponDef.upgradeScaling.attackSpeed
    )
    bonus_label.TextXAlignment = Enum.TextXAlignment.Center
    bonus_label.ZIndex      = 31
    bonus_label.Parent      = panel

    local function makeBtn(label: string, xOff: number, color: Color3): TextButton
        local btn           = Instance.new("TextButton")
        btn.Size            = UDim2.new(0, 160, 0, 40)
        btn.Position        = UDim2.new(0, xOff, 0, 104)
        btn.BackgroundColor3 = color
        btn.BorderSizePixel = 0
        btn.TextColor3      = Color3.new(1, 1, 1)
        btn.Font            = Enum.Font.GothamBold
        btn.TextSize        = 15
        btn.Text            = label
        btn.ZIndex          = 31
        btn.Parent          = panel
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = btn
        return btn
    end

    local upgradeBtn = makeBtn("UPGRADE  ⚒", 20,  Color3.fromRGB(40, 140, 40))
    local closeBtn   = makeBtn("CLOSE",       200, Color3.fromRGB(90, 30, 30))

    local dismissed = false
    local function dismiss()
        if dismissed then return end
        dismissed = true
        panel:Destroy()
    end

    upgradeBtn.MouseButton1Click:Connect(function()
        Remotes.UpgradeWeapon:FireServer()
        dismiss()
    end)

    closeBtn.MouseButton1Click:Connect(function()
        dismiss()
    end)

    task.delay(10, dismiss)
end)

-- ─── Kill Feed ───────────────────────────────────────────────────────────────

local MAX_KILL_FEED_ENTRIES = 6
local killFeedEntries: { TextLabel } = {}

Remotes.EnemyKilled.OnClientEvent:Connect(function(info: { displayName: string, killedBy: string, xpReward: number })
    -- Remove oldest entry if at max
    if #killFeedEntries >= MAX_KILL_FEED_ENTRIES then
        local oldest = table.remove(killFeedEntries, 1)
        if oldest and oldest.Parent then oldest:Destroy() end
    end

    -- Shift existing entries up
    for _, entry in killFeedEntries do
        entry.Position = UDim2.new(0, 0, entry.Position.Y.Scale - 0.04, 0)
    end

    local entry                 = Instance.new("TextLabel")
    entry.Size                  = UDim2.new(1, 0, 0, 22)
    entry.Position              = UDim2.new(0, 0, 1, -22)
    entry.BackgroundTransparency= 0.4
    entry.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
    entry.TextColor3            = Color3.fromRGB(255, 80, 80)
    entry.Font                  = Enum.Font.GothamBold
    entry.TextSize              = 13
    entry.Text                  = string.format("✕ %s  [+%d XP]", info.displayName, info.xpReward)
    entry.TextXAlignment        = Enum.TextXAlignment.Left
    entry.TextTruncate          = Enum.TextTruncate.AtEnd
    entry.ZIndex                = 5
    entry.Parent                = hud.killFeed

    table.insert(killFeedEntries, entry)

    -- Fade out after 4 seconds
    task.delay(4, function()
        if not entry.Parent then return end
        TweenService:Create(entry, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
        task.delay(0.6, function()
            if entry.Parent then entry:Destroy() end
            table.remove(killFeedEntries, table.find(killFeedEntries, entry) or 1)
        end)
    end)
end)
