--!strict
-- WeaponData.lua
-- Defines every weapon players can find, equip, and upgrade in the dungeon.
-- Weapons are tied to a "class" (melee/ranged/magic) and a rarity tier.

export type WeaponEffect = {
    type: "Burn" | "Freeze" | "Shock" | "Bleed" | "Poison" | "Stun" | "Knockback",
    chance: number,   -- 0–1 probability per hit
    duration: number, -- seconds
    value: number,    -- damage per tick OR slow/stun amount
}

export type WeaponDef = {
    id: string,
    displayName: string,
    description: string,
    lore: string,

    class: "Melee" | "Ranged" | "Magic",
    rarity: "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary",
    element: "None" | "Fire" | "Ice" | "Electric" | "Chaos",

    -- Base combat stats
    damage: number,
    attackSpeed: number,   -- attacks per second
    range: number,         -- studs; melee reach or projectile range
    aoeRadius: number,     -- 0 = single target; >0 = area-of-effect radius

    -- Special behaviour flags
    isPiercing: boolean,   -- projectile passes through multiple enemies
    isHoming: boolean,     -- projectile tracks nearest target

    -- On-hit status effects (can be multiple)
    effects: { WeaponEffect },

    -- Upgrade scaling (applied each upgrade level up to maxUpgradeLevel)
    upgradeScaling: {
        damage: number,      -- flat bonus per level
        attackSpeed: number, -- flat bonus per level
    },
    maxUpgradeLevel: number,

    -- Asset IDs (filled by artists/animators in Roblox Studio)
    modelId: string,
    iconId: string,
    swingAnimId: string,
    projectileModelId: string?,
    soundIdSwing: string,
    soundIdHit: string,
}

-- ─── Weapon Roster ───────────────────────────────────────────────────────────

local WeaponData: { [string]: WeaponDef } = {}

-- ─── COMMON ─────────────────────────────────────────────────────────────────

WeaponData["wooden_club"] = {
    id          = "wooden_club",
    displayName = "Wooden Club",
    description = "A sturdy chunk of wood. Not glamorous, but gets the job done.",
    lore        = "Found outside the dungeon entrance. Still has bark on it.",

    class   = "Melee",
    rarity  = "Common",
    element = "None",

    damage      = 20,
    attackSpeed = 1.5,
    range       = 5,
    aoeRadius   = 0,

    isPiercing = false,
    isHoming   = false,
    effects    = {},

    upgradeScaling    = { damage = 4, attackSpeed = 0.05 },
    maxUpgradeLevel   = 5,

    modelId        = "rbxassetid://PLACEHOLDER_wooden_club_model",
    iconId         = "rbxassetid://PLACEHOLDER_wooden_club_icon",
    swingAnimId    = "rbxassetid://PLACEHOLDER_melee_swing_anim",
    soundIdSwing   = "rbxassetid://PLACEHOLDER_swing_swoosh",
    soundIdHit     = "rbxassetid://PLACEHOLDER_blunt_hit",
}

WeaponData["slingshot"] = {
    id          = "slingshot",
    displayName = "Slingshot",
    description = "Fires pebbles at reasonable velocity.",
    lore        = "Carved from a dungeon branch. Two of them, actually.",

    class   = "Ranged",
    rarity  = "Common",
    element = "None",

    damage      = 15,
    attackSpeed = 2.0,
    range       = 30,
    aoeRadius   = 0,

    isPiercing = false,
    isHoming   = false,
    effects    = {},

    upgradeScaling  = { damage = 3, attackSpeed = 0.1 },
    maxUpgradeLevel = 5,

    modelId           = "rbxassetid://PLACEHOLDER_slingshot_model",
    iconId            = "rbxassetid://PLACEHOLDER_slingshot_icon",
    swingAnimId       = "rbxassetid://PLACEHOLDER_ranged_shoot_anim",
    projectileModelId = "rbxassetid://PLACEHOLDER_pebble_projectile",
    soundIdSwing      = "rbxassetid://PLACEHOLDER_slingshot_shoot",
    soundIdHit        = "rbxassetid://PLACEHOLDER_pebble_hit",
}

-- ─── UNCOMMON ────────────────────────────────────────────────────────────────

