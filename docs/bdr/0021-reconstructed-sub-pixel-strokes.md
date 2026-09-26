---
type: BDR
title: Reconstructed sub-pixel strokes
description: Redraw narrow single-color sub-pixel strokes as crisp opaque curves, keeping the raster residual for other untraceable marks.
status: Accepted
supersedes: "0020"
timestamp: 2026-09-26
---
# Reconstructed Sub-Pixel Strokes

## Context

Under [BDR 0020](/bdr/0020-smooth-thin-stroke-tracing.md), handwriting narrower than a source pixel stayed in a raster residual, which blurs at high zoom. The investigation is recorded in [Issue 0017](/issues/0017-reconstruct-sub-pixel-strokes.md).

## Description

For an image already classified as traceable, the factory divides visible pixels (alpha above `0`) into 8-connected components and represents each one in one of four ways:

- **Reconstructed stroke.** The component's alpha below `88` exceeds a quarter of its total alpha, and it is a narrow, single-color stroke of opaque ink. Narrow and single-color are measured over its pixels at or above half its peak alpha (rounded up): twice their count is less than three times the count of those pixels with a 4-neighbor below that level or outside the image, and they share one quantized color. The peak alpha must be at least `48`.
  - The component's alpha is interpolated with a Keys bicubic kernel on a grid four times finer per axis. Negative values become zero, and each sample is divided by the maximum within three samples in both axes.
  - Samples whose neighborhood maximum is below `24` are zero. The contour at `0.6` is simplified with the existing tolerance and emitted as the bounded cubic curves of BDR 0020, filled at opacity `1` in the stroke's color.
- **Raster residual.** Any other component whose alpha below `88` exceeds a quarter of its total alpha keeps its source pixels in one lossless PNG residual.
- **Smooth trace.** As BDR 0020 specifies.
- **Pixel trace.** As [BDR 0017](/bdr/0017-preserve-local-traced-detail.md) specifies.

Pixel-traced, smooth-traced, and reconstructed shapes form one vector artwork node, followed by the raster residual when present, with identical matrix, opacity, and clips. A resource whose components all use pixel tracing produces the same vector artwork as before. Components are 8-connected, so separating one never changes another's trace. Resource classification, color quantization, source ordering, the complexity limit, evaluation thresholds, the scene schema, and the browser runtime remain unchanged.

`visual-explanations/0021-reconstructed-strokes.svg` shows the untraceable branch splitting into reconstruction and raster residual inside `Factory.Vectorize`. Reviewers must verify three things:

- sub-pixel handwriting is crisp and continuous at high zoom;
- translucent and faint marks keep the raster residual;
- both fixed visual gates pass.

The existing SVG cleanup workflow deletes this PR-only artifact from `main` after merge.

## Scenarios and Test Design

| Given / When / Then | Instrument and proof |
| --- | --- |
| 1. Given a narrow sub-pixel stroke, when partitioned, then it is reconstructed. | Pure `partitionArtwork` test. |
| 2. Given a wide translucent mark, or a mark whose peak is below `48`, when partitioned, then it stays raster. | Two pure partition tests. |
| 3. Given a sub-pixel stroke beside thick artwork, when partitioned, then the stroke is reconstructed and the thick trace is unchanged. | Pure partition-pixel and trace-equality tests. |
| 4. Given a component just above a quarter untraced ink, when partitioned, then it leaves tracing. | Pure boundary test. |
| 5. Given a narrow stroke, when reconstructed, then it is one closed cubic contour of opaque ink. | Pure path-shape test. |
| 6. Given a shallow sub-pixel stroke whose peak dips where it straddles rows, when traced, then pixel tracing splits it while reconstruction keeps one contour. | Pure contour-count test. |
| 7. Given the same input twice, when reconstructed, then the output is identical. | Pure determinism test. |
| 8. Given the BDR 0020 scenarios, when rebuilt, then they still hold. | Existing smooth-trace and partition tests. |
| 9. Given both consumers, when rebuilt, then sub-pixel handwriting is crisp at 8× zoom and both whole-board gates pass. | Real-source before/after crops and consumer `make evaluate`. |

# References

1. [Reusable factory requirements](/prd/0002-reusable-freeform-site-factory.md)
2. [Sub-pixel stroke reconstruction decision](/adr/0014-reconstruct-sub-pixel-pen-strokes.md)
3. [Superseded smooth thin-stroke behavior](/bdr/0020-smooth-thin-stroke-tracing.md)
4. [Implementation issue](/issues/0017-reconstruct-sub-pixel-strokes.md)
