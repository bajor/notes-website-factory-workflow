---
type: Issue
title: Preserve faint traced SVG artwork
description: Retain faint mixed-resource source ink through fixed-opacity SVG layers.
status: In Progress
timestamp: 2026-09-16
---
# Preserve Faint Traced SVG Artwork

## Scope

Implement [BDR 0016](/bdr/0016-alpha-layer-traced-svg-artwork.md) without changing workflow inputs, browser runtime, generated scene ownership, resource classification boundaries, or evaluation thresholds.

## Acceptance Criteria

- Mixed traceable resources retain faint nonzero-alpha source strokes as SVG shapes with fixed quantized opacity.
- Whole low-alpha resources remain raster.
- Fully opaque artwork remains fully opaque.
- Focused alpha-layer tests, `make test`, `make evaluate`, and both consumer reusable-workflow evaluations pass.

## Validation Progress

- `make test` passed with 75 tests, and `make evaluate` passed the inspected synthetic 18 and 72 DPI report.
- The real GCP consumer build produced a 39,117,397-byte scene. Lower faint-layer boundaries produced 51,367,087 bytes at alpha `80`, 74,608,821 bytes at alpha `64`, and 222,253,060 bytes when all nonzero alpha was binned; 16 and 8 opacity-bin attempts exceeded the fixed structural point limit.
- The real Algorithms consumer build produced a 13,913,202-byte scene.

# References

1. [Alpha-layer behavior](/bdr/0016-alpha-layer-traced-svg-artwork.md)
2. [Prior contour issue](/issues/0012-interpolated-traced-svg-contours.md)
