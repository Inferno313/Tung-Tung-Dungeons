--!strict
-- DungeonManager.lua (ModuleScript, required by GameManager)
-- Handles procedural dungeon generation, room instantiation, and floor layout.
-- Phase 2: biome theming, Z-axis corridors, upgrade stations, locked combat doors.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local DungeonData = require(ReplicatedStorage.Data.DungeonData)
local Constants   = require(ReplicatedStorage.Data.Constants)
local Util        = require(ReplicatedStorage.Modules.Util)

-- ─── Types ───────────────────────────────────────────────────────────────────

type BiomeTheme = {
    floorMaterial: Enum.Material,
    wallMaterial:  Enum.Material,
    floorColor:    BrickColor,
    wallColor:     BrickColor,
}

type RoomInstance = {
    model:           Model,
    spawnPoints:     { Vector3 },
    doors:           { BasePart },
    lootPoints:      { Vector3 },
    upgradeStations: { Vector3 },
    isBoss:          boolean,
    isLoot:          boolean,
    isSafe:          boolean,
}

-- ─── Biome Themes ────────────────────────────────────────────────────────────

local BIOME_THEMES: { [string]: BiomeTheme } = {
    Underground = {
        floorMaterial = Enum.Material.Basalt,
        wallMaterial  = Enum.Material.Basalt,
        floorColor    = BrickColor.new("Dark stone grey"),
        wallColor     = BrickColor.new("Really black"),
    },
    Ruins = {
        floorMaterial = Enum.Material.Cobblestone,
        wallMaterial  = Enum.Material.Brick,
        floorColor    = BrickColor.new("Sand"),
        wallColor     = BrickColor.new("Medium stone grey"),
    },
    Swamp = {
        floorMaterial = Enum.Material.Mud,
        wallMaterial  = Enum.Material.SmoothPlastic,
        floorColor    = BrickColor.new("Bright green"),
        wallColor     = BrickColor.new("Dark green"),
    },
    Tundra = {
        floorMaterial = Enum.Material.Snow,
        wallMaterial  = Enum.Material.Ice,
        floorColor    = BrickColor.new("White"),
        wallColor     = BrickColor.new("Light blue"),
    },
    Volcano = {
        floorMaterial = Enum.Material.Basalt,
        wallMaterial  = Enum.Material.Basalt,
        floorColor    = BrickColor.new("Dark orange"),
        wallColor     = BrickColor.new("Really black"),
    },
    Chaos = {
        floorMaterial = Enum.Material.Neon,
        wallMaterial  = Enum.Material.SmoothPlastic,
        floorColor    = BrickColor.new("Hot pink"),
        wallColor     = BrickColor.new("Magenta"),
    },
}

local function getTheme(biome: string): BiomeTheme
    return (BIOME_THEMES[biome] or BIOME_THEMES["Ruins"]) :: BiomeTheme
end

-- ─── State ───────────────────────────────────────────────────────────────────

local DungeonManager = {}

local currentFloorFolder: Folder? = nil
local roomInstances: { RoomInstance } = {}
local TILE_SIZE      = 8   -- studs per layout character

-- Z-axis door column (1-indexed) standardised across all room layouts.
-- All room templates have their top/bottom 'D' at column 4.
local DOOR_COLUMN    = 4
local DOOR_X_CENTER  = (DOOR_COLUMN - 1) * TILE_SIZE + TILE_SIZE / 2  -- = 28 studs
local CORRIDOR_WIDTH = TILE_SIZE                                        -- = 8 studs (1 tile)

-- ─── Room Builder ────────────────────────────────────────────────────────────

