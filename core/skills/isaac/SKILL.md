---
name: isaac
description: Use this skill whenever the user is writing, modifying, debugging, or running Python code that targets NVIDIA Isaac Sim or NVIDIA Isaac Lab. Triggers include any mention of Isaac Sim, Isaac Lab, Omniverse Kit, SimulationApp, AppLauncher, DirectRLEnv, ManagerBasedRLEnv, isaaclab.sh, python.sh, USD stages with omni.usd/pxr, RL training in Isaac, or files that import from isaacsim, isaaclab, isaaclab_tasks, isaaclab_assets, omni.isaac, or omni.usd. Also use when the user asks to spawn robots, configure scenes, set up RL environments, or run training/play scripts in Isaac. Targets Isaac Sim 5.1.0 and Isaac Lab 2.3.2 by default; if user is on a different version, surface the difference before generating code.
compatibility: Runs on Linux x86_64 + NVIDIA RTX with Isaac Sim 5.1 (Python 3.11) / Isaac Lab 2.3.x; on macOS, author and check statically only.
metadata:
  isaac-sim-version: "5.1.0"
  isaac-lab-version: "2.3.2"
---

# Isaac Sim & Isaac Lab

This skill is for Arlan's robotics work. It targets **Isaac Sim 5.1.0** and **Isaac Lab 2.3.2** (last verified against upstream: 2026-09-22) — the API surface changed significantly from the 4.x / 1.x line and most tutorials on the web are still wrong. Read this whole file before writing any Isaac code.

The pin, venv path, task package, env style and robot facts come from the project's `CLAUDE.md`, `.gitmodules` and `STATUS.md`. Read those first; never guess.

## Boundaries (fixed decisions)

- **GPU jobs only when asked.** Start training, sweeps, demo collection or anything that holds the GPU longer than a smoke test only on the user's request, and first state the task, `--num_envs`, `--max_iterations` and the expected wall time.
- **Torch in the Isaac venv is pinned on purpose.** `isaacsim[all]` bundles a cu126 torch with no sm_120 kernels, so `cooper/scripts/setup_sim.sh` overrides it with torch 2.7.0+cu128 / torchvision 0.22.0 for the RTX 5080. Never install or upgrade torch there, and don't `pip install` anything into that venv unasked; for an approved package run `pip install --dry-run <pkg>` first and stop if it would replace torch.
- **Never re-run `./isaaclab.sh --install` unasked.** It reinstalls every `source/` extension and RL framework, reinstalls torch unless it is exactly 2.7.0+cu128, and may `sudo apt-get install cmake`.
- **Never edit the pinned Lab checkout** (`third_party/IsaacLab`). Extend it in the project package: subclassed cfgs, own `mdp` terms, wrappers around the stock scripts (Step 4). Bumping the pin is the user's call.
- **Keep the code-execution server (Step 8) on 127.0.0.1.** It runs any Python it receives. From the Mac, tunnel to it: `ssh -N -L 8226:127.0.0.1:8226 <linux-box>`.

## Step 0 — Detect the environment first

Before writing or running anything, find out what the project pins and what is installed. Run this once per session from the project root (read-only, safe in bash and zsh):

