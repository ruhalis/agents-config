#!/usr/bin/env python3
"""Pre-fill an rl-experiment-log entry from an Isaac Lab run dir. Read-only.

    rl_log_entry.py <run_dir> [--base <run_dir>] [--host NAME] [--ignore KEY ...]

Reads <run_dir>/params/env.yaml and params/agent.yaml, the config dump that Isaac Lab's
scripts/reinforcement_learning/{rsl_rl,skrl}/train.py write at launch, and prints the entry's
Run dir (with W&B when the run logs there), Env, Obs/Act, Algo, Reward terms, Curriculum, DR and
Seed(s) lines. With --base it also prints Changed: every leaf that differs between the two runs'
params/*.yaml, as `<file>.<dotted path>: old → new`, e.g. env.rewards.grasp_object.weight: 2.0 → 1.0.
Keys that differ on every run or only pick the logging backend are always left out: log_dir,
run_name, logger, wandb_project, neptune_project, and skrl's experiment.directory,
experiment.experiment_name, experiment.write_interval, experiment.wandb, experiment.wandb_kwargs.

Code, Stack, Inputs, Command and Expected are not in the dump; fill them by hand.

Needs PyYAML, which the Isaac Lab venv ships and a stock macOS python3 lacks. The dumps carry
!!python/tuple and !!python/object/apply:builtins.slice tags, which yaml.safe_load and
yaml.full_load both reject; this loads them with a SafeLoader that builds tuples and slices and
turns any other python/* tag into a placeholder string, never running code.

Validated on synthetic run dirs written by Isaac Lab 2.3.2's own dump code, not on a real
training run yet: check the first real output against the yaml files.

Exit 0: printed. 1: a run dir or params/*.yaml is missing, unreadable, not UTF-8, not YAML, not a
mapping, recursive, nested deeper than 300 levels or bigger than 1,000,000 values once aliases are
expanded. 2: usage error (argparse). 3: PyYAML is not installed for this python.
"""

from __future__ import annotations

import argparse
import math
import os
import socket
import sys

ALWAYS_IGNORED = (
    "log_dir", "run_name", "logger", "wandb_project", "neptune_project",  # rsl_rl (+ env/sim log_dir)
    "experiment.directory", "experiment.experiment_name", "experiment.write_interval",  # skrl
    "experiment.wandb", "experiment.wandb_kwargs",
)
SCENE_ENTITY_KEYS = {"name", "joint_names", "joint_ids", "body_names", "body_ids"}
MAX_DEPTH = 300
MAX_VALUES = 1_000_000
FMT_LIMIT = 400  # characters per value
LINE_LIMIT = 3000  # characters of terms per Reward/Curriculum/DR line


def parse_args(argv=None):
    ap = argparse.ArgumentParser(
        prog="rl_log_entry.py",
        description="Pre-fill an rl-experiment-log entry from an Isaac Lab run dir's params/*.yaml.",
        epilog="Run it with a python that has PyYAML, e.g. the Isaac Lab venv's python on the training host: "
        "ssh HOST '<venv>/bin/python - RUN_DIR [--base BASE_DIR]' < rl_log_entry.py. "
        "Exit 1: bad or missing params/*.yaml; 2: usage error; 3: no PyYAML.",
    )
    ap.add_argument("run_dir", help="the run's log dir, e.g. logs/rsl_rl/<experiment>/<timestamp>_<run-id>")
    ap.add_argument("--base", metavar="RUN_DIR", help="the Base run's log dir; prints Changed as the params diff")
    ap.add_argument("--host", help="host for the Run dir line (default: this machine; set it for a copied run dir)")
    ap.add_argument(
        "--ignore", action="append", default=[], metavar="KEY",
        help="also leave KEY and everything under it out of Changed, matched as whole dotted-path segments "
        "(e.g. --ignore seed when the seed is the declared change); repeatable",
    )
    return ap.parse_args(argv)


def fail(msg):
    sys.stderr.write(f"rl_log_entry.py: {msg}\n")
    sys.exit(1)


def import_yaml():
    try:
        import yaml
    except ImportError:
        sys.stderr.write(
            f"rl_log_entry.py: PyYAML is not installed for {sys.executable}.\n"
            "Run it with the Isaac Lab venv's python, which ships PyYAML (e.g. ~/isaac/venv/bin/python, "
            "or ./isaaclab.sh -p), on the training host or on a copied params/ dir.\n"
        )
        sys.exit(3)
    return yaml


