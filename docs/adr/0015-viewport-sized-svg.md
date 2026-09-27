---
type: ADR
title: Viewport-sized SVG
description: Zoom the SVG coordinate window instead of a board-sized CSS surface.
status: Accepted
timestamp: 2026-09-26
---
# Viewport-Sized SVG

## Context

The board-sized SVG of [ADR 0001](/adr/0001-vector-first-mixed-rendering.md) inherits the board's CSS zoom transform. At close zoom its rendered bounds can reach hundreds of thousands of pixels per axis. Browser compositing and raster tile management then handle an oversized surface even though only a small region is visible. The consumer reports artwork dropping out during close zoom; the investigation and its reproduction limits are recorded in [Issue 0018](/issues/0018-stabilize-close-zoom.md).

## Decision

`site/runtime.js` mounts one viewport-sized SVG beside the transformed HTML board. The same camera state sets the SVG `viewBox` and the HTML board transform in one synchronous update. The SVG owns a white source-board rectangle behind the existing ordered visuals. `site/styles.css` clips the SVG at the viewport and lets pointer events reach the board and its interactive overlays.

This refines only the browser-surface part of ADR 0001. Mixed SVG/raster representation, scene data, affine transforms, clipping, and source order retain their existing ownership and behavior.

## Rejected Alternatives

- Force compositor promotion with `will-change` or a 3D transform: the repository already removed `will-change: transform` to avoid large-board compositor exhaustion. Promotion retains the oversized surface.
- Reduce maximum zoom or revert traced strokes to raster: this removes useful close-up detail rather than fixing the viewer's surface dimensions.
- Split the scene into separately culled or rasterized tiles: this adds ordering, clipping, and cache invalidation work that a native SVG coordinate window avoids.

## Consequences and Verification

The browser may repaint vectors as the coordinate window changes, but the SVG surface remains bounded by viewport dimensions rather than board size times zoom. HTML links and activated embeds keep their existing positioning path. Readiness-only evaluation must clear both sibling scene roots.

The browser regression in `make test-runtime` enforces the surface bound, anchor preservation, and visual/link alignment at high zoom. `make evaluate` checks static rendering against the existing source oracle. [BDR 0022](/bdr/0022-bounded-zoom-rendering.md) owns the acceptance scenarios.

# References

1. [Vector-first mixed rendering](/adr/0001-vector-first-mixed-rendering.md)
2. [Bounded zoom behavior](/bdr/0022-bounded-zoom-rendering.md)
3. [Implementation record](/issues/0018-stabilize-close-zoom.md)