```bash
# 1. Project pin
grep -n -i -E 'isaac ?(sim|lab)[^0-9]{0,6}[0-9]+\.[0-9]' CLAUDE.md STATUS.md 2>/dev/null | head -20
cat .gitmodules 2>/dev/null; git submodule status 2>/dev/null
for lab in third_party/IsaacLab external/IsaacLab "$HOME/isaac/IsaacLab" "$HOME/IsaacLab"; do
  [ -f "$lab/VERSION" ] && echo "$lab: $(cat "$lab/VERSION") $(git -C "$lab" describe --tags 2>/dev/null)"
  [ -f "$lab/_isaac_sim/VERSION" ] && echo "  _isaac_sim: $(head -n 1 "$lab/_isaac_sim/VERSION")"
done
# 2. Isaac venvs (pip install): the active one and ~/isaac/venv (a project can have others, e.g. a train venv)
for v in "${VIRTUAL_ENV:-}" "$HOME/isaac/venv"; do
  [ -n "$v" ] && [ -x "$v/bin/python" ] && "$v/bin/python" -c 'import importlib.metadata as m, sys
for d in ("isaacsim", "isaaclab"):
    try: print(sys.prefix, d, m.version(d))
    except m.PackageNotFoundError: print(sys.prefix, d, "not installed")'
done
command -v isaacsim
# 3. Binary (zip) install
echo "ISAACSIM_PATH=${ISAACSIM_PATH:-unset}"
cat "${ISAACSIM_PATH:-$HOME/isaacsim}/VERSION" 2>/dev/null
# 4. Which OS
uname -s
```

**Where this runs.** Isaac needs Linux x86_64 with an NVIDIA RTX GPU. On macOS (`uname -s` prints `Darwin`), do not probe or launch Kit (`python.sh`, `isaaclab.sh`, `import isaacsim`): write the code, check it statically against the pinned source (the Lab checkout at the pinned tag), and hand the user the exact commands to run on the Linux RTX box.

**Check APIs against the pinned source and cite `file:line`.** Grep the project's Lab checkout (cooper: `third_party/IsaacLab` at v2.3.2) for every class, cfg field and flag you use, and cite it (e.g. `source/isaaclab/isaaclab/utils/assets.py:39`). If the submodule is empty (`git submodule status` prints a leading `-`), never run `git submodule update` in the user's repo unasked; clone the pinned tags into a temp dir instead:

```bash
SRC="${TMPDIR:-/tmp}/isaac-src"; mkdir -p "$SRC"
[ -d "$SRC/IsaacLab-2.3.2" ] || git clone -q --depth 1 --branch v2.3.2 https://github.com/isaac-sim/IsaacLab "$SRC/IsaacLab-2.3.2"
# Isaac Sim is large: sparse clone, then add only the extensions you need
[ -d "$SRC/IsaacSim-5.1.0" ] || git clone -q --depth 1 --branch v5.1.0 --filter=blob:none --sparse https://github.com/isaac-sim/IsaacSim "$SRC/IsaacSim-5.1.0"
git -C "$SRC/IsaacSim-5.1.0" sparse-checkout add source/extensions/isaacsim.storage.native
```

**Docs (pinned).** Isaac Lab 2.3.2: https://isaac-sim.github.io/IsaacLab/v2.3.2/index.html · Isaac Sim 5.1.0: https://docs.isaacsim.omniverse.nvidia.com/5.1.0/index.html. Never `main`, `latest` or a repo's default branch: those already describe Lab 3.0 / Sim 6.x.

If the project or machine is **not** on 5.1.0 / 2.3.2, stop and tell the user — the API differences are large enough that code generated for the wrong version fails to import. The biggest breaks are the **`omni.isaac.*` → `isaacsim.*`** rename in Isaac Sim 4.5+ and the **`omni.isaac.lab.*` → `isaaclab.*`** rename in Isaac Lab 2.0+. Ask only when both the project and the machine give no answer.

### Newer versions (not targeted)

Isaac Sim 6.0 / 6.1 are GA and Isaac Lab 3.0 is in Early Access (built for Sim 6.1, Python 3.12). **If Lab 3.x or Sim 6.x is detected, do not reuse this skill's templates or snippets**; much of it breaks silently there:
- Lab 3.0: quaternions wxyz → xyzw (identity `(0, 0, 0, 1)`); asset/sensor data are `ProxyArray` (`.torch` / `.warp`); `write_*_to_sim(data, env_ids)` → `write_*_to_sim_index` / `_mask`; `effort_limit_sim` → `joint_effort_limit`; per-library `train.py`/`play.py` → `isaaclab train|play --rl_library ...`; `--headless` removed; `isaaclab.sh` deprecated.
- Sim 6.0: the `omni.isaac.*` shims are removed; `isaacsim.core.api` / `.prims` / `.utils` are deprecated.
- Sim 6.x live exec (Step 8, per the 6.0 `isaacsim.code_editor.python_server` docs): the server runs code only on EOF, so call `s.shutdown(socket.SHUT_WR)` after `sendall`; with `require_auth` on, start the code with `# isaacsim-python-server-token: <token>` (printed at startup).
- Migrate with https://isaac-sim.github.io/IsaacLab/release/3.0.0/source/migration/migrating_to_isaaclab_3-0.html and upstream's `isaaclab-migrating-2x-to-3x` agent skill.

