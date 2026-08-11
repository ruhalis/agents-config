---
name: isaac
description: Use this skill whenever the user is writing, modifying, debugging, or running Python code that targets NVIDIA Isaac Sim or NVIDIA Isaac Lab. Triggers include any mention of Isaac Sim, Isaac Lab, Omniverse Kit, SimulationApp, AppLauncher, DirectRLEnv, ManagerBasedRLEnv, isaaclab.sh, python.sh, USD stages with omni.usd/pxr, RL training in Isaac, or files that import from isaacsim, isaaclab, isaaclab_tasks, isaaclab_assets, omni.isaac, or omni.usd. Also use when the user asks to spawn robots, configure scenes, set up RL environments, or run training/play scripts in Isaac. Targets Isaac Sim 5.1.0 and Isaac Lab 2.3.2 by default; if user is on a different version, surface the difference before generating code.
target_versions:
  isaac_sim: "5.1.0"
  isaac_lab: "2.3.2"
---

# Isaac Sim & Isaac Lab

This skill is for Arlan's robotics work. It targets **Isaac Sim 5.1.0** and **Isaac Lab 2.3.2** — the API surface changed significantly from the 4.x / 1.x line and most tutorials on the web are still wrong. Read this whole file before writing any Isaac code.

## Step 0 — Detect the environment first

Before writing or running anything, find out what's actually installed. Run this once per session:

```bash
# Isaac Sim location & version
echo "ISAAC_SIM_PATH=$ISAAC_SIM_PATH"
ls -d $HOME/.local/share/ov/pkg/isaac-sim-* 2>/dev/null
ls -d /isaac-sim 2>/dev/null
# Read the version file if you find a path
cat "$ISAAC_PATH/VERSION" 2>/dev/null || true

# Isaac Lab location & version
which isaaclab.sh 2>/dev/null
ls $HOME/IsaacLab 2>/dev/null
ls $HOME/IsaacLab/VERSION 2>/dev/null && cat $HOME/IsaacLab/VERSION

# Python interpreter Isaac will use
$HOME/.local/share/ov/pkg/isaac-sim-*/python.sh -c "import sys; print(sys.version)" 2>/dev/null
```

If the user is **not** on 5.1.0 / 2.3.2, stop and tell them — the API differences are large enough that code generated for the wrong version will fail to import. The single biggest break is the **`omni.isaac.*` → `isaacsim.*`** rename in Isaac Sim 4.5+, and the **`omni.isaac.lab.*` → `isaaclab.*`** rename in Isaac Lab 2.0+.

If nothing is detected, ask which version they're on before generating code.

## Step 1 — Pick the right execution model

There are three ways to run Python with Isaac Sim, and they have **different boilerplate**. Picking the wrong one is the most common source of "ModuleNotFoundError: No module named 'omni'".

| Model | When to use | Entry point |
|---|---|---|
| **Standalone Isaac Sim** | One-off scripts, scene authoring, sensor tests, sim setup | `from isaacsim import SimulationApp` |
| **Isaac Lab task** | RL training, anything using `DirectRLEnv` or `ManagerBasedRLEnv` | `from isaaclab.app import AppLauncher` |
| **Inside Isaac Sim GUI** | Script Editor, live experimentation, debugging a running sim | No entry point — Omniverse is already loaded |

**Hard rule for standalone and Lab scripts:** the entry-point class must be instantiated *before* any `omni.*`, `isaacsim.*` (except the `SimulationApp` import itself), `isaaclab.*`, or `pxr` import. The Kit runtime loads extensions at construction time; importing them before that crashes with module-not-found errors that look like the install is broken.

See `templates/` for the canonical boilerplate for each model. Copy the right template, don't write boilerplate from memory.

## Step 2 — Use version-correct imports

The 4.5 / 2.0 renames removed every `omni.isaac.*` and `omni.isaac.lab.*` symbol. If you see code on Stack Overflow, GitHub, or NVIDIA tutorials using the old names, it's pre-2025 and needs translation. Common 5.1 / 2.3 imports:

