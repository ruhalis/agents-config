#!/usr/bin/env python3
"""Static checks for Isaac Sim 5.1 / Isaac Lab 2.3 Python code. Read-only, stdlib only (ast + re); runs on
the Mac, imports nothing from Isaac and writes no bytecode.

    check_isaac_code.py PATH [PATH ...] [--exclude NAME ...]

PATH is a .py file or a directory, searched recursively for *.py. Below a directory it skips virtual envs
(any directory holding pyvenv.cfg or conda-meta), .git __pycache__ node_modules site-packages .tox .nox
.mypy_cache .pytest_cache .eggs *.egg-info, and third_party / _isaac_sim (the pinned Lab checkout and its
Isaac Sim link are never ours to fix). build/ and dist/ are scanned: a setuptools copy only repeats
findings, while skipping by name could hide a real package; add --exclude NAME to skip more. Each file is
compiled from its bytes exactly as py_compile does (encoding cookie, BOM), in memory, so no __pycache__.

One line per finding, `path:line: RULE message`:
  ISC000  syntax or compile error (Isaac code is Python 3.11: run this with python3 >= 3.11)
  ISC001  import of omni.isaac.* (renamed isaacsim.* in Sim 4.5; shims removed in 6.0)
  ISC002  import of omni.isaac.lab* (renamed isaaclab* in Lab 2.0; no shim)
  ISC010  omni / isaacsim / isaaclab* / pxr / carb import that runs before AppLauncher(...) or
          SimulationApp(...). Checked only in files that construct one of them, so env and cfg modules
          (imported after launch) are exempt. `from isaacsim import SimulationApp` and
          `from isaaclab.app import AppLauncher` may precede it.
  ISC020  gym.register(...) entry point (entry_point, or a *_entry_point key in kwargs) that is clearly
          not a string (a class, function, instance or container), so the env or cfg module is imported
          with the task package. Computed values (a helper's parameter, os.path.join) are not flagged.
  ISC021  a module that calls gym.register, or any parent package __init__.py of it, imports Kit at import
          time, directly or through relative / same-package imports, so the task package cannot be imported
          before AppLauncher (the wrapper pattern); keep them gymnasium-only with lazy string entry points
  ISC030  attach_yaw_only (deprecated since Lab 2.1.1): use ray_alignment="yaw"
  ISC031  effort_limit= / velocity_limit= on ImplicitActuatorCfg: use effort_limit_sim= /
          velocity_limit_sim= (velocity_limit is ignored there)
  ISC040  UrdfFileCfg(...) / UrdfConverterCfg(...) without joint_drive= (the default JointDriveCfg leaves
          gains.stiffness MISSING) or without fix_base= (MISSING); cfg validation fails. Skipped when the
          call has **kwargs or the file assigns .joint_drive / .fix_base.

Only literal usage is matched: aliases (IA = ImplicitActuatorCfg), values passed through **kwargs, .replace(),
attribute assignment after construction (except the cases noted above) and importlib / __import__ are not seen.
Append `# isaac-check: ignore` to a line to silence the findings reported on it.
Exit 0: no findings. 1: at least one finding. 2: usage error (bad option, missing path, no .py files).
"""
import argparse
import ast
import builtins
import io
import os
import re
import sys
import tokenize
from collections import deque

SKIP_DIRS = {
    ".git", "__pycache__", "node_modules", "site-packages", ".tox", ".nox", ".mypy_cache", ".pytest_cache",
    ".eggs", "third_party", "_isaac_sim",
}
LAUNCHERS = {"AppLauncher", "SimulationApp"}
KIT_ROOTS = {"omni", "isaacsim", "pxr", "carb"}
NON_STR_BUILTINS = {"dict", "list", "set", "tuple", "int", "float", "bool", "object", "type", "frozenset", "bytes",
                    "bytearray", "complex", "range", "slice", "property", "staticmethod", "classmethod"}
BUILTIN_NAMES = {n for n in dir(builtins) if not n.startswith("_")} - {"str", "format", "repr", "ascii", "chr"}
IGNORE_RE = re.compile(r"#\s*isaac-check:\s*ignore\b")
# fallback for files that do not parse
OLD_IMPORT_RE = re.compile(r"^\s*(?:from|import)\s+(omni\.isaac\b[\w.]*)", re.M)


