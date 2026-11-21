"""Runs tests/run.lua once per scenario, each in a fresh LuaJIT (Lua 5.1) runtime."""
import os
import sys
from lupa import luajit21

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
failed = 0
SCENARIOS = [("shaman", None), ("priest", None), ("warlock", None), ("template", None), ("warrior", None),
             ("robust", None), ("forever", None), ("talents", None), ("sweep", "WARLOCK"), ("sweep", "SHAMAN"), ("sweep", "PRIEST")]
ONLY = [a for a in sys.argv[1:] if not a.startswith("--")]
for scenario, sweep_class in SCENARIOS:
    if ONLY and scenario not in ONLY:
        continue
    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.ROOT = ROOT
    g.SCENARIO = scenario
    g.SWEEP_CLASS = sweep_class
    g.SWEEP_PRINT = "--print" in sys.argv
    g.print_real = lambda *a: print(*a, flush=True)
    with open(os.path.join(ROOT, "tests", "run.lua"), encoding="utf-8") as fh:
        code = fh.read()
    try:
        failed += int(lua.execute(code) or 0)
    except Exception as e:  # a Lua error escaping the addon
        print(f"{scenario}: CRASH {e}")
        failed += 1
sys.exit(1 if failed else 0)
