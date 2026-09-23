# Import migration: pre-2025 → Isaac Sim 5.1 / Isaac Lab 2.3

In Isaac Sim 4.5 (Jan 2025), almost every `omni.isaac.*` module was renamed to `isaacsim.*` (a few were removed; see the table).
In Isaac Lab 2.0 (Jan 2025), every `omni.isaac.lab*` module was renamed to `isaaclab*`.
Most tutorials, Stack Overflow answers, and GitHub repos predate these renames.

Sim: deprecated in 4.5; warning shims still ship through 5.1 and are removed in 6.0
(old code that still runs on 5.1 is running on the shim). Lab's `omni.isaac.lab*` has
no shim: `ModuleNotFoundError` at the import line. Always emit the new names.
Upstream rename table: https://docs.isaacsim.omniverse.nvidia.com/5.1.0/overview/extensions_renaming.html

## Isaac Sim rename rules

| Old (≤ 4.2)                          | New (≥ 4.5, including 5.1)                  |
|--------------------------------------|---------------------------------------------|
| `omni.isaac.kit.SimulationApp`       | `isaacsim.SimulationApp` (or `isaacsim.simulation_app.SimulationApp`) |
| `omni.isaac.core`                    | `isaacsim.core.api`                         |
| `omni.isaac.core.utils.*`            | `isaacsim.core.utils.*`                     |
| `omni.isaac.core.objects`            | `isaacsim.core.api.objects`                 |
| `omni.isaac.core.robots`             | `isaacsim.core.api.robots`                  |
| `omni.isaac.core.prims`              | `isaacsim.core.prims` (classes renamed, see below) |
| `omni.isaac.core.articulations`      | `isaacsim.core.prims` for `Articulation`/`ArticulationView` (renamed, see below); `ArticulationSubset`, `ArticulationGripper` stay in `isaacsim.core.api.articulations` |
| `omni.isaac.cloner`                  | `isaacsim.core.cloner`                      |
| `omni.isaac.core.utils.nucleus`      | `isaacsim.storage.native`                   |
| `omni.isaac.sensor`                  | `isaacsim.sensors.physics`, `isaacsim.sensors.camera`, `isaacsim.sensors.rtx` (split) |
| `omni.isaac.range_sensor`            | `isaacsim.sensors.physx`                    |
| `omni.isaac.dynamic_control`         | deprecated, no replacement; use `isaacsim.core.prims` / Lab `Articulation` |
| `omni.isaac.motion_generation`       | `isaacsim.robot_motion.motion_generation`   |
| `omni.isaac.manipulators`            | `isaacsim.robot.manipulators`               |
| `omni.isaac.wheeled_robots`          | `isaacsim.robot.wheeled_robots`             |
| `omni.isaac.franka`                  | `isaacsim.robot.manipulators.examples.franka` (robot, controllers, tasks) |
| `omni.importer.urdf`                 | `isaacsim.asset.importer.urdf`              |
| `omni.importer.mjcf`                 | `isaacsim.asset.importer.mjcf`              |
| `omni.isaac.ros2_bridge`             | `isaacsim.ros2.bridge`                      |
| `omni.isaac.gym`                     | removed; use Isaac Lab                      |

### Class renames in `isaacsim.core.prims`

The old single-prim name now means the batched view class, so a module-only rename
silently changes semantics.

| Old (`omni.isaac.core.*`) | New (`isaacsim.core.prims`) |
|---------------------------|-----------------------------|
| `Articulation`            | `SingleArticulation`        |
| `ArticulationView`        | `Articulation`              |
| `RigidPrim`               | `SingleRigidPrim`           |
| `RigidPrimView`           | `RigidPrim`                 |
| `XFormPrim`               | `SingleXFormPrim`           |
| `XFormPrimView`           | `XFormPrim`                 |
| `GeometryPrim`            | `SingleGeometryPrim`        |
| `GeometryPrimView`        | `GeometryPrim`              |

## Things that were NOT renamed

These are stable across Isaac Sim 4.x / 5.x — use them with confidence.

- `omni.usd` — USD context, stage helpers
- `omni.kit.*` — anything in the Kit framework (`omni.kit.app`, `omni.kit.commands`, `omni.kit.viewport.utility`, etc.)
- `omni.physx.*` — PhysX low-level APIs
- `carb` — Carbonite framework
- `pxr` — Pixar USD bindings (`UsdGeom`, `UsdLux`, `UsdPhysics`, `Gf`, `Sdf`, `Vt`, etc.)
- `warp` — NVIDIA Warp compute

## Isaac Lab rename rules

