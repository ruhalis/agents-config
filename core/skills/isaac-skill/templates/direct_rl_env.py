"""
Minimal Isaac Lab 2.3 DirectRLEnv template.

Place this under:
    <your_project>/<your_task>/<your_task>_env.py

Register the task in the sibling __init__.py (see task_register.py).

Run with:
    cd ~/IsaacLab
    ./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/train.py \
        --task Isaac-MyTask-Direct-v0 --headless --num_envs 4096
"""

from __future__ import annotations

import torch

import isaaclab.sim as sim_utils
from isaaclab.assets import Articulation, ArticulationCfg
from isaaclab.envs import DirectRLEnv, DirectRLEnvCfg
from isaaclab.scene import InteractiveSceneCfg
from isaaclab.sim import SimulationCfg
from isaaclab.utils import configclass


@configclass
class MyTaskEnvCfg(DirectRLEnvCfg):
    # --- Episode / control rate ---
    # Effective control rate = 1 / (sim.dt * decimation)
    decimation = 2                      # policy step = 2 physics steps
    episode_length_s = 10.0             # 10 second episodes

    # --- Spaces (Lab 2.x style: declare sizes here, gym.Space is built for you) ---
    action_space = 4                    # e.g. 4 actuators
    observation_space = 16              # e.g. 16-dim proprioceptive observation
    state_space = 0                     # 0 means single-agent / no critic-only state

    # --- Simulation ---
    sim: SimulationCfg = SimulationCfg(dt=1 / 120, render_interval=decimation)

    # --- Scene: num_envs, env spacing, robot config ---
    # Replace ROBOT_CFG with one from isaaclab_assets, or build your own ArticulationCfg.
    # Example: from isaaclab_assets import CARTPOLE_CFG
    robot_cfg: ArticulationCfg = ArticulationCfg(
        prim_path="/World/envs/env_.*/Robot",        # /env_.* expands per env
        spawn=sim_utils.UsdFileCfg(usd_path="REPLACE_WITH_YOUR_USD_PATH"),
        init_state=ArticulationCfg.InitialStateCfg(pos=(0.0, 0.0, 0.5)),
        actuators={},                                # populate with ImplicitActuatorCfg etc.
    )

    scene: InteractiveSceneCfg = InteractiveSceneCfg(
        num_envs=4096,
        env_spacing=4.0,
        replicate_physics=True,
    )

    # --- Task-specific tunables (free-form) ---
    action_scale = 1.0
    reward_scale_alive = 1.0
    reward_scale_progress = 1.0


class MyTaskEnv(DirectRLEnv):
    cfg: MyTaskEnvCfg

    def __init__(self, cfg: MyTaskEnvCfg, render_mode: str | None = None, **kwargs):
        super().__init__(cfg, render_mode, **kwargs)
        # action buffer — set in _pre_physics_step, applied in _apply_action
        self.actions = torch.zeros(self.num_envs, self.cfg.action_space, device=self.device)

    # 1. Build scene -----------------------------------------------------------
    def _setup_scene(self):
        self.robot = Articulation(self.cfg.robot_cfg)
        # Clone envs and filter out copies of the robot for collision groups
        self.scene.clone_environments(copy_from_source=False)
        self.scene.filter_collisions(global_prim_paths=[])
        # Register the articulation so the scene knows about it
        self.scene.articulations["robot"] = self.robot
        # Ground & lighting
        spawn_ground = sim_utils.GroundPlaneCfg()
        spawn_ground.func("/World/ground", spawn_ground)
        light_cfg = sim_utils.DomeLightCfg(intensity=2000.0, color=(0.75, 0.75, 0.75))
        light_cfg.func("/World/Light", light_cfg)

    # 2. Per-policy-step (called once per `decimation` physics steps) ----------
    def _pre_physics_step(self, actions: torch.Tensor) -> None:
        self.actions = actions.clone() * self.cfg.action_scale

    # 3. Per-physics-step ------------------------------------------------------
    def _apply_action(self) -> None:
        # Example: torque/effort control on all joints
        self.robot.set_joint_effort_target(self.actions)

    # 4. Observations ----------------------------------------------------------
    def _get_observations(self) -> dict:
        obs = torch.cat(
            (
                self.robot.data.joint_pos,
                self.robot.data.joint_vel,
                self.robot.data.root_lin_vel_b,
                self.robot.data.root_ang_vel_b,
            ),
            dim=-1,
        )
        return {"policy": obs}

    # 5. Rewards (must return shape (num_envs,)) -------------------------------
    def _get_rewards(self) -> torch.Tensor:
        alive = self.cfg.reward_scale_alive * torch.ones(self.num_envs, device=self.device)
        # progress example: forward velocity in body frame
        progress = self.cfg.reward_scale_progress * self.robot.data.root_lin_vel_b[:, 0]
        return alive + progress

    # 6. Termination (timeouts vs. failures returned separately) ---------------
    def _get_dones(self) -> tuple[torch.Tensor, torch.Tensor]:
        time_out = self.episode_length_buf >= self.max_episode_length - 1
        # Example failure: root falls below z=0.2
        fallen = self.robot.data.root_pos_w[:, 2] < 0.2
        return fallen, time_out

    # 7. Reset selected envs ---------------------------------------------------
    def _reset_idx(self, env_ids: torch.Tensor | None) -> None:
        if env_ids is None or len(env_ids) == self.num_envs:
            env_ids = self.robot._ALL_INDICES
        super()._reset_idx(env_ids)

        # Reset robot to default state (offset by env origin so envs don't overlap)
        default_root = self.robot.data.default_root_state[env_ids].clone()
        default_root[:, :3] += self.scene.env_origins[env_ids]
        self.robot.write_root_pose_to_sim(default_root[:, :7], env_ids)
        self.robot.write_root_velocity_to_sim(default_root[:, 7:], env_ids)

        joint_pos = self.robot.data.default_joint_pos[env_ids]
        joint_vel = self.robot.data.default_joint_vel[env_ids]
        self.robot.write_joint_state_to_sim(joint_pos, joint_vel, None, env_ids)
