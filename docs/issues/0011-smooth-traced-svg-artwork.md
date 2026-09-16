---
type: Issue
title: Smooth traced SVG artwork
description: Remove pixel-grid stair stepping from traceable SVG artwork while preserving vector classification.
status: Done
timestamp: 2026-09-16
---
# Smooth Traced SVG Artwork

## Scope

Implement [BDR 0014](/bdr/0014-smooth-traced-svg-artwork.md) for all existing traceable artwork without new workflow inputs, source-specific rules, or raster fallback.

## Acceptance Criteria

- Pixel-grid contour staircases are simplified within the fixed four-square-pixel tolerance.
- Closed contours, holes, source ordering, clipping, colors, alpha classification, and affine presentation remain unchanged.
- Every resource currently classified as traceable artwork remains a vector-artwork scene node.
- Focused unit tests, `make test`, and `make evaluate` pass.
- The target consumer passes the reusable workflow's fixed 18 and 72 DPI evaluation and deploys successfully.

## Plan

1. Increase the fixed contour simplification tolerance after deterministic boundary extraction.
2. Preserve the existing SVG path serialization and image classification.
3. Test simplified diagonal output and unchanged rectangle and hole topology.
4. Validate the synthetic fixture and target consumer before merging and redeploying.

## Completion

Factory pull request [#26](https://github.com/bajor/notes-website-factory-workflow/pull/26) merged at `6baf86e7ff6e1830c6739664820434567753ecfc`. `make test` and `make evaluate` passed before merge; the fixture report passed both fixed scales with zero difference. The [target consumer deployment run](https://github.com/bajor/notes-gcp-storage-and-data-processing-engines/actions/runs/35107883161) passed the build, 18 and 72 DPI evaluation, Pages artifact upload, and deployment. Its reusable workflow referenced the factory merge SHA, and the deployed site returned HTTP `200` on 2026-09-16.

# References

1. [Smooth traced SVG artwork behavior](/bdr/0014-smooth-traced-svg-artwork.md)
2. [Reusable factory requirements](/prd/0002-reusable-freeform-site-factory.md)
