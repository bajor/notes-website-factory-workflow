---
type: ADR
title: Reconstruct sub-pixel pen strokes
description: Redraw narrow single-color untraceable strokes as crisp vector ink from a locally normalized field instead of a soft raster residual.
status: Accepted
timestamp: 2026-09-26
---
# Reconstruct Sub-Pixel Pen Strokes

## Context

[ADR 0012](/adr/0012-component-raster-residual.md) keeps components that lose most of their ink below the vector alpha floor as a lossless raster residual. On the GCP consumer that residual holds handwriting from images Freeform downsampled to 20 to 60 pixels per inch. At reading zoom it matches the PDF; at high zoom it is a grey blur, and the site owner asked for it to be sharp.

Such a stroke is opaque pen ink narrower than a source pixel. Its peak alpha swings along its length: high where it lines up with a pixel, about half where it straddles two. Every single-level approach failed on the real handwriting ([Issue 0016](/issues/0016-smooth-thin-stroke-tracing.md)). The pixel tracer and a per-component ink-area level both break the strokes into fragments. A level low enough to stay connected yields wide, faint blobs.

## Decision

`Factory.Vectorize` adds a fourth component outcome. [BDR 0021](/bdr/0021-reconstructed-sub-pixel-strokes.md) owns the exact thresholds.

- **Which components.** An untraceable component is reconstructed when all three hold:
  - it is narrow when measured at half its own peak alpha, using the thin-stroke test of [ADR 0013](/adr/0013-supersampled-thin-stroke-tracing.md);
  - its pixels at half its peak or above share one quantized color;
  - its peak alpha is at least `48`.
- **How it is traced.** The same bicubic ×4 tiles are divided by the maximum of each sample's 7×7 neighborhood, so every point on the stroke's ridge reads about one however bright the source is there. The contour at `0.6` of that ridge then follows the stroke continuously.
- **Output.** Bounded cubic curves filled as opaque ink in the component's color.
- **Everything else is unchanged.** Wide translucent marks, faint smudges below the peak floor, and multicolor components keep the raster residual; thick and thin traceable components keep their existing tracers.

This deliberately trades one fidelity property for another. The source samples say where the ink is, but not how dark a sub-pixel stroke is. The reconstruction assumes opaque ink of the sampled color, which is true of Freeform pens. That assumption is why wide translucent marks, such as highlighter strokes, are excluded by the half-peak width test. The geometry is an iso-contour of the normalized source samples; no text, stroke, or shape is added that the samples do not show.

## Rejected Alternatives

- Keep the raster residual: faithful to the PDF, but soft at high zoom, which is the reported problem.
- Contour at a per-component ink-area level: breaks strokes wherever the peak dips.
- Translucent strokes at an ink-capturing level: connected, but wide and illegible.
- Skeleton extraction with a fixed stroke width: needs junction and loop handling that fails on letters a few pixels tall, and invents a width the samples do not constrain.
- A guard to keep very small writing raster. Six component measures failed to separate a note with a 2–3-pixel x-height from legible 5–12-pixel handwriting: thickness, footprint fill, re-imaging correlation, gap closing, curvature, and counter opening. Such writing gains no legibility from either rendering, and it is rare (about 1 to 3 of 215 GCP residual components).

## Consequences

On GCP, raster assets drop from 16 to 12, asset bytes from about 868 KB to 516 KB, and the scene script grows about 1.6 percent. Build time grows by about 25 seconds. Reconstructed strokes are crisp at every zoom but carry more ink than their blurred source, so board ink ratios rise slightly within the fixed gates. Writing whose letters are only two or three source pixels tall becomes crisp but remains hard to read, as it is in the PDF. Genuinely soft or translucent marks keep their raster residual.

# References

1. [Component raster residual](/adr/0012-component-raster-residual.md)
2. [Supersampled thin-stroke tracing](/adr/0013-supersampled-thin-stroke-tracing.md)
3. [Reconstructed sub-pixel stroke behavior](/bdr/0021-reconstructed-sub-pixel-strokes.md)
4. [Implementation issue](/issues/0017-reconstruct-sub-pixel-strokes.md)
