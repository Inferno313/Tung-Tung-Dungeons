--!strict
-- BrainrotData.lua
-- Defines every Brainrot enemy type: stats, AI behaviour, abilities, and lore.
-- Add new brainrots here — the EnemyManager will pick them up automatically.

export type AbilityDef = {
    name: string,
    cooldown: number,        -- seconds between uses
    range: number,           -- stud range to activate
    damage: number,
    description: string,
}

export type BrainrotDef = {
    id: string,
    displayName: string,
    lore: string,

    -- Base stats (scaled per floor by Constants)
    health: number,
    speed: number,
    damage: number,
    attackRange: number,
    attackRate: number,      -- attacks per second
    xpReward: number,
    goldReward: { min: number, max: number },

    -- AI archetype drives the state machine in EnemyManager
    archetype: "Charger" | "Ranged" | "Swarm" | "Tank" | "Stealth" | "Boss",

    -- Optional elemental affinity for resistances / weaknesses
    element: "None" | "Fire" | "Ice" | "Electric" | "Chaos",

    -- Unique abilities (can be empty)
    abilities: { AbilityDef },

    -- Asset IDs (filled in by artists in Roblox Studio)
    modelId: string,
    soundIdAggro: string,
    soundIdAttack: string,
    soundIdDeath: string,

    -- Drop table overrides (nil = use global Constants rates)
    dropTableOverride: { [string]: number }?,
}

-- ─── Brainrot Roster ─────────────────────────────────────────────────────────

local BrainrotData: { [string]: BrainrotDef } = {}

-- ─── COMMON TIER ─────────────────────────────────────────────────────────────

BrainrotData["tung_tung_tung"] = {
    id          = "tung_tung_tung",
    displayName = "Tung Tung Tung Sahur",
    lore        = "A rhythmic menace that charges at the sound of its own name. "
               .. "The faster you run, the louder it drums.",

    health      = 80,
    speed       = 20,
    damage      = 14,
    attackRange = 4,
    attackRate  = 1.2,
    xpReward    = 10,
    goldReward  = { min = 5, max = 12 },

    archetype   = "Charger",
    element     = "None",

    abilities   = {
        {
            name        = "Drum Rush",
            cooldown    = 6,
            range       = 30,
            damage      = 28,
            description = "Charges in a straight line, dealing double damage on impact.",
        },
    },

    modelId      = "rbxassetid://102119645434654",
    soundIdAggro = "rbxassetid://PLACEHOLDER_tung_tung_aggro",
    soundIdAttack= "rbxassetid://PLACEHOLDER_tung_tung_attack",
    soundIdDeath = "rbxassetid://PLACEHOLDER_tung_tung_death",
    dropTableOverride = nil,
}

BrainrotData["tralalero_tralala"] = {
    id          = "tralalero_tralala",
    displayName = "Tralalero Tralala",
    lore        = "Spawns in packs and circles its prey while singing off-key. "
               .. "Individually weak — collectively terrifying.",

    health      = 40,
    speed       = 26,
    damage      = 8,
    attackRange = 3,
    attackRate  = 1.8,
    xpReward    = 6,
    goldReward  = { min = 2, max = 8 },

    archetype   = "Swarm",
    element     = "None",

    abilities   = {
        {
            name        = "Pack Frenzy",
            cooldown    = 10,
            range       = 20,
            damage      = 5,
            description = "All nearby Tralaleros gain +40% speed for 5 seconds.",
        },
    },

    modelId      = "rbxassetid://PLACEHOLDER_tralalero",
    soundIdAggro = "rbxassetid://PLACEHOLDER_tralalero_aggro",
    soundIdAttack= "rbxassetid://PLACEHOLDER_tralalero_attack",
    soundIdDeath = "rbxassetid://PLACEHOLDER_tralalero_death",
    dropTableOverride = nil,
}

