"""
Task registration boilerplate.

Place this code in the __init__.py of your task package, e.g.:
    my_project/tasks/my_task/__init__.py

After this file runs once at import time, Lab's train.py / play.py can find
the task by its id.

If you put your task inside the IsaacLab tree (under
isaaclab_tasks/direct/<your_task>/ or isaaclab_tasks/manager_based/<your_task>/)
the surrounding __init__.py does package discovery for you — you only need
the gym.register() block. If your task lives in an external project, the
external project must be imported before the train script reads
gym.envs.registry.

For DirectRLEnv-style tasks, suffix the id with -Direct-v0 by Lab convention.
"""

import gymnasium as gym

from . import agents
from .my_task_env import MyTaskEnv, MyTaskEnvCfg

gym.register(
    id="Isaac-MyTask-Direct-v0",
    entry_point="my_project.tasks.my_task.my_task_env:MyTaskEnv",
    disable_env_checker=True,
    kwargs={
        "env_cfg_entry_point": MyTaskEnvCfg,
        # add the agent configs for whichever frameworks you'll train with:
        "rsl_rl_cfg_entry_point": f"{agents.__name__}.rsl_rl_ppo_cfg:MyTaskPPORunnerCfg",
        "rl_games_cfg_entry_point": f"{agents.__name__}:rl_games_ppo_cfg.yaml",
        "skrl_cfg_entry_point": f"{agents.__name__}:skrl_ppo_cfg.yaml",
        "sb3_cfg_entry_point": f"{agents.__name__}:sb3_ppo_cfg.yaml",
    },
)

# --- For an external project, ensure it's importable BEFORE training. ---
# Either:
#   1. Install your project as an editable package (pip install -e .) into Lab's
#      Python env: ./isaaclab.sh -p -m pip install -e .
#   2. Or pass --enable_extension to AppLauncher and structure your project
#      as an Omniverse extension.
#
# Then the training command becomes:
#   ./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/train.py \
#       --task Isaac-MyTask-Direct-v0 --headless --num_envs 4096
