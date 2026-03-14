--!strict
-- DungeonManager.lua (ModuleScript, required by GameManager)
-- Handles procedural dungeon generation, room instantiation, and floor layout.
-- Rooms are built from the layout strings in DungeonData then populated with
-- props and connection corridors.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local DungeonData = require(ReplicatedStorage.Data.DungeonData)
local Constants   = require(ReplicatedStorage.Data.Constants)
local Util        = require(ReplicatedStorage.Modules.Util)

-- ─── Types ───────────────────────────────────────────────────────────────────

type RoomInstance = {
    model:      Model,
    spawnPoints:{ Vector3 },
    doors:      { BasePart },
    lootPoints: { Vector3 },
    isBoss:     boolean,
    isLoot:     boolean,
    isSafe:     boolean,
}

-- ─── State ───────────────────────────────────────────────────────────────────

local DungeonManager = {}

local currentFloorFolder: Folder? = nil
local roomInstances: { RoomInstance } = {}
local TILE_SIZE = 8  -- studs per layout character

-- ─── Private Helpers ─────────────────────────────────────────────────────────

-- Converts a layout row string into part placements in the workspace.
local function buildRoomFromLayout(
    layout: { string },
    origin: Vector3,
    roomFolder: Folder
): { spawnPoints: { Vector3 }, doors: { BasePart }, lootPoints: { Vector3 } }
    local spawnPoints: { Vector3 } = {}
    local doors:       { BasePart } = {}
    local lootPoints:  { Vector3 } = {}

    for row, rowStr in layout do
        for col = 1, #rowStr do
            local char = string.sub(rowStr, col, col)
            local pos  = origin + Vector3.new(
                (col - 1) * TILE_SIZE,
                0,
                (row - 1) * TILE_SIZE
            )

            if char == "X" then
                -- Wall tile
                local wall       = Instance.new("Part")
                wall.Name        = "Wall"
                wall.Size        = Vector3.new(TILE_SIZE, Constants.DUNGEON_ROOM_SIZE.Y, TILE_SIZE)
                wall.Position    = pos + Vector3.new(TILE_SIZE / 2, Constants.DUNGEON_ROOM_SIZE.Y / 2, TILE_SIZE / 2)
                wall.Anchored    = true
                wall.Material    = Enum.Material.SmoothPlastic
                wall.BrickColor  = BrickColor.new("Dark stone grey")
                wall.Parent      = roomFolder

            elseif char == "." then
                -- Floor tile
                local floor      = Instance.new("Part")
                floor.Name       = "Floor"
                floor.Size       = Vector3.new(TILE_SIZE, 1, TILE_SIZE)
                floor.Position   = pos + Vector3.new(TILE_SIZE / 2, -0.5, TILE_SIZE / 2)
                floor.Anchored   = true
                floor.Material   = Enum.Material.SmoothPlastic
                floor.BrickColor = BrickColor.new("Medium stone grey")
                floor.Parent     = roomFolder

            elseif char == "D" then
                -- Door tile (walkable, tracked for AI pathfinding links)
                local door      = Instance.new("Part")
                door.Name       = "Door"
                door.Size       = Vector3.new(TILE_SIZE, 1, TILE_SIZE)
                door.Position   = pos + Vector3.new(TILE_SIZE / 2, -0.5, TILE_SIZE / 2)
                door.Anchored   = true
                door.Transparency = 1
                door.CanCollide = false
                door.Parent     = roomFolder
                table.insert(doors, door)

            elseif char == "S" then
                -- Enemy spawn marker
                local floor2    = Instance.new("Part")
                floor2.Name     = "Floor"
                floor2.Size     = Vector3.new(TILE_SIZE, 1, TILE_SIZE)
                floor2.Position = pos + Vector3.new(TILE_SIZE / 2, -0.5, TILE_SIZE / 2)
                floor2.Anchored = true
                floor2.Material = Enum.Material.SmoothPlastic
                floor2.BrickColor = BrickColor.new("Medium stone grey")
                floor2.Parent   = roomFolder
                table.insert(spawnPoints, pos + Vector3.new(TILE_SIZE / 2, 1, TILE_SIZE / 2))

            elseif char == "L" then
                -- Loot spawn point
                local lootFloor     = Instance.new("Part")
                lootFloor.Name      = "LootFloor"
                lootFloor.Size      = Vector3.new(TILE_SIZE, 1, TILE_SIZE)
                lootFloor.Position  = pos + Vector3.new(TILE_SIZE / 2, -0.5, TILE_SIZE / 2)
                lootFloor.Anchored  = true
                lootFloor.Material  = Enum.Material.SmoothPlastic
                lootFloor.BrickColor= BrickColor.new("Bright yellow")
                lootFloor.Parent    = roomFolder
                table.insert(lootPoints, pos + Vector3.new(TILE_SIZE / 2, 1.5, TILE_SIZE / 2))
            end
        end
    end

    return { spawnPoints = spawnPoints, doors = doors, lootPoints = lootPoints }
