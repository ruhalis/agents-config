"""
RSL-RL PPO runner cfg for a Lab 2.3 task (modeled on isaaclab_tasks/direct/cartpole/agents).

Place this under:
    <your_task>/agents/rsl_rl_ppo_cfg.py        (next to agents/__init__.py)
and point the registration at it:
    "rsl_rl_cfg_entry_point": f"{agents.__name__}.rsl_rl_ppo_cfg:MyTaskPPORunnerCfg"

Every field set below is MISSING in isaaclab_rl.rsl_rl; leave none out. obs_groups is
left unset, as in upstream cartpole (set it only for extra observation groups).
Checkpoints land in logs/rsl_rl/<experiment_name>/<timestamp>/model_<iter>.pt under the cwd.
"""

from isaaclab.utils import configclass

from isaaclab_rl.rsl_rl import RslRlOnPolicyRunnerCfg, RslRlPpoActorCriticCfg, RslRlPpoAlgorithmCfg


@configclass
class MyTaskPPORunnerCfg(RslRlOnPolicyRunnerCfg):
    num_steps_per_env = 24
    max_iterations = 1000               # --max_iterations overrides
    save_interval = 50
    experiment_name = "my_task"
    policy = RslRlPpoActorCriticCfg(
        init_noise_std=1.0,
        actor_obs_normalization=False,  # replaces the deprecated runner-level empirical_normalization
        critic_obs_normalization=False,
        actor_hidden_dims=[256, 128, 64],
        critic_hidden_dims=[256, 128, 64],
        activation="elu",
    )
    algorithm = RslRlPpoAlgorithmCfg(
        value_loss_coef=1.0,
        use_clipped_value_loss=True,
        clip_param=0.2,
        entropy_coef=0.005,
        num_learning_epochs=5,
        num_mini_batches=4,
        learning_rate=1.0e-3,
        schedule="adaptive",
        gamma=0.99,
        lam=0.95,
        desired_kl=0.01,
        max_grad_norm=1.0,
    )
