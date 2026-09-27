# Vicky's Game — Design Document

A first-person 3D survival/crafting prototype built in **Godot 4.2** (Forward+ renderer).
The player is stranded on an island, gathers resources by hand and with tools, crafts
new items, builds structures, and contends with wildlife while managing energy and health.

This document describes the game as it exists in the repository today. Where a system is
planned but not implemented, it is marked **(not implemented)**. A companion review of
defects and technical debt lives in [`CODE_REVIEW.md`](CODE_REVIEW.md).

---

## 1. Design pillars

| Pillar | What it means in this build |
| --- | --- |
| **Hands-on harvesting** | Resources are not clicked out of the world — trees and boulders have hitboxes, and you swing a specific tool at them. The wrong tool does nothing. |
| **Energy as the clock** | There is no day/night timer. Pressure comes from energy, which drains per metre walked and per tool swing, and bleeds into health once exhausted. |
| **Readable, diegetic feedback** | Held items are real 3D models animated in a separate viewport layer; build placement previews turn green/red in the world rather than in a menu. |
| **Small, legible island** | One hand-authored stage rather than procedural generation, so encounters and resource density are deliberate. |

## 2. Core loop

```
      ┌──────────────────────────────────────────────────────┐
      │                                                      │
      ▼                                                      │
  EXPLORE ──► HARVEST ──► CRAFT ──► EQUIP ──► BUILD / FIGHT ──┘
  (walk,      (swing      (TAB      (hotbar    (place tent,
   energy      tool at     menu,     1–9)       kill wolf,
   drains)     hitbox)     spend                eat to
                           costs)               refill energy)
```

1. **Explore.** WASD + mouse look, `Shift` to sprint. Walking costs energy proportional to distance travelled.
2. **Gather.** Loose items (sticks, stones, plants, mushrooms) are picked up with `E` via a 3 m interaction raycast. Trees and boulders must be *hit* with the matching tool; they drop rigid-body items at authored spawn markers.
3. **Craft.** `TAB` opens the crafting menu, which freezes the player, shows the 28-slot inventory, and lists craftable blueprints with their costs. Affordable recipes are enabled; the rest are greyed out.
4. **Equip.** Drag an item from the inventory into one of 9 hotbar slots, then press `1`–`9`. Pressing the active slot's key again unequips.
5. **Use.** Left mouse plays the held item's `use_item` animation, which calls back into the item's script at authored keyframes — that is how a swing lands damage, a mushroom is eaten, or a tent is planted.
6. **Survive.** Wolves hunt the player; cows flee. Eating restores energy. Energy at zero starts draining health.

## 3. Architecture

### 3.1 Event bus

The project deliberately avoids node-to-node references between systems. `game/event_system.gd`
is registered as the single autoload (`EventSystem`) and declares every cross-system signal.
Managers `connect` in `_enter_tree()` and emitters call `EventSystem.<SIGNAL>.emit(...)`.

Signals are grouped by a three-letter domain prefix:

| Prefix | Domain | Signals |
| --- | --- | --- |
| `BUL_` | Bulletins (transient UI) | `create_bulletin`, `destroy_bulletin` |
| `INV_` | Inventory | `try_to_pickup_item`, `ask_update_inventory`, `inventory_updated`, `switch_two_item_indexes`, `add_item`, `craft_item`, `hotbar_updated`, `delete_item_by_index` |
| `PLA_` | Player | `freeze_player`, `unfreeze_player`, `change_energy`, `energy_updated`, `change_health`, `health_updated` |
| `EQU_` | Equipment | `hotkey_pressed`, `equip_item`, `unequip_item`, `active_hotbar_slot_updated`, `delete_equipped_item` |
| `SPA_` | Spawning | `spawn_scene` |

**Benefit:** the HUD, the inventory, and the player controller know nothing about each other.
`ui/hud/player_stats_container.gd` listens for `PLA_energy_updated` and moves a progress bar; it
never touches `PlayerStatsManager`.

**Cost:** there is no compile-time contract. The signals are declared without parameters, so
argument lists are only agreed by convention, and a rename breaks silently at runtime.

### 3.2 Config classes as the content registry

`game/configs/` holds three static, script-only classes that map enum keys to resource paths:

