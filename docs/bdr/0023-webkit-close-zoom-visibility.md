---
type: BDR
title: WebKit close-zoom visibility
description: Keep traced artwork visible and stable in WebKit throughout close-up zoom by emitting it in board points.
status: Accepted
timestamp: 2026-09-27
---
# WebKit Close-Zoom Visibility

## Context and Behavior

The GCP consumer owner reports that reconstructed handwriting flickers at close zoom. [BDR 0022](/bdr/0022-bounded-zoom-rendering.md) requires artwork to remain visible throughout zoom but verifies only Chromium. The investigation is recorded in [Issue 0019](/issues/0019-webkit-close-zoom-culling.md).

Traced vector artwork renders the same in WebKit as in Chromium at every supported zoom. Each vector artwork node carries its shapes as SVG path data in [board units](/context/glossary.md#board-unit), rounded to a thousandth of a point, with no matrix. This replaces the normalized coordinate precision rule of [BDR 0017](/bdr/0017-preserve-local-traced-detail.md). Tracing, source geometry, order, opacity, clipping, raster presentation, and the BDR 0022 surface bound are unchanged. [ADR 0016](/adr/0016-board-point-vector-artwork.md) owns the mechanism.

The review-only diagram `visual-explanations/0023-board-point-artwork.svg` contrasts browser-placed normalized artwork with generator-placed board-point artwork. Reviewers should verify that placed paths match the former browser presentation, that no vector container or path carries a transform, and that WebKit evidence matches Chromium. The existing cleanup workflow deletes the SVG from `main` after merge.

## Scenarios and Test Design

| Given / When / Then | Instrument and proof |
| --- | --- |
| 1. Given traced contours and a sheared placement matrix, when placed, then each sample `(x, y)` lands at the matrix image of `(x, 1 - y)`. | Pure `placeVectorPath` test. |
| 2. Given an image resource drawn by the interpreter, when emitted, then its vector artwork holds board-point commands and no matrix. | Pure interpreter tests of vector and mixed resources. |
| 3. Given placed paths, when serialized, then coordinates round to a thousandth of a point, trailing zeros drop, and the node has no matrix. | Pure JSON serialization test. |
| 4. Given clipped vector artwork, when zoomed between 4× and 16×, then clip wrappers, artwork groups, and paths keep board units, and the rendered path stays aligned with its link. | The Chromium close-zoom regression in `make test-runtime`. |
| 5. Given the real GCP consumer, when zoomed closely in WebKit, then traced strokes match Chromium at every step. | Local WebKit and Chromium captures of fixed board regions from 1× to 16×, recorded in the implementation issue. |
| 6. Given the factory fixture or the GCP consumer, when rebuilt, then the fixed 18 and 72 DPI gates still pass. | Factory `make evaluate` and the GCP consumer workflow evaluation. |

# References

1. [Bounded zoom rendering](/bdr/0022-bounded-zoom-rendering.md)
2. [Rendering decision](/adr/0016-board-point-vector-artwork.md)
3. [Superseded precision rule](/bdr/0017-preserve-local-traced-detail.md)
4. [Implementation record](/issues/0019-webkit-close-zoom-culling.md)
