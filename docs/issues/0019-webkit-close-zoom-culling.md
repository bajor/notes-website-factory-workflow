---
type: Issue
title: Fix WebKit close-zoom culling
description: Stop traced strokes from flickering in WebKit at close zoom and redeploy the GCP consumer.
status: In Progress
timestamp: 2026-09-27
---
# Fix WebKit Close-Zoom Culling

## Evidence and Scope

After [Issue 0018](/issues/0018-stabilize-close-zoom.md), the owner reports that regions formerly held in the raster residual flicker at very close zoom. Those regions now contain the reconstructed and smooth-traced strokes of [BDR 0021](/bdr/0021-reconstructed-sub-pixel-strokes.md). Chromium software and SwiftShader GPU captures of the local GCP build at `2` device pixels per CSS pixel draw them at every scale, and a 121-frame continuous zoom shows no ink drop.

Playwright's WPE WebKit 26.5 reproduces the defect. Its missing system libraries were extracted from Ubuntu packages into a private directory; nothing was installed system-wide. At board point `(7699, 9996)` the handwriting disappears from 4× zoom upward, and at two other reconstructed-stroke points no ink remains from 10× through 16×. Each vector artwork group scales normalized paths by up to 14,794 points per unit, and WebKit truncates its group-local paint rectangle to 1/64 of that unit.

Implements [ADR 0016](/adr/0016-transform-traced-paths-individually.md) and [BDR 0023](/bdr/0023-webkit-close-zoom-visibility.md). The change targets browser rendering; generated scene data is unchanged.

## Plan

1. Move the vector artwork transform from each group onto its paths.
2. Extend the close-zoom browser regression with the board-unit precondition and rendered-path alignment.
3. Compare WebKit and Chromium on the real GCP build, run the factory gates, and review the PR.
4. Merge, redeploy the GCP consumer, and verify the published viewer.

## Verification

- Baseline: `make test` passes all 107 tests.
- The extended close-zoom regression fails on the previous runtime with `Vector artwork group changed board units` and passes with the fix.
- Offline variants of the GCP build were compared in WebKit. Board-coordinate paths and per-path transforms both restore the strokes and match Chromium's ink at every sampled scale. Per-path transforms were chosen because they leave the scene schema unchanged.
- Twenty-five aligned captures (five board regions at 1×, 4×, 8×, 12×, and 16×) were compared against Chromium. The previous runtime in WebKit loses ink in both reconstructed-stroke regions from 4× upward and differs in a pixel-traced region at 12×. With the fix, every WebKit capture has Chromium's dark-pixel fraction, and at most 0.0001 of pixels differ in luma by more than `96`.
- Fine WebKit sweeps from 10× to 16× in 0.5× steps change ink smoothly with the fix: `0.129` to `0.197` and `0.0048` to `0.0194` at the two stroke points, compared with `0` throughout before.
- Chromium continuous-zoom frame time on the GCP build is unchanged: 33.3 ms median before and after with SwiftShader GPU rasterization.

## Acceptance

The linked BDR scenarios pass, the reviewed fix is merged, and the GCP consumer deployment succeeds and serves the corrected viewer.