- **`ItemConfig`** — the heart of the content model. One `Keys` enum (19 entries) is the single
  identifier for an item everywhere in the codebase: in the inventory array, in blueprint costs,
  in harvesting weapon filters, in drop tables. Five separate dictionaries map that key to
  different assets, each with a `static func` accessor:

  | Dictionary | Maps a key to | Used by |
  | --- | --- | --- |
  | `ITEM_RESOURCE_PATHS` | `.tres` stats/display data | inventory UI, crafting UI, weapons, consumables |
  | `CRAFTING_BLUEPRINT_RESOURCE_PATHS` | recipe resource | crafting menu |
  | `EQUIPPABLE_ITEM_SCENES` | first-person held-item scene | `EquippableItemHolder` |
  | `PICKUPPABLE_ITEM_PATHS` | world drop scene | harvesting, animal death |
  | `CONSTRUCTABLE_SCENES_PATHS` | placed structure scene | `EquippableConstructable` |

  `CRAFTABLE_ITEM_KEYS` is a curated list controlling which recipes appear in the menu — the
  commented-out entries (Campfire, Multitool, Tinderbox, Torch, Tent, Raft) are the content roadmap.

- **`BulletinConfig`** — maps `Keys` (`InteractionPrompt`, `CraftingMenu`) to UI scenes.
- **`StageConfig`** — maps `Keys` (`Island`) to stage scenes.

**Why this shape works:** adding a craftable item is a data task — author a `.tres`, register a
path, add the key to `CRAFTABLE_ITEM_KEYS` — with no code change. **Where it strains:** the key
is duplicated inside each `ItemResource.item_key`, so the dictionary and the resource can disagree
(and today, do — see review item D1).

### 3.3 Scene graph and ownership

```
MainGame (main scene)
├── StageController ................ swaps stages; loads Island on _ready
│   └── Island ..................... hand-authored stage
│       ├── NavigationRegion3D
│       │   ├── Terrain (+ StaticBody, layer "ground")
│       │   └── Objects ............ HittableTree / HittableCoalBolder / ...
│       ├── Player ................. see below
│       ├── Spawner ................ receives SPA_spawn_scene, parents drops under $Items
│       ├── Cow, Cow2, Wolf
│       ├── Pickuppables ........... loose mushrooms/sticks/stones/plants
│       ├── Water, DirectionalLight3D, WorldEnvironment
└── UILayer (CanvasLayer)
    ├── HUDController
    │   └── HUD .................... crosshair, 9 hotbar slots, health + energy bars
    └── BulletinController ......... spawns/destroys transient UI by key
```

The player scene owns both its body and the gameplay managers:

```
Player (CharacterBody3D, layer "actor", group "Player")
├── CollisionShape3D (capsule, r=0.25 h=1.8)
├── Head
│   ├── MainCamera .............. cull_mask excludes layer 2
│   ├── InteractionRayCast ...... 3 m, mask "interactable", collides with areas
│   └── SubViewportContainer
│       └── SubViewport
│           └── EquippableItemCamera (cull_mask = layer 2 only)
│               └── EquippableItemHolder .... the held item lives here
└── Managers
    ├── InventoryManager
    ├── EquippedItemManager
    └── PlayerStatsManager
```

**The two-camera trick.** Held items are rendered by a second camera into a `SubViewport`
composited over the main view. `MainCamera` culls visual layer 2 and `EquippableItemCamera`
renders *only* layer 2; `EquippableItem._ready()` moves the held mesh onto layer 2, and
`main_camera.gd` copies the main camera's transform to the item camera each frame. The result is
that a large axe model never clips into walls, because it is not really in the world — but the
`SubViewport` shares the main `World3D`, so `EquippableWeapon.check_hit()` can still raycast
against real hitboxes from the weapon's position.

### 3.4 Physics layers

| # | Name | Used by |
| --- | --- | --- |
| 1 | `ground` | terrain static body |
| 2 | `actor` | player, animals |
| 3 | `interactable` | `Interactable` areas (pickup prompts) |
| 4 | `hitbox` | `Hitbox` areas on trees, boulders, animals |
| 5 | `big_rigid_pickuppable` | logs |
| 6 | `small_rigid_pickuppable` | coal, flintstone, meat |
| 7 | `static_body` | harvestable object bodies, placed constructables |

