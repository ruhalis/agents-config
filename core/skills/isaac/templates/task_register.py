"""
Task registration boilerplate.

Place this code in the __init__.py of your task package, e.g.:
    my_project/tasks/my_task/__init__.py
with the runner cfgs in a sibling agents/ package (agents/__init__.py +
agents/rsl_rl_ppo_cfg.py, see templates/agents/).

After this file runs once at import time, gym.make() can find the task by its id.

If you put your task inside the IsaacLab tree (under
isaaclab_tasks/direct/<your_task>/ or isaaclab_tasks/manager_based/<your_task>/)
`import isaaclab_tasks` imports it recursively — you only need the
gym.register() block. For an external project, see the footer.

For DirectRLEnv-style tasks, suffix the id with -Direct-v0 by Lab convention.
"""

import gymnasium as gym

from . import agents

# lazy strings: importing this package needs only gymnasium, so it is safe before AppLauncher
gym.register(
    id="Isaac-MyTask-Direct-v0",
    entry_point=f"{__name__}.my_task_env:MyTaskEnv",
    # Manager-based task: entry_point="isaaclab.envs:ManagerBasedRLEnv" and
    # env_cfg_entry_point=f"{__name__}.my_task_env_cfg:MyTaskEnvCfg"
    disable_env_checker=True,
    kwargs={
        "env_cfg_entry_point": f"{__name__}.my_task_env:MyTaskEnvCfg",
        "rsl_rl_cfg_entry_point": f"{agents.__name__}.rsl_rl_ppo_cfg:MyTaskPPORunnerCfg",
        # Other frameworks read YAML files you must add to agents/ (copy from a similar
        # upstream task's agents/ folder), then uncomment:
        # "rl_games_cfg_entry_point": f"{agents.__name__}:rl_games_ppo_cfg.yaml",
        # "skrl_cfg_entry_point": f"{agents.__name__}:skrl_ppo_cfg.yaml",
        # "sb3_cfg_entry_point": f"{agents.__name__}:sb3_ppo_cfg.yaml",
    },
)

# --- External project: make the stock train/play scripts see the task. ---
# Stock <IsaacLab>/scripts/reinforcement_learning/*/train.py only sees tasks in
# isaaclab_tasks; `pip install -e` alone still gives NameNotFound. Either:
#   (a) generate the project with `<IsaacLab>/isaaclab.sh --new` (the copied scripts
#       add `import <pkg>.tasks`; it pip-installs the template's requirements into
#       the active env), or
#   (b) use a wrapper (the cooper pattern, cooper/sim/il/ppo_finetune.py):
#
#       import os, runpy, sys
#       STOCK = "<IsaacLab>/scripts/reinforcement_learning/rsl_rl/train.py"
#       sys.path.insert(0, "<dir holding my_project>")  # skip if pip install -e'd
#       import my_project.tasks  # noqa: F401  (registers the ids; lazy strings, no Kit needed)
#       sys.path.insert(0, os.path.dirname(STOCK))  # stock script imports its sibling cli_args
#       runpy.run_path(STOCK, run_name="__main__")  # argv passes through unchanged
#
#   OMNI_KIT_ACCEPT_EULA=YES <venv>/bin/python train_wrapper.py \
#       --task Isaac-MyTask-Direct-v0 --headless --num_envs 4096
#
# If Kit itself needs flags (extra extension folders, extensions), pass them through
# AppLauncher: --kit_args "--ext-folder=<dir> --enable <ext>"
