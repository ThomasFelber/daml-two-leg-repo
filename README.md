# daml-two-leg-repo

A weekend-sized Daml project: atomic DvP, a two-leg repo with minute-priced
interest, a pre-commit eligibility gate and a haircut floor. Built to back a
claim with code rather than assurances.

## Quickstart (about 5 minutes)

You need JDK 17+ and the Daml SDK. This installs the exact SDK version the
project pins (2.10.4):

```
curl -sSL https://get.daml.com/ | sh -s 2.10.4
```

Then:

```
git clone https://github.com/ThomasFelber/daml-two-leg-repo.git
cd daml-two-leg-repo
daml test
```

The first run downloads dependencies and takes a minute; after that it is
seconds. Success looks like this — six `ok` lines at the top (order varies),
followed by a long test-coverage report you can ignore:

```
Test Summary

daml/Main.daml:allocateParties: ok, 0 active contracts, 0 transactions.
daml/Main.daml:testDvp: ok, 2 active contracts, 4 transactions.
daml/Main.daml:testRepoRejectsBreachedHaircut: ok, 4 active contracts, 5 transactions.
daml/Main.daml:testRepoRejectsIneligibleCollateral: ok, 4 active contracts, 5 transactions.
daml/Main.daml:testRepoHappyPath: ok, 4 active contracts, 7 transactions.
daml/Main.daml:setup: ok, 14 active contracts, 21 transactions.
```

Two things in that output would otherwise look wrong:

- **`ok` on the two `Rejects…` scripts means the rejection happened.** They
  assert with `submitMustFail`: an ineligible ISIN or a breached haircut must
  abort *before* anything commits. The failure is the feature under test.
- **Six lines, not four.** `daml test` runs every top-level `Script` value,
  so `allocateParties` (a helper) and `setup` (the `daml start` init script,
  which replays all four scenarios) are counted too.

## See the privacy model (about 2 minutes)

The point of this project is *who may see what*, and you can click through
that instead of taking my word for it:

```
daml start    # sandbox + Navigator on http://localhost:7500, runs Main:setup
```

Log in as one user at a time — `dealer`, `mmf`, `riskdesk` — and open the
*Contracts* view. After `setup` the ledger holds 14 active contracts, and
each login sees a different subset:

- **dealer** sees 10: its bonds and cash, the two open repo proposals, and
  the risk desk's eligibility lists — but not MMF's undisclosed cash.
- **mmf** sees 11: its own cash and bonds, plus the same proposals and
  criteria — but not the dealer's other holdings.
- **riskdesk** sees all 14 — *not* because it is an admin, but because in
  this lab it has a role in every contract: signatory on the criteria,
  issuer/registrar observer on every asset, gate on every proposal.

That last line is the point: there is no "view everything" flag anywhere.
Visibility follows contractual role — change the roles and the view
changes; there is no other knob. The same picture per scenario, with
less clicking: run `daml studio`, open [daml/Main.daml](daml/Main.daml) and
click *Script results* above any test — the table view has a visibility
column per party (X vs –).

## What it does

Read the code in this order — four files, 348 lines, about 20 minutes:

1. [`daml/Assets.daml`](daml/Assets.daml): minimal `Cash` and `Bond`
   templates with explicit disclosure (`disclosedTo`), because on this ledger
   model nothing is visible by default.
2. [`daml/Dvp.daml`](daml/Dvp.daml): delivery versus payment as one atomic
   transaction via propose-accept. Both legs move or neither does; there is
   no half-settled state to reconcile afterwards.
3. [`daml/Repo.daml`](daml/Repo.daml): a two-leg repo. The open leg swaps
   bond against cash atomically; the close leg returns principal plus
   interest priced to the minute (a 4-hour repo pays 4 hours of interest,
   not a day). The close leg exists as an enforceable contract state from
   the moment the repo opens, which is precisely the property that makes
   intraday repo tradable. The open leg is guarded by a **pre-commit policy
   gate**: eligibility (ISIN whitelist) and a haircut floor are checked
   against the risk desk's reference data BEFORE anything commits. An
   ineligible ISIN or a breached haircut aborts the whole transaction: there
   is no failed trade to clean up, because the trade never existed.
4. [`daml/Main.daml`](daml/Main.daml): four scripts — DvP happy path, repo
   happy path, and the two pre-commit rejections.

## Three things that struck me while building it

1. **The privacy model stopped my own tests, and that is the feature.** My
   first version failed at settlement because the counterparty could not even
   fetch the asset it was buying: need-to-know is the default, and disclosure
   has to be explicit (`disclosedTo`). On an EVM, everything is public and
   privacy is the retrofit; here visibility is an authorization property of
   the language. This is the privacy dilemma from our first conversation,
   experienced as a compiler-grade constraint rather than a slide.

2. **Decimal rounding produced a reconciliation problem in miniature.** My
   test computed the repurchase price with different operator grouping than
   the contract, and on a 98 million notional the two "identical" formulas
   disagreed by fractions of a cent, which failed the close leg. The fix was
   not a tolerance band; it was making the formula exist exactly once
   (`repurchasePrice` in `Repo.daml`), imported by contract and test alike.
   One definition, no second book, nothing to reconcile. That is the entire
   thesis of this technology, encountered at line level.

3. **Authority composes the way settlement should.** The proposal's
   signatories carry their authority into the accepting transaction, so an
   atomic multi-party settlement needs no approvals, no allowances, no
   escrow contract holding custody in the middle. Propose-accept is not a
   workaround; it is the authorization model doing the work that an escrow
   pattern fakes on account-model chains.

## A requirement I would reject

"Give the operations desk read access to all positions, for support." On this
ledger model that is not a support feature, it is a privacy-architecture
change: visibility is entitlement, not a UI setting. The right answer is
scoped, explicit disclosure (observer roles per workflow, time-boxed if
needed), so support sees the contract in question, not the book. The ability
to say no starts with understanding why the design is what it is.

## Deliberate simplifications

Honesty section: this is a lab, not a product.

- The asset owner is the sole signatory, so issuance control is out of scope;
  in production the issuer or registrar is a signatory and transfers run
  through issuer-authorized workflows or a token standard.
- No time-based maturity enforcement on the repo; `RepoEnforce` is a stub for
  default handling. Real term logic needs ledger time assertions and grace
  periods.
- Single cash and bond units instead of fungible splits/merges; no partial
  settlement, no substitution, no netting. Each of those is exactly where a
  production collateral workflow gets interesting.
