---
type: BDR
title: Raster residual for untraceable strokes
description: Keep traced artwork components as source raster when tracing would drop most of their ink.
status: Accepted
timestamp: 2026-09-25
---
# Raster Residual for Untraceable Strokes

## Context

Freeform caps each embedded image at 4,096 pixels per side, so a large artwork group can arrive at 20 to 60 pixels per inch instead of the usual 216. Handwriting in such an image is narrower than one source pixel: its anti-aliased samples stay mostly below the alpha `88` floor of the vector layers. [BDR 0017](/bdr/0017-preserve-local-traced-detail.md) tracing then keeps only isolated fragments of each word, while a PDF viewer shows the same samples as continuous, readable strokes. The investigation is recorded in [Issue 0015](/issues/0015-raster-residual-for-untraceable-strokes.md).

## Description

For an image already classified as traceable, the factory divides visible pixels (alpha above `0`) into 8-connected components. A component is untraceable when the alpha of its samples below `88` exceeds a quarter of its total alpha; the fixed bound is `0.25`. Components at or under the bound are traced exactly as [BDR 0017](/bdr/0017-preserve-local-traced-detail.md) specifies. Untraceable components are emitted as one lossless PNG residual that keeps their source RGB and alpha and clears every other pixel.

A resource with no untraceable component produces the same vector artwork as before. A resource whose every component is untraceable becomes a raster asset. A mixed resource emits its vector artwork and then its raster residual at the same position, with the same matrix, opacity, and clips. Because 8-connected components never share a 2×2 contour cell, removing a residual component cannot change another component's trace. Resource classification, color quantization, opacity layers, source ordering, the complexity limit, evaluation thresholds, and the browser runtime remain unchanged.

`visual-explanations/0019-raster-residual.svg` contrasts the former all-vector trace with the component partition. `Factory.Vectorize` owns the partition, `Factory.Pdf` materializes the residual, and `Factory.Interpreter` emits both nodes. Reviewers must verify that sub-pixel handwriting reads like the PDF, that fully traceable resources are unchanged, and that both fixed visual gates pass. The existing SVG cleanup workflow deletes this PR-only artifact from `main` after merge.

## Scenarios and Test Design

| Given / When / Then | Instrument and proof |
| --- | --- |
| 1. Given traceable artwork with no untraceable component, when partitioned, then the complete source image is traced unchanged. | Pure `partitionArtwork` test compares the traceable result with the input. |
| 2. Given artwork whose only component keeps most of its ink below alpha `88`, when partitioned, then the resource stays raster. | Pure test expects the untraceable result. |
| 3. Given a sub-pixel stroke beside opaque artwork, when partitioned, then the stroke moves to the residual and the opaque component stays traceable. | Pure test checks the pixels of both images. |
| 4. Given a mixed partition, when its traceable image is traced, then the result equals the trace of the opaque component alone. | Pure test compares both traces. |
| 5. Given a component at exactly a quarter untraced ink, or just above it, when partitioned, then it stays vector or becomes raster respectively. | Two pure boundary tests. |
| 6. Given an opaque pixel diagonally touching a faint pixel, when partitioned, then they form one traceable component. | Pure 8-connectivity test. |
| 7. Given a mixed resource, when interpreted, then a vector node precedes an image node with identical placement. | Pure interpreter test. |
| 8. Given the motivating GCP consumer, when rebuilt, then the broken handwriting reads like the Poppler reference and both whole-board gates pass. | Real-source before/after crops and consumer `make evaluate`. |

# References

1. [Reusable factory requirements](/prd/0002-reusable-freeform-site-factory.md)
2. [Component raster residual decision](/adr/0012-component-raster-residual.md)
3. [Local traced detail behavior](/bdr/0017-preserve-local-traced-detail.md)
4. [Implementation issue](/issues/0015-raster-residual-for-untraceable-strokes.md)