def make_loader(yaml):
    class IsaacDumpLoader(yaml.SafeLoader):
        pass

    def python_tuple(loader, node):
        return tuple(loader.construct_sequence(node, deep=True))

    def python_apply(loader, suffix, node):
        if isinstance(node, yaml.SequenceNode):
            args = loader.construct_sequence(node, deep=True)
        elif isinstance(node, yaml.MappingNode):
            args = loader.construct_mapping(node, deep=True).get("args", [])
        else:
            args = [loader.construct_scalar(node)]
        if suffix == "builtins.slice" and len(args) <= 3 and all(a is None or isinstance(a, int) for a in args):
            return slice(*args)
        return f"<{suffix}{tuple(args)!r}>"

    def python_other(loader, suffix, node):
        return f"<python/{suffix}>"

    IsaacDumpLoader.add_constructor("tag:yaml.org,2002:python/tuple", python_tuple)
    IsaacDumpLoader.add_multi_constructor("tag:yaml.org,2002:python/object/apply:", python_apply)
    IsaacDumpLoader.add_multi_constructor("tag:yaml.org,2002:python/", python_other)
    return IsaacDumpLoader


def children(v):
    if isinstance(v, dict):
        return list(v.values())
    if isinstance(v, (list, tuple)):
        return list(v)
    return ()


def tree_problem(root):
    """Why a loaded document can't be walked safely (alias cycle, depth, alias blow-up), or None.
    Iterative, and each shared (aliased) container is visited once."""
    done = {}  # id -> (depth, expanded values)
    open_ids = set()
    stack = [(root, False)]
    while stack:
        node, finished = stack.pop()
        nid = id(node)
        if finished:
            open_ids.discard(nid)
            depth, size = 1, 1
            for c in children(node):
                d, s = done[id(c)] if isinstance(c, (dict, list, tuple)) else (0, 1)
                depth, size = max(depth, d + 1), size + s
            if depth > MAX_DEPTH:
                return f"nested deeper than {MAX_DEPTH} levels"
            if size > MAX_VALUES:
                return f"expands to more than {MAX_VALUES:,} values through YAML aliases"
            done[nid] = (depth, size)
            continue
        if nid in done:
            continue
        open_ids.add(nid)
        stack.append((node, True))
        for c in children(node):
            if isinstance(c, (dict, list, tuple)):
                if id(c) in open_ids:
                    return "a YAML alias refers to its own ancestor (recursive structure)"
                if id(c) not in done:
                    stack.append((c, False))
    return None


def load_params(yaml, loader, run_dir):
    run_dir = os.path.abspath(run_dir)
    if os.path.basename(run_dir) == "params" and os.path.isfile(os.path.join(run_dir, "env.yaml")):
        run_dir = os.path.dirname(run_dir)
    if not os.path.isdir(run_dir):
        fail(f"{run_dir} is not a directory")
    out = {}
    for name in ("env", "agent"):
        path = os.path.join(run_dir, "params", f"{name}.yaml")
        if not os.path.isfile(path):
            fail(
                f"{path} is missing. Isaac Lab's train.py writes params/ at launch (rsl_rl after the env and "
                "runner are built); a custom trainer's run dir needs its own config dump."
            )
        try:
            with open(path, encoding="utf-8") as f:
                data = yaml.load(f, Loader=loader)
        except yaml.YAMLError as e:
            mark = getattr(e, "problem_mark", None)
            where = f" (line {mark.line + 1})" if mark is not None else ""
            fail(f"cannot parse {path}{where}: {getattr(e, 'problem', None) or str(e).splitlines()[0]}")
        except UnicodeDecodeError as e:
            fail(f"{path} is not UTF-8 text (byte {e.start}: {e.reason})")
        except RecursionError:
            fail(f"{path} is nested too deeply to parse")
        except OSError as e:
            fail(f"cannot read {path}: {e.strerror or e}")
        if not isinstance(data, dict):
            what = "empty" if data is None else f"a top-level {type(data).__name__}"
            fail(f"{path} is {what}, not a mapping, so not an Isaac Lab config dump")
        problem = tree_problem(data)
        if problem:
            fail(f"{path}: {problem}")
        out[name] = data
    return run_dir, out["env"], out["agent"]


# ---- formatting ----

def fmt(v, limit=FMT_LIMIT):
    """Compact text for a value, cut at `limit` characters without building the rest."""
    parts, budget = [], [limit]
    _fmt(v, parts, budget)
    s = "".join(parts)
    return s if budget[0] >= 0 else s[:limit] + "…"


def _emit(parts, budget, s):
    parts.append(s)
    budget[0] -= len(s)


