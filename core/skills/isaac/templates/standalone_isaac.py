"""
Minimal Isaac Sim 5.1 standalone script template.

Run with Isaac's Python 3.11, never the system python:
    <venv>/bin/python standalone_isaac.py --headless        # pip install (e.g. ~/isaac/venv)
    $ISAACSIM_PATH/python.sh standalone_isaac.py --headless  # binary (zip) install
Prefix headless/SSH runs with OMNI_KIT_ACCEPT_EULA=YES (no interactive EULA prompt).
"""

import argparse

# --- 1. Parse CLI args BEFORE creating SimulationApp ---
parser = argparse.ArgumentParser(description="Isaac Sim 5.1 standalone template")
parser.add_argument("--headless", action="store_true", help="Run without GUI")
parser.add_argument("--num_steps", type=int, default=300)
args = parser.parse_args()

# --- 2. Boot the Kit runtime. NOTHING omniverse-related may be imported above this line. ---
from isaacsim import SimulationApp

simulation_app = SimulationApp({"headless": args.headless})

# --- 3. NOW it's safe to import the rest. ---
import numpy as np
from isaacsim.core.api import World
from isaacsim.core.api.objects import VisualCuboid, DynamicCuboid, GroundPlane
from isaacsim.core.utils.stage import add_reference_to_stage
from isaacsim.storage.native import get_assets_root_path
import omni.usd
from pxr import UsdLux, Sdf

# --- 4. Build the scene ---
world = World(stage_units_in_meters=1.0)
world.scene.add_default_ground_plane()

# A simple lit cube falling onto the ground
cube = world.scene.add(
    DynamicCuboid(
        prim_path="/World/falling_cube",
        name="falling_cube",
        position=np.array([0.0, 0.0, 1.0]),
        size=0.2,
        color=np.array([0.9, 0.2, 0.2]),
    )
)

# Add a light
stage = omni.usd.get_context().get_stage()
distant = UsdLux.DistantLight.Define(stage, Sdf.Path("/World/DistantLight"))
distant.CreateIntensityAttr(3000.0)

# --- 5. Initialize & step ---
world.reset()  # required before stepping when assets were added programmatically

for i in range(args.num_steps):
    world.step(render=not args.headless)
    if i % 60 == 0:
        pos, _ = cube.get_world_pose()
        print(f"step={i}  cube_z={pos[2]:.3f}")

# --- 6. Shutdown ---
# simulation_app.close() hangs on Blackwell (RTX 50xx) Kit teardown (see cooper/scripts/setup_sim.sh),
# so flush (and close any files you wrote) and hard-exit once the work is done.
# On other GPUs the clean form is:
#   simulation_app.close()
import os
import sys

sys.stdout.flush()
os._exit(0)