## Step 1 — Pick the right execution model

There are three ways to run Python with Isaac Sim, and they have **different boilerplate**. Picking the wrong one is the most common source of "ModuleNotFoundError: No module named 'omni'".

| Model | When to use | Entry point |
|---|---|---|
| **Standalone Isaac Sim** | One-off scripts, scene authoring, sensor tests, sim setup | `from isaacsim import SimulationApp` |
| **Isaac Lab task** | RL training, anything using `DirectRLEnv` or `ManagerBasedRLEnv` | `from isaaclab.app import AppLauncher` |
| **Inside Isaac Sim GUI** | Script Editor, live experimentation, debugging a running sim | No entry point — Omniverse is already loaded |

**Hard rule for standalone and Lab scripts:** the entry-point class must be instantiated *before* any `omni.*`, `isaacsim.*` (except the `SimulationApp` import itself), `isaaclab.*`, or `pxr` import. The Kit runtime loads extensions at construction time; importing them before that crashes with module-not-found errors that look like the install is broken.

See `templates/` for the canonical boilerplate for each model (`templates/standalone_isaac.py`; for a custom Lab script, `templates/lab_app_script.py`). Copy the right template, don't write boilerplate from memory.

## Step 2 — Use version-correct imports

Sim's `omni.isaac.*` names were deprecated in 4.5; warning shims still ship through 5.1 and are removed in 6.0. Lab's `omni.isaac.lab*` has no shim. Always emit the new names. Code on Stack Overflow, GitHub, or in NVIDIA tutorials that uses the old names is pre-2025 and needs translation. Common 5.1 / 2.3 imports:

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

Pick Direct for tightly coupled custom dynamics, Manager-based for standard locomotion/manipulation; follow whatever the project already uses.

Templates: `templates/direct_rl_env.py` and `templates/manager_based_env.py`. Decorate every Cfg class with `@configclass` (trap 11).

## Step 4 — Task registration

A Lab task is a `gymnasium.register()` call in the package's `__init__.py`. Pattern:

```python
import gymnasium as gym

from . import agents

# lazy strings: importing this package needs only gymnasium, so it is safe before AppLauncher
gym.register(
    id="Isaac-MyTask-Direct-v0",
    entry_point=f"{__name__}.my_env:MyEnv",
    disable_env_checker=True,
    kwargs={
        "env_cfg_entry_point": f"{__name__}.my_env:MyEnvCfg",
        "rsl_rl_cfg_entry_point": f"{agents.__name__}.rsl_rl_ppo_cfg:MyTaskPPORunnerCfg",
        # add cfg entry points for whichever frameworks you intend to train with
    },
)

# Manager-based: the env class is Lab's own, only the cfg is yours
gym.register(
    id="Isaac-MyTask-v0",
    entry_point="isaaclab.envs:ManagerBasedRLEnv",
    disable_env_checker=True,
    kwargs={
        "env_cfg_entry_point": f"{__name__}.my_task_env_cfg:MyTaskEnvCfg",
        "rsl_rl_cfg_entry_point": f"{agents.__name__}.rsl_rl_ppo_cfg:MyTaskPPORunnerCfg",
    },
)
```