def _fmt(v, parts, budget):
    if budget[0] < 0:
        return
    if isinstance(v, dict):
        if SCENE_ENTITY_KEYS <= v.keys():
            _emit(parts, budget, fmt_entity(v))
            return
        items = [(f"{k}: ", x) for k, x in v.items()]
        opener, closer = "{", "}"
    elif isinstance(v, (list, tuple)):
        items = [("", x) for x in v]
        opener, closer = ("(", ")") if isinstance(v, tuple) else ("[", "]")
        if isinstance(v, tuple) and len(v) == 1:
            closer = ",)"
    else:
        if isinstance(v, slice):
            s = "all" if v == slice(None) else f"{v.start}:{v.stop}" + (f":{v.step}" if v.step is not None else "")
        elif isinstance(v, float):
            s = repr(v)
        else:
            s = str(v)
        _emit(parts, budget, s)
        return
    _emit(parts, budget, opener)
    for i, (label, x) in enumerate(items):
        if budget[0] < 0:
            return
        _emit(parts, budget, (", " if i else "") + label)
        _fmt(x, parts, budget)
    _emit(parts, budget, closer)


def fmt_entity(v):
    """A SceneEntityCfg dict (a dozen keys, mostly None/slice) as name[the fields that were set]."""
    parts = []
    for key in ("joint_names", "body_names", "fixed_tendon_names", "object_collection_names"):
        if v.get(key) is not None:
            parts.append(f"{key}={fmt(v[key])}")
    if v.get("preserve_order"):
        parts.append("preserve_order")
    return f"{fmt(v.get('name'))}[{', '.join(parts)}]" if parts else fmt(v.get("name"))


def short_func(f):
    return f.rsplit(":", 1)[-1] if isinstance(f, str) else fmt(f)


def params_text(p):
    return f" {fmt(p)}" if isinstance(p, dict) and p else ""


def sub(d, *keys):
    """d[k1][k2]... as a dict, {} when any level is missing or not a mapping."""
    for k in keys:
        d = d.get(k) if isinstance(d, dict) else None
    return d if isinstance(d, dict) else {}


def as_list(v):
    return v if isinstance(v, list) else []


# ---- entry lines ----

def run_dir_line(run_dir, host, agent):
    line = f"- Run dir: {host}:{run_dir}"
    if agent.get("logger") == "wandb":  # rsl_rl: WandbSummaryWriter names the run after the run dir
        line += (f"; W&B <$WANDB_USERNAME on the host, else the account default>/{fmt(agent.get('wandb_project'))}, "
                 f"run {os.path.basename(run_dir)}")
    exp = sub(agent, "agent", "experiment")
    if exp.get("wandb"):  # skrl
        kw = sub(exp, "wandb_kwargs")
        line += f"; W&B {fmt(kw.get('entity', '?'))}/{fmt(kw.get('project', '?'))}, run {fmt(kw.get('name', '? (skrl default)'))}"
    return line


def env_lines(env):
    scene, sim = sub(env, "scene"), sub(env, "sim")
    dt, dec = sim.get("dt"), env.get("decimation")
    ok = isinstance(dt, (int, float)) and isinstance(dec, int) and not isinstance(dec, bool) and dt and dec
    rate = f" ({1.0 / (dt * dec):g} Hz control)" if ok and math.isfinite(dt) else ""
    lines = [
        f"- Env: <task>, num_envs {fmt(scene.get('num_envs'))}, episode_length_s {fmt(env.get('episode_length_s'))}, "
        f"sim dt {fmt(dt)} / decimation {fmt(dec)}{rate}"
    ]
    obs = []
    for group, g in sub(env, "observations").items():
        if isinstance(g, dict):
            terms = [str(k) for k, t in g.items() if isinstance(t, dict) and "func" in t]
            obs.append(f"{group}[{', '.join(terms)}]" + (" concat" if g.get("concatenate_terms") else ""))
    act = []
    for name, a in sub(env, "actions").items():
        if isinstance(a, dict):
            extra = f" scale {fmt(a['scale'])}" if "scale" in a else ""
            act.append(f"{name} {short_func(a.get('class_type'))}{extra}")
    if obs or act:
        lines.append(f"- Obs/Act (optional): {'; '.join(obs) or '?'}; {', '.join(act) or '?'}")
    return lines


def scalars(d, skip):
    return [f"{k} {fmt(v)}" for k, v in d.items() if k not in skip and v is not None and not isinstance(v, dict)]


