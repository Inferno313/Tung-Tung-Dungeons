# Tung Tung Dungeons 🥁

> *A top-down dungeon crawler on Roblox where players battle the internet's most chaotic Brainrots, collect powerful weapons, and descend endlessly into madness.*

---

## Game Overview

**Tung Tung Dungeons** is a Roblox game inspired by Minecraft Dungeons and classic roguelikes. Up to **4 players** fight cooperatively through procedurally assembled dungeon floors, each populated with increasingly dangerous **Brainrot enemies** — internet meme characters with unique abilities, archetypes, and elemental affinities.

Players collect weapons of escalating rarity, survive boss encounters, and push as deep into the dungeon as possible. Every run is different. No run ends quietly.

---

## Brainrot Roster

| Brainrot | Archetype | Element | Signature Ability |
|---|---|---|---|
| Tung Tung Tung Sahur | Charger | None | Drum Rush (double-damage charge) |
| Tralalero Tralala | Swarm | None | Pack Frenzy (+40% speed aura) |
| Bombardiro Crocodilo | Ranged | Fire | Bomb Barrage + Napalm Dive |
| Boneca Ambalabu | Tank | None | Swamp Slam (AOE stun) + Doll Shield |
| Brrr Brrr Patapim | Ranged | Electric | Static Burst (control invert) |
| Cappuccino Assassino | Stealth | None | Espresso Vanish + Backstab Brew |
| Frigo Camelo | Ranged | Ice | Blizzard Breath + Hump Missile |
| **Grande Tung Tung** *(Boss)* | Boss | Chaos | 4-phase boss with summons & shockwaves |
| **Il Bombardiro Supremo** *(Boss)* | Boss | Fire | Carpet Bomb, Missile Volley, Nuclear Option |

---

## Weapon Tiers

| Rarity | Examples | Drop Rate |
|---|---|---|
| Common | Wooden Club, Slingshot | ~78% |
| Uncommon | Drum Beater, Croc Launcher, Chaos Wand | ~15% |
| Rare | Frozen Tusk, Espresso Daggers | ~5% |
| Epic | *(future weapons)* | ~2% |
| Legendary | Drum of the Ancients, Supreme Bombardier | ~0.5% |

All weapons are upgradeable up to their `maxUpgradeLevel` using gold found in the dungeon.

---

## Architecture

```
Tung-Tung-Dungeons/
├── default.project.json          # Rojo sync config
├── selene.toml                   # Luau linter config
├── wally.toml                    # Wally package manager config
│
└── src/
    ├── ReplicatedStorage/
    │   ├── Data/
    │   │   ├── Constants.lua     # Global game constants (speeds, ranges, rates)
    │   │   ├── BrainrotData.lua  # All enemy definitions + helpers
    │   │   ├── WeaponData.lua    # All weapon definitions + helpers
    │   │   └── DungeonData.lua   # Room templates, floor defs, dynamic generator
    │   ├── Modules/
    │   │   ├── StateMachine.lua  # Generic FSM (used by all enemy AI)
    │   │   └── Util.lua          # Shared utilities (math, tables, strings, vectors)
    │   └── Remotes/
    │       └── init.lua          # Single source of truth for all RemoteEvents
    │
    ├── ServerScriptService/
    │   ├── GameManager.server.lua      # Root game loop (Lobby → InGame → GameOver)
    │   ├── DungeonManager.lua          # Floor generation, room instantiation
    │   ├── EnemyManager.lua            # Enemy spawning, AI heartbeat, combat
    │   ├── LootManager.lua             # Weapon/gold/health drop spawning
    │   └── PlayerDataManager.lua       # DataStore persistence, XP/levelling
    │
    ├── StarterPlayerScripts/
    │   ├── PlayerController.client.lua # WASD movement, dodge, attack, interact
    │   ├── CameraController.client.lua # Fixed top-down camera tracking
    │   └── UIController.client.lua     # HUD, boss bar, floor banners, game over
    │
    └── StarterCharacterScripts/
        └── CharacterSetup.client.lua   # Humanoid config, stamina, camera lock
```

### Data Flow

```
[Client Input] → PlayerController → RemoteEvent → [Server]
                                                       │
                                              EnemyManager (combat)
                                              LootManager  (drops)
                                              PlayerDataManager (XP/gold)
                                                       │
                                              RemoteEvent → [Client]
                                                       │
                                              UIController (HUD update)
```