local function buildRoomFromLayout(
    layout: { string },
    origin: Vector3,
    roomFolder: Folder,
    theme: BiomeTheme
): { spawnPoints: { Vector3 }, doors: { BasePart }, lootPoints: { Vector3 }, upgradeStations: { Vector3 } }

    local spawnPoints:     { Vector3 }  = {}
    local doors:           { BasePart } = {}
    local lootPoints:      { Vector3 }  = {}
    local upgradeStations: { Vector3 }  = {}

    for row, rowStr in layout do
        for col = 1, #rowStr do
            local char = string.sub(rowStr, col, col)
            local pos  = origin + Vector3.new(
                (col - 1) * TILE_SIZE,
                0,
                (row - 1) * TILE_SIZE
            )

            if char == "X" then
                local wall          = Instance.new("Part")
                wall.Name           = "Wall"
                wall.Size           = Vector3.new(TILE_SIZE, Constants.DUNGEON_ROOM_SIZE.Y, TILE_SIZE)
                wall.Position       = pos + Vector3.new(TILE_SIZE / 2, Constants.DUNGEON_ROOM_SIZE.Y / 2, TILE_SIZE / 2)
                wall.Anchored       = true
                wall.Material       = theme.wallMaterial
                wall.BrickColor     = theme.wallColor
                wall.Parent         = roomFolder

            elseif char == "." then
                local floor         = Instance.new("Part")
                floor.Name          = "Floor"
                floor.Size          = Vector3.new(TILE_SIZE, 1, TILE_SIZE)
                floor.Position      = pos + Vector3.new(TILE_SIZE / 2, -0.5, TILE_SIZE / 2)
                floor.Anchored      = true
                floor.Material      = theme.floorMaterial
                floor.BrickColor    = theme.floorColor
                floor.Parent        = roomFolder

            elseif char == "D" then
                local door          = Instance.new("Part")
                door.Name           = "Door"
                door.Size           = Vector3.new(TILE_SIZE, 1, TILE_SIZE)
                door.Position       = pos + Vector3.new(TILE_SIZE / 2, -0.5, TILE_SIZE / 2)
                door.Anchored       = true
                door.Transparency   = 1
                door.CanCollide     = false
                door.Material       = theme.floorMaterial
                door.BrickColor     = theme.floorColor
                door.Parent         = roomFolder
                table.insert(doors, door)

            elseif char == "S" then
                local floor2        = Instance.new("Part")
                floor2.Name         = "Floor"
                floor2.Size         = Vector3.new(TILE_SIZE, 1, TILE_SIZE)
                floor2.Position     = pos + Vector3.new(TILE_SIZE / 2, -0.5, TILE_SIZE / 2)
                floor2.Anchored     = true
                floor2.Material     = theme.floorMaterial
                floor2.BrickColor   = theme.floorColor
                floor2.Parent       = roomFolder
                table.insert(spawnPoints, pos + Vector3.new(TILE_SIZE / 2, 1, TILE_SIZE / 2))

            elseif char == "L" then
                local lootFloor     = Instance.new("Part")
                lootFloor.Name      = "LootFloor"
                lootFloor.Size      = Vector3.new(TILE_SIZE, 1, TILE_SIZE)
                lootFloor.Position  = pos + Vector3.new(TILE_SIZE / 2, -0.5, TILE_SIZE / 2)
                lootFloor.Anchored  = true
                lootFloor.Material  = theme.floorMaterial
                lootFloor.BrickColor = BrickColor.new("Bright yellow")
                lootFloor.Parent    = roomFolder
                table.insert(lootPoints, pos + Vector3.new(TILE_SIZE / 2, 1.5, TILE_SIZE / 2))

            elseif char == "U" then
                -- Upgrade station: floor tile + glowing anvil prop
                local uFloor        = Instance.new("Part")
                uFloor.Name         = "Floor"
                uFloor.Size         = Vector3.new(TILE_SIZE, 1, TILE_SIZE)
                uFloor.Position     = pos + Vector3.new(TILE_SIZE / 2, -0.5, TILE_SIZE / 2)
                uFloor.Anchored     = true
                uFloor.Material     = theme.floorMaterial
                uFloor.BrickColor   = theme.floorColor
                uFloor.Parent       = roomFolder

                local anvil         = Instance.new("Part")
                anvil.Name          = "UpgradeStation"
                anvil.Size          = Vector3.new(2.5, 2, 2)
                anvil.Position      = pos + Vector3.new(TILE_SIZE / 2, 1.5, TILE_SIZE / 2)
                anvil.Anchored      = true
                anvil.Material      = Enum.Material.Metal
                anvil.BrickColor    = BrickColor.new("Dark stone grey")
                anvil.Parent        = roomFolder
                table.insert(upgradeStations, anvil.Position)

            elseif char == "B" then
                -- Boss arena floor tile (reddish accent)
                local bossFloor     = Instance.new("Part")
                bossFloor.Name      = "Floor"
                bossFloor.Size      = Vector3.new(TILE_SIZE, 1, TILE_SIZE)
                bossFloor.Position  = pos + Vector3.new(TILE_SIZE / 2, -0.5, TILE_SIZE / 2)
                bossFloor.Anchored  = true
                bossFloor.Material  = theme.floorMaterial
                bossFloor.BrickColor = BrickColor.new("Bright red")
                bossFloor.Parent    = roomFolder
            end
        end
    end

    return { spawnPoints = spawnPoints, doors = doors, lootPoints = lootPoints, upgradeStations = upgradeStations }
