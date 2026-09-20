---
type: BDR
title: Alpha-layer traced SVG artwork
description: Preserve faint content inside traceable artwork resources through fixed-opacity SVG layers.
status: Superseded
superseded_by: "0017"
supersedes: "0015"
timestamp: 2026-09-16
---
# Alpha-Layer Traced SVG Artwork

## Context

BDR 0015 corrected contour geometry, but its vector paths retained only pixels at alpha `96` or above and emitted every retained fill at opacity `1`. The result visibly improves primary handwriting while removing or fragmenting faint anti-aliased and light source strokes.

## Description

For an image already classified as traceable vector artwork, the factory emits two fixed opacity layers: faint source alpha `88` through `95` and opaque source alpha `96` through `255`. Each layer has its own color-and-opacity SVG shape, emits fractional source-alpha contours, and meets adjacent layers on a shared boundary. This preserves visible faint source ink as light SVG geometry without fragmenting the scene by every alpha variation. Images whose complete masks remain below alpha `96` retain the existing low-alpha raster path. RGB quantization, source ordering, clipping, affine presentation, the fixed structural point limit, and fixed evaluation thresholds remain unchanged.

`visual-explanations/0016-alpha-layer-tracing.svg` shows the previous opaque-only vector path and the resulting fixed-opacity layer path. Before this change, `Factory.Vectorize` discarded sub-`96` pixels from a traceable image and `Factory.Pdf` received opaque vector shapes. After this change, `Factory.Vectorize` owns the faint alpha `88` through `95` layer and passes colored SVG shapes with layer opacity through the unchanged `Factory.Pdf` and browser rendering path. Reviewers must verify that whole low-alpha resources remain raster, visible faint pixels in mixed vector resources remain light rather than opaque, and the fixed 18 and 72 DPI gates pass. The SVG is a PR review artifact and the existing `bajor/github-workflows/.github/workflows/delete-visual-explanation-svgs.yml` cleanup workflow deletes it from `main` after merge.

## Scenarios

1. Given a traceable artwork resource containing a light stroke at source alpha `88` through `95`, when the factory builds it, then the generated SVG contains a nonzero-opacity shape for the stroke.
2. Given two adjacent alpha layers of the same quantized color, when the factory traces them, then their SVG shapes meet without a gap.
3. Given a fully opaque source pixel, when the factory traces it, then its final opacity layer remains `1`.
4. Given a resource whose mask has no alpha sample at or above `96`, when the factory classifies it, then it remains raster.
5. Given either target consumer PDF, when the reusable workflow evaluates it, then the fixed 18 and 72 DPI gates pass without threshold changes.

## Test Design

| Scenario | Instrument | Proof |
| --- | --- | --- |
| 1 | Pure `traceImage` unit test | A mixed-opacity image emits a nonempty low-opacity vector shape. |
| 2 | Pure `traceImage` unit test | Adjacent opacity layers share their normalized contour boundary. |
| 3 | Pure `traceImage` unit test | The final opacity layer serializes at opacity `1`. |
| 4 | Existing `classifyImage` unit test | A wholly low-alpha image selects `PreserveLowAlphaRaster`. |
| 5 | Factory and consumer visual evaluation | `make evaluate`, report inspection, and both reusable workflow runs pass. |

# References

1. [Reusable factory requirements](/prd/0002-reusable-freeform-site-factory.md)
2. [Vector-first rendering decision](/adr/0001-vector-first-mixed-rendering.md)
3. [Superseded interpolated contours](/bdr/0015-interpolated-traced-svg-contours.md)
4. [Implementation issue](/issues/0013-alpha-layer-traced-svg-artwork.md)