### Enemy AI State Machine

Every Brainrot runs its own `StateMachine` with five states:

```
Idle ──(playerInRange)──► Chase ──(playerInAttack)──► Attack
  ▲                         │  ▲                          │
  └──(playerOutRange)───────┘  └────(playerOutAttack)─────┘
                              │
                    (abilityReady)
                              ▼
                           Ability ──(abilityCast)──► Chase
```

---

## Development Roadmap

### Phase 1 — Foundation ✅ *(this PR)*
- [x] Rojo project scaffold
- [x] All data modules (Brainrots, Weapons, Dungeons, Constants)
- [x] Shared utilities (StateMachine, Util, Remotes)
- [x] Server: GameManager, DungeonManager, EnemyManager, LootManager, PlayerDataManager
- [x] Client: PlayerController, CameraController, UIController, CharacterSetup

### Phase 2 — Core Gameplay Loop
- [ ] Replace placeholder models with actual Brainrot meshes
- [ ] Implement full pathfinding with PathfindingService in EnemyManager
- [ ] Weapon hitbox system (melee arc, projectile physics, AoE)
- [ ] Weapon upgrade station in safe rooms
- [ ] Proper dungeon generation (connected rooms via corridors, locked doors)
- [ ] Floor biome theming (materials, lighting, music per biome)

### Phase 3 — Polish & Feel
- [ ] Per-archetype VFX for abilities (Drum Rush screen shake, Bomb explosions, ice freeze)
- [ ] Status effect system (Burn DoT, Freeze slow, Shock control-invert, Bleed, Poison)
- [ ] Weapon choice UI (keep equipped vs. swap on loot pickup)
- [ ] Inventory panel (view stats, upgrade weapons)
- [ ] Kill feed animations
- [ ] Boss intro cinematics
- [ ] Procedural dungeon minimap

### Phase 4 — Meta Progression
- [ ] Persistent player levels (1–100) with passive stat bonuses
- [ ] Leaderboard (deepest floor reached, total brainrots defeated)
- [ ] Unlockable starting weapons
- [ ] Daily challenge mode (fixed seed dungeons with bonus rewards)
- [ ] Lobby area with NPC merchants and character customisation

### Phase 5 — Monetisation & Live Ops
- [ ] Robux shop: cosmetic weapon skins, character trails, emotes
- [ ] Season pass: themed cosmetic tracks (Brainrot Season, Chaos Season)
- [ ] New Brainrot drop: periodic content updates with new enemy types
- [ ] Co-op dungeon boss events (server-wide raids)

---

## Getting Started (Developer Setup)

### Prerequisites
- [Roblox Studio](https://www.roblox.com/create)
- [Rojo](https://rojo.space/) v7+
- [Wally](https://wally.run/) (optional, for package management)
- [Selene](https://kampfkarren.github.io/selene/) (optional, for linting)

### Setup

```bash
# Clone the repo
git clone https://github.com/Inferno313/Tung-Tung-Dungeons.git
cd Tung-Tung-Dungeons

# Install dependencies (when wally.toml has entries)
wally install

# Start Rojo sync server
rojo serve default.project.json
```

Then in Roblox Studio:
1. Install the [Rojo Studio plugin](https://www.roblox.com/library/13916111246/Rojo)
2. Open Studio → Rojo plugin → Connect to `localhost:34872`
3. Click **Sync In** — all scripts will populate the correct services

### Replacing Placeholders

All `rbxassetid://PLACEHOLDER_*` strings in `BrainrotData.lua`, `WeaponData.lua`, and `DungeonData.lua` need to be replaced with real uploaded asset IDs. This is the primary work for Phase 2 environment and art pass.

---

## Contributing

1. Branch off `main`: `git checkout -b feature/your-feature`
2. Write code in `src/` — Rojo syncs automatically
3. Run `selene src/` before committing
4. Open a PR with a clear description of what changed and why

### Code Style
- Use `--!strict` at the top of every file
- Prefer explicit types over `any`
- Keep modules focused — one responsibility per file
- All game constants go in `Constants.lua`, not scattered in scripts

---

## License

MIT — see `LICENSE` for details.
