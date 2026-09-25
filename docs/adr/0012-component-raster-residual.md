---
type: ADR
title: Component raster residual
description: Keep untraceable connected components of traced artwork as a source raster residual.
status: Accepted
timestamp: 2026-09-25
---
# Component Raster Residual

## Context

[ADR 0001](/adr/0001-vector-first-mixed-rendering.md) traces substantially transparent image resources as a whole. Four successive tracing refinements ([BDR 0014](/bdr/0014-smooth-traced-svg-artwork.md) through [BDR 0017](/bdr/0017-preserve-local-traced-detail.md)) improved contour geometry but kept a fixed alpha floor. Freeform downsamples large artwork groups to 4,096 pixels per side, and the GCP consumer contains traced images at 20 to 60 pixels per inch. Their handwriting strokes are narrower than a source pixel. A fixed contour threshold cannot represent a stroke whose peak coverage is 30 to 60 percent: it either drops the stroke or, with a lower floor, bloats it. [Issue 0013](/issues/0013-alpha-layer-traced-svg-artwork.md) already measured that lower floors and more opacity bins grow the GCP scene from 39 MB to between 51 and 222 MB, or exceed the fixed point limit.

## Decision

`Factory.Vectorize` partitions each traceable image into 8-connected visible components. A component whose alpha below the vector floor (`88`) exceeds a quarter of its total alpha stays raster; every other component is traced as before. `Factory.Pdf` writes the untraceable components as one PNG residual under the resource's asset name, and `Factory.Interpreter` emits a vector node followed by an image node with the same placement. The scene schema and browser runtime do not change. [BDR 0019](/bdr/0019-raster-residual-for-untraceable-strokes.md) owns the observable behavior.

The site still distinguishes traced vector artwork from raster content: residual pixels are the unmodified source samples that the tracer cannot represent, emitted as an ordinary raster image node.

The `0.25` bound came from inspecting real components on either side of it. Components losing up to 25 percent of their ink traced into readable letters. Components losing 25 to 35 percent already showed broken or blotchy strokes as vector. On the GCP consumer the bound moves 0.14 percent of all traced ink, in 15 of 575 traced resources, to raster; on the Algorithms consumer it moves two negligible components.

## Rejected Alternatives

- Lower the alpha floor or add opacity bands: bloated or haloed strokes, much larger scenes, and point-limit failures.
- Rasterize whole resources below a resolution cutoff: this uses geometry as a proxy for fidelity and discards crisp vector strokes that trace well in the same resource.
- Split components where the traced region becomes disconnected: faint anti-aliasing halos bridge separate letters, so this flagged healthy artwork and moved over 9 percent of GCP ink to raster.
- Reconstruct centerlines of thin strokes: this invents geometry that the PDF does not contain.

## Consequences

Sub-pixel handwriting renders like a PDF viewer: smooth at reading zoom and soft at extreme zoom, because the source contains no more detail. Components that trace well stay resolution-independent. Mixed resources add one PNG asset each; on the GCP consumer, 15 residual PNGs add about 0.75 MB while the scene script shrinks by about 0.7 MB. Labeling is linear in image pixels and did not measurably change build time. A traced resource that covers the whole board and has an untraceable component fails existing full-board raster validation instead of deploying.

# References

1. [Vector-first mixed rendering](/adr/0001-vector-first-mixed-rendering.md)
2. [Raster residual behavior](/bdr/0019-raster-residual-for-untraceable-strokes.md)
3. [Implementation issue](/issues/0015-raster-residual-for-untraceable-strokes.md)
