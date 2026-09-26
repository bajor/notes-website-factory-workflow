---
type: BDR
title: Smooth thin-stroke tracing
description: Trace thin single-color strokes at their source weight as smooth curves, beside pixel tracing and the raster residual.
status: Accepted
supersedes: "0019"
timestamp: 2026-09-26
---
# Smooth Thin-Stroke Tracing

## Context

[BDR 0019](/bdr/0019-raster-residual-for-untraceable-strokes.md) moved strokes narrower than a source pixel to a raster residual and traced every other component as [BDR 0017](/bdr/0017-preserve-local-traced-detail.md) specifies. In images that Freeform downsampled to 20 to 60 pixels per inch, lettering one to three pixels wide still traced visibly bolder and blockier than the source. The pixel tracer places edges at alpha `95.5`, about 37 percent coverage, instead of the 50 percent edge of opaque ink, and joins straight segments whose vertices sit on the coarse pixel grid. The investigation is recorded in [Issue 0016](/issues/0016-smooth-thin-stroke-tracing.md).

## Description

For an image already classified as traceable, the factory divides visible pixels (alpha above `0`) into 8-connected components and represents each one in one of three ways:

- **Raster residual.** A component whose alpha below `88` exceeds a quarter of its total alpha keeps its source pixels in one lossless PNG residual, as in BDR 0019.
- **Smooth trace.** Otherwise, a component is thin when twice its count of pixels at alpha `128` or above is less than three times the count of those pixels with a 4-neighbor below `128` or outside the image. That identifies strokes up to about three pixels wide. A thin component whose pixels at alpha `88` or above share one quantized color is traced from a bicubic field supersampled four times per axis. Its contour level is chosen so the enclosed area equals the component's ink area (total alpha divided by `255`). The contour is simplified with the existing tolerance and emitted as closed cubic curves at opacity `1`. Each point's tangent follows its neighbors, each handle reaches at most a third of its own segment, and turns sharper than 120 degrees remain corners.
- **Pixel trace.** Every other component is traced exactly as BDR 0017 specifies.

A resource whose components all use pixel tracing produces the same vector artwork as before BDR 0019. Pixel-traced and smooth-traced shapes form one vector artwork node, followed by the raster residual when present, with identical matrix, opacity, and clips. Components are 8-connected, so separating one never changes another's trace. Resource classification, color quantization, opacity layers, source ordering, the complexity limit, evaluation thresholds, the scene schema, and the browser runtime remain unchanged.

`visual-explanations/0020-smooth-thin-strokes.svg` shows the three-way partition inside `Factory.Vectorize`. Reviewers must verify that low-resolution lettering is lighter and smooth, that solid dots at stroke ends stay solid, that native-resolution artwork is effectively unchanged, and that both fixed visual gates pass. The existing SVG cleanup workflow deletes this PR-only artifact from `main` after merge.

## Scenarios and Test Design

| Given / When / Then | Instrument and proof |
| --- | --- |
| 1. Given thick artwork, when partitioned, then the complete source image is pixel-traced unchanged. | Pure `partitionArtwork` test. |
| 2. Given a sub-pixel stroke alone or beside thick artwork, when partitioned, then it moves to the residual and the thick trace is unchanged. | Existing pure partition, pixel, and trace-equality tests. |
| 3. Given a component at exactly or just above a quarter untraced ink, when partitioned, then it stays vector or becomes raster respectively. | Two pure boundary tests. |
| 4. Given a thin single-color stroke, when partitioned, then it is smooth-traced; given a thin multicolor stroke, then it keeps pixel tracing. | Two pure partition tests. |
| 5. Given a one-pixel opaque line, when smooth-traced, then it is one closed cubic contour whose enclosed area is within 20 percent of its ink area. | Pure path-shape and sampled-curve area tests. |
| 6. Given a long line ending in a dot, when smooth-traced, then no handle exceeds a third of its segment. | Pure handle-bound test. |
| 7. Given a thin line, when smooth-traced, then its sharp ends remain corners. | Pure corner test. |
| 8. Given the same input twice, when smooth-traced, then the output is identical. | Pure determinism test. |
| 9. Given both consumers, when rebuilt, then low-resolution lettering reads closer to the Poppler reference and both whole-board gates pass. | Real-source before/after crops and consumer `make evaluate`. |

# References

1. [Reusable factory requirements](/prd/0002-reusable-freeform-site-factory.md)
2. [Supersampled thin-stroke tracing decision](/adr/0013-supersampled-thin-stroke-tracing.md)
3. [Component raster residual decision](/adr/0012-component-raster-residual.md)
4. [Superseded raster residual behavior](/bdr/0019-raster-residual-for-untraceable-strokes.md)
5. [Implementation issue](/issues/0016-smooth-thin-stroke-tracing.md)
