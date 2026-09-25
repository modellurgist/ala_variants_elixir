# V35 — Composed Inputs (the frontier variant)

The current top variant: tied at **88/95** on the main scorecard with V30/V33/V34, and the leader
on the two supplements — **P-family 19/20** (presentation purity) and **E-family 23/25** (adherence
to the ALA function-encoding rubric). It is V33 (V32 presentation purity + V33 flows + the D6
second consumer) plus two encoding-rubric fixes:

- **R3 — calibration on the diagram (V34).** Domain abstractions were made generic (calibration
  passed in as data); the values that make the app *this* app — shipping rates, promo codes, volume
  tiers, gift-wrap price, the undo window — live in a manifest `config:` channel, spliced into
  `init/1`. Measured cost ~+1.8% author bits; makes per-consumer divergence ~0.39× the cost of
  forking a shared abstraction.
- **R2 — composed cross-slot inputs (V35).** A feature reads/writes only its own slot; the
  composition (shell) resolves any peer-slot data and passes it in. A `CrossSlotRead` detector
  reports violations (6→5, the 5 residual being thin structural reads of the aggregate).

Both target non-adherences the function-encoding rubric found in v33
([`ala_lab/docs/ALA-encoding-applied-to-v33.md`](../../ala_lab/docs/ALA-encoding-applied-to-v33.md)).

**162 tests, 0 failures**, through the checked seam (`zc.gen --check`, `zc.gen.contracts --check`,
`credo --only Purity`). Both additions are behavior-preserving.

## Building on this variant

- **[`docs/techniques.md`](docs/techniques.md)** — one worked recipe per mechanism (zero-coupled
  feature, intent, boundary projection, typed fact + reaction, contracts, `config:`, flows,
  reaction placement, cross-slot inputs).
- **[`docs/adding-a-feature.md`](docs/adding-a-feature.md)** — a verified end-to-end walkthrough
  (building "recently viewed" checker-clean).
- **[`docs/architecture.md`](docs/architecture.md)** — the layer map (V32→V35 additions + the V30
  spine).

## What changed

- **Parametric domain abstractions** (now literal-free, genuinely `[]`): `CalculateShipping`,
  `ShippingInfo`, `ValidatePromo`, `CalculateGiftWrapCost`, `VolumeTier` all take their
  calibration as an argument.
- **`Cart` carries a `config` map**, injected at construction; `recalc`/`apply_promo` read it.
  The aggregate holds no baked rates or codes.
- **A manifest `config:` channel.** Each slot may declare `config:`; the generator splices it into
  that slot's `init/1` at generation time (a few lines in `page_generator.ex`, reusing the
  existing init path — no new runtime mechanism). The two manifests carry `@retail_pricing` and
  `@portal_pricing` blocks — reading them *is* reading each consumer's pricing policy.
- **Undo window** is `config: [window_ms: 5_000]`, not a module attribute.

Left as declared residue (noted, not hoisted): the `StockStatus` low-stock threshold (a display
constant, low reuse value) and the PO/postal regexes (essential per-feature content, not shared
calibration).

## Measured (`ala_lab/docs/info-content-scripts/r3_measure.py`, xz 9e, 2026-09-18)

| reading | result |
|---|---|
| **Total hand-authored bits, v34 vs v33** | **101.8%** (+7,232 bits, +1.8%) — near-free relocation, *not* the 213% that UI-abstraction extraction cost. R3 compliance is cheap. |
| **Relocation** | 848 B of calibration data left the abstractions and reappeared in the manifests; the abstraction files grew only by parametric signatures + docs. Conservation, again. |
| **Divergence cost (2nd consumer, different shipping)** | **v34/v33 ≈ 0.39** — a config edit (~240 B, already on the consumer's diagram) vs forking the shared abstraction (~621 B). The gap widens per consumer and per divergent value. |

**Reading:** R3 buys genuine ALA compliance (the abstractions stop lying about being generic) and
single-locus readability (each consumer's pricing in one manifest block) for ~1.8% more author
information — a good trade, and the amortization the lab keeps looking for shows up on the
*divergence* axis: per-consumer config is ~2.6× cheaper than forking, exactly where a growing
multi-consumer catalog spends. The one real cost is **test-coupling**: with no baked defaults,
pure domain/aggregate tests must now supply config (they play the composition role) — visible in
`domain_test.exs` and the one `cart_test.exs` helper.

## Verify

```
mix test
python3 ../../ala_lab/docs/info-content-scripts/r3_measure.py
```
