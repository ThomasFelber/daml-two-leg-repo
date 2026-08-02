#!/usr/bin/env bash
# One command to bring the whole demo up:  ledger + seed + UI.
#
#   bash ui/start.sh        ->   http://localhost:8080
#
# If a Canton sandbox + JSON API is already running on :7575 it is REUSED
# (fast path). Otherwise a fresh sandbox is started in the FOREGROUND and
# Ctrl-C in this terminal tears everything down.
set -uo pipefail
export PATH="$HOME/.daml/bin:/opt/homebrew/opt/openjdk@17/bin:/opt/homebrew/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ledger_up(){ curl -s --max-time 3 http://localhost:7575/readyz 2>/dev/null | grep -q SERVING; }
ui_up(){ curl -s --max-time 2 http://localhost:8080/api/config >/dev/null 2>&1; }

start_ui(){
  if ui_up; then echo "• UI already running on :8080"; else
    echo "• starting UI on :8080"
    node ui/serve.mjs >/tmp/twoleg-ui.log 2>&1 &
    echo $! > /tmp/twoleg-ui.pid
    sleep 1
  fi
}

banner(){ echo; echo "  ▶  DEMO READY   http://localhost:8080"; echo "     reset between runs:  bash ui/reseed.sh   (then reload the page)"; echo "     stop the UI:         bash ui/stop.sh"; echo; }

if ledger_up; then
  echo "• ledger already up on :7575 — reusing it"
  bash ui/reseed.sh >/tmp/twoleg-seed.log 2>&1 && echo "• demo seeded (ui/demo-config.json refreshed)" \
    || { echo "  seed failed — see /tmp/twoleg-seed.log"; exit 1; }
  start_ui
  banner
  exit 0
fi

# Fresh machine: UI in background (cleaned up on Ctrl-C), ledger in foreground.
echo "• no ledger on :7575 — starting a fresh Canton sandbox (~30–40s the first time)…"
daml build >/dev/null 2>&1
start_ui
trap 'echo; echo "• stopping…"; [ -f /tmp/twoleg-ui.pid ] && kill "$(cat /tmp/twoleg-ui.pid)" 2>/dev/null; rm -f /tmp/twoleg-ui.pid' EXIT
echo "• launching the ledger — once it reports ready, open http://localhost:8080"
echo "  (Ctrl-C here stops the ledger AND the UI)"
daml start --start-navigator no --open-browser no --on-start "bash '$ROOT/ui/reseed.sh'"
