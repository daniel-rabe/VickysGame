# Code Review — Vicky's Game

Reviewed at commit `19c31cd` ("[UPDATE] 15_07_2024"), against the whole tree
(21 GDScript files, ~1130 lines, plus scenes and resources).
Architecture and intent are described in [`DESIGN.md`](DESIGN.md).

## Verdict

The architecture is genuinely good for a prototype of this size. The `EventSystem` bus,
the `ItemConfig` key→asset registry, the resource-driven harvesting and animal data, the
animation-method-track pattern for item use, and the two-camera held-item rendering are all
choices that will still hold up at 5× the content. Very little here needs rearchitecting.

What it needs is a correctness pass. The defects below are concentrated in three places:
**state that is broadcast but not stored consistently** (energy), **arrays indexed without
checking they were initialised** (hotbar), and **content data that has drifted from the code
that consumes it** (`is_equippable` vs. `EQUIPPABLE_ITEM_SCENES`, the fruit resource).

Counts: **6 crash-or-corruption bugs**, **7 logic bugs**, **3 data bugs**, plus robustness,
style and hygiene items. The six in section A have since been fixed; everything from section B
onward is still open.

---

## A. Crashes and state corruption

> **All six items in this section have been fixed.** Each carries a status line below.
> Sections B onward are still open.

### A1 — Pressing `1`–`9` before ever using the hotbar crashes the game
`game/managers/equipped_item_manager.gd:9-11`, `game/managers/inventory_manager.gd:82-87`

`EquippedItemManager.hotbar` starts as an empty `Array` and is only populated by
`INV_hotbar_updated`. `InventoryManager._ready()` resizes its own `hotbar` but never calls
`send_hotbar()`, and `send_hotbar()` is otherwise only reached from `switch_two_item_indexes()`
and `delete_item_by_index()`.

**Failure:** launch the game, press `1`. `hotbar[0]` on an empty array →
`Invalid access to index 0 on a base object of type Array`. The hotbar UI is also blank until
the first drag, for the same reason.

**Fix:** call `send_hotbar()` alongside the inventory initialisation in
`InventoryManager._ready()`, and guard `hotbar_pressed()` with a bounds check.