Separating `interactable` from `hitbox` is what lets the same tree be both walked into, chopped,
and (via its dropped log) picked up, with three independent queries and no tag checks in code.

## 4. Systems

### 4.1 Inventory (`game/managers/inventory_manager.gd`)

A flat `Array` of 28 nullable `ItemConfig.Keys` plus a 9-slot hotbar array. No stacking — one item
per slot. `add_item()` finds the first `null` via `Array.find(null)`; on success it broadcasts
`INV_inventory_updated` with the whole array, and every listener re-renders. Drag-and-drop between
inventory and hotbar is a single `INV_switch_two_item_indexes` swap that works uniformly in both
directions via `isHotbar` flags.

Starting kit is hard-coded in `_ready()`: Axe, Pickaxe, Tent, broadcast on the first frame.

Crafting is a single checked operation on this manager (`craft_item`, via `INV_craft_item`): it
re-verifies affordability and that the result has a slot before consuming any materials, so a
craft either happens completely or not at all.

The manager is a child of the **Player** scene, so the inventory is stage-scoped: changing stages
destroys it. There is no serialisation — **no save/load (not implemented)**.

### 4.2 Player stats (`game/managers/player_stats_manager.gd`)

Two floats, `current_energy` and `current_health`, both capped at 100. Energy is spent by:

- **Walking** — `player.gd:34` bills `-0.05` energy per metre of horizontal travel per frame.
- **Tool use** — `WeaponItemResource.energy_change_per_use` (`-0.5`) fired from an animation keyframe.

Energy is restored by consumables. Once energy goes negative, the overdraft is charged to health —
the starvation mechanic. There is **no death or game-over handling (not implemented)**; health
simply reaches zero.

### 4.3 Equipment and item use

`EquippedItemManager` holds `active_hotbar_slot` and the hotbar mirror. A hotkey press either
equips that slot's item or, if it is already active, unequips. `EquippableItemHolder` instantiates
the item scene from `ItemConfig.EQUIPPABLE_ITEM_SCENES` and injects its data by type:

| Subclass | Injected | `use_item` animation calls |
| --- | --- | --- |
| `EquippableWeapon` | `WeaponItemResource` | `change_energy()`, then `check_hit()` |
| `EquippableConsumable` | `ConsumableItemResource` | `consume()`, then `destroy_self()` |
| `EquippableConstructable` | `constructable_item_key` | `try_to_construct()`, then `destroy_self()` |

**Animation-driven gameplay** is the defining pattern here: `EquippableItem.try_to_use()` only
plays an animation and refuses to re-trigger while one is playing, which gives every action its
cooldown for free. The gameplay effect fires from a method track at the visually correct frame —
the axe's `check_hit()` lands at the bottom of the swing arc, not on the click.

`check_hit()` casts a short ray from the weapon origin out to a `HitCheckMarker` placed at
`-damage_range` on Z, against the `hitbox` layer only, and calls `take_hit(weapon_item_resource)`
on whatever it finds. Both harvestable objects and animals expose that same method, so one weapon
implementation covers both.

### 4.4 Harvesting (`objects/hittable_objects/`)

`HittableObjectTemplate` composes a `StaticBody3D` (collision), a `Hitbox` area, and an
`ItemSpawnPoints` node of `Marker3D`s. Behaviour is entirely data-driven by a
`HittableObjectAttributes` resource:

| Object | Drop | Health | Required tool |
| --- | --- | --- | --- |
| Tree | Log | 80 | Axe |
| Coal boulder | Coal | 80 | Pickaxe |
| Flintstone boulder | Flintstone | 80 | Pickaxe |

An empty `weapon_filter` would mean "any tool". On death, one drop spawns per marker via
`SPA_spawn_scene`, and the object swaps itself for a pre-authored **residue** body (the tree
becomes a stump) rather than vanishing.

### 4.5 Animal AI (`Actors/animals/animal.gd`)

