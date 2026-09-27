---
type: ADR
title: Vector-first mixed rendering
description: Use traced inline SVG for Freeform artwork and raster files for screenshots.
status: Accepted
timestamp: 2026-08-20
---
# Vector-First Mixed Rendering

## Context

The source PDF contains 44 image XObjects but no recoverable Freeform object geometry. Most artwork resources have substantial transparent backgrounds; screenshots and diagrams are opaque or nearly opaque.

## Decision

Use automatic soft-mask classification. Trace substantially transparent resources into deterministic SVG contours, preserve opaque and near-opaque resources as raster, and fail the build for the ambiguity interval. Render both resource kinds in one board-sized SVG so their PDF source order is retained.

[ADR 0005](/adr/0005-preserve-low-alpha-soft-masks-as-raster.md) refines this decision for masks whose source samples are nonzero but all below the vector tracer's alpha cutoff; those masks remain raster.

On 2026-09-26, [ADR 0015](/adr/0015-viewport-sized-svg.md) supersedes the board-sized browser surface with a viewport-sized SVG. The mixed representation and source-order decision remain in force.

## Rejected Alternatives

- Preserve all 44 resources as raster: visually faithful at one scale but pixelated when zoomed and fails the vector-first goal.
- Trace all 44 resources: damages screenshots, code samples, and video thumbnails by replacing genuine raster detail with quantized contours.
- Reconstruct semantic handwriting and shapes: impossible from this PDF without guessing or OCR because the original Freeform geometry is absent.

## Consequences

Zoomed artwork remains resolution-independent. Tracing is lossy and increases generated scene JSON, while only nine raster files are deployed. Pure classification and tracing are owned by `Factory.Vectorize`; `Factory.Pdf` owns decoding and materialization; `site/runtime.js` owns SVG rendering.

# References

1. [Observed source profile](/pdf-investigation.md)
2. [Vector-first product requirements](/prd/0001-vector-first-static-site.md)