BrainrotData["bombardiro_crocodilo"] = {
    id          = "bombardiro_crocodilo",
    displayName = "Bombardiro Crocodilo",
    lore        = "Half crocodile, half bomber. Fully determined to ruin your day "
               .. "from a comfortable distance.",

    health      = 100,
    speed       = 12,
    damage      = 18,
    attackRange = 28,
    attackRate  = 0.6,
    xpReward    = 15,
    goldReward  = { min = 8, max = 18 },

    archetype   = "Ranged",
    element     = "Fire",

    abilities   = {
        {
            name        = "Bomb Barrage",
            cooldown    = 8,
            range       = 30,
            damage      = 35,
            description = "Lobs three explosive projectiles in an arc, each leaving a fire puddle.",
        },
        {
            name        = "Napalm Dive",
            cooldown    = 20,
            range       = 15,
            damage      = 50,
            description = "Leaps into the air and crashes down, creating a fire ring on impact.",
        },
    },

    modelId      = "rbxassetid://PLACEHOLDER_bombardiro",
    soundIdAggro = "rbxassetid://PLACEHOLDER_bombardiro_aggro",
    soundIdAttack= "rbxassetid://PLACEHOLDER_bombardiro_attack",
    soundIdDeath = "rbxassetid://PLACEHOLDER_bombardiro_death",
    dropTableOverride = nil,
}

-- ─── UNCOMMON TIER ───────────────────────────────────────────────────────────

BrainrotData["boneca_ambalabu"] = {
    id          = "boneca_ambalabu",
    displayName = "Boneca Ambalabu",
    lore        = "An ancient doll-frog of enormous patience and even more enormous "
               .. "hit points. It doesn't rush. It doesn't need to.",

    health      = 280,
    speed       = 8,
    damage      = 22,
    attackRange = 5,
    attackRate  = 0.5,
    xpReward    = 25,
    goldReward  = { min = 15, max = 30 },

    archetype   = "Tank",
    element     = "None",

    abilities   = {
        {
            name        = "Swamp Slam",
            cooldown    = 7,
            range       = 6,
            damage      = 44,
            description = "Slams the ground, stunning all players in a 6 stud radius for 1.5s.",
        },
        {
            name        = "Doll Shield",
            cooldown    = 18,
            range       = 0,
            damage      = 0,
            description = "Becomes briefly invincible and reflects 30% of incoming damage.",
        },
    },

    modelId      = "rbxassetid://PLACEHOLDER_boneca",
    soundIdAggro = "rbxassetid://PLACEHOLDER_boneca_aggro",
    soundIdAttack= "rbxassetid://PLACEHOLDER_boneca_attack",
    soundIdDeath = "rbxassetid://PLACEHOLDER_boneca_death",
    dropTableOverride = nil,
}

BrainrotData["brrr_brrr_patapim"] = {
    id          = "brrr_brrr_patapim",
    displayName = "Brrr Brrr Patapim",
    lore        = "Emits a chaotic field of noise that scrambles player controls. "
               .. "Nobody knows what it is. Nobody wants to find out.",

    health      = 120,
    speed       = 14,
    damage      = 12,
    attackRange = 15,
    attackRate  = 0.9,
    xpReward    = 20,
    goldReward  = { min = 10, max = 22 },

    archetype   = "Ranged",
    element     = "Electric",

    abilities   = {
        {
            name        = "Static Burst",
            cooldown    = 5,
            range       = 18,
            damage      = 20,
            description = "Releases an electric pulse that briefly inverts movement controls.",
        },
        {
            name        = "Pata-Pata Chain",
            cooldown    = 12,
            range       = 22,
            damage      = 15,
            description = "Chains electricity between up to 3 nearby players.",
        },
    },

    modelId      = "rbxassetid://PLACEHOLDER_patapim",
    soundIdAggro = "rbxassetid://PLACEHOLDER_patapim_aggro",
    soundIdAttack= "rbxassetid://PLACEHOLDER_patapim_attack",
    soundIdDeath = "rbxassetid://PLACEHOLDER_patapim_death",
    dropTableOverride = nil,
}

