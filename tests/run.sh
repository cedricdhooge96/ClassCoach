#!/bin/sh
# Runs tests/run.lua once per scenario, each in a fresh Lua 5.1 with its own
# time limit: a scenario that hangs is a finding, and it does not stop the rest.
#
#   tests/run.sh                 everything
#   tests/run.sh forever ui      only these scenarios
#   tests/run.sh --print sweep   the sweep also prints what it checks
#   LUA=luajit tests/run.sh      another Lua 5.1 interpreter
#
# The game runs Lua 5.1, so the tests do too (PUC-Rio lua5.1; LuaJIT also works).
cd "$(dirname "$0")/.." || exit 1
LUA="${LUA:-lua5.1}"
LIMIT="${LIMIT:-300}"
if ! command -v "$LUA" >/dev/null 2>&1; then
  echo "No $LUA found: install Lua 5.1 (apt install lua5.1) or set LUA=..." >&2
  exit 2
fi
PRINT=false
ONLY=""
for a in "$@"; do
  case "$a" in
    --print) PRINT=true ;;
    *) ONLY="$ONLY $a" ;;
  esac
done
# Every scenario runs at the same time in its own process; the results print in order.
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
n=0
for entry in shaman priest warlock template warrior robust forever talents focus bars ui wand trace \
             sweep:WARLOCK sweep:SHAMAN sweep:PRIEST; do
  scenario=${entry%%:*}
  class=""
  [ "$scenario" != "$entry" ] && class=${entry#*:}
  if [ -n "$ONLY" ]; then
    case " $ONLY " in *" $scenario "*) ;; *) continue ;; esac
  fi
  n=$((n + 1))
  (
    SC="$scenario" CL="$class" PR="$PRINT" ROOT="$PWD" timeout "$LIMIT" "$LUA" -e '
      ROOT = os.getenv("ROOT"); SCENARIO = os.getenv("SC")
      local c = os.getenv("CL"); if c ~= "" then SWEEP_CLASS = c end
      SWEEP_PRINT = os.getenv("PR") == "true"
      print_real = print
      local chunk = assert(loadfile(ROOT .. "/tests/run.lua"))
      local ok, r = pcall(chunk)
      if not ok then print(SCENARIO .. ": CRASH " .. tostring(r)); os.exit(1) end
      os.exit((tonumber(r) or 0) > 0 and 1 or 0)' >"$OUT/$n.log" 2>&1
    code=$?
    [ $code -eq 124 ] && echo "$scenario: HUNG (more than ${LIMIT}s)" >>"$OUT/$n.log"
    echo $code >"$OUT/$n.code"
  ) &
done
wait
failed=0
i=1
while [ $i -le $n ]; do
  cat "$OUT/$i.log"
  [ "$(cat "$OUT/$i.code")" != 0 ] && failed=1
  i=$((i + 1))
done
[ $n -eq 0 ] && { echo "No scenario matched:$ONLY" >&2; exit 2; }
exit $failed