end

-- ─── Corridor Builder ────────────────────────────────────────────────────────
-- Fills the gap between two rooms along the Z axis with a 1-tile-wide walkable
-- passage aligned to DOOR_X_CENTER so it connects the top/bottom 'D' doors.

local function buildCorridor(startZ: number, endZ: number, folder: Folder, theme: BiomeTheme)
    if endZ <= startZ then return end
    local length    = endZ - startZ
    local cx        = DOOR_X_CENTER
    local halfW     = CORRIDOR_WIDTH / 2
    local wallThick = TILE_SIZE / 2
    local roomH     = Constants.DUNGEON_ROOM_SIZE.Y

    local floor     = Instance.new("Part")
    floor.Name      = "CorridorFloor"
    floor.Size      = Vector3.new(CORRIDOR_WIDTH, 1, length)
    floor.Position  = Vector3.new(cx, -0.5, startZ + length / 2)
    floor.Anchored  = true
    floor.Material  = theme.floorMaterial
    floor.BrickColor = theme.floorColor
    floor.Parent    = folder

    local wallL     = Instance.new("Part")
    wallL.Name      = "CorridorWallL"
    wallL.Size      = Vector3.new(wallThick, roomH, length)
    wallL.Position  = Vector3.new(cx - halfW - wallThick / 2, roomH / 2, startZ + length / 2)
    wallL.Anchored  = true
    wallL.Material  = theme.wallMaterial
    wallL.BrickColor = theme.wallColor
    wallL.Parent    = folder

    local wallR     = Instance.new("Part")
    wallR.Name      = "CorridorWallR"
    wallR.Size      = Vector3.new(wallThick, roomH, length)
    wallR.Position  = Vector3.new(cx + halfW + wallThick / 2, roomH / 2, startZ + length / 2)
    wallR.Anchored  = true
    wallR.Material  = theme.wallMaterial
    wallR.BrickColor = theme.wallColor
    wallR.Parent    = folder
end

-- ─── Room Sequence Picker ────────────────────────────────────────────────────

