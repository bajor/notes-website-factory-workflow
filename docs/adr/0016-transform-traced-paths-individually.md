---
type: ADR
title: Transform traced paths individually
description: Apply each vector artwork placement on its paths so SVG containers keep board units.
status: Accepted
timestamp: 2026-09-27
---
# Transform Traced Paths Individually

## Context

Vector artwork paths use normalized image coordinates, and each placement's [affine image transform](/context/glossary.md#affine-image-transform) maps the unit square onto the board. On the GCP consumer that transform scales one local unit to as much as 14,794 points.

WebKit culls the children of a transformed SVG group against the paint rectangle in the group's own units. It stores that rectangle in fixed point with 1/64-unit precision and truncates it. At close zoom the rectangle is smaller than 1/64 of a normalized image, so it collapses, and child paths are culled wherever they miss the truncated rectangle. Small reconstructed and smooth-traced strokes, about 0.0035 image units wide, disappear first. As zoom changes, the truncated rectangle moves, and strokes flicker. Chromium maps cull rectangles conservatively and draws them. The reproduction is recorded in [Issue 0019](/issues/0019-webkit-close-zoom-culling.md).

## Decision

`site/runtime.js` sets the presentation transform on each vector artwork path instead of on its group. The group keeps the node opacity and clips in [board units](/context/glossary.md#board-unit). WebKit then culls each path by its bounds mapped into board units. The scene schema, generated coordinates, source order, clipping, and opacity compositing are unchanged. [BDR 0023](/bdr/0023-webkit-close-zoom-visibility.md) owns the observable contract.

## Rejected Alternatives

- Emit vector artwork in board coordinates from the generator: this also works in WebKit, but it moves per-placement serialization from `Factory.Vectorize` into the interpreter and changes the scene schema for a presentation constraint.
- Rewrite path coordinates in the browser at load: the GCP scene needed 3.1 seconds of JavaScript on the build server, and phones are slower.
- Keep the group transform and reduce maximum zoom: WebKit already loses strokes at 4× on the GCP board.

## Consequences

WebKit and Chromium render the same close-up artwork. Chromium zoom frame time is unchanged on the GCP board. Browser checks cannot observe WebKit culling, so the runtime regression enforces its precondition: every vector artwork group keeps board units. A future runtime change must not add a scaling transform to an SVG container.

# References

1. [Viewport-sized SVG](/adr/0015-viewport-sized-svg.md)
2. [WebKit close-zoom visibility](/bdr/0023-webkit-close-zoom-visibility.md)
3. [Implementation record](/issues/0019-webkit-close-zoom-culling.md)
