"""
Minimal Isaac Lab 2.3 ManagerBasedRLEnv template.

Use this style when your task naturally decomposes into independent reward terms,
observation groups, and randomization events. For tightly-coupled custom physics,
prefer DirectRLEnv (see direct_rl_env.py).

Layout convention:
    my_task/
        __init__.py            # gym.register(...)
        my_task_env_cfg.py     # this file
        mdp/
            __init__.py
            rewards.py         # reward term functions
            observations.py    # observation term functions
            terminations.py    # termination term functions
            events.py          # event/randomization term functions
"""

from __future__ import annotations

import isaaclab.sim as sim_utils
from isaaclab.assets import ArticulationCfg, AssetBaseCfg
from isaaclab.envs import ManagerBasedRLEnvCfg
from isaaclab.managers import (
    EventTermCfg as EventTerm,
    ObservationGroupCfg as ObsGroup,
    ObservationTermCfg as ObsTerm,
    RewardTermCfg as RewTerm,
    SceneEntityCfg,
    TerminationTermCfg as DoneTerm,
)
from isaaclab.scene import InteractiveSceneCfg
from isaaclab.utils import configclass
import isaaclab.envs.mdp as mdp  # built-in MDP terms (joint_pos, time_out, etc.)


# --- Scene config ---
@configclass
class MyTaskSceneCfg(InteractiveSceneCfg):
    ground = AssetBaseCfg(
        prim_path="/World/ground",
        spawn=sim_utils.GroundPlaneCfg(),
    )
    dome_light = AssetBaseCfg(
        prim_path="/World/Light",
        spawn=sim_utils.DomeLightCfg(intensity=2000.0, color=(0.75, 0.75, 0.75)),
    )
    robot: ArticulationCfg = ArticulationCfg(
        prim_path="{ENV_REGEX_NS}/Robot",            # placeholder, replace per env
        spawn=sim_utils.UsdFileCfg(usd_path="REPLACE_WITH_YOUR_USD_PATH"),
        init_state=ArticulationCfg.InitialStateCfg(pos=(0.0, 0.0, 0.5)),
        actuators={},
    )


# --- Action manager ---
@configclass
class ActionsCfg:
    joint_effort = mdp.JointEffortActionCfg(asset_name="robot", joint_names=[".*"], scale=1.0)


# --- Observation manager ---
@configclass
class ObservationsCfg:
    @configclass
    class PolicyCfg(ObsGroup):
        joint_pos = ObsTerm(func=mdp.joint_pos_rel)
        joint_vel = ObsTerm(func=mdp.joint_vel_rel)
        base_lin_vel = ObsTerm(func=mdp.base_lin_vel)
        base_ang_vel = ObsTerm(func=mdp.base_ang_vel)
        last_action = ObsTerm(func=mdp.last_action)

        def __post_init__(self):
            self.enable_corruption = False
            self.concatenate_terms = True

    policy: PolicyCfg = PolicyCfg()


# --- Reward manager ---
@configclass
class RewardsCfg:
    alive = RewTerm(func=mdp.is_alive, weight=1.0)
    terminating = RewTerm(func=mdp.is_terminated, weight=-2.0)
    # add task-specific rewards here, e.g.:
    # progress = RewTerm(func=mdp.base_lin_vel_x, weight=1.0)


# --- Termination manager ---
@configclass
class TerminationsCfg:
    time_out = DoneTerm(func=mdp.time_out, time_out=True)
    # bad_orientation = DoneTerm(func=mdp.bad_orientation, params={"limit_angle": 1.0})


# --- Event manager (resets, randomization) ---
@configclass
class EventsCfg:
    reset_robot = EventTerm(
        func=mdp.reset_joints_by_offset,
        mode="reset",
        params={
            "position_range": (-0.1, 0.1),
            "velocity_range": (-0.1, 0.1),
            "asset_cfg": SceneEntityCfg("robot"),
        },
    )


# --- Top-level env config ---
@configclass
class MyTaskEnvCfg(ManagerBasedRLEnvCfg):
    scene: MyTaskSceneCfg = MyTaskSceneCfg(num_envs=4096, env_spacing=4.0)
    observations: ObservationsCfg = ObservationsCfg()
    actions: ActionsCfg = ActionsCfg()
    rewards: RewardsCfg = RewardsCfg()
    terminations: TerminationsCfg = TerminationsCfg()
    events: EventsCfg = EventsCfg()

    def __post_init__(self):
        self.decimation = 2
        self.episode_length_s = 10.0
        self.sim.dt = 1 / 120
        self.sim.render_interval = self.decimation