The task ID **must be unique across the whole gym registry**. By convention IDs start with `Isaac-` (`list_envs.py` only lists IDs containing "Isaac"); train/play accept any registered ID. The agent configs live in a sibling `agents/` package (it needs an `__init__.py`): `rsl_rl_ppo_cfg.py` (configclass, see `templates/agents/rsl_rl_ppo_cfg.py`); `rl_games_ppo_cfg.yaml`, `skrl_ppo_cfg.yaml`, `sb3_ppo_cfg.yaml`.

For tasks to be visible at training time, the package must be imported. `import isaaclab_tasks` recursively imports every subpackage (blacklist: `utils`, `.mdp`, `pick_place`, `direct.humanoid_amp.motions`), so a task under `isaaclab_tasks/direct/` or `isaaclab_tasks/manager_based/` registers automatically. The stock `scripts/reinforcement_learning/*/train.py` import only `isaaclab_tasks`, so an external project's task is `NameNotFound` there even after `pip install -e`. Either use a wrapper that does `import <pkg>.tasks`, puts the stock script dir on `sys.path` (for `cli_args`), and calls `runpy.run_path("<IsaacLab>/scripts/reinforcement_learning/rsl_rl/train.py", run_name="__main__")` — the cooper pattern (`sim/il/ppo_finetune.py`, sketch in `templates/task_register.py`; the wrapper is why entry points must be lazy strings) — or, for a **new project or task**, generate it with `isaaclab.sh --new` (the bundled templates are for adding to an existing package). The generator is interactive (InquirerPy prompts) and pip-installs its own requirements (InquirerPy, rich, Jinja2) into the active env, so don't run it yourself: ask the user to run `<IsaacLab>/isaaclab.sh --new` on the Linux box with the Isaac venv active, and tell them what to pick. Task type `External` (asked only when Lab is a source install); Project path outside the IsaacLab checkout; Project name a Python identifier; workflow `Direct | single-agent` or `Manager-based | single-agent` (match the project); RL library `rsl_rl` unless the project trains with another. Checkboxes start empty: Space toggles, Enter confirms. It writes `<path>/<name>/` as a new git repo (init + first commit) with tasks `Template-<Name>-Direct-v0` / `Template-<Name>-v0`, agents cfgs, lazy registration and `scripts/` (train/play, `zero_agent.py`, `random_agent.py`, `list_envs.py`) that `import <name>.tasks`; the user then runs `python -m pip install -e source/<name>` from that dir, venv active.

## Step 5 — Run commands

Run with Isaac's Python, never the *system* python:

| Install | Run a script with |
|---|---|
| pip venv (cooper: `~/isaac/venv`) | `<venv>/bin/python script.py`, or `<IsaacLab>/isaaclab.sh -p script.py` with the venv active |
| Binary zip (`$ISAACSIM_PATH`) | `$ISAACSIM_PATH/python.sh script.py`, or `<IsaacLab>/isaaclab.sh -p script.py` (uses `<IsaacLab>/_isaac_sim/python.sh`) |

Prefix headless/SSH commands with `OMNI_KIT_ACCEPT_EULA=YES`, or the interactive EULA prompt crashes on EOF. The stock train/play scripts write `logs/<library>/...` under the current directory.

