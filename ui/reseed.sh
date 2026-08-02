#!/usr/bin/env bash
# Reset the demo: allocate a fresh party set + an open repo proposal, and rewrite
# ui/demo-config.json so the running UI picks it up on the next browser reload
# (serve.mjs re-reads the config per request — no server restart needed).
set -uo pipefail
export PATH="$HOME/.daml/bin:/opt/homebrew/opt/openjdk@17/bin:/opt/homebrew/bin:$PATH"
cd "$(dirname "$0")/.." || exit 1

echo "building + seeding…"
daml build >/dev/null 2>&1
DAR=$(ls -t .daml/dist/*.dar | head -1)
PKG=$(daml damlc inspect-dar --json "$DAR" | node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(0)).main_package_id)')
OUT=$(daml script --dar "$DAR" --script-name Demo:demoInit --ledger-host localhost --ledger-port 6865 --upload-dar yes 2>&1)

D=$(printf '%s\n' "$OUT" | sed -n "s/.*DEMO_DEALER='\([^']*\)'.*/\1/p")
M=$(printf '%s\n' "$OUT" | sed -n "s/.*DEMO_MMF='\([^']*\)'.*/\1/p")
R=$(printf '%s\n' "$OUT" | sed -n "s/.*DEMO_RISKDESK='\([^']*\)'.*/\1/p")

if [ -z "$D" ] || [ -z "$M" ] || [ -z "$R" ]; then
  echo "seed failed — output was:"; printf '%s\n' "$OUT" | tail -20; exit 1
fi

node -e 'const fs=require("fs");const[pkg,d,m,r]=process.argv.slice(1);
  fs.writeFileSync("ui/demo-config.json",JSON.stringify({ledgerId:"sandbox",pkg,parties:{Dealer:d,MMF:m,RiskDesk:r}},null,2)+"\n")' "$PKG" "$D" "$M" "$R"

echo "reseeded — new ui/demo-config.json:"
cat ui/demo-config.json
echo "reload http://localhost:8080"