local function pickRoomSequence(floorDef: DungeonData.FloorDef): { string }
    local allowed  = Util.shallowCopy(floorDef.allowedRoomIds)
    local sequence: { string } = {}
    local roomCount = Constants.ROOMS_PER_FLOOR

    table.insert(sequence, "safe_room")

    for _ = 2, roomCount - 1 do
        if math.random() < Constants.LOOT_ROOM_CHANCE and Util.contains(allowed, "loot_chamber") then
            table.insert(sequence, "loot_chamber")
        else
            local combatRooms = {}
            for _, id in allowed do
                local roomDef = DungeonData.Rooms[id]
                if roomDef and roomDef.type == "Combat" then
                    table.insert(combatRooms, id)
                end
            end
            if #combatRooms > 0 then
                table.insert(sequence, combatRooms[math.random(#combatRooms)])
            end
        end
    end

    if floorDef.bossId and Util.contains(allowed, "boss_lair") then
        table.insert(sequence, "boss_lair")
    else
        table.insert(sequence, "wide_battleground")
    end

    return sequence
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Loads a complete floor: generates room sequence, builds geometry,
-- applies biome theme, and builds corridors between rooms.
function DungeonManager.loadFloor(floorNumber: number, onComplete: () -> ())
    DungeonManager.unload()

    local floorDef     = DungeonData.getFloor(floorNumber)
    local theme        = getTheme(floorDef.biome)

    local floorFolder  = Instance.new("Folder")
    floorFolder.Name   = string.format("Floor_%d", floorNumber)
    floorFolder.Parent = Workspace
    currentFloorFolder = floorFolder

    local roomSequence = pickRoomSequence(floorDef)
    roomInstances      = {}

    local prevRoomEndZ: number? = nil

    for i, templateId in roomSequence do
        local template = DungeonData.Rooms[templateId]
        if not template then continue end

        local origin = Vector3.new(
            0, 0,
            (i - 1) * (Constants.DUNGEON_ROOM_SIZE.Z + Constants.DUNGEON_CORRIDOR_WIDTH)
        )

        -- Build corridor from previous room's end to this room's start
        if prevRoomEndZ ~= nil then
            buildCorridor(prevRoomEndZ, origin.Z, floorFolder, theme)
        end

        local roomFolder  = Instance.new("Folder")
        roomFolder.Name   = string.format("Room_%d_%s", i, templateId)
        roomFolder.Parent = floorFolder

        local built = buildRoomFromLayout(template.layout, origin, roomFolder, theme)

        local roomModel   = Instance.new("Model")
        roomModel.Name    = roomFolder.Name
        roomModel.Parent  = roomFolder

        table.insert(roomInstances, {
            model           = roomModel,
            spawnPoints     = built.spawnPoints,
            doors           = built.doors,
            lootPoints      = built.lootPoints,
            upgradeStations = built.upgradeStations,
            isBoss          = template.type == "Boss",
            isLoot          = template.type == "Loot",
            isSafe          = template.type == "Safe",
        })

        prevRoomEndZ = origin.Z + #template.layout * TILE_SIZE
    end

    task.defer(onComplete)
end

-- Loads just a single room (used when advancing through already-built floors).
function DungeonManager.loadRoom(_floorNumber: number, _roomIndex: number, onComplete: () -> ())
    task.defer(onComplete)
end

-- ─── Door Control ─────────────────────────────────────────────────────────────

-- Locks all doors in a room: solid, semi-transparent red barrier.
function DungeonManager.lockRoomDoors(roomIndex: number)
    local room = roomInstances[roomIndex]
    if not room then return end
    for _, door in room.doors do
        door.CanCollide   = true
        door.Transparency = 0.5
        door.BrickColor   = BrickColor.new("Bright red")
        door.Size         = Vector3.new(door.Size.X, Constants.DUNGEON_ROOM_SIZE.Y, door.Size.Z)
    end
end

-- Unlocks all doors in a room: back to invisible passthrough.
function DungeonManager.unlockRoomDoors(roomIndex: number)
    local room = roomInstances[roomIndex]
    if not room then return end
    for _, door in room.doors do
        door.CanCollide   = false
        door.Transparency = 1
        door.Size         = Vector3.new(door.Size.X, 1, door.Size.Z)
    end
end

-- Returns true if the room should have its doors locked during combat.
function DungeonManager.isRoomLockable(_floorNumber: number, roomIndex: number): boolean
    local room = roomInstances[roomIndex]
    return room ~= nil and not room.isSafe and not room.isLoot
end

-- ─── Queries ──────────────────────────────────────────────────────────────────

function DungeonManager.getRoomSpawnPoints(roomIndex: number): { Vector3 }
    local room = roomInstances[roomIndex]
    if room then return room.spawnPoints end
    return {}
end

function DungeonManager.getRoomLootPoints(roomIndex: number): { Vector3 }
    local room = roomInstances[roomIndex]
    if room then return room.lootPoints end
    return {}
end

function DungeonManager.getRoomUpgradeStations(roomIndex: number): { Vector3 }
    local room = roomInstances[roomIndex]
    if room then return room.upgradeStations end
    return {}
end

function DungeonManager.isBossRoom(_floorNumber: number, roomIndex: number): boolean
    local room = roomInstances[roomIndex]
    return room ~= nil and room.isBoss
end

function DungeonManager.isLastRoom(_floorNumber: number, roomIndex: number): boolean
    return roomIndex >= #roomInstances
end

-- Destroys all current floor geometry.
function DungeonManager.unload()
    if currentFloorFolder then
        currentFloorFolder:Destroy()
        currentFloorFolder = nil
    end
    roomInstances = {}
end

return DungeonManager