WeaponData["drum_beater"] = {
    id          = "drum_beater",
    displayName = "Drum Beater",
    description = "A heavy mallet stolen from a defeated Tung Tung Tung. "
               .. "Hits multiple enemies in a wide arc.",
    lore        = "Still vibrating with the ghost of the rhythm.",

    class   = "Melee",
    rarity  = "Uncommon",
    element = "None",

    damage      = 32,
    attackSpeed = 1.0,
    range       = 6,
    aoeRadius   = 5,   -- wide swing

    isPiercing = false,
    isHoming   = false,
    effects    = {
        { type = "Stun", chance = 0.20, duration = 0.8, value = 0 },
    },

    upgradeScaling  = { damage = 6, attackSpeed = 0.04 },
    maxUpgradeLevel = 8,

    modelId      = "rbxassetid://102119645434654",
    iconId       = "rbxassetid://PLACEHOLDER_drum_beater_icon",
    swingAnimId  = "rbxassetid://PLACEHOLDER_heavy_swing_anim",
    soundIdSwing = "rbxassetid://PLACEHOLDER_drum_hit_swing",
    soundIdHit   = "rbxassetid://PLACEHOLDER_drum_hit_impact",
}

WeaponData["croc_launcher"] = {
    id          = "croc_launcher",
    displayName = "Croc Launcher",
    description = "Repurposed bomber tech from a fallen Bombardiro. "
               .. "Fires small explosive rounds.",
    lore        = "The safety was removed. By a crocodile.",

    class   = "Ranged",
    rarity  = "Uncommon",
    element = "Fire",

    damage      = 40,
    attackSpeed = 0.8,
    range       = 35,
    aoeRadius   = 4,   -- explosion radius

    isPiercing = false,
    isHoming   = false,
    effects    = {
        { type = "Burn", chance = 0.45, duration = 3, value = 5 },
    },

    upgradeScaling  = { damage = 7, attackSpeed = 0.03 },
    maxUpgradeLevel = 8,

    modelId           = "rbxassetid://PLACEHOLDER_croc_launcher_model",
    iconId            = "rbxassetid://PLACEHOLDER_croc_launcher_icon",
    swingAnimId       = "rbxassetid://PLACEHOLDER_launcher_shoot_anim",
    projectileModelId = "rbxassetid://PLACEHOLDER_mini_bomb_projectile",
    soundIdSwing      = "rbxassetid://PLACEHOLDER_launcher_shoot",
    soundIdHit        = "rbxassetid://PLACEHOLDER_explosion",
}

WeaponData["chaos_wand"] = {
    id          = "chaos_wand",
    displayName = "Chaos Wand",
    description = "Shoots erratic bolts of pure chaos energy. "
               .. "Effect on impact is… variable.",
    lore        = "Tastes like static. Found it, kept it.",

    class   = "Magic",
    rarity  = "Uncommon",
    element = "Chaos",

    damage      = 28,
    attackSpeed = 1.6,
    range       = 28,
    aoeRadius   = 0,

    isPiercing = true,
    isHoming   = false,
    effects    = {
        { type = "Shock",  chance = 0.25, duration = 1.5, value = 8 },
        { type = "Stun",   chance = 0.10, duration = 1.0, value = 0 },
    },

    upgradeScaling  = { damage = 5, attackSpeed = 0.08 },
    maxUpgradeLevel = 8,

    modelId           = "rbxassetid://PLACEHOLDER_chaos_wand_model",
    iconId            = "rbxassetid://PLACEHOLDER_chaos_wand_icon",
    swingAnimId       = "rbxassetid://PLACEHOLDER_wand_cast_anim",
    projectileModelId = "rbxassetid://PLACEHOLDER_chaos_bolt",
    soundIdSwing      = "rbxassetid://PLACEHOLDER_magic_cast",
    soundIdHit        = "rbxassetid://PLACEHOLDER_chaos_hit",
}

-- ─── RARE ────────────────────────────────────────────────────────────────────

WeaponData["frozen_tusk"] = {
    id          = "frozen_tusk",
    displayName = "Frozen Tusk",
    description = "A huge ice spear ripped from Frigo Camelo's back. "
               .. "Impales multiple enemies in a line.",
    lore        = "Cold to the touch. The camel was colder.",

    class   = "Melee",
    rarity  = "Rare",
    element = "Ice",

    damage      = 55,
    attackSpeed = 0.9,
    range       = 8,
    aoeRadius   = 0,

    isPiercing = true,
    isHoming   = false,
    effects    = {
        { type = "Freeze", chance = 0.40, duration = 2.0, value = 0 },
        { type = "Bleed",  chance = 0.20, duration = 4.0, value = 6 },
    },

    upgradeScaling  = { damage = 9, attackSpeed = 0.03 },
    maxUpgradeLevel = 10,

    modelId      = "rbxassetid://PLACEHOLDER_frozen_tusk_model",
    iconId       = "rbxassetid://PLACEHOLDER_frozen_tusk_icon",
    swingAnimId  = "rbxassetid://PLACEHOLDER_spear_thrust_anim",
    soundIdSwing = "rbxassetid://PLACEHOLDER_ice_swing",
    soundIdHit   = "rbxassetid://PLACEHOLDER_ice_shatter",
}

