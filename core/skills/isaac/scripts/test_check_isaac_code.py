#!/usr/bin/env python3
"""Regression tests for check_isaac_code.py. Stdlib only; fixtures live in a temp dir, no bytecode is written.

    python3 test_check_isaac_code.py        (exit 0 when every test passes)
"""
import contextlib
import io
import os
import sys
import tempfile
import time
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_isaac_code as chk  # noqa: E402


class CheckerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        chk._CACHE.clear()
        chk._CLEAN.clear()
        chk._CHAINS.clear()

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text, raw=None):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as fh:
            fh.write(raw if raw is not None else text.encode())
        return path

    def run_checker(self, *rels):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            code = chk.main([os.path.join(self.root, r) for r in rels] or [self.root])
        return code, out.getvalue()

    def rules(self, text):
        return sorted(line.split(": ", 1)[1].split()[0] for line in text.splitlines())

    def test_diamond_import_graph_is_linear(self):
        n = 40  # each module imports the next two: exponential without memoisation
        self.write("tp/__init__.py", 'import gymnasium as gym\nfrom . import m0\ngym.register(id="Isaac-X-v0", '
                   'entry_point="a:b")\n')
        for i in range(n):
            self.write("tp/m%d.py" % i, "from . import m%d, m%d\n" % (i + 1, i + 2))
        self.write("tp/m%d.py" % n, "import os\n")
        self.write("tp/m%d.py" % (n + 1), "import isaaclab.sim\n")
        start = time.time()
        code, out = self.run_checker()
        self.assertLess(time.time() - start, 5.0)
        self.assertEqual(code, 1)
        self.assertEqual(self.rules(out), ["ISC021"])

    def test_env_dir_is_scanned_but_venv_is_not(self):
        self.write("mytask/__init__.py", "")
        self.write("mytask/env/my_env.py", "from omni.isaac.core import World\n")
        self.write("venv/pyvenv.cfg", "home = /usr/bin\n")
        self.write("venv/lib/bad.py", "from omni.isaac.core import World\n")
        code, out = self.run_checker()
        self.assertEqual(self.rules(out), ["ISC001"])
        self.assertIn("my_env.py", out)

    def test_parent_init_eager_import(self):
        self.write("proj/__init__.py", "")
        self.write("proj/tasks/__init__.py", "from .mytask.env import MyEnv\n")
        self.write("proj/tasks/mytask/__init__.py", 'import gymnasium as gym\ngym.register(id="Isaac-X-v0", '
                   'entry_point=f"{__name__}.env:MyEnv")\n')
        self.write("proj/tasks/mytask/env.py", "from isaaclab.envs import DirectRLEnv\n")
        code, out = self.run_checker("proj/tasks/mytask")
        self.assertEqual(self.rules(out), ["ISC021"])
        self.assertIn("parent package", out)

    def test_entry_points(self):
        self.write("pkg/__init__.py", (
            "import os\nimport gymnasium as gym\nfrom .env import MyEnv\n"
            "def _reg(tid, cfg_path):\n"
            "    gym.register(id=tid, entry_point='isaaclab.envs:ManagerBasedRLEnv', "
            "kwargs={'env_cfg_entry_point': cfg_path})\n"
            "gym.register(id='A', entry_point=MyEnv)\n"
            "gym.register('B', MyEnv)\n"
            "gym.register(id='C', entry_point='x:y', kwargs={'env_cfg_entry_point': os.path.join('a', 'b'), "
            "'rsl_rl_cfg_entry_point': dict})\n"))
        self.write("pkg/env.py", "class MyEnv: pass\n")
        code, out = self.run_checker("pkg")
        self.assertEqual(self.rules(out), ["ISC020", "ISC020", "ISC020"])

    def test_decoding_matches_py_compile(self):
        self.write("bom.py", "", raw=b"\xef\xbb\xbfimport os\n")
        self.write("latin1_nocookie.py", "", raw=b'x = "caf\xe9"\n')
        self.write("latin1_cookie.py", "", raw=b'# -*- coding: latin-1 -*-\nx = "caf\xe9"\n')
        code, out = self.run_checker()
        self.assertEqual(self.rules(out), ["ISC000"])
        self.assertIn("latin1_nocookie.py", out)

    def test_import_order_and_templates(self):
        self.write("s.py", "import isaaclab.sim\nfrom isaaclab.app import AppLauncher\napp = AppLauncher().app\n")
        code, out = self.run_checker()
        self.assertEqual(self.rules(out), ["ISC010"])
        templates = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "templates")
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(chk.main([templates]), 0)


if __name__ == "__main__":
    unittest.main()
