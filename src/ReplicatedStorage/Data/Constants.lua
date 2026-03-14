--!strict
-- Constants.lua
-- Global game constants shared between server and client.

local Constants = {}

-- ─── Game Settings ──────────────────────────────────────────────────────────

Constants.GAME_VERSION = "0.1.0"
Constants.MAX_PLAYERS_PER_SERVER = 4

-- Top-down camera height above the player (studs)
Constants.CAMERA_HEIGHT = 40
Constants.CAMERA_ANGLE = -75  -- degrees pitch

-- ─── Player Stats ───────────────────────────────────────────────────────────

Constants.BASE_PLAYER_SPEED = 16
Constants.BASE_PLAYER_HEALTH = 100
Constants.BASE_PLAYER_STAMINA = 100
Constants.STAMINA_REGEN_RATE = 20   -- per second
Constants.STAMINA_SPRINT_COST = 30  -- per second
Constants.DODGE_STAMINA_COST = 25
Constants.DODGE_DISTANCE = 10
Constants.DODGE_COOLDOWN = 0.8      -- seconds

-- ─── Dungeon ────────────────────────────────────────────────────────────────

Constants.DUNGEON_ROOM_SIZE = Vector3.new(80, 10, 80)
Constants.DUNGEON_CORRIDOR_WIDTH = 14
Constants.ROOMS_PER_FLOOR = 7
Constants.BOSS_ROOM_SPAWN_FLOOR = 5  -- every Nth floor has a boss room
Constants.LOOT_ROOM_CHANCE = 0.25    -- 25% rooms are loot rooms

-- ─── Enemy ──────────────────────────────────────────────────────────────────

Constants.ENEMY_AGGRO_RANGE = 35        -- studs; brainrot detects player
Constants.ENEMY_DEAGGRO_RANGE = 60      -- studs; brainrot gives up chase
Constants.ENEMY_PATH_UPDATE_RATE = 0.2  -- seconds between pathfinding updates
Constants.MAX_ENEMIES_PER_ROOM = 12

-- Wave scaling multipliers per floor
Constants.ENEMY_HEALTH_SCALE_PER_FLOOR = 0.15   -- +15% hp each floor
Constants.ENEMY_DAMAGE_SCALE_PER_FLOOR = 0.10   -- +10% dmg each floor
Constants.ENEMY_COUNT_SCALE_PER_FLOOR  = 0.08   -- +8% enemy count each floor

-- ─── Loot ───────────────────────────────────────────────────────────────────

Constants.LOOT_DROP_CHANCE = 0.40       -- base drop rate per enemy
Constants.GOLD_DROP_MIN = 5
Constants.GOLD_DROP_MAX = 25
Constants.RARE_WEAPON_CHANCE = 0.05
Constants.EPIC_WEAPON_CHANCE = 0.02
Constants.LEGENDARY_WEAPON_CHANCE = 0.005

-- ─── XP / Progression ───────────────────────────────────────────────────────

Constants.XP_PER_LEVEL_BASE = 100
Constants.XP_PER_LEVEL_EXPONENT = 1.4  -- xp needed = base * (level ^ exponent)
Constants.MAX_PLAYER_LEVEL = 100

-- ─── Rarity Colors (BrickColor names) ───────────────────────────────────────

Constants.RARITY_COLORS = {
    Common    = Color3.fromRGB(180, 180, 180),
    Uncommon  = Color3.fromRGB(80,  220,  80),
    Rare      = Color3.fromRGB(60,  120, 255),
    Epic      = Color3.fromRGB(160,  60, 255),
    Legendary = Color3.fromRGB(255, 165,   0),
}

-- ─── UI ─────────────────────────────────────────────────────────────────────

Constants.HUD_HEALTH_BAR_COLOR   = Color3.fromRGB(220,  50,  50)
Constants.HUD_STAMINA_BAR_COLOR  = Color3.fromRGB( 50, 200, 255)
Constants.HUD_XP_BAR_COLOR       = Color3.fromRGB(255, 215,   0)

-- ─── Remote Names ───────────────────────────────────────────────────────────
-- Single source of truth for all RemoteEvent / RemoteFunction names.

Constants.Remotes = {
    -- Player → Server
    PlayerAttack          = "PlayerAttack",
    PlayerDodge           = "PlayerDodge",
    PlayerInteract        = "PlayerInteract",
    EquipWeapon           = "EquipWeapon",
    RequestNextRoom       = "RequestNextRoom",

    -- Server → Player
    DungeonRoomLoaded     = "DungeonRoomLoaded",
    EnemyHealthUpdated    = "EnemyHealthUpdated",
    PlayerStatsUpdated    = "PlayerStatsUpdated",
    LootDropped           = "LootDropped",
    FloorCompleted        = "FloorCompleted",
    GameOver              = "GameOver",
    BossSpawned           = "BossSpawned",
}

return Constants