```bash
LAB=third_party/IsaacLab     # the project's Isaac Lab checkout (found in Step 0)
source ~/isaac/venv/bin/activate   # pip install: the venv Step 0 found; isaaclab.sh -p uses the active venv
PY="$VIRTUAL_ENV/bin/python"       # binary install: PY=$ISAACSIM_PATH/python.sh, skip the activate
export OMNI_KIT_ACCEPT_EULA=YES

# --- Isaac Sim standalone (no Lab) ---
"$PY" my_scene.py --headless     # --headless only if your script wires it into SimulationApp

# --- Isaac Lab ---
# Smoke test an env (no policy, zero actions)
$LAB/isaaclab.sh -p $LAB/scripts/environments/zero_agent.py --task Isaac-MyTask-Direct-v0 --num_envs 16

# Random-action sanity check
$LAB/isaaclab.sh -p $LAB/scripts/environments/random_agent.py --task Isaac-MyTask-Direct-v0 --num_envs 16

# Train (pick the framework that matches your registered agent cfg)
$LAB/isaaclab.sh -p $LAB/scripts/reinforcement_learning/rsl_rl/train.py --task Isaac-MyTask-Direct-v0 --headless --num_envs 4096
$LAB/isaaclab.sh -p $LAB/scripts/reinforcement_learning/rl_games/train.py --task Isaac-MyTask-Direct-v0 --headless
$LAB/isaaclab.sh -p $LAB/scripts/reinforcement_learning/skrl/train.py --task Isaac-MyTask-Direct-v0 --headless
$LAB/isaaclab.sh -p $LAB/scripts/reinforcement_learning/sb3/train.py --task Isaac-MyTask-Direct-v0 --headless --num_envs 64

# Play / visualize a trained policy
$LAB/isaaclab.sh -p $LAB/scripts/reinforcement_learning/rsl_rl/play.py --task Isaac-MyTask-Direct-v0 --num_envs 32

# Record video while headless (uses off-screen renderer)
$LAB/isaaclab.sh -p $LAB/scripts/reinforcement_learning/rsl_rl/train.py --task Isaac-MyTask-Direct-v0 --headless --video --video_length 200 --video_interval 2000
```

When starting or changing a training run, also apply rl-experiment-log (record the exact command, reward terms, seed).

rsl_rl play loads the newest run's latest `model_*.pt` by default. Pick a run with `--load_run <run_dir>`, or a file with `--checkpoint <full path to model_N.pt>`. `--use_last_checkpoint` exists only in rl_games/sb3 `play.py`. For an external task package, run these through the wrapper from Step 4.

**Important:** in Lab 2.0+, the workflow scripts live under `scripts/`, not `source/standalone/workflows/`. If a tutorial mentions `source/standalone/workflows/`, it's pre-2.0 and the path no longer exists.

**Flags worth knowing:**
- `--headless` — skip GUI rendering. ~2-4× faster training on most setups. Required for cluster / SSH.
- `--enable_cameras` — required for any Camera/TiledCamera sensor (trap 3).
- `--num_envs N` — vectorization count. For RTX 4090-class GPUs, 4096 is a reasonable default for proprioceptive locomotion; drop to 256–1024 if you have vision.
- `--device cuda:0` / `--device cpu` — pipeline backend. Default is `cuda:0`.
- `--seed N` — reproducibility.
- `--resume --load_run <run_dir> [--checkpoint model_<N>.pt]` — rsl_rl train. `--resume` is a switch; `--load_run` is a regex over the run dirs in `logs/rsl_rl/<experiment_name>/`, `--checkpoint` a regex over the files in the chosen run. rl_games/skrl/sb3 resume with `--checkpoint <path>`.
- `--kit_args "--ext-folder=<dir> --enable <ext>"` — raw flags for Kit (there is no `--enable_extension`).

Unknown flags and bare values are passed on to Hydra and abort startup.

## Step 6 — Verify before handing off

Before giving the user commands for the Linux box, check every file you wrote or changed. It is static and runs on the Mac; nothing imports Isaac. `${CLAUDE_SKILL_DIR}` is this skill's directory:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/check_isaac_code.py" path/to/changed_file.py path/to/task_pkg
```

It compiles each file from its bytes as py_compile does, in memory (no `__pycache__`; needs python3 ≥ 3.11), then applies the rules `--help` lists. Exit 0 clean, 1 findings (`path:line: ISCnnn message`), 2 usage error; `--help` lists the rules. Fix each finding or say why it is a false positive (`# isaac-check: ignore` silences a line).

Then hand over a smoke test for the Linux box; it passes when it prints the observation and action spaces and keeps stepping without a traceback. Hand over the train command only after that:

```bash
# Task inside isaaclab_tasks (the stock script sees only those); runs until Ctrl-C
OMNI_KIT_ACCEPT_EULA=YES $LAB/isaaclab.sh -p $LAB/scripts/environments/zero_agent.py --task <id> --num_envs 16 --headless
# External package: the project's scripts/zero_agent.py (from --new), or a copy of templates/lab_app_script.py, e.g.
OMNI_KIT_ACCEPT_EULA=YES <venv>/bin/python scripts/smoke_env.py --task <id> --num_envs 16 --steps 200 --headless
```

## Step 7 — Common traps (read these — they bite every time)

1. **Imports before SimulationApp / AppLauncher.** Symptom: `ModuleNotFoundError: No module named 'omni'` or `'isaacsim'`. Fix: move the import below the `simulation_app = SimulationApp(...)` line. The only allowed import above it is `SimulationApp` / `AppLauncher` itself.

2. **Wrong Python.** Lab scripts run on Isaac's Python 3.11 (venv or bundled). If you `pip install` something into your system Python, Lab won't see it. Install into Isaac's env, only when the user asks and never torch (Boundaries): `<venv>/bin/python -m pip install <pkg>` (binary install: `<IsaacLab>/isaaclab.sh -p -m pip install <pkg>`).

3. **Camera sensors without `--enable_cameras`.** Required whenever the env has Camera/TiledCamera sensors, GUI or headless. Without it, env creation raises RuntimeError "A camera was spawned without the --enable_cameras flag". `--video` turns it on automatically.

4. **`num_envs` in cfg vs CLI.** Stock 2.3 scripts override `cfg.scene.num_envs` with `--num_envs`; custom scripts must do this themselves. Check "Number of environments: N" in the `[INFO]: Scene manager` block.

5. **`DirectRLEnv` reward returning shape `(num_envs, 1)` instead of `(num_envs,)`.** rl_games and rsl_rl both expect 1D. Squeeze the last dim or return a 1D tensor.

6. **Decimation gotcha.** In `DirectRLEnvCfg`, `sim.dt` is the physics step, and `decimation` is how many physics steps run per *policy* step. So an effective control rate of 60 Hz with `dt=1/120` means `decimation=2`. Episode length in seconds is `episode_length_s = max_episode_steps * decimation * dt`.

7. **USD prim paths must start with `/`.** `World/Robot` will silently fail to find anything. Use `/World/Robot`.

8. **Asset paths.** In Lab code use `ISAAC_NUCLEUS_DIR` / `ISAACLAB_NUCLEUS_DIR` from `isaaclab.utils.assets` (e.g. `f"{ISAACLAB_NUCLEUS_DIR}/Robots/..."`, as `isaaclab_assets` does; the module needs Kit, so only in code imported after launch). `get_assets_root_path()` from `isaacsim.storage.native` is for raw Isaac Sim scripts only. Hardcoding `omniverse://localhost/NVIDIA/Assets/...` will break on machines that don't run a Nucleus server (most laptops).

9. **ROS 2 bridge.** Isaac Sim 5.1 ships its own internal ROS 2 libs (Humble on 22.04, Jazzy on 24.04). If you `source /opt/ros/<distro>/setup.bash` *before* launching Isaac Sim, you must use Python 3.11–built ROS — otherwise let Isaac Sim load its internal libs and don't source ROS in that shell. On DDS middleware errors (e.g. CycloneDDS), check `$RMW_IMPLEMENTATION` and `$ROS_DISTRO`.

10. **Fabric vs USD stage.** Lab 2.x runs the physics on Fabric (USDRT) by default for speed. If you read prim attributes via `UsdGeom.Xformable(prim).GetXformOpOrderAttr().Get()` mid-simulation, you'll get stale values. Use the Lab `Articulation` / `RigidObject` wrappers (`root_pos_w`, `root_quat_w`, etc.) which read from Fabric correctly.

11. **`@configclass` decorator missing.** Without it, subclass overrides silently revert to the parent defaults; `validate()` fails at env creation, or the parent values are used. Always decorate Cfg classes.