**Status: fixed.** `InventoryManager._ready()` now broadcasts the starting inventory and hotbar (deferred to end-of-frame, so the HUD's `@onready` references are resolved first), and `hotbar_pressed()` bounds-checks the index.

### A2 — Energy is broadcast clamped but stored unclamped, so starvation compounds and the health bar lies
`game/managers/player_stats_manager.gd:9-16`

```gdscript
current_energy += delta
if current_energy < 0:
    current_health += current_energy          # (a) no signal emitted
EventSystem.PLA_energy_updated.emit(
    MAX_ENERGY, clamp(current_energy, 0, MAX_ENERGY)   # (b) clamps the copy, not the field
)
```

Three separate problems from one root cause — the clamp is applied to the emitted value, not to
the stored field:

- **Compounding drain.** Once `current_energy` is negative it keeps falling, and the *entire*
  running deficit is charged to health again every frame. At −1 you lose 1 health/frame; at −10,
  10/frame. Starvation is quadratic, not linear.
- **The health bar never moves.** Line 12 writes `current_health` directly without emitting
  `PLA_health_updated`, so the player watches a full health bar while dying.
- **Eating barely helps.** A mushroom's `+10` is applied to a deeply negative number, so after any
  significant starvation food does nothing visible.

Symmetrically, eating above 100 stores >100 energy while displaying 100, so the next
stretch of walking is free.

**Fix:** clamp `current_energy` into the field; compute the overdraft, clamp the field to 0, and
route the health loss through `change_health()` so the signal fires.

**Status: fixed.** `current_energy` is now clamped in the field; the overdraft is charged once and routed through `change_health()` so `PLA_health_updated` fires. Both stat fields are explicitly typed `float`.

### A3 — `Interactable.startInteraction` is never callable
`items/interactables/interactable.gd:7` vs `Actors/player/interaction_ray_cast.gd:11`

The base class defines `startInteraction()` (camelCase); the caller invokes
`collider.start_interaction()` (snake_case). Only `Pickuppable` happens to define the
snake_case name, so every current interactable works by accident.

**Failure:** any new `Interactable` that relies on the base method →
`Invalid call. Nonexistent function 'start_interaction'`.

**Fix:** rename the base method to `start_interaction()`.

**Status: fixed.** Base method renamed to `start_interaction()`.

### A4 — `can_see_player()` calls the FOV check twice and never checks line of sight
`Actors/animals/animal.gd:137-138`

```gdscript
return player_in_vision_range and player_in_fov() and player_in_fov()
```

`player_in_los()` (lines 140-148) is fully implemented, carefully masks ground + static bodies,
and is **never called anywhere**. The duplicated `player_in_fov()` is clearly where it belongs.

**Failure:** wolves detect and chase the player straight through terrain, trees and boulders.
Also note `vision_fov = 80.0` is compared against `angle_to()`, which returns the angle from
centre — so the cone is 160° wide, not 80°.

**Fix:** `return player_in_vision_range and player_in_fov() and player_in_los()`, and halve
`vision_fov` (or `deg_to_rad(vision_fov / 2.0)`) to make the export mean total FOV.

**Status: fixed** (line of sight). `can_see_player()` now calls `player_in_los()` instead of `player_in_fov()` twice, and `player_in_los()` resolves the player's head by node lookup rather than by an untyped property access. The `vision_fov` half-angle/total-angle question is a tuning decision and was left alone.

### A5 — Hotbar-equippable items with no equippable scene crash on equip
`Actors/player/equippable_item_holder.gd:12`, `game/configs/item_config.gd:79-89`

`get_equippable_item_scene()` returns `null` for unregistered keys, and the caller immediately
does `.instantiate()` on it. The guard that is supposed to prevent this —
`HotbarSlot._can_drop_data` checking `is_equippable` — disagrees with the scene registry:

| `is_equippable = true` in `.tres` | Has an entry in `EQUIPPABLE_ITEM_SCENES` |
| --- | --- |
| Axe, Pickaxe, Mushroom, Tent | ✅ |
| **Campfire, CookedMeat, Fruit, Multitool, Raft, Tinderbox, Torch** | ❌ |

**Failure:** get any of those seven items into the inventory, drag it to the hotbar (permitted),
press its key → `Attempt to call 'instantiate()' on a null value`.

**Fix:** null-check in `equip_item()` and bail early; and derive `_can_drop_data` from
`EQUIPPABLE_ITEM_SCENES.has(key)` rather than from a hand-maintained flag, so the two cannot drift.

**Status: fixed.** `equip_item()` null-checks the packed scene, and both `_can_drop_data` guards now ask `ItemConfig.is_equippable()`, which reads `EQUIPPABLE_ITEM_SCENES` directly. The `ItemResource.is_equippable` field is now unused by logic and should be dropped in a data pass (see D2).

### A6 — Broken ternary in `updateIcon` inverts the null guard it was meant to be
`ui/custom_nodes/inventory_slot.gd:17`

```gdscript
icon_texture_rect.texture = resource == null if null else resource.icon
```

GDScript's conditional is `<true_expr> if <cond> else <false_expr>`, so this parses as
condition `null` (always falsy) → evaluate `resource.icon`. The intent was
`null if resource == null else resource.icon`; as written the null branch is unreachable and the
non-null branch is taken unconditionally.

**Failure:** a slot holding a key missing from `ITEM_RESOURCE_PATHS` →
`Invalid get index 'icon' on a base object of type 'Nil'`. Latent today because every key is
registered, but the guard on line 15 shows this path was expected to be hit.

**Status: fixed.** Ternary corrected to `null if resource == null else resource.icon`.

---

## B. Logic bugs

### B1 — The last inventory slot can never be filled
`game/managers/inventory_manager.gd:14`

```gdscript
if slot > -1 && slot < INVENTORY_SIZE - 1:
```

`get_free_slot()` already returns `-1` when full, so the upper bound is redundant — and being
`< 27` rather than `< 28` it rejects the valid last slot. The inventory is effectively 27 slots,
and picking up an item into the final slot silently fails.

**Fix:** `if slot > -1:`.

### B2 — Crafting into a full inventory destroys the materials
`bulletins/player_menus/crafting_menu.gd:36-40`, `game/managers/inventory_manager.gd:12-18`

`crafting_button_pressed()` emits `INV_delete_crafting_blueprint_costs` and then `INV_add_item`
without checking the `bool` that `add_item()` returns. If the inventory is full the costs are
already gone and the crafted item never appears.

Compounding it, `delete_item()` (line 58-64) never calls `send_inventory()`, so when `add_item()`
fails nothing broadcasts and the UI keeps showing materials the player no longer owns until some
other event refreshes it.

**Fix:** check capacity before consuming costs (or add first, then consume), and emit
`send_inventory()` from the deletion paths.

### B3 — `FleeTimer` is not one-shot, so a spooked animal is yanked back to Idle forever
`Actors/animals/animal_template.tscn` (`FleeTimer` has no `one_shot`), `Actors/animals/animal.gd:150-177`

Every other timer in the template sets `one_shot = true`; `FleeTimer` does not. It is started in
the `Flee` branch and stopped only in the `Hurt`, `Chase` and `Dead` branches — **not** in `Idle`
or `Wander`.

**Failure:** hit a cow once. It flees, the timer fires after 3 s and returns it to Idle — then
repeats every 3 s for the rest of the session, cancelling each new Wander and leaving the cow
twitching in place.

**Fix:** set `one_shot = true` on `FleeTimer`, and stop it in the `Idle`/`Wander` entry branches.

### B4 — Animals have no gravity
`Actors/animals/animal.gd` (no `velocity.y` handling anywhere)

`pick_wander_velocity()`, `chase_loop()` and `pick_away_from_velocity()` all write a `velocity`
with `y` at 0 and call `move_and_slide()`. Nothing ever applies gravity, unlike the player
(`player.gd:21-22`).

**Failure:** an animal that starts or ends up above the terrain hovers there; one that walks off a
ledge crosses the gap in mid-air.

### B5 — `Hurt` and `Dead` have no per-frame case, so animals freeze in place while reacting
`Actors/animals/animal.gd:104-115`

The `_physics_process` `match` handles `Idle`, `Wander`, `Flee`, `Chase`, `Attack` but not `Hurt`.
With B4 that means a fleeing animal hit mid-stride stops dead in the air until the hurt animation
finishes, then teleports back into motion.

### B6 — The interaction prompt does not update when looking from one interactable to another
`Actors/player/interaction_ray_cast.gd:12-14`

`is_hitting` is a single boolean with no memory of *which* collider it refers to. The prompt is
created on the false→true edge only, so panning directly from a stick to a mushroom (with no
empty frame between) leaves the stick's prompt on screen.

**Fix:** track the current collider and refresh the bulletin when it changes.

### B7 — Freezing the player does not stop key input, so the crafting menu cannot be closed with a key and hotkeys still fire
`Actors/player/player.gd:13-17` and `63-72`

`set_freeze()` calls `set_process_input()` and `set_process_unhandled_input()`, but the hotkey
handler is `_unhandled_key_input()`, which is gated by the separate
`set_process_unhandled_key_input()`. That method is never called.

**Failure:** with the crafting menu open and the player "frozen", `1`–`9` still equip and unequip
items behind the menu, `TAB` still re-emits the create request, and `Esc` re-captures the mouse —
which makes the menu's only exit (its `CloseButton`) unclickable. The menu has no keyboard close
path at all.

**Fix:** add `set_process_unhandled_key_input(!freeze)` to `set_freeze()`, and bind `Esc`/`TAB` to
close an open menu.

---

## C. Robustness

### C1 — Detached residue bodies leak
`objects/hittable_objects/hittable_object.gd:31-33`

`_ready()` calls `remove_child(residue_static_body)` and holds the reference. A node with no
parent is not freed when its former parent is freed, so every tree or boulder destroyed by a
stage change (`StageController.change_stage`) leaks its stump.

**Fix:** keep the residue in the tree and hide/disable it, or `queue_free()` it in `_exit_tree()`
when it is still detached.

### C2 — `die()` is not idempotent
`objects/hittable_objects/hittable_object.gd:20-29`

`queue_free()` is deferred, so the `Hitbox` survives until the end of the frame while
`current_health` stays ≤ 0. A second `register_hit` in that window re-enters `die()` and calls
`add_child(residue_static_body)` on a node that already has a parent → error. Add an
`is_dead` guard.

Also dead code: `if item_spawn_points == null` (line 24) can never be true — `item_spawn_points`
is `@onready $ItemSpawnPoints`, so a missing node would already have failed at line 22.

### C3 — `delete_equipped_item()` indexes with a possibly-null slot
`game/managers/equipped_item_manager.gd:22-23`

`INV_delete_item_by_index.emit(active_hotbar_slot, true)` with `active_hotbar_slot == null` reaches
`hotbar[null]`. Reachable if a `use_item` animation's `destroy_self`/`consume` keyframe fires after
the slot was cleared by another path.

### C4 — Sub-resources shared across every instance of an inherited scene
`Actors/animals/animal.gd:119`, `items/equippables/equippable_constructable.gd:52-53`

`vision_area_collision_shape.shape.radius = vision_range` mutates the `SphereShape3D` declared in
`animal_template.tscn`, which is shared by every wolf and cow. It is harmless only because both
species use the default `vision_range = 15`; give the wolf a different value and every cow inherits
it. Mark the shape `resource_local_to_scene`, or `duplicate()` before writing.

(By contrast, `equippable_constructable.gd` does this correctly — it `duplicate()`s the mesh before
building the preview.)

### C5 — Blueprint lookups are unguarded
`bulletins/player_menus/crafting_menu.gd:11-17`, `45`

`get_item_blueprint()` returns `null` for unregistered keys, and both `show_crafting_info()` and
`update_inventory()` dereference `.costs` immediately. Any key added to `CRAFTABLE_ITEM_KEYS`
before its blueprint exists crashes the menu — which is exactly what the six commented-out entries
in `item_config.gd:30-36` would do if uncommented.

### C6 — Frame-rate-dependent gravity
`Actors/player/player.gd:5`, `21-22`

`velocity.y -= gravity` is applied per physics frame without `delta`. It is stable while the
physics tick is fixed at 60 Hz, but the constant silently means "per tick", not "per second", and
breaks on any tick-rate change. Prefer `get_gravity()` / `ProjectSettings` and scale by `delta`.

### C7 — `int(event.as_text())` to recover a hotkey number
`Actors/player/player.gd:72`

Parsing the key number out of a human-readable string works only because `int()` stops at the
first non-digit (`"1 (Physical)"` → `1`). Read `event.keycode`/`physical_keycode` and subtract
`KEY_1`, or declare nine separate actions.

### C8 — Signals declared with no parameters
`game/event_system.gd`

Every signal is bare (`signal INV_try_to_pickup_item`) while emitters pass one to four arguments.
Godot does not validate this, so the argument contract exists only in the emit and connect sites —
no editor autocompletion, no static checking, and a rename or reorder fails silently at runtime.
Declaring the parameters (`signal INV_try_to_pickup_item(key: ItemConfig.Keys, on_taken: Callable)`)
costs nothing and documents the bus.

---

## D. Content data defects

### D1 — `fruit_item_resource.tres` is a copy of the mushroom resource
`resources/item_resources/fruit_item_resource.tres`

```
item_key = 3          # ItemConfig.Keys.Mushroom — should be 4 (Fruit)
display_name = "Mushroom"
```

Two resources now claim `item_key = 3`. `WeaponItemResource.item_key` is what
`HittableObject.register_hit` matches against `weapon_filter`, so this class of drift silently
breaks harvesting; here it means fruit would display and behave as a mushroom.

Root cause worth fixing: `item_key` inside the `.tres` duplicates the `ItemConfig` dictionary key,
giving two sources of truth with nothing checking them. A `_ready` assertion over
`ITEM_RESOURCE_PATHS`, or dropping the field and passing the key in from the caller, removes the
class of bug.

### D2 — Seven items are flagged `is_equippable` without an equippable scene
See A5. `is_equippable` is a second, hand-maintained source of truth for the same fact
`EQUIPPABLE_ITEM_SCENES` already encodes.

### D3 — Placeholder resources typed as weapons
`campfire`, `multitool`, `raft`, `tinderbox`, `torch` `_item_resource.tres`

All five are `WeaponItemResource` with an identical `damage = 20.0 / damage_range = 1.5 /
energy_change_per_use = -0.5`, which is clearly copy-paste scaffolding rather than intent — a
campfire and a raft are not weapons. Worth retyping before they become load-bearing.

---

## E. Style and consistency

### E1 — Mixed naming conventions
GDScript convention is `snake_case` for members and functions. Current exceptions:

| Location | Current | Should be |
| --- | --- | --- |
| `player.gd:2-7` | `normalSpeed`, `sprintSpeed`, `jumpVelocity`, `mouseSensitivity` | `normal_speed`, … |
| `player.gd:24-27` | `isSprinting`, `inputDirection` | `is_sprinting`, `input_direction` |
| `pickuppable.gd:5` | `itemKey` | `item_key` |
| `inventory_manager.gd:34-36` | `isHotbar1`, `isHotbar2` | `is_hotbar_1`, … |
| `inventory_slot.gd:12` | `updateIcon()` | `update_icon()` |
| `crafting_menu.gd:24` | `isNotEmpty()` | `is_not_empty()` |
| `interactable.gd:7` | `startInteraction()` | `start_interaction()` (also A3) |
| `stage_controller.gd:9` | `newStage` | `new_stage` |

### E2 — Typos in identifiers and filenames
- `obstactles` → `obstacles` (`equippable_constructable.gd:13, 62, 66`)
- `bolder` → `boulder`: `hittable_coal_bolder.tscn`, `hittable_flintstone_bolder.tscn`,
  `coal_bolder_attributes.tres`, `flintstone_bolder_attributes.tres` — note the root-level
  `flintstone_boulder.tscn` spells it correctly, so both spellings are live.
- `UNACTIVE_COLOR` → `INACTIVE_COLOR` (`hotbar_slot.gd:5`)
- `pick_away_from_velocity()` (`animal.gd:121`) neither picks a velocity *from* a velocity nor
  reads as what it does — it sets a velocity away from the player. `flee_from_player()` would say it.

### E3 — Inconsistent semicolons
`player.gd`, `interaction_ray_cast.gd`, `interactable.gd`, `pickuppable.gd`,
`bulletin_controller.gd`, `stage_config.gd`, `bulletin_config.gd` and
`interaction_prompt.gd` terminate statements with `;`; the rest of the codebase does not.
GDScript does not use them. Pick one (idiomatically: none).

### E4 — Debug `print` left in a hot path
`objects/hittable_objects/hittable_object.gd:16` prints remaining health on every hit.

### E5 — Redundant and dead code
- `crafting_menu.gd:31-34` re-declares `hide_item_info()` identically to `PlayerMenuBase`'s.
- `inventory_manager.gd:58-64` checks `inventory.has(item_key)` and then `rfind`s it — two full
  scans where `rfind` and an `!= -1` check suffice.
- `stage_controller.gd:10` — `if newStage is Node` is always true, since `get_stage()` is typed `-> Node`.
- `PlayerMenuBase.close()` hardcodes `BulletinConfig.Keys.CraftingMenu` (line 14), so the shared
  base class closes the crafting menu regardless of which menu subclass it belongs to.
- `player.gd:4` `jumpVelocity` is exported and never read; `jump` is bound in `project.godot` and
  never handled.

### E6 — Case-mismatched resource paths will break exported builds on case-sensitive filesystems
`game/configs/bulletin_config.gd:9`, `game/configs/stage_config.gd:8`

```gdscript
Keys.InteractionPrompt : "res://Bulletins/interaction_prompt.tscn"   # dir is bulletins/
Keys.Island            : "res://Stages/island.tscn"                 # dir is stages/
```

These resolve on Windows/macOS but fail in a packed export and on Linux. (`res://Actors/...`
elsewhere is fine — that directory really is capitalised.)

---

## F. Repository hygiene

### F1 — Godot editor temp files are committed
`game/mai20F9.tmp`, `game/maiD43.tmp`, `game/maiDCE7.tmp`, `stages/isl15BA.tmp`,
`ui/hud/hud41CC.tmp`, `ui/hud/hud5B4E.tmp` — six scene-save temp files tracked in git.
Add `*.tmp` to `.gitignore` and `git rm --cached` them.

### F2 — Stray scenes at the repository root
`campfire.tscn`, `fruit.tscn` and `log.tscn` sit at the root and are referenced by nothing;
`flintstone_boulder.tscn`, `pickaxe.tscn` and `stone.tscn` are referenced but belong under
`meshes/` or `objects/` with the rest of their kind. Every other asset in the project is
neatly foldered, so these read as forgotten scratch files.

### F3 — No README
The project has no README, no build/run instructions, and no note of the required Godot version
(4.2, per `project.godot`).

### F4 — No tests and no CI
Nothing verifies the data-integrity invariants that defects D1/D2 violate, and those are exactly
the kind that a headless Godot script could check in seconds: every `Keys` entry has a resource,
every resource's `item_key` matches its dictionary key, every `is_equippable` item has an
equippable scene, every key in `CRAFTABLE_ITEM_KEYS` has a blueprint, every blueprint cost
references a real key.

---

## Suggested order of work

**A1–A6 are done** — the crash paths, the energy/health accounting, and the wall-hacking wolf AI.

Remaining, in order:

1. **B1, B2, B7** — inventory correctness and being able to close the menu.
2. **D1 + D2** — fix the fruit resource, and drop the now-unused `ItemResource.is_equippable` field
   (A5 already moved the drop rules onto `EQUIPPABLE_ITEM_SCENES`, so the field has no readers left).
3. **B3, B4, B5** — animal movement and the flee-timer loop.
4. **F1, F4** — gitignore the temp files; add the data-integrity check as a headless test.
5. **C1–C8, E1–E6** — cleanup, ideally alongside whatever feature touches each file next.
