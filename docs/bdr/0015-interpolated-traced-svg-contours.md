---
type: BDR
title: Interpolated traced SVG contours
description: Trace vector-artwork contours at source alpha crossings instead of source-pixel cell boundaries.
status: Accepted
supersedes: "0014"
timestamp: 2026-09-16
---
# Interpolated Traced SVG Contours

## Context

BDR 0014 increased contour simplification to four square source pixels. The target consumer showed that this removes too much handwritten detail and produces visibly low-polygon SVG artwork. Returning only to the former one-square-pixel boundary trace would retain pixel-grid staircases rather than matching the source PDF's anti-aliased edges.

## Description

The factory continues to classify every traceable artwork resource as vector artwork. It derives each style contour from the source alpha `96` crossing between adjacent samples, emitting fractional source-image coordinates instead of pixel-cell boundaries. When that crossing collapses every contour of a style at the discrete alpha cutoff, it uses the existing pixel-cell boundary for that style so supported visible source pixels cannot become an empty SVG path. It then simplifies contours with a fixed squared perpendicular error limit of `0.25` source pixels. Contours remain linear SVG paths, preserve closed regions and holes, and fail before emission when their structural point count exceeds the existing fixed limit. Classification, RGB quantization, low-alpha raster behavior, source order, clipping, and affine presentation remain unchanged.

## Scenarios

1. Given an anti-aliased diagonal traceable stroke, when the generated site renders it at high zoom, then its SVG contour contains fractional diagonal coordinates rather than repeated horizontal and vertical pixel steps.
2. Given a source alpha ramp crossing `96`, when the factory traces it, then the contour crosses the sample edge at the linearly interpolated source coordinate.
3. Given adjacent traceable regions with different quantized colors, when the factory traces them, then their contours meet at the same source coordinate without a gap or overlap.
4. Given a rectangular traceable region or a traceable region containing a transparent hole, when the factory traces it, then closed contour topology remains valid.
5. Given traceable artwork exceeding the fixed structural point limit, when the factory traces it, then the build fails explicitly before emitting a Pages artifact.
6. Given the target consumer PDF, when the factory builds and evaluates it, then traceable artwork remains SVG and the fixed 18 and 72 DPI visual gates pass without threshold changes.
7. Given a traceable pixel exactly at alpha `96`, when interpolation would collapse its contour, then the factory emits a non-empty closed pixel-cell trace.

## Test Design

| Scenario | Instrument | Proof |
| --- | --- | --- |
| 1 | Pure `traceImage` unit test | An anti-aliased diagonal serializes fractional diagonal contour positions. |
| 2 | Pure `traceImage` unit test | A known alpha ramp serializes the expected crossing coordinate. |
| 3 | Pure `traceImage` unit test | Adjacent styles share their interpolated boundary coordinate. |
| 4 | Existing rectangle and hole `traceImage` unit tests | Closed outer regions and holes remain separate contours. |
| 5 | Pure `traceImage` unit test | A fixed complexity limit rejects before serialization. |
| 6 | Factory and consumer visual evaluation | `make evaluate`, report inspection, and reusable workflow evidence pass both fixed scales. |
| 7 | Pure `traceImage` unit test | A one-pixel alpha-`96` image serializes a non-empty closed path. |

# References

1. [Reusable factory requirements](/prd/0002-reusable-freeform-site-factory.md)
2. [Vector-first rendering decision](/adr/0001-vector-first-mixed-rendering.md)
3. [Superseded smooth-contour behavior](/bdr/0014-smooth-traced-svg-artwork.md)
4. [Implementation issue](/issues/0012-interpolated-traced-svg-contours.md)