BrainrotData["cappucino_assassino"] = {
    id          = "cappucino_assassino",
    displayName = "Cappuccino Assassino",
    lore        = "A coffee-powered shadow. Vanishes when damaged, reappears behind "
               .. "you. Still somehow finds time to make latte art.",

    health      = 90,
    speed       = 22,
    damage      = 30,
    attackRange = 3,
    attackRate  = 0.8,
    xpReward    = 22,
    goldReward  = { min = 12, max = 25 },

    archetype   = "Stealth",
    element     = "None",

    abilities   = {
        {
            name        = "Espresso Vanish",
            cooldown    = 9,
            range       = 0,
            damage      = 0,
            description = "Turns invisible for 3 seconds and resets aggro.",
        },
        {
            name        = "Backstab Brew",
            cooldown    = 0,
            range       = 3,
            damage      = 60,
            description = "First attack from stealth deals triple damage.",
        },
    },

    modelId      = "rbxassetid://PLACEHOLDER_cappucino",
    soundIdAggro = "rbxassetid://PLACEHOLDER_cappucino_aggro",
    soundIdAttack= "rbxassetid://PLACEHOLDER_cappucino_attack",
    soundIdDeath = "rbxassetid://PLACEHOLDER_cappucino_death",
    dropTableOverride = nil,
}

-- ─── RARE TIER ───────────────────────────────────────────────────────────────

BrainrotData["frigo_camelo"] = {
    id          = "frigo_camelo",
    displayName = "Frigo Camelo",
    lore        = "A refrigerator camel from the tundra. Breathes ice, absorbs heat, "
               .. "and is very upset about global warming.",

    health      = 200,
    speed       = 11,
    damage      = 20,
    attackRange = 20,
    attackRate  = 0.7,
    xpReward    = 35,
    goldReward  = { min = 20, max = 40 },

    archetype   = "Ranged",
    element     = "Ice",

    abilities   = {
        {
            name        = "Blizzard Breath",
            cooldown    = 6,
            range       = 22,
            damage      = 30,
            description = "Sprays an ice cone, slowing hit players by 60% for 3s.",
        },
        {
            name        = "Permafrost Stomp",
            cooldown    = 15,
            range       = 10,
            damage      = 0,
            description = "Freezes the ground, creating an icy zone that slows movement.",
        },
        {
            name        = "Hump Missile",
            cooldown    = 25,
            range       = 35,
            damage      = 55,
            description = "Launches a giant ice shard across the room.",
        },
    },

    modelId      = "rbxassetid://PLACEHOLDER_frigo",
    soundIdAggro = "rbxassetid://PLACEHOLDER_frigo_aggro",
    soundIdAttack= "rbxassetid://PLACEHOLDER_frigo_attack",
    soundIdDeath = "rbxassetid://PLACEHOLDER_frigo_death",
    dropTableOverride = { ["rare_weapon"] = 0.12 },
}

-- ─── BOSS TIER ───────────────────────────────────────────────────────────────

