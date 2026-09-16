---
type: Issue
title: Interpolate traced SVG contours
description: Replace low-polygon pixel-cell tracing with source-alpha contour interpolation.
status: Done
timestamp: 2026-09-16
---
# Interpolate Traced SVG Contours

## Scope

Implement [BDR 0015](/bdr/0015-interpolated-traced-svg-contours.md) without changing workflow inputs, scene schema, browser runtime, vector/raster classification, or the fixed evaluation thresholds.

## Acceptance Criteria

- Traceable SVG contours use fractional alpha-crossing coordinates.
- The fixed `0.25` square-pixel simplification bound retains visibly more detail than BDR 0014's four-square-pixel bound.
- Closed contours, holes, adjacent style boundaries, source ordering, clipping, and affine placement remain valid.
- Structural point counting rejects excessive complexity before site emission.
- Focused tests, `make test`, factory `make evaluate`, and target-consumer evaluation pass before deployment.

## Plan

1. Replace binary pixel-cell boundary extraction with deterministic style-aware alpha-isocontours.
2. Generalize contour joining and simplification to fractional coordinates.
3. Add focused interpolation, topology, adjacent-style, and determinism tests while preserving the existing complexity guard.
4. Validate against the target consumer, merge the factory change, and redeploy the consumer site.

## Validation Progress

- `make test` passed with 72 tests.
- `make evaluate` passed for the synthetic fixture; the inspected 18 and 72 DPI report recorded zero mean error, a `1.0` pixels-within-tolerance ratio, and a `1.0` ink ratio.
- The target consumer revision `152473810213e651424845f2e79e9f5e7d59c1e8` built with 575 vector artworks, one raster image, and a 24,529,169-byte scene.
- Local target-consumer evaluation remains blocked by the pre-existing Chromium readiness failure before capture. The reusable workflow must provide the required 18 and 72 DPI evidence after this factory change merges.
- The first post-merge Algorithms for Slow Learners run identified a traceable alpha-`96` style that interpolated to an empty vector path and failed scene validation. The follow-up branch adds a per-style pixel-boundary fallback and regression test before retrying deployment.
- Factory pull requests [#28](https://github.com/bajor/notes-website-factory-workflow/pull/28) and [#29](https://github.com/bajor/notes-website-factory-workflow/pull/29) passed reusable-workflow CI. Both target consumers passed their final build, 18 and 72 DPI evaluation, and Pages deployment: [GCP run 35137488717](https://github.com/bajor/notes-gcp-storage-and-data-processing-engines/actions/runs/35137488717) and [Algorithms run 35137488782](https://github.com/bajor/notes-algos-for-slow-learners/actions/runs/35137488782).

# References

1. [Interpolated contour behavior](/bdr/0015-interpolated-traced-svg-contours.md)
2. [Reusable factory requirements](/prd/0002-reusable-freeform-site-factory.md)
