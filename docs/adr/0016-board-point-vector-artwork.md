---
type: ADR
title: Board-point vector artwork
description: Place traced artwork into board points in the generator so no SVG element rescales coordinates.
status: Accepted
timestamp: 2026-09-27
---
# Board-Point Vector Artwork

## Context

Traced paths were serialized in normalized image coordinates, and the browser placed each artwork with its [affine image transform](/context/glossary.md#affine-image-transform) on an SVG group. On the GCP consumer that transform scales one local unit to as much as 14,794 points.

WebKit culls SVG content against the paint rectangle expressed in local units, stored in fixed point with 1/64-unit precision and truncated. At close zoom the rectangle is smaller than 1/64 of a normalized image, so it collapses. Paths that miss it are culled, and small reconstructed and smooth-traced strokes disappear first. As zoom changes, the truncated rectangle moves, so strokes flicker. Chromium maps cull rectangles conservatively and draws them. The reproduction is recorded in [Issue 0019](/issues/0019-webkit-close-zoom-culling.md).

## Decision

Vector artwork reaches the browser in [board units](/context/glossary.md#board-unit):

- `Factory.Vectorize` returns closed contours of line and cubic segments in normalized image space instead of path text.
- `Factory.Geometry.imagePresentationMatrix` is the only rule that maps image samples, rows counted from the top, onto the board.
- `Factory.Interpreter` uses that presentation matrix for every image placement. Raster image nodes carry it, and the browser applies it unchanged. Vector artwork nodes carry their contours placed through it as board `PathCommand`s.
- `validateScene` rejects empty or non-finite placed paths.
- `Factory.Domain` serializes placed paths as SVG path data in board points, rounded to a thousandth of a point. That is under a tenth of a device pixel at the viewer's maximum zoom of 16× on screens up to 4 device pixels per CSS pixel. Vector artwork JSON nodes carry no matrix.
- `site/runtime.js` draws vector artwork without a transform.

[BDR 0023](/bdr/0023-webkit-close-zoom-visibility.md) owns the observable contract.

## Rejected Alternatives

- Move the transform from each group onto its paths: WebKit then culls correctly, but every transformed path becomes a separate Chromium paint chunk. On the GCP board, uncapped Chromium zoom frames rose from a 7 to 13 ms median to 16 to 17 ms. Paths would also keep sub-1/64-unit local bounds.
- Serialize each placement to text during interpretation: this is compact, but it moves output formatting into the interpreter and takes path validation out of `validateScene`.
- Rewrite path coordinates in the browser at load: the GCP scene needed 3.1 seconds of JavaScript on the build server, and phones are slower.
- Keep the group transform and reduce maximum zoom: WebKit already loses strokes at 4× on the GCP board.

## Consequences

WebKit and Chromium render the same close-up artwork. Across six rounds on the generated GCP site, uncapped Chromium zoom frames have a 3 to 9 ms median, against 7 to 11 ms before, because no path needs a transform. Board-point coordinates grow the GCP scene script by about 4 percent.

Browser checks cannot observe WebKit culling, so the runtime regression enforces its precondition: vector containers and paths keep board units. Placed board geometry stays in the scene until JSON emission. Strict, unboxed points keep it compact, and strict summary counts let traced resources be collected once validation has forced placement. On the GCP board, the previous and new generators reach the same 2.33 GB of live heap during tracing, which runs before placement.

# References

1. [Viewport-sized SVG](/adr/0015-viewport-sized-svg.md)
2. [WebKit close-zoom visibility](/bdr/0023-webkit-close-zoom-visibility.md)
3. [Implementation record](/issues/0019-webkit-close-zoom-culling.md)