A 7-state machine — `Idle`, `Wander`, `Flee`, `Chase`, `Attack`, `Hurt`, `Dead` — driven by
`set_state()` for entry actions, a `match` in `_physics_process` for per-frame behaviour, and
`AnimationPlayer.animation_finished` for exits. Three one-shot `Timer`s pace idling, wandering and
fleeing; the `IdleTimer` autostarts, which is what boots the machine one second after spawn.
`set_state()` stops all three on entry, so a timer from the previous state cannot fire and drag the
animal back out of the new one.

Gravity and a single `move_and_slide()` sit *outside* the `match`, so they apply in every state —
including `Hurt`, which has no per-frame case and only needs to keep falling while it flinches.
States that should hold still (`Idle`, `Hurt`, `Attack`) zero their horizontal velocity on entry;
steering goes through `set_horizontal_velocity()` so it never clobbers the vertical component.

Perception is a `VisionArea` sphere (radius set from `vision_range`) for range, a FOV cone check,
and a line-of-sight raycast against ground and static bodies, so cover works. `is_aggressive`
is the single switch that makes the same script a predator or prey:

| | Cow | Wolf |
| --- | --- | --- |
| Health | 80 | 60 |
| Aggressive | no — flees when hurt | yes — chases on sight |
| Wander / alarmed speed | 0.6 / 1.8 | 0.9 / 2.5 |
| Attack distance | 2.0 | 1.3 |
| Damage | 20 | 20 |
| Vision range / FOV | 15 / 80 | 15 / 80 |

Chasing uses a `NavigationAgent3D` against the island's `NavigationRegion3D`. Attacks check
`AttackHitArea` overlap from an animation keyframe, so a swing can miss. On death the animal plays
its death animation, disables its collision, spawns raw meat at a marker, and despawns after 10 s.

### 4.6 Building (`items/equippables/equippable_constructable.gd`)

While a constructable is equipped, a `top_level` `Area3D` carrying a duplicate of the held mesh is
projected onto whatever an `ItemPlaceRay` hits, rotated to face the player. Its collision shape is
generated at runtime with `create_convex_shape()` from that mesh, and it tracks overlapping bodies
in an obstacle list. Placement is valid only when the ray hits something and the obstacle list is
empty; the preview mesh is tinted with a valid/invalid material accordingly. Committing spawns the
real structure into the stage and consumes the item.

Only the **tent** exists as a constructable, and the placed tent is an inert `StaticBody3D` —
**sleeping/shelter is not implemented**.

### 4.7 UI (`bulletins/` and `ui/`)

Two distinct UI concepts:

- **Persistent HUD** (`ui/hud/hud.tscn`) — always mounted, purely reactive to `PLA_*` and `INV_*`
  signals. Crosshair, 9 hotbar slots, health and energy bars.
- **Bulletins** — transient UI spawned on demand. `BulletinController` keeps a `key → instance`
  dictionary so a bulletin is idempotent: asking for one that already exists does nothing. Two
  exist: the interaction prompt (driven by what the interaction raycast is aimed at) and the
  crafting menu. Asking for a bulletin whose key is already present **refreshes** it — that is how
  the prompt changes text as the crosshair moves between interactables without being destroyed and
  rebuilt.

`PlayerMenuBase` is the shared scaffolding for full-screen menus: on open it releases the mouse,
emits `PLA_freeze_player`, requests an inventory refresh, and wires hover handlers for both
inventory slots and (via the `HotbarSlots` group) hotbar slots, so item tooltips work across both.

Drag-and-drop uses Godot's native `_get_drag_data` / `_can_drop_data` / `_drop_data`.
`HotbarSlot` extends `InventorySlot` and narrows `_can_drop_data` to items `ItemConfig`
reports as equippable — that is, items with an entry in `EQUIPPABLE_ITEM_SCENES` — which is the
only rule preventing a log from being placed in the hotbar.

## 5. Content inventory

**Items (19 keys).** Gatherable: Stick, Stone, Plant, Mushroom, Fruit, Log, Coal, Flintstone,
RawMeat, CookedMeat. Craftable/tool: Axe, Pickaxe, Campfire, Multitool, Rope, Tinderbox, Torch,
Tent, Raft.

