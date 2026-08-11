# Import migration: pre-2025 → Isaac Sim 5.1 / Isaac Lab 2.3

In Isaac Sim 4.5 (Jan 2025), every `omni.isaac.*` module was renamed to `isaacsim.*`.
In Isaac Lab 2.0 (Jan 2025), every `omni.isaac.lab*` module was renamed to `isaaclab*`.
Most tutorials, Stack Overflow answers, and GitHub repos predate these renames.

This is not a deprecation — the old import paths are **gone**. Code using them
raises `ModuleNotFoundError` at the import line.

## Isaac Sim rename rules

| Old (≤ 4.2)                          | New (≥ 4.5, including 5.1)                  |
|--------------------------------------|---------------------------------------------|
| `omni.isaac.kit.SimulationApp`       | `isaacsim.SimulationApp` (or `isaacsim.simulation_app.SimulationApp`) |
| `omni.isaac.core`                    | `isaacsim.core.api`                         |
| `omni.isaac.core.utils.*`            | `isaacsim.core.utils.*`                     |
| `omni.isaac.core.objects`            | `isaacsim.core.api.objects`                 |
| `omni.isaac.core.robots`             | `isaacsim.core.api.robots`                  |
| `omni.isaac.core.articulations`      | `isaacsim.core.prims` (Articulation lives in prims now) |
| `omni.isaac.core.utils.nucleus`      | `isaacsim.storage.native`                   |
| `omni.isaac.sensor`                  | `isaacsim.sensors.physics`, `isaacsim.sensors.camera`, `isaacsim.sensors.rtx` (split) |
| `omni.isaac.range_sensor`            | `isaacsim.sensors.physx`                    |
| `omni.isaac.dynamic_control`         | `isaacsim.core.utils.dynamic_control`       |
| `omni.isaac.motion_generation`       | `isaacsim.robot_motion.motion_generation`   |
| `omni.isaac.manipulators`            | `isaacsim.robot.manipulators`               |
| `omni.isaac.wheeled_robots`          | `isaacsim.robot.wheeled_robots`             |
| `omni.isaac.franka`                  | `isaacsim.robot.policy.examples.robots.franka` (examples moved) |
| `omni.importer.urdf`                 | `isaacsim.asset.importer.urdf`              |
| `omni.importer.mjcf`                 | `isaacsim.asset.importer.mjcf`              |
| `omni.isaac.ros2_bridge`             | `isaacsim.ros2.bridge`                      |
| `omni.isaac.gym`                     | `isaacsim.gym` (mostly removed in favor of Isaac Lab) |

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
| `omni.isaac.lab_tasks.wrappers` (RL wrappers)   | `isaaclab_rl` (split into its own module in 2.0) |

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

When porting a pre-2025 snippet, do these replacements in order:

1. `omni.isaac.lab` → `isaaclab`  (do Lab first — it's a substring of the next one)
2. `omni.isaac.kit.SimulationApp` → `isaacsim.SimulationApp`
3. `omni.isaac.core` → `isaacsim.core.api`
4. `omni.isaac.` → `isaacsim.`  (catches everything else)
5. `omni.importer.` → `isaacsim.asset.importer.`
6. `source/standalone/workflows/` → `scripts/reinforcement_learning/` (or `scripts/imitation_learning/`)

After step 4, search for any remaining `omni.isaac` references — those are the cases not covered above and need manual lookup.

If the user pastes pre-2025 code and asks for help, **translate it first**, then explain what you changed.