# ------------------------------------------------------------------ helpers
def is_kit(module):
    root = module.split(".")[0]
    return root in KIT_ROOTS or root.startswith("isaaclab")


def pre_launch_ok(node):
    """Imports allowed above the launcher: the launcher classes themselves (no Kit needed)."""
    if isinstance(node, ast.Import):
        return all(a.name in ("isaacsim", "isaacsim.simulation_app", "isaaclab", "isaaclab.app") for a in node.names)
    mod = node.module or ""
    names = {a.name for a in node.names}
    if mod in ("isaacsim.simulation_app", "isaaclab.app"):
        return True
    if mod == "isaacsim":
        return names <= {"SimulationApp", "AppFramework"}
    if mod == "isaaclab":
        return names <= {"app"}
    return False


def kit_modules(node):
    """Absolute Kit modules an Import/ImportFrom node brings in (empty for relative imports)."""
    if isinstance(node, ast.Import):
        return [a.name for a in node.names if is_kit(a.name)]
    if node.level == 0 and node.module and is_kit(node.module):
        return [node.module]
    return []


def final_name(func):
    if isinstance(func, ast.Name):
        return func.id
    if isinstance(func, ast.Attribute):
        return func.attr
    return None


def is_capwords(name):
    return bool(name) and name[:1].isupper() and not name.isupper()


def import_text(node):
    if isinstance(node, ast.Import):
        return "import " + ", ".join(a.name for a in node.names)
    names = ", ".join(a.name for a in node.names)
    return "from {}{} import {}".format("." * node.level, node.module or "", names)


def is_type_checking(test):
    return (isinstance(test, ast.Name) and test.id == "TYPE_CHECKING") or (
        isinstance(test, ast.Attribute) and test.attr == "TYPE_CHECKING"
    )


def is_main_guard(test):
    if not (isinstance(test, ast.Compare) and len(test.ops) == 1 and isinstance(test.ops[0], ast.Eq)):
        return False
    sides = [test.left] + list(test.comparators)
    has_name = any(isinstance(s, ast.Name) and s.id == "__name__" for s in sides)
    has_main = any(isinstance(s, ast.Constant) and s.value == "__main__" for s in sides)
    return has_name and has_main


def decode(data):
    """Source bytes to text the way the interpreter decodes them (cookie, BOM), for comments and regexes."""
    try:
        encoding, _ = tokenize.detect_encoding(io.BytesIO(data).readline)
    except SyntaxError:
        encoding = "utf-8"
    return data.decode(encoding, errors="replace")


class Parsed:
    """A parsed file plus the context of every node: enclosing function, TYPE_CHECKING, main guard."""

    def __init__(self, path, text, tree):
        self.path = path
        self.lines = text.splitlines()
        self.tree = tree
        self.parent = {}
        for node in ast.walk(tree):
            for child in ast.iter_child_nodes(node):
                self.parent[child] = node
        self._import_time = None

    def _chain(self, node):
        while node in self.parent:
            parent = self.parent[node]
            yield node, parent
            node = parent

    def scope(self, node):
        for _, anc in self._chain(node):
            if isinstance(anc, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)):
                return anc
        return None

    def under_if(self, node, pred):
        for child, anc in self._chain(node):
            if isinstance(anc, ast.If) and pred(anc.test) and any(child is s for s in anc.body):
                return True
        return False

    def imports(self):
        return [n for n in ast.walk(self.tree) if isinstance(n, (ast.Import, ast.ImportFrom))]

    def import_time_imports(self):
        """Imports that run when the module is imported (not in functions, TYPE_CHECKING or a main guard)."""
        if self._import_time is None:
            self._import_time = sorted(
                (n for n in self.imports() if self.scope(n) is None and not self.under_if(n, is_type_checking)
                 and not self.under_if(n, is_main_guard)),
                key=lambda n: n.lineno,
            )
        return self._import_time

    def calls(self):
        return [n for n in ast.walk(self.tree) if isinstance(n, ast.Call)]


