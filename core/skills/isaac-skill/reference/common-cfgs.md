# Common Cfg snippets (Isaac Lab 2.3)

Drop-in fragments for the configs you write over and over. All examples assume the imports at the top of `direct_rl_env.py` or `manager_based_env.py`.

## Articulation from a USD file

```python
from isaaclab.assets import ArticulationCfg
from isaaclab.actuators import ImplicitActuatorCfg
import isaaclab.sim as sim_utils

ROBOT_CFG = ArticulationCfg(
    prim_path="/World/envs/env_.*/Robot",
    spawn=sim_utils.UsdFileCfg(
        usd_path="/path/to/robot.usd",
        rigid_props=sim_utils.RigidBodyPropertiesCfg(
            disable_gravity=False,
            max_depenetration_velocity=10.0,
        ),
        articulation_props=sim_utils.ArticulationRootPropertiesCfg(
            enabled_self_collisions=False,
            solver_position_iteration_count=4,
            solver_velocity_iteration_count=0,
        ),
    ),
    init_state=ArticulationCfg.InitialStateCfg(
        pos=(0.0, 0.0, 0.5),
        rot=(1.0, 0.0, 0.0, 0.0),                 # w, x, y, z
        joint_pos={".*": 0.0},
    ),
    actuators={
        "all_joints": ImplicitActuatorCfg(
            joint_names_expr=[".*"],
            stiffness=100.0,
            damping=10.0,
            effort_limit=200.0,
            velocity_limit=10.0,
        ),
    },
)
```

## Articulation from a URDF (convert at runtime)

```python
spawn=sim_utils.UrdfFileCfg(
    asset_path="/path/to/robot.urdf",
    rigid_props=sim_utils.RigidBodyPropertiesCfg(),
    articulation_props=sim_utils.ArticulationRootPropertiesCfg(),
    # URDF-specific:
    fix_base=False,
    merge_fixed_joints=True,
    convert_mimic_joints_to_normal_joints=False,
)
```

## Camera sensor

For training with cameras, remember to launch with `--enable_cameras` when `--headless` is set.

```python
from isaaclab.sensors import CameraCfg

camera_cfg = CameraCfg(
    prim_path="/World/envs/env_.*/Robot/head/Camera",
    update_period=0.1,                            # 10 Hz; 0 = every step
    height=120,
    width=160,
    data_types=["rgb", "distance_to_image_plane"],
    spawn=sim_utils.PinholeCameraCfg(
        focal_length=24.0,
        focus_distance=400.0,
        horizontal_aperture=20.955,
        clipping_range=(0.1, 20.0),
    ),
    offset=CameraCfg.OffsetCfg(pos=(0.1, 0.0, 0.05), rot=(0.5, -0.5, 0.5, -0.5), convention="ros"),
)
```

## Contact sensor (for foot contact, collision detection)

```python
from isaaclab.sensors import ContactSensorCfg

contact_cfg = ContactSensorCfg(
    prim_path="/World/envs/env_.*/Robot/.*FOOT",
    history_length=3,
    track_air_time=True,
    update_period=0.0,                            # every step
)
```

## RayCaster sensor (height scanner / lidar-like)

```python
from isaaclab.sensors import RayCasterCfg, patterns

height_scanner_cfg = RayCasterCfg(
    prim_path="/World/envs/env_.*/Robot/base",
    update_period=0.02,
    offset=RayCasterCfg.OffsetCfg(pos=(0.0, 0.0, 20.0)),
    attach_yaw_only=True,
    pattern_cfg=patterns.GridPatternCfg(resolution=0.1, size=(1.6, 1.0)),
    debug_vis=False,
    mesh_prim_paths=["/World/ground"],
)
```

## Terrain

```python
from isaaclab.terrains import TerrainImporterCfg, TerrainGeneratorCfg, HfRandomUniformTerrainCfg

# Flat ground
flat = TerrainImporterCfg(
    prim_path="/World/ground",
    terrain_type="plane",
    collision_group=-1,
    physics_material=sim_utils.RigidBodyMaterialCfg(
        friction_combine_mode="multiply",
        restitution_combine_mode="multiply",
        static_friction=1.0,
        dynamic_friction=1.0,
    ),
)

# Procedural rough terrain
rough = TerrainImporterCfg(
    prim_path="/World/ground",
    terrain_type="generator",
    terrain_generator=TerrainGeneratorCfg(
        size=(8.0, 8.0),
        border_width=2.0,
        num_rows=10, num_cols=10,
        sub_terrains={
            "random_rough": HfRandomUniformTerrainCfg(
                proportion=1.0, noise_range=(0.02, 0.10), noise_step=0.02,
                border_width=0.25,
            ),
        },
    ),
)
```

## Scene (DirectRLEnv style)

```python
from isaaclab.scene import InteractiveSceneCfg

scene_cfg = InteractiveSceneCfg(
    num_envs=4096,
    env_spacing=4.0,
    replicate_physics=True,            # True is faster but blocks per-env physics randomization
)
```

## Manager-based action terms (common ones)

```python
import isaaclab.envs.mdp as mdp

# Effort/torque on selected joints
joint_effort = mdp.JointEffortActionCfg(
    asset_name="robot", joint_names=[".*"], scale=1.0
)

# Position target
joint_position = mdp.JointPositionActionCfg(
    asset_name="robot", joint_names=[".*"], scale=0.5, use_default_offset=True
)

# Velocity target
joint_velocity = mdp.JointVelocityActionCfg(
    asset_name="robot", joint_names=[".*"], scale=1.0
)
```

## Manager-based observation terms (common ones)

```python
ObsTerm(func=mdp.base_lin_vel)                      # (3,)
ObsTerm(func=mdp.base_ang_vel)                      # (3,)
ObsTerm(func=mdp.projected_gravity)                 # (3,) — gravity vector in body frame
ObsTerm(func=mdp.joint_pos_rel)                     # joint pos relative to default
ObsTerm(func=mdp.joint_vel_rel)                     # joint vel relative to default
ObsTerm(func=mdp.last_action)                       # previous action
ObsTerm(func=mdp.generated_commands, params={"command_name": "base_velocity"})  # cmd input
```

## Manager-based reward terms (common building blocks)

```python
# Survival
alive = RewTerm(func=mdp.is_alive, weight=1.0)
terminating = RewTerm(func=mdp.is_terminated, weight=-2.0)

# Tracking a velocity command
track_lin_vel = RewTerm(
    func=mdp.track_lin_vel_xy_exp,
    weight=1.0,
    params={"command_name": "base_velocity", "std": 0.5},
)
track_ang_vel = RewTerm(
    func=mdp.track_ang_vel_z_exp,
    weight=0.5,
    params={"command_name": "base_velocity", "std": 0.5},
)

# Penalties
ang_vel_xy = RewTerm(func=mdp.ang_vel_xy_l2, weight=-0.05)
lin_vel_z = RewTerm(func=mdp.lin_vel_z_l2, weight=-2.0)
dof_torques = RewTerm(func=mdp.joint_torques_l2, weight=-2.5e-5)
action_rate = RewTerm(func=mdp.action_rate_l2, weight=-0.01)
```

## Common termination terms

```python
time_out = DoneTerm(func=mdp.time_out, time_out=True)
base_contact = DoneTerm(
    func=mdp.illegal_contact,
    params={"sensor_cfg": SceneEntityCfg("contact_forces", body_names="base"), "threshold": 1.0},
)
bad_orientation = DoneTerm(
    func=mdp.bad_orientation,
    params={"limit_angle": 0.7},                    # ~40 degrees
)
```