**Isaac Sim 5.1 (standalone Python):**
```python
from isaacsim import SimulationApp                          # entry point
from isaacsim.core.api import World                         # was omni.isaac.core
from isaacsim.core.api.objects import VisualCuboid, GroundPlane
from isaacsim.core.api.robots import Robot
from isaacsim.core.utils.extensions import enable_extension
from isaacsim.core.utils.stage import add_reference_to_stage
from isaacsim.core.utils.prims import get_prim_at_path
from isaacsim.storage.native import get_assets_root_path   # for Nucleus assets
from isaacsim.sensors.camera import Camera
import omni.usd                                             # this prefix is unchanged
from pxr import UsdGeom, Gf, UsdLux, Sdf                    # pxr is USD core, never renamed
```

**Isaac Lab 2.3:**
```python
from isaaclab.app import AppLauncher                        # entry point for Lab
import isaaclab.sim as sim_utils
from isaaclab.assets import Articulation, ArticulationCfg, RigidObject, RigidObjectCfg
from isaaclab.envs import DirectRLEnv, DirectRLEnvCfg
from isaaclab.envs import ManagerBasedRLEnv, ManagerBasedRLEnvCfg
from isaaclab.scene import InteractiveScene, InteractiveSceneCfg
from isaaclab.sim import SimulationCfg
from isaaclab.terrains import TerrainImporterCfg
from isaaclab.utils import configclass
from isaaclab.sensors import CameraCfg, ContactSensorCfg, RayCasterCfg
from isaaclab_assets import HUMANOID_CFG, ANYMAL_C_CFG     # pre-defined robot configs
import isaaclab_tasks                                       # registers all tasks via __init__
```

**Things that did NOT rename** (use them with confidence): `omni.usd`, `omni.kit.*`, `carb`, `pxr`, `warp`.

For a longer mapping of old-name → new-name, see `reference/import-migration.md`.

## Step 3 — Direct vs Manager-based RL envs (Lab only)

Lab 2.x has two parallel workflows for RL environments. Pick deliberately:

- **`DirectRLEnv`** — one class, you write `_setup_scene`, `_pre_physics_step`, `_apply_action`, `_get_observations`, `_get_rewards`, `_get_dones`, `_reset_idx` directly. Closer to IsaacGymEnvs style. Best for: custom physics logic, tight performance needs, anything where you want PyTorch JIT in the inner loop. Suffix tasks with `-Direct-v0`.
- **`ManagerBasedRLEnv`** — decompose into managers (observation, reward, termination, event, action) each declared as configclass entries. More modular, easier to swap reward terms. Best for: standard locomotion / manipulation where the components are recognizable.

For Arlan's TVC rocket RL work: use **`DirectRLEnv`**. Reward shaping for rocket control involves jet dynamics that are awkward to express as separate reward terms, and the project already uses the Direct style.

Template for a Direct env is in `templates/direct_rl_env.py`. Don't skip the `@configclass` decorator on the Cfg dataclass — Lab won't register it otherwise.

## Step 4 — Task registration

A Lab task is a `gymnasium.register()` call in the package's `__init__.py`. Pattern:

```python
import gymnasium as gym
from . import agents
from .my_env import MyEnv, MyEnvCfg

gym.register(
    id="Isaac-MyTask-Direct-v0",
    entry_point="my_package.my_env:MyEnv",
    disable_env_checker=True,
    kwargs={
        "env_cfg_entry_point": MyEnvCfg,
        "rsl_rl_cfg_entry_point": f"{agents.__name__}.rsl_rl_ppo_cfg:MyTaskPPORunnerCfg",
        # add cfg entry points for whichever frameworks you intend to train with
    },
)
```