12. **RTX 50xx (Blackwell): `simulation_app.close()` hangs on Kit teardown.** Batch scripts flush and `os._exit(0)` after the work; don't rely on `close()` (see `templates/standalone_isaac.py`, `templates/lab_app_script.py`).

13. **Install and pip errors on the Linux box** (bundled cu126 torch, the `setuptools<81` / flatdict build failure, Python 3.11): the fixes are in the header of `cooper/scripts/setup_sim.sh`; point there instead of re-deriving them.

## Step 8 — Live experimentation (script a running sim)

If you want to script into a running Isaac Sim GUI without restarting it for every change, launch Isaac Sim with the code-editor extension:

```bash
$ISAACSIM_PATH/isaac-sim.sh --enable isaacsim.code_editor.vscode          # binary install
isaacsim isaacsim.exp.full --enable isaacsim.code_editor.vscode            # pip install, venv active
```

This opens a TCP code-execution server on `127.0.0.1:8226` (keep it there, Boundaries). Each connection takes UTF-8 Python source and answers once with JSON `{status, output}`, plus `ename`, `evalue`, `traceback` when `status` is `"error"`, then closes. From another terminal (on the Mac, through the SSH tunnel):

```bash
python3 - <<'EOF'
import json, socket
CODE = "import omni.usd; print([str(p.GetPath()) for p in omni.usd.get_context().get_stage().Traverse()])"
try:
    s = socket.create_connection(("127.0.0.1", 8226), timeout=10)
except OSError as e:  # refused or timed out
    raise SystemExit(f"cannot connect ({e}): is Isaac Sim up with isaacsim.code_editor.vscode (from the Mac: the SSH tunnel)?")
s.sendall(CODE.encode())  # 5.1: no shutdown(SHUT_WR); the server replies, then closes
buf = b""
try:
    while chunk := s.recv(4096):
        buf += chunk
except socket.timeout:
    raise SystemExit("no reply within 10 s: the code is still running or the sim is busy (raise the timeout for long code)")
if not buf:
    raise SystemExit("no reply: the server closed the connection")
r = json.loads(buf)
print("status:", r["status"])
if r["output"]:
    print(r["output"])
if r["status"] == "error":
    print(f"{r['ename']}: {r['evalue']}")
    print("".join(r["traceback"]))
    raise SystemExit(1)
EOF
```

- Only stdout comes back: `print()` what you want; a bare expression's value is dropped.
- 5.1 runs each TCP chunk it receives as its own program and closes after the first reply, so keep a payload to a few lines; for more, put the code in a file on the box and send `exec(open("/path/on/box.py").read())`. Don't half-close: 5.1 closes on EOF and the reply is lost (6.x is the opposite, see Newer versions).

## Files in this skill

- `SKILL.md` — this file. Read in full before writing Isaac code.
- `templates/standalone_isaac.py` — minimal Isaac Sim standalone boilerplate (5.1).
- `templates/lab_app_script.py` — Lab AppLauncher script: parse_env_cfg + gym.make, bounded zero-action loop, hard exit (2.3).
- `templates/direct_rl_env.py`, `templates/manager_based_env.py` — minimal Lab `DirectRLEnv` / `ManagerBasedRLEnv` task skeletons (2.3).
- `templates/task_register.py` — `gym.register` boilerplate for a custom task, plus the external-project wrapper.
- `templates/agents/__init__.py`, `templates/agents/rsl_rl_ppo_cfg.py` — the `agents/` package with an rsl_rl PPO runner cfg (2.3).
- `reference/import-migration.md` — old-name → new-name mapping for porting pre-2025 code.
- `reference/common-cfgs.md` — common Cfg snippets (Articulation, Camera, ContactSensor, RayCaster, TerrainImporter).
- `scripts/check_isaac_code.py` — stdlib static checker run in Step 6 (`--help` lists the rules); `scripts/test_check_isaac_code.py` is its regression test (`python3 scripts/test_check_isaac_code.py`).
