---
type: ADR
title: Supersampled thin-stroke tracing
description: Trace thin single-color components at their source ink area from a supersampled field and emit bounded cubic curves.
status: Accepted
timestamp: 2026-09-26
---
# Supersampled Thin-Stroke Tracing

## Context

After [ADR 0012](/adr/0012-component-raster-residual.md), low-resolution lettering that the pixel tracer can still represent rendered bolder and blockier than the source. On the motivating GCP lettering, the traced ink was 1.21 times the Poppler reference. Two causes compound. First, the opaque contour sits at alpha `95.5`, about 37 percent coverage, instead of the 50 percent edge of opaque ink; the dilation is a large share of a one-to-three-pixel stroke. Second, marching squares on the source grid produces straight segments between pixel-edge crossings, so each letter is a coarse polygon at reading zoom.

## Decision

`Factory.Vectorize` gives the component partition a third outcome. A traceable component that is thin and single-colored is traced by a separate path. [BDR 0020](/bdr/0020-smooth-thin-stroke-tracing.md) owns the exact thresholds and observable behavior.

1. Evaluate a Keys bicubic interpolation of the component's own alpha on a grid four times finer per axis. Only 16-pixel tiles within three source pixels of the component are evaluated, so long connector lines cost in proportion to their footprint, not their bounding box.
2. Choose the contour level from a histogram of those samples so the enclosed area equals the component's ink area. Weight then matches the source by construction, and dim diagonal runs are not cut by a global level.
3. Assemble marching-squares contours with the existing edge walker and simplification tolerance in source pixels.
4. Emit closed cubic curves. Tangents follow neighboring points, handles reach at most a third of their own segment, and turns sharper than 120 degrees stay corners.

Thick components and multicolor thin components keep the pixel tracer unchanged. Untraceable components keep the raster residual.

## Rejected Alternatives

- Raise the global contour level to 50 percent coverage: weight improves, but thin strokes break where their peak alpha dips, and all native-resolution output changes.
- Round polygon corners without supersampling: facets remain and the weight is unchanged.
- Blur before supersampling: no visible benefit on real lettering, and samples stop depending only on their four-by-four neighborhood.
- Uniform Catmull-Rom curves: a handle sized by a long neighboring segment loops around small features, turning solid dots at line ends into hollow hooks under the even-odd fill.
- Smooth-trace the raster residual too. At its ink-area level, sub-pixel handwriting fragments. At a level that keeps it connected, it becomes wide, faint, illegible strokes. The soft raster remains the most faithful rendering of those samples.

## Consequences

On the GCP consumer, 874 components switch to smooth tracing; 8 more are thin but multicolor and keep pixel tracing. About 89 percent of traceable components below 100 pixels per inch are thin, against under 1 percent at 180 pixels per inch or more. The scene script grows 1.6 percent, and build time grows by about 15 seconds. Path data now contains cubic segments, which the browser renders without runtime changes. Low-resolution lettering stays an approximation of the source samples: it is smooth and weight-true, but it cannot recover detail finer than the source pixels.

# References

1. [Component raster residual](/adr/0012-component-raster-residual.md)
2. [Smooth thin-stroke behavior](/bdr/0020-smooth-thin-stroke-tracing.md)
3. [Implementation issue](/issues/0016-smooth-thin-stroke-tracing.md)