The task ID **must be unique across the whole gym registry** and **must start with `Isaac-`** by Lab convention (the train scripts filter on this). The agent configs live in a sibling `agents/` directory, one file per RL framework (`rsl_rl_ppo_cfg.py`, `rl_games_ppo_cfg.py`, `sb3_ppo_cfg.py`, `skrl_ppo_cfg.py`).

For tasks to be visible at training time, the package must be imported. Lab handles this automatically when you put the task under `isaaclab_tasks/direct/<your_task>/` or `isaaclab_tasks/manager_based/<your_task>/` and the parent `__init__.py` calls `import_packages("isaaclab_tasks.direct")`.

## Step 5 — Run commands

Run everything through `isaaclab.sh -p` (Lab) or `python.sh` (raw Isaac Sim). Never use plain `python` — neither environment is on the system Python path.

```bash
# --- Isaac Sim standalone (no Lab) ---
$ISAAC_SIM_PATH/python.sh my_scene.py
$ISAAC_SIM_PATH/python.sh my_scene.py --headless        # if your script wires it through SimulationApp

# --- Isaac Lab ---
cd ~/IsaacLab

# Smoke test an env (no policy, zero actions)
./isaaclab.sh -p scripts/environments/zero_agent.py --task Isaac-MyTask-Direct-v0 --num_envs 16

# Random-action sanity check
./isaaclab.sh -p scripts/environments/random_agent.py --task Isaac-MyTask-Direct-v0 --num_envs 16

# Train (pick the framework that matches your registered agent cfg)
./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/train.py --task Isaac-MyTask-Direct-v0 --headless --num_envs 4096
./isaaclab.sh -p scripts/reinforcement_learning/rl_games/train.py --task Isaac-MyTask-Direct-v0 --headless
./isaaclab.sh -p scripts/reinforcement_learning/skrl/train.py --task Isaac-MyTask-Direct-v0 --headless
./isaaclab.sh -p scripts/reinforcement_learning/sb3/train.py --task Isaac-MyTask-Direct-v0 --headless --num_envs 64

# Play / visualize a trained policy
./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/play.py --task Isaac-MyTask-Direct-v0 --num_envs 32 --use_last_checkpoint

# Record video while headless (uses off-screen renderer)
./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/train.py --task Isaac-MyTask-Direct-v0 --headless --video --video_length 200 --video_interval 2000
```

**Important:** in Lab 2.0+, the workflow scripts live under `scripts/`, not `source/standalone/workflows/`. If a tutorial mentions `source/standalone/workflows/`, it's pre-2.0 and the path no longer exists.

**Flags worth knowing:**
- `--headless` — skip GUI rendering. ~2-4× faster training on most setups. Required for cluster / SSH.
- `--enable_cameras` — needed when `--headless` is set AND you have camera sensors that need to render off-screen. Without this, camera observations will be zeros.
- `--num_envs N` — vectorization count. For RTX 4090-class GPUs, 4096 is a reasonable default for proprioceptive locomotion; drop to 256–1024 if you have vision.
- `--device cuda:0` / `--device cpu` — pipeline backend. Default is `cuda:0`.
- `--seed N` — reproducibility.
- `--resume true --load_run <name>` — continue from a previous checkpoint.

## Step 6 — Common traps (read these — they bite every time)

1. **Imports before SimulationApp / AppLauncher.** Symptom: `ModuleNotFoundError: No module named 'omni'` or `'isaacsim'`. Fix: move the import below the `simulation_app = SimulationApp(...)` line. The only allowed import above it is `SimulationApp` / `AppLauncher` itself.

2. **Wrong Python.** Lab scripts run on Isaac Sim's bundled Python 3.11. If you `pip install` something into your system Python, Lab won't see it. Install into Lab's env: `./isaaclab.sh -p -m pip install <pkg>`.

3. **`--headless` + camera sensors silently produces black images.** Add `--enable_cameras`.

4. **`num_envs` mismatch between cfg and CLI.** The CLI flag overrides the config but only for some scripts. If you set `scene.num_envs = 4096` in the cfg and pass `--num_envs 64`, the cfg value wins in older scripts. Always pass on the CLI to be safe and verify in the log line `[INFO] Spawning N environments`.

