--!strict
-- DungeonData.lua
-- Defines dungeon floors, room templates, enemy spawn tables, and layout rules.

export type SpawnEntry = {
    brainrotId: string,
    weight: number,       -- relative weight for weighted random selection
    minFloor: number,     -- earliest floor this enemy can appear
    maxCount: number,     -- max spawns of this type per room (0 = unlimited)
}

export type RoomTemplate = {
    id: string,
    displayName: string,
    type: "Combat" | "Loot" | "Shop" | "Boss" | "Safe",
    -- Tile layout key: "X" = wall, "." = floor, "D" = door, "S" = spawn, "L" = loot
    -- Each string is a row (top-down); use DungeonManager to instantiate
    layout: { string },
    enemyCountRange: { min: number, max: number },
    -- Override the floor's spawn table with specific entries (optional)
    forcedSpawns: { SpawnEntry }?,
    -- Props / decorations to scatter (asset IDs, filled by environment artists)
    decorations: { string },
}

export type FloorDef = {
    floorNumber: number,
    displayName: string,
    theme: string,   -- drives material/lighting/music in DungeonManager
    biome: "Underground" | "Ruins" | "Swamp" | "Tundra" | "Volcano" | "Chaos",

    -- Spawn table for this floor (weighted random)
    spawnTable: { SpawnEntry },

    -- Which room templates are allowed on this floor
    allowedRoomIds: { string },

    -- Boss that appears at the end of this floor
    bossId: string?,

    -- Modifiers applied to all enemies on this floor
    enemyModifiers: {
        healthMultiplier: number,
        damageMultiplier: number,
        speedMultiplier: number,
    },

    -- Music track asset IDs
    ambientSoundId: string,
    bossMusicId: string?,
}

-- ─── Room Templates ──────────────────────────────────────────────────────────

local Rooms: { [string]: RoomTemplate } = {}

Rooms["small_arena"] = {
    id          = "small_arena",
    displayName = "Small Arena",
    type        = "Combat",
    layout      = {
        "XXXDXXXX",   -- Z-axis door at col 4, centre X = 28
        "X......X",
        "X..SS..X",
        "XD....DX",
        "X..SS..X",
        "X......X",
        "XXXDXXXX",
    },
    enemyCountRange = { min = 3, max = 6 },
    forcedSpawns    = nil,
    decorations     = {
        "rbxassetid://PLACEHOLDER_torch",
        "rbxassetid://PLACEHOLDER_barrel",
    },
}

Rooms["corridor_ambush"] = {
    id          = "corridor_ambush",
    displayName = "Corridor Ambush",
    type        = "Combat",
    layout      = {
        "XXXDXXX",   -- widened to 7 cols to align door at col 4
        "X.....X",
        "X..S..X",
        "D.....D",
        "X..S..X",
        "X.....X",
        "XXXDXXX",
    },
    enemyCountRange = { min = 2, max = 4 },
    forcedSpawns    = nil,
    decorations     = {
        "rbxassetid://PLACEHOLDER_cracked_wall",
    },
}

Rooms["wide_battleground"] = {
    id          = "wide_battleground",
    displayName = "Wide Battleground",
    type        = "Combat",
    layout      = {
        "XXXDXXXXXXXX",   -- door at col 4
        "X..........X",
        "X.SSSS.SSS.X",
        "D..........D",
        "X.SSS..SSS.X",
        "X..........X",
        "XXXDXXXXXXXX",
    },
    enemyCountRange = { min = 7, max = 12 },
    forcedSpawns    = nil,
    decorations     = {
        "rbxassetid://PLACEHOLDER_pillar",
        "rbxassetid://PLACEHOLDER_rubble",
        "rbxassetid://PLACEHOLDER_torch",
    },
}

Rooms["loot_chamber"] = {
    id          = "loot_chamber",
    displayName = "Loot Chamber",
    type        = "Loot",
    layout      = {
        "XXXDXXX",   -- door at col 4
        "X.LLL.X",
        "X.....X",
        "D.....D",
        "X.....X",
        "X.LLL.X",
        "XXXDXXX",
    },
    enemyCountRange = { min = 0, max = 0 },
    forcedSpawns    = nil,
    decorations     = {
        "rbxassetid://PLACEHOLDER_chest_gold",
        "rbxassetid://PLACEHOLDER_pedestal",
    },
}