**Recipes (3 active).** Axe = Stick + Stone + Rope · Pickaxe = Stick + Stone + Rope · Rope = 2 Plant.
Blueprints support `needs_multitool` / `needs_tinderbox` station gates, displayed in the menu but
**not enforced (not implemented)**.

**Assets.** ~15 meshes (tree, stump, tent, raft, torch, axe, boulders, food items), 2 rigged GLTF
animals, a terrain mesh with texture, 3 music tracks and 17 SFX.

**Audio is entirely unused** — there are no `AudioStreamPlayer` nodes anywhere in the project, so
all 20 audio files ship unreferenced. Their names read as a checklist of intended feedback:
`footstep`, `jump_land`, `weapon_swoosh`, `tree_hit`, `boulder_hit`, `item_pickup`, `craft`,
`build`, `eat`, `campfire`, `torch`, `go_in_tent`, `ui_click`, and hurt/attack pairs for both
animals.

## 6. Controls

| Input | Action |
| --- | --- |
| `W A S D` / arrows | Move |
| Mouse | Look |
| `Shift` | Sprint (ground only) |
| `Space` | Bound as `jump` — **no jump logic exists** |
| `E` / Enter | Interact (pick up) |
| Left mouse | Use equipped item |
| `1`–`9` | Equip / unequip hotbar slot |
| `TAB` | Open / close crafting menu |
| `Esc` | Close an open menu; otherwise toggle mouse capture (there is no pause menu) |

## 7. Known gaps and roadmap

Ordered roughly by how much each unlocks.

1. **Audio pass.** Every sound is authored and none is played. The cheapest large improvement.
2. **Death and respawn.** Health reaches zero with no consequence; the survival loop has no fail state.
3. **Cooking.** `RawMeat`, `CookedMeat` and a campfire mesh, item and SFX all exist; the campfire is not craftable and nothing converts one to the other.
4. **Save/load.** Inventory, stats, and world state are all runtime-only, and live under the Player, so they cannot survive a stage change.
5. **The commented-out recipes.** Campfire, Multitool, Tinderbox, Torch, Tent, Raft are registered as items with meshes and icons but excluded from `CRAFTABLE_ITEM_KEYS`; several also lack blueprints and held-item scenes.
6. **Station gates.** `needs_multitool` / `needs_tinderbox` are authored and displayed but never checked.
7. **Tent function.** Buildable but inert. A `go_in_tent` sound is waiting.
8. **Raft / stage transition.** `StageConfig` and `StageController` are built for multiple stages and only Island exists; the raft item suggests escape was the intended win condition.
9. **Stacking, and full-inventory feedback.** One item per slot makes 28 slots tight, and `try_to_pickup_item` has an explicit `# Todo: show message` where the "inventory full" notice belongs.
10. **Jump.** The action and `jumpVelocity` export exist; the movement code never reads either.

## 8. Conventions for contributors

- **Cross-system communication goes through `EventSystem`.** Do not reach across the tree for a manager.
- **Content lives in `.tres` resources; code reads it.** Prefer a new exported field on a resource over a branch in a script.
- **New item?** Add the `Keys` entry, author the `.tres`, and register it in the relevant `ItemConfig` dictionaries.
  - Keep `ItemResource.item_key` equal to its dictionary key. Nothing checks this, and `HittableObject` matches on it, so a wrong value silently breaks harvesting.
  - An item becomes equippable by having an entry in `EQUIPPABLE_ITEM_SCENES` — there is no flag to set.
  - Copying an existing `.tres` as a starting point is how both D1 and D4 happened. Check every field, including the icon.
- **`res://` paths are case-sensitive** in exported builds and on Linux, even though the editor on Windows and macOS forgives a mismatch. `res://Stages/…` against a `stages/` folder stopped the game booting entirely (review item E6).
- **New behaviour on a held item?** Put the *effect* in a method and call it from a `use_item` animation method track, so timing stays an animator's decision.
- **Scene inheritance over duplication.** `*_template.tscn` files are the base scenes; concrete content inherits from them (`equippable_item_template` → `equippable_constructable_template` → `equippable_tent`).
- **Naming.** GDScript standard is `snake_case` for members and functions, `PascalCase` for classes and node names. Parts of the codebase predate that decision (see review item E1).
