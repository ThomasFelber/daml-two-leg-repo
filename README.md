# daml-two-leg-repo

A weekend-sized Daml project: atomic DvP, a two-leg repo with minute-priced
interest, a pre-commit eligibility gate and a haircut floor. Built to back a
claim with code rather than assurances.

## What it does

- **`Assets.daml`**: minimal `Cash` and `Bond` templates with explicit
  disclosure (`disclosedTo`), because on this ledger model nothing is visible
  by default.
- **`Dvp.daml`**: delivery versus payment as one atomic transaction via
  propose-accept. Both legs move or neither does; there is no half-settled
  state to reconcile afterwards.
- **`Repo.daml`**: a two-leg repo. The open leg swaps bond against cash
  atomically; the close leg returns principal plus interest priced to the
  minute (a 4-hour repo pays 4 hours of interest, not a day). The close leg
  exists as an enforceable contract state from the moment the repo opens,
  which is precisely the property that makes intraday repo tradable.
- **Pre-commit policy gate**: eligibility (ISIN whitelist) and a haircut floor
  are checked by a risk desk's reference data BEFORE anything commits. An
  ineligible ISIN or a breached haircut aborts the whole transaction: there is
  no failed trade to clean up, because the trade never existed.
- **`Main.daml`**: four scripts: DvP happy path, repo happy path, and two
  pre-commit rejections.

## Run it

```
daml test     # runs all four scripts
daml start    # sandbox + Navigator, runs Main:setup
```

Built against Daml SDK 2.10.4 (JDK 17).

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

## What a second pass found

Three things I did not see the first time. They are not simplifications, they
are holes, and the reason they are here rather than quietly fixed is that each
one is more instructive than the code that hides it.

1. **The close leg keeps the overpayment.** `RepoClose` asserts that the
   repayment is *at least* the repurchase price, then transfers the whole cash
   contract to the cash provider. Pay 1,000,000 against a 950,000 obligation
   and the excess is simply gone. The honest fix is either an equality
   assertion or a split with change returned, and choosing between those is a
   product decision, not a technical one: equality demands that the payer
   compute the minute-priced interest exactly as the contract does, which
   pushes the rounding problem out to every client.

2. **The pledged bond can be pulled out from under the close leg.** `Bond` has
   the owner as sole signatory and no choices, so after the open leg the cash
   provider can archive it unilaterally. `RepoClose` then fails at `fetch`, and
   the collateral provider has lost the bond with the cash still outstanding.
   This is the same simplification listed below, followed one step further:
   sole-signatory ownership does not just skip issuance control, it makes
   rehypothecation structurally possible. Real collateral needs the holding to
   be jointly controlled for the life of the repo.

3. **The default remedy is unconditional.** `RepoEnforce` carries no time
   assertion, so the cash provider can enforce one second after opening and
   keep the collateral. "No maturity enforcement" understates it: the remedy
   is not merely untimed, it is available immediately.

The related design smell, worth stating plainly: `RepoAgreement` stores
`pledgedBondCid` in its payload. A contract ID in a contract goes stale as soon
as anything else archives and recreates the asset. It survives here only
because nothing else can touch that bond, which is precisely the assumption
finding 2 breaks.

## Deliberate simplifications

Honesty section: this is a lab, not a product.

- The asset owner is the sole signatory, so issuance control is out of scope;
  in production the issuer or registrar is a signatory and transfers run
  through issuer-authorized workflows or a token standard. See finding 2 above
  for where that assumption bites.
- No time-based maturity enforcement on the repo; `RepoEnforce` is a stub for
  default handling. Real term logic needs ledger time assertions and grace
  periods.
- Single cash and bond units instead of fungible splits/merges; no partial
  settlement, no substitution, no netting. Each of those is exactly where a
  production collateral workflow gets interesting.
