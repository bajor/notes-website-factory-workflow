---
type: Issue
title: Stabilize close zoom
description: Bound the SVG rendering surface, verify close-up navigation, and redeploy the GCP consumer.
status: In Progress
timestamp: 2026-09-27
---
# Stabilize Close Zoom

## Evidence and Scope

The owner reports that parts of the GCP board disappear while zooming closely. The deployed consumer commit is `0070a6dabd70e2ea0ebc13bc58a2d81acd1135ca`, built by [run 36250823168](https://github.com/bajor/notes-gcp-storage-and-data-processing-engines/actions/runs/36250823168). Its runtime and stylesheet match factory `b6462f7`.

The board is 28,464.39 by 18,857.34 points. The old SVG inherits CSS scaling, reaching approximately 455,430 by 301,717 CSS pixels at 16×. Local Chromium software and SwiftShader GPU animation captures did not reproduce the reported disappearance. They did confirm that zoom uses compositor raster tiles over the scaled surface. A viewport-sized prototype preserves visible detail through 4× to 16× zoom and bounds the SVG independently of board size.

Implements [ADR 0015](/adr/0015-viewport-sized-svg.md) and [BDR 0022](/bdr/0022-bounded-zoom-rendering.md). The change targets browser rendering; generated source content is unchanged.

## Plan

1. Move SVG zoom into its coordinate window and retain the shared camera for HTML overlays.
2. Add a browser regression for the surface bound, anchored zoom, and overlay alignment.
3. Run factory gates, inspect real-consumer close-up captures, and review the PR.
4. Merge, redeploy the GCP consumer, and verify the published viewer.
5. Remove legacy GitHub Pages deployments from the factory repository as requested.

## Verification

- Baseline: all 107 tests, runtime checks, and factory visual comparisons pass. The initial build hit a full `/tmp`; repeating with a dedicated disk-backed `TMPDIR` passed.
- The new high-zoom regression fails on the deployed runtime because the SVG exceeds the viewport. The corrected runtime passes the surface, requested-scale, anchor, overlay, keyboard-pan, and Fit checks.
- `make test` passes all 107 tests. `make evaluate` passes with zero difference at 18 and 72 DPI; its report and enlarged captures were inspected. The runtime suite also passes after the final regression assertions.
- Evaluation exposed a late Chromium viewport resize; evaluation mode now updates its coordinate window on resize while retaining its requested scale and offset.
- [PR #37](https://github.com/bajor/notes-website-factory-workflow/pull/37) passed reusable-workflow CI. The configured Claude `/review` timed out; a fresh, focused Claude review completed with no blocking findings. Its fractional-viewport precision finding was fixed with exact rendered dimensions and a fractional-size browser fixture.
- Real-source verification inspected 102 GPU-rendered zoom frames with no blank content frame, plus all six 4× and 8× detail crops. The crops retain the deployed artwork with small antialiasing differences.
- The local full-consumer evaluation was interrupted by a server restart. Deployment acceptance requires the consumer's complete reusable-workflow run.

## Acceptance

The linked BDR scenarios pass, the evaluated and reviewed fix is merged, the consumer deployment succeeds and serves the corrected viewer, and the factory's legacy Pages deployment records are removed.