Rooms["safe_room"] = {
    id          = "safe_room",
    displayName = "Safe Room",
    type        = "Safe",
    layout      = {
        "XXXDXXX",   -- door at col 4
        "X..U..X",   -- 'U' = upgrade station (anvil)
        "X.....X",
        "D.....D",
        "X.....X",
        "X.....X",
        "XXXDXXX",
    },
    enemyCountRange = { min = 0, max = 0 },
    forcedSpawns    = nil,
    decorations     = {
        "rbxassetid://PLACEHOLDER_campfire",
        "rbxassetid://PLACEHOLDER_healing_fountain",
    },
}

Rooms["boss_lair"] = {
    id          = "boss_lair",
    displayName = "Boss Lair",
    type        = "Boss",
    layout      = {
        "XXXDXXXXXXXXXXXX",   -- door at col 4
        "X..............X",
        "X..............X",
        "X......BB......X",   -- 'B' = boss arena floor (red tint)
        "D..............X",
        "X......BB......X",
        "X..............X",
        "X..............X",
        "XXXDXXXXXXXXXXXX",
    },
    enemyCountRange = { min = 1, max = 1 },
    forcedSpawns    = nil,
    decorations     = {
        "rbxassetid://PLACEHOLDER_boss_throne",
        "rbxassetid://PLACEHOLDER_skull_pile",
        "rbxassetid://PLACEHOLDER_chains",
    },
}

-- ─── Floor Definitions ───────────────────────────────────────────────────────

local Floors: { FloorDef } = {}

-- Floor 1 – The Entrance Ruins
table.insert(Floors, {
    floorNumber  = 1,
    displayName  = "The Entrance Ruins",
    theme        = "Ruins",
    biome        = "Ruins",

    spawnTable = {
        { brainrotId = "tung_tung_tung",   weight = 50, minFloor = 1, maxCount = 4 },
        { brainrotId = "tralalero_tralala", weight = 50, minFloor = 1, maxCount = 6 },
    },

    allowedRoomIds = { "small_arena", "corridor_ambush", "loot_chamber", "safe_room" },
    bossId         = nil,

    enemyModifiers = {
        healthMultiplier = 1.0,
        damageMultiplier = 1.0,
        speedMultiplier  = 1.0,
    },

    ambientSoundId = "rbxassetid://PLACEHOLDER_ruins_ambient",
    bossMusicId    = nil,
})

-- Floor 2 – Bombardiro's Cradle
table.insert(Floors, {
    floorNumber  = 2,
    displayName  = "Bombardiro's Cradle",
    theme        = "Underground",
    biome        = "Underground",

    spawnTable = {
        { brainrotId = "tung_tung_tung",      weight = 30, minFloor = 1, maxCount = 3 },
        { brainrotId = "tralalero_tralala",    weight = 20, minFloor = 1, maxCount = 5 },
        { brainrotId = "bombardiro_crocodilo", weight = 40, minFloor = 2, maxCount = 2 },
        { brainrotId = "brrr_brrr_patapim",   weight = 10, minFloor = 2, maxCount = 2 },
    },

    allowedRoomIds = { "small_arena", "wide_battleground", "loot_chamber", "safe_room" },
    bossId         = nil,

    enemyModifiers = {
        healthMultiplier = 1.15,
        damageMultiplier = 1.10,
        speedMultiplier  = 1.05,
    },

    ambientSoundId = "rbxassetid://PLACEHOLDER_cave_ambient",
    bossMusicId    = nil,
})

-- Floor 3 – Boneca's Swamp
table.insert(Floors, {
    floorNumber  = 3,
    displayName  = "Boneca's Swamp",
    theme        = "Swamp",
    biome        = "Swamp",

    spawnTable = {
        { brainrotId = "tralalero_tralala",    weight = 25, minFloor = 1, maxCount = 8 },
        { brainrotId = "bombardiro_crocodilo", weight = 25, minFloor = 2, maxCount = 2 },
        { brainrotId = "boneca_ambalabu",      weight = 30, minFloor = 3, maxCount = 2 },
        { brainrotId = "cappucino_assassino",  weight = 20, minFloor = 3, maxCount = 2 },
    },

    allowedRoomIds = { "small_arena", "wide_battleground", "corridor_ambush", "loot_chamber" },
    bossId         = nil,

    enemyModifiers = {
        healthMultiplier = 1.30,
        damageMultiplier = 1.20,
        speedMultiplier  = 1.05,
    },

    ambientSoundId = "rbxassetid://PLACEHOLDER_swamp_ambient",
    bossMusicId    = nil,
})