def algo_line(agent):
    alg = agent.get("algorithm")
    if isinstance(alg, dict) and "class_name" in alg:  # rsl_rl
        pol = sub(agent, "policy")
        runner = [f"{k} {fmt(agent.get(k))}" for k in ("num_steps_per_env", "max_iterations") if k in agent]
        line = f"- Algo: {fmt(alg['class_name'])} ({fmt(agent.get('class_name'))}): {', '.join(scalars(alg, {'class_name'}))}; {', '.join(runner)}"
        pp = scalars(pol, {"class_name"})
        if pp:
            line += f"; policy {fmt(pol.get('class_name'))}: {', '.join(pp)}"
        if agent.get("resume"):
            line += f"; resume load_run {fmt(agent.get('load_run'))} load_checkpoint {fmt(agent.get('load_checkpoint'))}"
        return line
    ag = agent.get("agent")
    if isinstance(ag, dict) and "class" in ag:  # skrl
        nets = []
        for role, m in sub(agent, "models").items():
            if isinstance(m, dict):
                layers = [f"{fmt(n.get('layers'))} {fmt(n.get('activations'))}" for n in as_list(m.get("network")) if isinstance(n, dict)]
                nets.append(f"{role} {fmt(m.get('class'))} {' '.join(layers)}".rstrip())
        trainer = sub(agent, "trainer")
        line = (f"- Algo: {fmt(ag['class'])} (skrl): {', '.join(scalars(ag, {'class', 'experiment'}))}; "
                f"{fmt(trainer.get('class'))} timesteps {fmt(trainer.get('timesteps'))}")
        return line + (f"; models: {'; '.join(nets)}" if nets else "")
    return f"- Algo: ? (agent.yaml layout not recognised; top-level keys: {fmt(list(agent))})"


def terms_line(label, section, render):
    terms, used = [], 0
    items = [(name, t) for name, t in section.items() if t is None or isinstance(t, dict)]
    for i, (name, t) in enumerate(items):
        if used > LINE_LIMIT:
            terms.append(f"… and {len(items) - i} more terms")
            break
        terms.append(f"{name} off" if t is None else render(name, t))
        used += len(terms[-1]) + 2
    return f"- {label}: " + ("; ".join(terms) or "none")


def reward(name, t):
    return f"{name} → {fmt(t.get('weight'))}{params_text(t.get('params'))}"


def curriculum(name, t):
    return f"{name}: {short_func(t.get('func'))}{params_text(t.get('params'))}"


def event(name, t):
    mode = fmt(t.get("mode"))
    if mode == "interval" and t.get("interval_range_s") is not None:
        mode += f" {fmt(t['interval_range_s'])} s"
    return f"{name} ({mode}): {short_func(t.get('func'))}{params_text(t.get('params'))}"


def seed_line(env, agent):
    es, ag = env.get("seed"), agent.get("seed")
    return f"- Seed(s): {fmt(es)}" if es == ag else f"- Seed(s): env {fmt(es)} / agent {fmt(ag)}"


# ---- diff ----

def same(a, b):
    if isinstance(a, float) and isinstance(b, float) and math.isnan(a) and math.isnan(b):
        return True
    if isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool) and not isinstance(b, bool):
        return a == b  # 1 and 1.0 are the same weight
    return type(a) is type(b) and a == b


def ignored(path, keys):
    dotted = "." + path.replace("[", ".[") + "."
    return any(f".{k}." in dotted for k in keys)


MISSING = object()


def diff_into(a, b, path, keys, out):
    """Walk both configs together; a key that turns from null into a term (or back) is one entry."""
    if path and ignored(path, keys):
        return
    if isinstance(a, dict) and isinstance(b, dict) and a and b:
        for k in list(b) + [k for k in a if k not in b]:
            diff_into(a.get(k, MISSING), b.get(k, MISSING), f"{path}.{k}" if path else str(k), keys, out)
    elif (isinstance(a, list) and isinstance(b, list) and len(a) == len(b)
          and any(isinstance(x, dict) for x in a + b)):
        for i, (x, y) in enumerate(zip(a, b)):
            diff_into(x, y, f"{path}[{i}]", keys, out)
    elif not same(a, b):
        old = "(absent)" if a is MISSING else fmt(a)
        new_v = "(absent)" if b is MISSING else fmt(b)
        out.append(f"{path}: {old} → {new_v}")


def changed_line(new, base, extra_ignore):
    diffs = []
    diff_into(base, new, "", ALWAYS_IGNORED + tuple(extra_ignore), diffs)
    if not diffs:
        return "- Changed: nothing in params/*.yaml (a code-only change must cite its commit; otherwise the declared change did not land)"
    return "- Changed: " + "; ".join(diffs)


def main(argv=None):
    args = parse_args(argv)
    yaml = import_yaml()
    loader = make_loader(yaml)
    run_dir, env, agent = load_params(yaml, loader, args.run_dir)

    lines = [run_dir_line(run_dir, args.host or socket.gethostname(), agent)]
    if args.base:
        base_dir, benv, bagent = load_params(yaml, loader, args.base)
        sys.stderr.write(f"rl_log_entry.py: Changed is the params/*.yaml diff against {base_dir}\n")
        lines.append(changed_line({"env": env, "agent": agent}, {"env": benv, "agent": bagent}, args.ignore))
    lines += env_lines(env)
    lines += [
        algo_line(agent),
        terms_line("Reward terms", sub(env, "rewards"), reward),
        terms_line("Curriculum", sub(env, "curriculum"), curriculum),
        terms_line("DR", sub(env, "events"), event),
        seed_line(env, agent),
    ]
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