_CACHE = {}


def load(path):
    """Compile from bytes like py_compile, in memory. Returns (Parsed or None, (line, message) or None)."""
    path = os.path.abspath(path)
    if path in _CACHE:
        return _CACHE[path]
    try:
        with open(path, "rb") as fh:
            data = fh.read()
        compile(data, path, "exec", dont_inherit=True)  # py_compile's check: decoding, syntax, symtable
        tree = ast.parse(data, filename=path)
        result = (Parsed(path, decode(data), tree), None)
    except SyntaxError as exc:
        msg = exc.msg
        if sys.version_info < (3, 11):
            msg += "; parsed with Python {}.{}, Isaac code is 3.11: use python3 >= 3.11".format(*sys.version_info[:2])
        result = (None, (exc.lineno or 1, msg))
    except (OSError, ValueError) as exc:
        result = (None, (1, str(exc)))
    _CACHE[path] = result
    return result


# --------------------------------------------------- resolving project-local imports
def resolve_parts(base, parts, names):
    """Files executed by importing `parts` (then `names` from it) below directory `base`."""
    files, cur = [], base
    for i, part in enumerate(parts):
        pkg = os.path.join(cur, part)
        if os.path.isfile(os.path.join(pkg, "__init__.py")):
            files.append(os.path.join(pkg, "__init__.py"))
            cur = pkg
        elif i == len(parts) - 1 and os.path.isfile(pkg + ".py"):
            files.append(pkg + ".py")
            return files
        else:
            return files
    for name in names:
        sub = os.path.join(cur, name)
        if os.path.isfile(os.path.join(sub, "__init__.py")):
            files.append(os.path.join(sub, "__init__.py"))
        elif os.path.isfile(sub + ".py"):
            files.append(sub + ".py")
    return files


def package_root(path):
    """(name, parent dir) of the top package holding `path`, or (None, None)."""
    top = None
    d = os.path.dirname(os.path.abspath(path))
    while os.path.isfile(os.path.join(d, "__init__.py")):
        top = d
        d = os.path.dirname(d)
    return (os.path.basename(top), os.path.dirname(top)) if top else (None, None)


def parent_inits(path):
    """__init__.py of every package above the module at `path`, nearest first, up to the top package."""
    path = os.path.abspath(path)
    d = os.path.dirname(path)
    if os.path.basename(path) == "__init__.py":
        d = os.path.dirname(d)
    out = []
    while os.path.isfile(os.path.join(d, "__init__.py")):
        out.append(os.path.join(d, "__init__.py"))
        d = os.path.dirname(d)
    return out


def local_targets(path, node):
    """Project files an import node executes: relative imports and same-package absolute imports."""
    if isinstance(node, ast.ImportFrom) and node.level > 0:
        base = os.path.dirname(os.path.abspath(path))
        for _ in range(node.level - 1):
            base = os.path.dirname(base)
        parts = node.module.split(".") if node.module else []
        return resolve_parts(base, parts, [a.name for a in node.names if a.name != "*"])
    top, root = package_root(path)
    if not top:
        return []
    if isinstance(node, ast.Import):
        files = []
        for a in node.names:
            parts = a.name.split(".")
            if parts[0] == top:
                files += resolve_parts(root, parts, [])
        return files
    parts = (node.module or "").split(".")
    if parts[0] == top:
        return resolve_parts(root, parts, [a.name for a in node.names if a.name != "*"])
    return []


_CLEAN = set()   # modules whose whole import-time closure is proven Kit-free
_CHAINS = {}     # module -> first Kit chain found from it