5. **`DirectRLEnv` reward returning shape `(num_envs, 1)` instead of `(num_envs,)`.** rl_games and rsl_rl both expect 1D. Squeeze the last dim or return a 1D tensor.

6. **Decimation gotcha.** In `DirectRLEnvCfg`, `sim.dt` is the physics step, and `decimation` is how many physics steps run per *policy* step. So an effective control rate of 60 Hz with `dt=1/120` means `decimation=2`. Episode length in seconds is `episode_length_s = max_episode_steps * decimation * dt`.

7. **USD prim paths must start with `/`.** `World/Robot` will silently fail to find anything. Use `/World/Robot`.

8. **Asset paths.** Use `get_assets_root_path()` from `isaacsim.storage.native` to find the Nucleus assets root — it handles local vs streamed automatically. Hardcoding `omniverse://localhost/NVIDIA/Assets/...` will break on machines that don't run a Nucleus server (most laptops).

9. **CycloneDDS + ROS 2 bridge.** Isaac Sim 5.1 ships its own internal ROS 2 libs (Humble on 22.04, Jazzy on 24.04). If you `source /opt/ros/<distro>/setup.bash` *before* launching Isaac Sim, you must use Python 3.11–built ROS — otherwise let Isaac Sim load its internal libs and don't source ROS in that shell. Arlan has hit CycloneDDS middleware errors with ROS 2 before; if they recur, check `$RMW_IMPLEMENTATION` and `$ROS_DISTRO`.

10. **Fabric vs USD stage.** Lab 2.x runs the physics on Fabric (USDRT) by default for speed. If you read prim attributes via `UsdGeom.Xformable(prim).GetXformOpOrderAttr().Get()` mid-simulation, you'll get stale values. Use the Lab `Articulation` / `RigidObject` wrappers (`root_pos_w`, `root_quat_w`, etc.) which read from Fabric correctly.

11. **`@configclass` decorator missing.** Without it, the dataclass won't be treated as a Lab config and registration will fail with cryptic errors. Always decorate Cfg classes.

## Step 7 — Live experimentation (the Principia trick)

If you want to script into a running Isaac Sim GUI without restarting it for every change, launch Isaac Sim with the code-editor extension:

```bash
$ISAAC_SIM_PATH/isaac-sim.sh --enable isaacsim.code_editor.vscode
```

This opens a TCP code-execution server on `127.0.0.1:8226`. Each connection accepts a UTF-8 Python source body and returns a JSON `{status, output, ename, evalue, traceback}` response, then closes. Useful for poking at a live scene from a separate terminal:

```bash
# Run one-off Python in the running sim
python3 -c "
import socket, json
s = socket.create_connection(('127.0.0.1', 8226), timeout=10)
s.sendall(b'import omni.usd; print([p.GetPath() for p in omni.usd.get_context().get_stage().Traverse()])')
buf = b''
while True:
    chunk = s.recv(4096)
    if not chunk: break
    buf += chunk
print(json.loads(buf).get('output'))
"
```

This is the same mechanism Principia uses for its CLI integration.

## Files in this skill

- `SKILL.md` — this file. Read in full before writing Isaac code.
- `templates/standalone_isaac.py` — minimal Isaac Sim standalone boilerplate (5.1).
- `templates/direct_rl_env.py` — minimal Lab `DirectRLEnv` task skeleton (2.3).
- `templates/manager_based_env.py` — minimal Lab `ManagerBasedRLEnv` task skeleton (2.3).
- `templates/task_register.py` — `gym.register` boilerplate for a custom task.
- `reference/import-migration.md` — old-name → new-name mapping for porting pre-2025 code.
- `reference/common-cfgs.md` — common Cfg snippets (Articulation, Camera, ContactSensor, RayCaster, TerrainImporter).
