"""
Minimal Isaac Lab 2.3 script: boot Kit with AppLauncher, register the task package, build the env
with parse_env_cfg + gym.make, step it with zero actions, then hard-exit.

Model for any custom Lab script on a task package (bounded smoke test, eval, demo collection). To reuse
a stock train/play script instead, see the wrapper in task_register.py. Modeled on
<IsaacLab>/scripts/environments/zero_agent.py, but bounded by --steps and with the Blackwell teardown
rule from standalone_isaac.py.

Run with Isaac's Python 3.11, never the system python:
    OMNI_KIT_ACCEPT_EULA=YES <venv>/bin/python lab_app_script.py \
        --task Isaac-MyTask-Direct-v0 --num_envs 16 --steps 200 --headless
    (binary install: <IsaacLab>/isaaclab.sh -p lab_app_script.py ...)
AppLauncher adds --headless, --device, --enable_cameras (needed for Camera/TiledCamera sensors),
--kit_args and more; unknown flags abort startup.
"""

import argparse

from isaaclab.app import AppLauncher

# --- 1. CLI: your flags + AppLauncher's ---
parser = argparse.ArgumentParser(description="Isaac Lab 2.3 script template")
parser.add_argument("--task", type=str, required=True, help="Registered gym id, e.g. Isaac-MyTask-Direct-v0")
parser.add_argument("--num_envs", type=int, default=None, help="Override cfg.scene.num_envs")
parser.add_argument("--steps", type=int, default=200, help="Env steps to run before exiting")
AppLauncher.add_app_launcher_args(parser)
args_cli = parser.parse_args()

# --- 2. Boot Kit. Nothing from isaaclab.* (except isaaclab.app), isaacsim.*, omni.*, carb or pxr above this. ---
app_launcher = AppLauncher(args_cli)
simulation_app = app_launcher.app

# --- 3. Now import the rest ---
import os
import sys

import gymnasium as gym
import torch

from isaaclab_tasks.utils import parse_env_cfg  # imports isaaclab_tasks, which registers the upstream tasks

# REPLACE: your task package (registers its gym ids). Not pip-installed? sys.path.insert(0, "<dir holding it>") first.
import my_project.tasks  # noqa: F401


def main():
    # cfg from the registry (env_cfg_entry_point), with --device / --num_envs applied
    env_cfg = parse_env_cfg(args_cli.task, device=args_cli.device, num_envs=args_cli.num_envs)
    env = gym.make(args_cli.task, cfg=env_cfg)
    print(f"[INFO] observation space: {env.observation_space}  action space: {env.action_space}")

    env.reset()
    for step in range(args_cli.steps):
        if not simulation_app.is_running():  # GUI window closed
            break
        with torch.inference_mode():
            actions = torch.zeros(env.action_space.shape, device=env.unwrapped.device)
            _, reward, terminated, truncated, _ = env.step(actions)
        if step % 50 == 0:
            done = (terminated | truncated).sum().item()
            print(f"[INFO] step={step} mean_reward={reward.mean().item():.4f} resets={done}")
    env.close()


if __name__ == "__main__":
    main()
    # simulation_app.close() hangs on Blackwell (RTX 50xx) Kit teardown (see cooper/scripts/setup_sim.sh),
    # so flush (and close any files you wrote) and hard-exit once the work is done.
    # On other GPUs the clean form is:
    #   simulation_app.close()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(0)