def kit_chain(path):
    """Shortest chain of import-time imports from `path` that reaches Kit, as [(file, line, text)], else None.
    Breadth-first over the project-local import graph, each module visited once, so linear in its size."""
    path = os.path.abspath(path)
    if path in _CLEAN:
        return None
    if path in _CHAINS:
        return _CHAINS[path]
    came_from = {path: None}  # module -> (importer, line, import text)
    queue = deque([path])
    while queue:
        cur = queue.popleft()
        parsed, _ = load(cur)
        if parsed is None:
            continue
        for node in parsed.import_time_imports():
            if kit_modules(node) and not pre_launch_ok(node):
                chain = [(cur, node.lineno, import_text(node))]
                while came_from[cur] is not None:
                    cur, line, text = came_from[cur]
                    chain.insert(0, (cur, line, text))
                _CHAINS[path] = chain
                return chain
            for target in local_targets(cur, node):
                target = os.path.abspath(target)
                if target not in came_from and target not in _CLEAN:
                    came_from[target] = (cur, node.lineno, import_text(node))
                    queue.append(target)
    _CLEAN.update(came_from)  # the search exhausted every module it reached
    return None


def chain_finding(chain, what):
    here = os.path.dirname(chain[0][0])
    hops = " -> ".join("{}:{} `{}`".format(os.path.relpath(f, here), line, text) for f, line, text in chain[1:])
    return (chain[0][1], "ISC021", "{} imports Kit at import time: `{}`{}; keep it gymnasium-only (lazy string "
            "entry points)".format(what, chain[0][2], " -> " + hops if hops else ""))


# ------------------------------------------------------------------ rules
def gym_register_calls(p):
    gym_names, register_names = {"gym", "gymnasium"}, set()
    for node in p.imports():
        if isinstance(node, ast.Import):
            for a in node.names:
                if a.name in ("gym", "gymnasium"):
                    gym_names.add(a.asname or a.name)
        elif node.module in ("gymnasium", "gym", "gymnasium.envs.registration", "gym.envs.registration"):
            for a in node.names:
                if a.name == "register":
                    register_names.add(a.asname or a.name)
    out = []
    for call in p.calls():
        f = call.func
        on_gym = isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) and f.value.id in gym_names
        if (on_gym and f.attr == "register") or (isinstance(f, ast.Name) and f.id in register_names):
            out.append(call)
    return out


class ModuleNames:
    """What module-level names are bound to: strings, objects (imports, def, class), or other assignments."""

    def __init__(self, tree):
        self.strings, self.objects, self.assigned = set(), set(), {}
        for node in tree.body:
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                for a in node.names:
                    self.objects.add(a.asname or a.name.split(".")[0])
            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                self.objects.add(node.name)
            elif isinstance(node, ast.Assign):
                for t in node.targets:
                    if isinstance(t, ast.Name):
                        self.assigned[t.id] = node.value
        for name, value in self.assigned.items():
            if is_stringish(value, set()):
                self.strings.add(name)


def is_stringish(node, str_names):
    if isinstance(node, ast.Constant):
        return isinstance(node.value, str)
    if isinstance(node, ast.JoinedStr):
        return True
    if isinstance(node, ast.Name):
        return node.id in str_names
    if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Mod)):
        return is_stringish(node.left, str_names) or is_stringish(node.right, str_names)
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "format":
        return is_stringish(node.func.value, str_names)
    return False


def clearly_not_string(node, names, depth=0):
    """True only for values that cannot be an "module:attr" string. Unknown computed values are False."""
    if depth > 5 or is_stringish(node, names.strings):
        return False
    if isinstance(node, ast.Constant):
        return True  # a non-str constant (None, a number)
    if isinstance(node, (ast.Dict, ast.List, ast.Tuple, ast.Set, ast.Lambda, ast.ListComp, ast.DictComp,
                         ast.SetComp, ast.GeneratorExp)):
        return True
    if isinstance(node, ast.Name):
        if node.id in names.objects:
            return True
        if node.id in names.assigned:
            return clearly_not_string(names.assigned[node.id], names, depth + 1)
        return node.id in BUILTIN_NAMES
    if isinstance(node, ast.Attribute):
        return is_capwords(node.attr)  # module.MyEnvCfg
    if isinstance(node, ast.Call):
        callee = final_name(node.func)
        return is_capwords(callee) or (isinstance(node.func, ast.Name) and callee in NON_STR_BUILTINS)
    return False