WeaponData["espresso_daggers"] = {
    id          = "espresso_daggers",
    displayName = "Espresso Daggers",
    description = "Twin blades caffeinated to supernatural sharpness. "
               .. "Extremely fast. Extremely over-caffeinated.",
    lore        = "Cappuccino Assassino dropped these. Suspiciously willingly.",

    class   = "Melee",
    rarity  = "Rare",
    element = "None",

    damage      = 22,
    attackSpeed = 3.5,
    range       = 4,
    aoeRadius   = 0,

    isPiercing = false,
    isHoming   = false,
    effects    = {
        { type = "Bleed", chance = 0.55, duration = 3.0, value = 7 },
        { type = "Poison", chance = 0.15, duration = 5.0, value = 4 },
    },

    upgradeScaling  = { damage = 4, attackSpeed = 0.15 },
    maxUpgradeLevel = 10,

    modelId      = "rbxassetid://PLACEHOLDER_espresso_daggers_model",
    iconId       = "rbxassetid://PLACEHOLDER_espresso_daggers_icon",
    swingAnimId  = "rbxassetid://PLACEHOLDER_dagger_combo_anim",
    soundIdSwing = "rbxassetid://PLACEHOLDER_fast_slash",
    soundIdHit   = "rbxassetid://PLACEHOLDER_dagger_hit",
}

-- ─── LEGENDARY ───────────────────────────────────────────────────────────────

WeaponData["drum_of_the_ancients"] = {
    id          = "drum_of_the_ancients",
    displayName = "Drum of the Ancients",
    description = "Seized from Grande Tung Tung himself. "
               .. "Each beat sends shockwaves across the entire room.",
    lore        = "You can feel it breathing. That's normal.",

    class   = "Melee",
    rarity  = "Legendary",
    element = "Chaos",

    damage      = 90,
    attackSpeed = 0.7,
    range       = 7,
    aoeRadius   = 12,

    isPiercing = false,
    isHoming   = false,
    effects    = {
        { type = "Stun",     chance = 0.50, duration = 1.5, value = 0 },
        { type = "Knockback",chance = 0.80, duration = 0.3, value = 20 },
    },

    upgradeScaling  = { damage = 14, attackSpeed = 0.04 },
    maxUpgradeLevel = 15,

    modelId      = "rbxassetid://PLACEHOLDER_ancient_drum_model",
    iconId       = "rbxassetid://PLACEHOLDER_ancient_drum_icon",
    swingAnimId  = "rbxassetid://PLACEHOLDER_drum_slam_anim",
    soundIdSwing = "rbxassetid://PLACEHOLDER_ancient_drum_boom",
    soundIdHit   = "rbxassetid://PLACEHOLDER_ancient_shockwave",
}

WeaponData["supreme_bombardier"] = {
    id          = "supreme_bombardier",
    displayName = "Supreme Bombardier",
    description = "Il Bombardiro Supremo's personal weapon. "
               .. "Auto-targets enemies and fires homing incendiary payloads.",
    lore        = "The Supremo called it 'Giuseppina'. We'll keep the name.",

    class   = "Ranged",
    rarity  = "Legendary",
    element = "Fire",

    damage      = 75,
    attackSpeed = 1.2,
    range       = 50,
    aoeRadius   = 7,

    isPiercing = false,
    isHoming   = true,
    effects    = {
        { type = "Burn", chance = 0.90, duration = 5.0, value = 12 },
    },

    upgradeScaling  = { damage = 12, attackSpeed = 0.06 },
    maxUpgradeLevel = 15,

    modelId           = "rbxassetid://PLACEHOLDER_supreme_bomb_model",
    iconId            = "rbxassetid://PLACEHOLDER_supreme_bomb_icon",
    swingAnimId       = "rbxassetid://PLACEHOLDER_supreme_fire_anim",
    projectileModelId = "rbxassetid://PLACEHOLDER_homing_missile",
    soundIdSwing      = "rbxassetid://PLACEHOLDER_missile_launch",
    soundIdHit        = "rbxassetid://PLACEHOLDER_supreme_explosion",
}

-- ─── Lookup Helpers ───────────────────────────────────────────────────────────

function WeaponData.getByRarity(rarity: string): { string }
    local result = {}
    for id, def in WeaponData do
        if type(def) == "table" and def.rarity == rarity then
            table.insert(result, id)
        end
    end
    table.sort(result)
    return result
end

function WeaponData.getByClass(class: string): { string }
    local result = {}
    for id, def in WeaponData do
        if type(def) == "table" and def.class == class then
            table.insert(result, id)
        end
    end
    table.sort(result)
    return result
end

return WeaponData
