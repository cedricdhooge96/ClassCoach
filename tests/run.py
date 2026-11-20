"""Runs tests/run.lua once per scenario, each in a fresh LuaJIT (Lua 5.1) runtime."""
import os
import sys
from lupa import luajit21

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
failed = 0
for scenario in ("shaman", "priest", "warlock", "template", "warrior"):
    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.ROOT = ROOT
    g.SCENARIO = scenario
    g.print_real = lambda *a: print(*a)
    with open(os.path.join(ROOT, "tests", "run.lua"), encoding="utf-8") as fh:
        code = fh.read()
    try:
        failed += int(lua.execute(code) or 0)
    except Exception as e:  # a Lua error escaping the addon
        print(f"{scenario}: CRASH {e}")
        failed += 1
sys.exit(1 if failed else 0)
