---
type: BDR
title: Zoom-detail evidence
description: Capture deterministic handwriting detail at four and eight times native-point scale.
status: Accepted
timestamp: 2026-09-20
---
# Zoom-Detail Evidence

## Behavior

After the existing whole-board comparisons, partition the 18 DPI reference into 32-pixel square regions, clipping edge regions. Rank regions containing neutral nonwhite reference pixels by summed RGB error on those pixels; break ties in row-major order. A neutral pixel has equal red, green, and blue channel values; nonwhite excludes value `255`. Capture up to three regions at 288 and 576 DPI (4× and 8× native-point scale), each at most 1,024 pixels per side. White backgrounds and colored highlights do not determine the ranking. Selection measures pixels, not text semantics: screenshots and native paths can also supply detail regions.

The evaluator adds `reference-detail-N-DPI.png`, `generated-detail-N-DPI.png`, and `difference-detail-N-DPI.png`, where `N` starts at one in selected-region order. The `details` array in `evaluation.json` carries `number`, `dpi`, output-pixel `x` and `y` origins, actual pixel `width` and `height`, `inspectionOnly: true`, and comparison metrics. `report.html` displays the crops. These are inspection evidence, not additional pass thresholds. Tool, readiness, or dimension failures abort evaluation. Existing whole-board filenames, thresholds, and pass semantics remain unchanged.

`visual-explanations/0018-zoom-detail-evidence.svg` shows the existing whole-board gate and the added bounded crop branch. Previously the report stopped at whole-page metrics. Afterward `Factory.Evaluation` reuses `site/runtime.js` evaluation offsets to render selected detail. Reviewers must check crop alignment, the explicit inspection-only label, and unchanged whole-board pass semantics. The existing SVG cleanup workflow deletes the review artifact from `main` after merge.

## Scenarios and Test Design

| Given / When / Then | Instrument and proof |
| --- | --- |
| 1. Given unequal handwriting errors, when regions are selected, then the largest errors are selected first. | Pure region-selection test checks ranking. |
| 2. Given equal errors, when regions are selected, then no more than three regions appear in row-major order. | Pure selection regression checks the bound and tie-break. |
| 3. Given a blank reference, when selected, then no detail regions are emitted. | Pure empty-selection regression. |
| 4. Given an edge region, when captured at reading zoom, then reference and browser dimensions agree. | Pure clipping regression and synthetic factory browser evaluation. |
| 5. Given a rendering change, when reviewed, then enlarged reference, generated, and difference images accompany the whole-board results. | Factory and real-consumer report inspection. |
| 6. Given colored highlights without neutral ink, when selected, then no detail regions are emitted. | Pure color-exclusion regression. |
| 7. Given unequal image dimensions, when selected, then evaluation fails explicitly. | Pure dimension-error regression. |

# References

1. [Reusable factory requirements](/prd/0002-reusable-freeform-site-factory.md)
2. [Evaluation strategy](/adr/0011-bounded-zoom-detail-evidence.md)
3. [Existing whole-board evaluation](/bdr/0007-tiled-visual-evaluation.md)
4. [Implementation issue](/issues/0014-preserve-local-traced-detail.md)
