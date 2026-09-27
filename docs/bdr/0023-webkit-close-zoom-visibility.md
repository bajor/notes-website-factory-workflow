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

Traced vector artwork renders the same in WebKit as in Chromium at every supported zoom. Scene JSON changes in two ways:

- A vector artwork node carries its shapes as SVG path data in [board units](/context/glossary.md#board-unit), rounded to a thousandth of a point, and no matrix.
- An image node's matrix is its presentation matrix, which already counts sample rows from the top.

This replaces the normalized coordinate precision rule and scenario 7 of [BDR 0017](/bdr/0017-preserve-local-traced-detail.md). Tracing, rendered geometry, source order, opacity, clipping, and the BDR 0022 surface bound are unchanged. [ADR 0016](/adr/0016-board-point-vector-artwork.md) owns the mechanism.

The review-only diagram `visual-explanations/0023-board-point-artwork.svg` contrasts browser-placed normalized artwork with generator-placed board-point artwork. Reviewers should verify three things:

- placed paths and raster matrices match the former browser presentation;
- no vector container or path carries a transform;
- the WebKit evidence matches Chromium.

The existing cleanup workflow deletes the SVG from `main` after merge.

## Scenarios and Test Design

| Given / When / Then | Instrument and proof |
| --- | --- |
| 1. Given an image matrix, when presented, then sample rows count from the top. | Pure `imagePresentationMatrix` test. |
| 2. Given traced contours, when placed, then each contour becomes one closed board path of the same segments. | Pure `placeVectorPath` test. |
| 3. Given raster and vector resources drawn by the interpreter, when emitted, then images carry presentation matrices and artwork carries placed board commands. | Pure interpreter tests of raster, vector, and mixed resources. |
| 4. Given placed paths, when serialized, then coordinates round to a thousandth of a point and trailing zeros drop. | Pure JSON serialization test. |
| 5. Given a one-pixel cutoff component placed at a tenth of a point per source pixel, when serialized, then its path keeps nonzero area. | Pure 20,000-pixel-wide trace, placement, and serialization regression. |
| 6. Given vector artwork with a non-finite placed coordinate, when validated, then the scene is rejected. | Pure `validateScene` test. |
| 7. Given clipped vector artwork, when zoomed between 4× and 16×, then clip wrappers, artwork groups, and paths keep board units, and the rendered path stays aligned with its link. | The Chromium close-zoom regression in `make test-runtime`. |
| 8. Given a raster image, when rendered, then its presentation matrix reaches the DOM unchanged. | The existing runtime DOM check for the image matrix. |
| 9. Given the real GCP consumer, when zoomed closely in WebKit, then traced strokes match Chromium at every step, and Chromium output matches the previous build. | Local WebKit and Chromium captures of fixed board regions from 1× to 16×, recorded in the implementation issue. |
| 10. Given the factory fixture or the GCP consumer, when rebuilt, then the fixed 18 and 72 DPI gates still pass. | Factory `make evaluate` and the GCP consumer workflow evaluation. |

# References

1. [Bounded zoom rendering](/bdr/0022-bounded-zoom-rendering.md)
2. [Rendering decision](/adr/0016-board-point-vector-artwork.md)
3. [Refined precision rule](/bdr/0017-preserve-local-traced-detail.md)
4. [Implementation record](/issues/0019-webkit-close-zoom-culling.md)