def entry_point_values(call, names):
    """(name, value node) for entry_point (keyword or 2nd positional), *_entry_point keywords and kwargs keys."""
    out = []
    if len(call.args) > 1:
        out.append(("entry_point", call.args[1]))
    for kw in call.keywords:
        if kw.arg and kw.arg.endswith("entry_point"):
            out.append((kw.arg, kw.value))
        if kw.arg != "kwargs":
            continue
        value = kw.value
        if isinstance(value, ast.Name) and isinstance(names.assigned.get(value.id), (ast.Dict, ast.Call)):
            value = names.assigned[value.id]
        if isinstance(value, ast.Dict):
            for key, val in zip(value.keys, value.values):
                if isinstance(key, ast.Constant) and str(key.value).endswith("entry_point"):
                    out.append((key.value, val))
        elif isinstance(value, ast.Call) and final_name(value.func) == "dict":
            out += [(k.arg, k.value) for k in value.keywords if k.arg and k.arg.endswith("entry_point")]
    return out


def check_file(path):
    """Findings as {abs path: [(line, rule, message)]}: the file itself, plus parent __init__.py files (ISC021)."""
    apath = os.path.abspath(path)
    findings = []
    out = {apath: findings}
    parsed, err = load(path)
    if parsed is None:
        line, msg = err
        findings.append((line, "ISC000", msg))
        try:
            with open(path, "rb") as fh:
                text = decode(fh.read())
        except OSError:
            text = ""
        for m in OLD_IMPORT_RE.finditer(text):
            lineno = text.count("\n", 0, m.start()) + 1
            rule = "ISC002" if m.group(1).startswith("omni.isaac.lab") else "ISC001"
            findings.append((lineno, rule, "{} (found by regex; the file does not parse)".format(m.group(1))))
        return out
    p = parsed

    # ISC001 / ISC002: pre-rename namespaces
    for node in p.imports():
        if isinstance(node, ast.Import):
            mods = [a.name for a in node.names]
        elif node.level == 0 and node.module in ("omni", "omni.isaac"):
            mods = ["{}.{}".format(node.module, a.name) for a in node.names]  # from omni.isaac import lab
        elif node.level == 0 and node.module:
            mods = [node.module]
        else:
            mods = []
        for mod in mods:
            if mod == "omni.isaac.lab" or mod.startswith(("omni.isaac.lab.", "omni.isaac.lab_")):
                new = "isaaclab" + mod[len("omni.isaac.lab"):]
                findings.append((node.lineno, "ISC002", "{}: Lab 2.x name is {} (no shim)".format(mod, new)))
            elif mod == "omni.isaac" or mod.startswith("omni.isaac."):
                findings.append((node.lineno, "ISC001",
                                 "{}: pre-4.5 name, use isaacsim.* (reference/import-migration.md)".format(mod)))

    # ISC010: Kit imports above the launcher
    launches = [c for c in p.calls() if final_name(c.func) in LAUNCHERS]
    if launches:
        module_level = [c for c in launches if p.scope(c) is None]
        first = min(module_level or launches, key=lambda c: c.lineno)
        first_scope = p.scope(first)
        what = final_name(first.func)
        for node in p.imports():
            if not kit_modules(node) or pre_launch_ok(node) or p.under_if(node, is_type_checking):
                continue
            scope = p.scope(node)
            if first_scope is None:
                early = scope is None and node.lineno < first.lineno
            else:
                early = (scope is None and not p.under_if(node, is_main_guard)) or (
                    scope is first_scope and node.lineno < first.lineno
                )
            if early:
                findings.append((node.lineno, "ISC010", "`{}` runs before {}(...) at line {}: move it below the launcher"
                                 .format(import_text(node), what, first.lineno)))

    # ISC020 / ISC021: registration and the packages above it must stay lazy
    registers = gym_register_calls(p)
    if registers:
        names = ModuleNames(p.tree)
        for call in registers:
            for name, value in entry_point_values(call, names):
                if clearly_not_string(value, names):
                    findings.append((value.lineno, "ISC020", '{} is not a string: use "<module>:<Class>" '
                                     '(f"{{__name__}}.my_env:MyEnv") or "<pkg>:<file>.yaml"'.format(name)))
        chain = kit_chain(path)
        if chain:
            findings.append(chain_finding(chain, "registration module"))
        for init in parent_inits(path):
            chain = kit_chain(init)
            if chain:
                out.setdefault(init, []).append(chain_finding(chain, "parent package of a task registration"))

    # ISC030 / ISC031 / ISC040: cfg fields
    assigned = set()  # attribute names assigned anywhere (cfg.joint_drive = ...)
    for n in ast.walk(p.tree):
        if isinstance(n, (ast.Assign, ast.AugAssign, ast.AnnAssign)):
            for t in n.targets if isinstance(n, ast.Assign) else [n.target]:
                if isinstance(t, ast.Attribute):
                    assigned.add(t.attr)
                    if t.attr == "attach_yaw_only":
                        findings.append((n.lineno, "ISC030", 'attach_yaw_only is deprecated: use ray_alignment="yaw"'))
    for call in p.calls():
        name = final_name(call.func)
        kws = {kw.arg for kw in call.keywords}
        for kw in call.keywords:
            if kw.arg == "attach_yaw_only":
                findings.append((kw.value.lineno, "ISC030", 'attach_yaw_only is deprecated: use ray_alignment="yaw"'))
        if name == "ImplicitActuatorCfg":
            for kw in call.keywords:
                if kw.arg in ("effort_limit", "velocity_limit"):
                    note = " (velocity_limit is ignored by implicit actuators)" if kw.arg == "velocity_limit" else ""
                    findings.append((kw.value.lineno, "ISC031",
                                     "{}= on ImplicitActuatorCfg: use {}_sim={}".format(kw.arg, kw.arg, note)))
        if name in ("UrdfFileCfg", "UrdfConverterCfg") and None not in kws:
            for field, why in (("joint_drive", "the default JointDriveCfg leaves gains.stiffness MISSING"),
                               ("fix_base", "fix_base is MISSING")):
                if field not in kws and field not in assigned:
                    findings.append((call.lineno, "ISC040",
                                     "{}(...) without {}=: {}, so cfg validation fails".format(name, field, why)))
    return out


