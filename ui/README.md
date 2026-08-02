# Two-Leg Repo — Ledger View (demo UI)

A tiny, zero-dependency web UI that shows the `daml-two-leg-repo` model **from each
party's own vantage point** and lets you drive the trade live: propose → accept →
close, plus a pre-commit rejection. It exists to make one thing tangible to a
non-Daml audience (a bank, a stakeholder): **on Canton, the same trade looks
different to each party, and settlement is atomic and policy-gated before commit.**

## Run it

Prereqs: the Daml SDK (2.10.4) and a JVM on your `PATH`, plus Node ≥ 18. One command:

```bash
bash ui/start.sh          # ledger + seed + UI  ->  http://localhost:8080
```

- Reuses a Canton sandbox already running on `:7575`; otherwise starts a fresh one
  (Ctrl-C in that terminal stops everything).
- **Reset between runs** (the demo is stateful — accepting consumes the proposal):

  ```bash
  bash ui/reseed.sh        # fresh parties + open proposal, then reload the page
  ```

- Stop the UI: `bash ui/stop.sh`.

## The 90-second demo

1. Click through **Dealer / MMF / RiskDesk** — same trade, three views. Note the
   `✓ owned` vs `👁 observing (disclosed)` badges: each party sees only what it is
   entitled to. *That is Canton's sub-transaction privacy, not a UI filter.*
2. On **MMF → Accept repo**: the bond moves Dealer→MMF and the cash MMF→Dealer in
   **one atomic step**. Switch tabs to see both sides flip.
3. On **Dealer → Close repo**: repays principal + **minute-priced interest**
   (≈ $2,014 for a 4-hour repo on 98m); the bond returns.
4. **Attempt ineligible collateral**: the ledger refuses with
   *"collateral ISIN not eligible"* — the gate runs **before** commit, so there is
   no failed trade to clean up.

## How it's built (and why)

```
browser  ──►  ui/serve.mjs  ──►  Canton JSON Ledger API (:7575)  ──►  Canton (:6865)
(index.html)   (Node proxy)         /v1/query · /v1/create · /v1/exercise
```

- **`ui/index.html`** — one self-contained file (no framework, no build step).
- **`ui/serve.mjs`** — a ~70-line Node proxy that (a) serves the page *same-origin*
  so there is no CORS to configure, and (b) **mints a per-party JWT server-side**
  for each request, so the browser needs no auth code. The dev token is an HS256
  JWT carrying `{ ledgerId, actAs, readAs }`; the sandbox runs without auth, so the
  signature is not verified — the party claim is what scopes every query and command.
- **`ui/demo-config.json`** — the three party ids + package id, **generated** by
  `reseed.sh` (never hand-edited) and re-read on every request, so a reseed takes
  effect on a plain browser reload.
- **`daml/Demo.daml`** — `demoInit`, the seed: one clean party set and one open,
  accept-ready proposal. Kept separate from the proof/test scripts in `Main.daml`.

**Why not `create-daml-app`?** That scaffold's `react-scripts` toolchain does not
build cleanly on very new Node, and it pulls in hundreds of dependencies for what is
a read-mostly demo. A single HTML file talking straight to the documented JSON
Ledger API is more robust, instantly inspectable, and makes the point that *the
ledger + API is the product; the UI is yours*. On Daml 3.x the same UI would target
the JSON Ledger API **v2** (Navigator is removed there); the proxy is the only piece
that would change.

**Deliberate simplification:** the close leg mints fresh repayment cash rather than
reusing the borrowed cash (as `Main.daml`'s happy-path test does) — the lab studies
settlement composition, not cash-account bookkeeping.
