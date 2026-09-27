---
type: BDR
title: WebKit close-zoom visibility
description: Keep traced artwork visible and stable in WebKit throughout close-up zoom.
status: Accepted
timestamp: 2026-09-27
---
# WebKit Close-Zoom Visibility

## Context and Behavior

The GCP consumer owner reports that reconstructed handwriting flickers at close zoom. Local WebKit 26.5 drops those strokes from 4× zoom upward, while Chromium draws them. [BDR 0022](/bdr/0022-bounded-zoom-rendering.md) requires artwork to remain visible throughout zoom but verifies only Chromium. The investigation is recorded in [Issue 0019](/issues/0019-webkit-close-zoom-culling.md).

Traced vector artwork renders the same in WebKit as in Chromium at every supported zoom. Every SVG container keeps [board units](/context/glossary.md#board-unit); each traced path carries its placement's presentation transform. Source geometry, order, opacity, clipping, the scene schema, and the BDR 0022 surface bound are unchanged. [ADR 0016](/adr/0016-transform-traced-paths-individually.md) owns the mechanism.

The review-only diagram `visual-explanations/0023-board-unit-artwork.svg` contrasts the former scaled artwork group with per-path transforms. Reviewers should verify that artwork groups carry no transform, paths carry the former group matrix, and WebKit evidence matches Chromium. The existing cleanup workflow deletes the SVG from `main` after merge.

## Scenarios and Test Design

| Given / When / Then | Instrument and proof |
| --- | --- |
| 1. Given vector artwork, when zoomed between 4× and 16×, then each artwork group keeps board units and its rendered path stays aligned with its link. | The Chromium close-zoom regression in `make test-runtime` compares group and SVG screen matrices and the rendered path with the link bounds. |
| 2. Given a vector artwork fixture, when rendered, then the path carries the presentation matrix. | The existing runtime DOM check for the artwork matrix. |
| 3. Given the real GCP consumer, when zoomed closely in WebKit, then traced strokes match Chromium at every step. | Local WebKit and Chromium captures of fixed board regions from 1× to 16×, recorded in the implementation issue. |
| 4. Given the factory fixture or the GCP consumer, when rebuilt, then the fixed 18 and 72 DPI gates still pass. | Factory `make evaluate` and the GCP consumer workflow evaluation. |

# References

1. [Bounded zoom rendering](/bdr/0022-bounded-zoom-rendering.md)
2. [Rendering decision](/adr/0016-transform-traced-paths-individually.md)
3. [Implementation record](/issues/0019-webkit-close-zoom-culling.md)
