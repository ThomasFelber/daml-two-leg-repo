#!/usr/bin/env bash
# Stop the demo UI server. (A fresh ledger started via ui/start.sh is stopped by
# Ctrl-C in its own terminal — Canton then takes a few seconds to release ports.)
if [ -f /tmp/twoleg-ui.pid ]; then
  kill "$(cat /tmp/twoleg-ui.pid)" 2>/dev/null && echo "• UI (pid $(cat /tmp/twoleg-ui.pid)) stopped"
  rm -f /tmp/twoleg-ui.pid
fi
pkill -f 'ui/serve.mjs' 2>/dev/null && echo "• any stray UI servers stopped"
echo "done."