| Old (≤ 1.4)                                     | New (≥ 2.0, including 2.3)                |
|-------------------------------------------------|-------------------------------------------|
| `omni.isaac.lab`                                | `isaaclab`                                |
| `omni.isaac.lab.sim`                            | `isaaclab.sim`                            |
| `omni.isaac.lab.assets`                         | `isaaclab.assets`                         |
| `omni.isaac.lab.envs`                           | `isaaclab.envs`                           |
| `omni.isaac.lab.envs.mdp`                       | `isaaclab.envs.mdp`                       |
| `omni.isaac.lab.scene`                          | `isaaclab.scene`                          |
| `omni.isaac.lab.terrains`                       | `isaaclab.terrains`                       |
| `omni.isaac.lab.sensors`                        | `isaaclab.sensors`                        |
| `omni.isaac.lab.actuators`                      | `isaaclab.actuators`                      |
| `omni.isaac.lab.controllers`                    | `isaaclab.controllers`                    |
| `omni.isaac.lab.managers`                       | `isaaclab.managers`                       |
| `omni.isaac.lab.utils`                          | `isaaclab.utils`                          |
| `omni.isaac.lab.app`                            | `isaaclab.app`                            |
| `omni.isaac.lab_assets`                         | `isaaclab_assets` (split into `.robots` and `.sensors`) |
| `omni.isaac.lab_assets.anymal`                  | `isaaclab_assets.robots.anymal`           |
| `omni.isaac.lab_tasks`                          | `isaaclab_tasks`                          |
| `omni.isaac.lab_tasks.utils.wrappers.<lib>` (RL wrappers) | `isaaclab_rl.<lib>` (`rsl_rl`, `rl_games`, `skrl`, `sb3`) |

## Directory rename (Lab repo)

When following old tutorials that reference paths inside the IsaacLab repo:

| Old path                                     | New path (2.0+)                          |
|----------------------------------------------|------------------------------------------|
| `source/standalone/workflows/rsl_rl/`        | `scripts/reinforcement_learning/rsl_rl/` |
| `source/standalone/workflows/rl_games/`      | `scripts/reinforcement_learning/rl_games/` |
| `source/standalone/workflows/sb3/`           | `scripts/reinforcement_learning/sb3/`    |
| `source/standalone/workflows/skrl/`          | `scripts/reinforcement_learning/skrl/`   |
| `source/standalone/workflows/robomimic/`     | `scripts/imitation_learning/robomimic/`  |
| `source/extensions/omni.isaac.lab/`          | `source/isaaclab/`                       |
| `source/extensions/omni.isaac.lab_tasks/`    | `source/isaaclab_tasks/`                 |
| `source/extensions/omni.isaac.lab_assets/`   | `source/isaaclab_assets/`                |

## Quick translation pattern

Map each old module by its **longest matching prefix** of whole dotted components (first match in this list wins; `omni.isaac.core_nodes` does not match `omni.isaac.core`):

1. `omni.isaac.lab_tasks.utils.wrappers.<lib>` → `isaaclab_rl.<lib>`
2. `omni.isaac.lab` → `isaaclab`, `omni.isaac.lab_tasks` → `isaaclab_tasks`, `omni.isaac.lab_assets` → `isaaclab_assets` (its submodules also move under `.robots`/`.sensors`)
3. `omni.isaac.kit` → `isaacsim.simulation_app` (write `from isaacsim import SimulationApp`)
4. `omni.isaac.core.utils.nucleus` → `isaacsim.storage.native`
5. `omni.isaac.core.utils` → `isaacsim.core.utils`
6. `omni.isaac.core.prims` / `omni.isaac.core.articulations` → `isaacsim.core.prims`, then apply the class renames (`ArticulationSubset`/`ArticulationGripper` → `isaacsim.core.api.articulations`)
7. `omni.isaac.core` → `isaacsim.core.api`
8. every other row of the Isaac Sim table (`sensor` splits by class, `range_sensor`, `ros2_bridge`, `motion_generation`, `manipulators`, `wheeled_robots`, `franka`, `cloner`, `dynamic_control`, `gym`)
9. `omni.importer.` → `isaacsim.asset.importer.`
10. `source/standalone/workflows/` → `scripts/reinforcement_learning/` (or `scripts/imitation_learning/`)

There is no catch-all: `omni.isaac.` → `isaacsim.` produces modules that do not exist
(`isaacsim.sensor`, `isaacsim.kit`, `isaacsim.franka`, `isaacsim.ros2_bridge`, ...).
Flag any unmapped `omni.isaac.*` for lookup (rename table link above) instead of guessing.
Afterwards grep the result for `isaacsim\.core\.api\.(utils|prims)`: both are wrong (rules 5/6 were skipped).

If the user pastes pre-2025 code and asks for help, **translate it first**, then explain what you changed.