end

-- Chooses a sequence of room template IDs for a floor, ending with a boss room
-- if the floor has a boss.
local function pickRoomSequence(floorDef: DungeonData.FloorDef): { string }
    local allowed  = Util.shallowCopy(floorDef.allowedRoomIds)
    local sequence: { string } = {}
    local roomCount = Constants.ROOMS_PER_FLOOR

    -- Always start with a safe room
    table.insert(sequence, "safe_room")

    for i = 2, roomCount - 1 do
        -- Occasionally insert a loot room
        if math.random() < Constants.LOOT_ROOM_CHANCE and Util.contains(allowed, "loot_chamber") then
            table.insert(sequence, "loot_chamber")
        else
            -- Pick a weighted combat room
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

    -- Last room: boss lair if there's a boss, otherwise wide combat
    if floorDef.bossId and Util.contains(allowed, "boss_lair") then
        table.insert(sequence, "boss_lair")
    else
        table.insert(sequence, "wide_battleground")
    end

    return sequence
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Loads a complete floor: generates room sequence, builds geometry, stores instances.
function DungeonManager.loadFloor(floorNumber: number, onComplete: () -> ())
    DungeonManager.unload()

    local floorDef     = DungeonData.getFloor(floorNumber)
    local floorFolder  = Instance.new("Folder")
    floorFolder.Name   = string.format("Floor_%d", floorNumber)
    floorFolder.Parent = Workspace
    currentFloorFolder = floorFolder

    local roomSequence = pickRoomSequence(floorDef)
    roomInstances      = {}

    for i, templateId in roomSequence do
        local template   = DungeonData.Rooms[templateId]
        if not template then continue end

        local roomFolder = Instance.new("Folder")
        roomFolder.Name  = string.format("Room_%d_%s", i, templateId)
        roomFolder.Parent= floorFolder

        -- Offset each room along the Z axis for a simple linear layout
        local origin = Vector3.new(0, 0, (i - 1) * (Constants.DUNGEON_ROOM_SIZE.Z + Constants.DUNGEON_CORRIDOR_WIDTH))

        local built = buildRoomFromLayout(template.layout, origin, roomFolder)

        local roomModel    = Instance.new("Model")
        roomModel.Name     = roomFolder.Name
        roomModel.Parent   = roomFolder

        table.insert(roomInstances, {
            model       = roomModel,
            spawnPoints = built.spawnPoints,
            doors       = built.doors,
            lootPoints  = built.lootPoints,
            isBoss      = template.type == "Boss",
            isLoot      = template.type == "Loot",
            isSafe      = template.type == "Safe",
        })
    end

    task.defer(onComplete)
end

-- Loads just a single room (used when advancing through already-built floors).
function DungeonManager.loadRoom(floorNumber: number, roomIndex: number, onComplete: () -> ())
    -- In this architecture the entire floor is pre-built; this callback signals
    -- readiness for enemy spawning on the next room.
    task.defer(onComplete)
end

-- Returns spawn points for the given room.
function DungeonManager.getRoomSpawnPoints(roomIndex: number): { Vector3 }
    local room = roomInstances[roomIndex]
    if room then return room.spawnPoints end
    return {}
end

-- Returns loot point positions for the given room.
function DungeonManager.getRoomLootPoints(roomIndex: number): { Vector3 }
    local room = roomInstances[roomIndex]
    if room then return room.lootPoints end
    return {}
end

-- Returns true if the room at roomIndex on floorNumber is a boss room.
function DungeonManager.isBossRoom(floorNumber: number, roomIndex: number): boolean
    local room = roomInstances[roomIndex]
    return room ~= nil and room.isBoss
end

-- Returns true if roomIndex is the last room on the floor.
function DungeonManager.isLastRoom(floorNumber: number, roomIndex: number): boolean
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