-- Floor 4 – Frigo's Tundra
table.insert(Floors, {
    floorNumber  = 4,
    displayName  = "Frigo's Tundra",
    theme        = "Tundra",
    biome        = "Tundra",

    spawnTable = {
        { brainrotId = "boneca_ambalabu",     weight = 20, minFloor = 3, maxCount = 2 },
        { brainrotId = "cappucino_assassino", weight = 20, minFloor = 3, maxCount = 3 },
        { brainrotId = "brrr_brrr_patapim",  weight = 25, minFloor = 2, maxCount = 3 },
        { brainrotId = "frigo_camelo",        weight = 35, minFloor = 4, maxCount = 2 },
    },

    allowedRoomIds = { "small_arena", "wide_battleground", "loot_chamber", "safe_room" },
    bossId         = nil,

    enemyModifiers = {
        healthMultiplier = 1.50,
        damageMultiplier = 1.35,
        speedMultiplier  = 1.10,
    },

    ambientSoundId = "rbxassetid://PLACEHOLDER_tundra_ambient",
    bossMusicId    = nil,
})

-- Floor 5 – The Grande Lair (BOSS FLOOR)
table.insert(Floors, {
    floorNumber  = 5,
    displayName  = "The Grande Lair",
    theme        = "Chaos",
    biome        = "Chaos",

    spawnTable = {
        { brainrotId = "tung_tung_tung",      weight = 30, minFloor = 1, maxCount = 4 },
        { brainrotId = "bombardiro_crocodilo", weight = 30, minFloor = 2, maxCount = 2 },
        { brainrotId = "frigo_camelo",         weight = 40, minFloor = 4, maxCount = 1 },
    },

    allowedRoomIds = { "wide_battleground", "loot_chamber", "boss_lair", "safe_room" },
    bossId         = "grande_tung_tung",

    enemyModifiers = {
        healthMultiplier = 1.75,
        damageMultiplier = 1.50,
        speedMultiplier  = 1.15,
    },

    ambientSoundId = "rbxassetid://PLACEHOLDER_chaos_ambient",
    bossMusicId    = "rbxassetid://PLACEHOLDER_boss_music_grande",
})

-- ─── Dynamic Floor Generator ─────────────────────────────────────────────────
-- For floors beyond the defined list, generate a scaled floor definition.

local function generateDynamicFloor(floorNumber: number): FloorDef
    local scale = 1 + (floorNumber - 1) * 0.18
    return {
        floorNumber  = floorNumber,
        displayName  = string.format("Floor %d — Chaos Depths", floorNumber),
        theme        = "Chaos",
        biome        = "Chaos",

        spawnTable = {
            { brainrotId = "tung_tung_tung",      weight = 20, minFloor = 1, maxCount = 5 },
            { brainrotId = "tralalero_tralala",    weight = 20, minFloor = 1, maxCount = 8 },
            { brainrotId = "bombardiro_crocodilo", weight = 20, minFloor = 2, maxCount = 3 },
            { brainrotId = "boneca_ambalabu",      weight = 15, minFloor = 3, maxCount = 3 },
            { brainrotId = "cappucino_assassino",  weight = 15, minFloor = 3, maxCount = 4 },
            { brainrotId = "frigo_camelo",         weight = 10, minFloor = 4, maxCount = 2 },
        },

        allowedRoomIds = { "small_arena", "wide_battleground", "corridor_ambush",
                           "loot_chamber", "boss_lair", "safe_room" },
        bossId = (floorNumber % 5 == 0) and "il_bombardiro_supremo" or nil,

        enemyModifiers = {
            healthMultiplier = scale,
            damageMultiplier = scale * 0.9,
            speedMultiplier  = 1 + (floorNumber - 1) * 0.05,
        },

        ambientSoundId = "rbxassetid://PLACEHOLDER_chaos_ambient",
        bossMusicId    = "rbxassetid://PLACEHOLDER_boss_music_supremo",
    }
end

-- ─── Public API ──────────────────────────────────────────────────────────────

local DungeonData = {}
DungeonData.Rooms  = Rooms
DungeonData.Floors = Floors

-- Returns the floor definition for any floor number (generates if beyond static list).
function DungeonData.getFloor(floorNumber: number): FloorDef
    if floorNumber <= #Floors then
        return Floors[floorNumber]
    end
    return generateDynamicFloor(floorNumber)
end

return DungeonData