BrainrotData["grande_tung_tung"] = {
    id          = "grande_tung_tung",
    displayName = "Grande Tung Tung Sahur",
    lore        = "The progenitor of all rhythm chaos. Its drum beats shatter walls, "
               .. "summon minions, and can be felt three dimensions away.",

    health      = 2000,
    speed       = 16,
    damage      = 40,
    attackRange = 8,
    attackRate  = 1.0,
    xpReward    = 200,
    goldReward  = { min = 100, max = 200 },

    archetype   = "Boss",
    element     = "Chaos",

    abilities   = {
        {
            name        = "Mega Drum Rush",
            cooldown    = 12,
            range       = 50,
            damage      = 80,
            description = "Charges across the entire room, knocking players into walls.",
        },
        {
            name        = "Summon Rhythmlings",
            cooldown    = 20,
            range       = 0,
            damage      = 0,
            description = "Spawns 4 Tung Tung Tung minions.",
        },
        {
            name        = "Beat Drop",
            cooldown    = 30,
            range       = 0,
            damage      = 60,
            description = "Phase 2 (below 50% HP): shockwaves radiate across the floor every 3s.",
        },
        {
            name        = "Chaos Rhythm",
            cooldown    = 45,
            range       = 0,
            damage      = 0,
            description = "Phase 3 (below 25% HP): all ability cooldowns halved, +50% speed.",
        },
    },

    modelId      = "rbxassetid://PLACEHOLDER_grande_tung",
    soundIdAggro = "rbxassetid://PLACEHOLDER_grande_tung_aggro",
    soundIdAttack= "rbxassetid://PLACEHOLDER_grande_tung_attack",
    soundIdDeath = "rbxassetid://PLACEHOLDER_grande_tung_death",
    dropTableOverride = {
        ["legendary_weapon"] = 0.30,
        ["epic_weapon"]      = 0.70,
    },
}

BrainrotData["il_bombardiro_supremo"] = {
    id          = "il_bombardiro_supremo",
    displayName = "Il Bombardiro Supremo",
    lore        = "Ancient air force general. Hundreds of years old. Still bitter. "
               .. "Equipped with weapons that should not legally exist in a dungeon.",

    health      = 3500,
    speed       = 10,
    damage      = 55,
    attackRange = 40,
    attackRate  = 0.5,
    xpReward    = 400,
    goldReward  = { min = 200, max = 400 },

    archetype   = "Boss",
    element     = "Fire",

    abilities   = {
        {
            name        = "Carpet Bomb",
            cooldown    = 8,
            range       = 40,
            damage      = 45,
            description = "Drops a row of bombs across the room.",
        },
        {
            name        = "Missile Volley",
            cooldown    = 15,
            range       = 40,
            damage      = 30,
            description = "Fires 8 homing missiles at all players simultaneously.",
        },
        {
            name        = "Nuclear Option",
            cooldown    = 40,
            range       = 0,
            damage      = 120,
            description = "Clears the entire room with a massive explosion — safe zones telegraphed 3s early.",
        },
        {
            name        = "Air Support",
            cooldown    = 30,
            range       = 0,
            damage      = 0,
            description = "Spawns 2 Bombardiro Crocodilos as aerial support.",
        },
    },

    modelId      = "rbxassetid://PLACEHOLDER_supremo",
    soundIdAggro = "rbxassetid://PLACEHOLDER_supremo_aggro",
    soundIdAttack= "rbxassetid://PLACEHOLDER_supremo_attack",
    soundIdDeath = "rbxassetid://PLACEHOLDER_supremo_death",
    dropTableOverride = {
        ["legendary_weapon"] = 0.60,
        ["epic_weapon"]      = 1.00,
    },
}

-- ─── Lookup Helpers ───────────────────────────────────────────────────────────

-- Returns a sorted list of all brainrot IDs in a given archetype.
function BrainrotData.getByArchetype(archetype: string): { string }
    local result = {}
    for id, def in BrainrotData do
        if type(def) == "table" and def.archetype == archetype then
            table.insert(result, id)
        end
    end
    table.sort(result)
    return result
end

-- Returns a list of all boss IDs.
function BrainrotData.getBosses(): { string }
    return BrainrotData.getByArchetype("Boss")
end

-- Returns a list of all non-boss brainrot IDs (for regular room spawns).
function BrainrotData.getRegularEnemies(): { string }
    local result = {}
    for id, def in BrainrotData do
        if type(def) == "table" and def.archetype ~= "Boss" then
            table.insert(result, id)
        end
    end
    table.sort(result)
    return result
end

return BrainrotData