def not_ignored(apath, finding):
    parsed, _ = load(apath)
    lines = parsed.lines if parsed else []
    line = finding[0]
    return not (0 < line <= len(lines) and IGNORE_RE.search(lines[line - 1]))


def is_venv(d):
    return os.path.isfile(os.path.join(d, "pyvenv.cfg")) or os.path.isdir(os.path.join(d, "conda-meta"))


def iter_files(paths, excludes):
    for path in paths:
        if os.path.isfile(path):
            yield path
            continue
        for root, dirs, files in os.walk(path):
            dirs[:] = sorted(d for d in dirs if d not in excludes and not d.endswith(".egg-info")
                             and not is_venv(os.path.join(root, d)))
            for f in sorted(files):
                if f.endswith(".py"):
                    yield os.path.join(root, f)


def display(apath, given):
    if apath in given:
        return given[apath]
    rel = os.path.relpath(apath)
    return apath if rel.startswith("..") else rel


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="check_isaac_code.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("paths", nargs="+", metavar="PATH", help=".py file or directory (searched recursively)")
    ap.add_argument("--exclude", action="append", default=[], metavar="NAME",
                    help="directory name to skip below a PATH (repeatable; adds to the defaults)")
    args = ap.parse_args(argv)

    missing = [p for p in args.paths if not os.path.exists(p)]
    if missing:
        ap.error("no such file or directory: " + ", ".join(missing))
    files = list(dict.fromkeys(iter_files(args.paths, SKIP_DIRS | set(args.exclude))))
    if not files:
        ap.error("no .py files under: " + ", ".join(args.paths))

    given = {os.path.abspath(f): f for f in files}
    results = {}
    for path in files:
        for apath, found in check_file(path).items():
            results.setdefault(apath, set()).update(f for f in found if not_ignored(apath, f))
    total = 0
    order = list(given) + sorted(a for a in results if a not in given)
    for apath in order:
        for line, rule, msg in sorted(results.get(apath, ())):
            print("{}:{}: {} {}".format(display(apath, given), line, rule, msg))
            total += 1
    sys.stdout.flush()
    print("check_isaac_code: {} finding(s) in {} file(s)".format(total, len(files)), file=sys.stderr)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
