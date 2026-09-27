---
type: Issue
title: Fix WebKit close-zoom culling
description: Stop traced strokes from flickering in WebKit at close zoom and redeploy the GCP consumer.
status: In Progress
timestamp: 2026-09-27
---
# Fix WebKit Close-Zoom Culling

## Evidence and Scope

After [Issue 0018](/issues/0018-stabilize-close-zoom.md), the owner reports that regions formerly held in the raster residual flicker at very close zoom. Those regions now contain the reconstructed and smooth-traced strokes of [BDR 0021](/bdr/0021-reconstructed-sub-pixel-strokes.md).

Chromium does not reproduce the defect. Captures of the local GCP build at `2` device pixels per CSS pixel draw the strokes at every scale, with both software rasterization and SwiftShader (Chromium's CPU implementation of the GPU interface). A 121-frame continuous zoom also shows no ink drop.

WebKit does reproduce it. The evidence uses the WPE port of WebKit 26.5, WebKit's embedded Linux port, which shares the WebCore SVG paint code with Safari; Playwright downloads a build of it. Missing system libraries were extracted from Ubuntu packages into a private directory, and nothing was installed system-wide. At board point `(7699, 9996)` the handwriting disappears from 4× zoom upward. At two other reconstructed-stroke points no ink remains from 10× through 16×. The deployed GCP site reproduces the same dropout. [ADR 0016](/adr/0016-board-point-vector-artwork.md) records the cause.

Implements ADR 0016 and [BDR 0023](/bdr/0023-webkit-close-zoom-visibility.md).

## Plan

1. Emit vector artwork in board points from the generator and draw it without a transform.
2. Extend the close-zoom browser regression with the board-unit precondition, a clipped mark, and rendered-path alignment.
3. Compare WebKit and Chromium on the real GCP build, measure build memory and zoom frame time, run the factory gates, and review the PR.
4. Merge, redeploy the GCP consumer, and verify the published viewer.

## Verification

- Baseline: `make test` passes all 107 tests. After the change, all 110 pass.
- The close-zoom regression passes, and it fails when an artwork group rescales board units even though its paths compensate and stay aligned.
- An offline board-point variant of the GCP scene matches Chromium in WebKit. Twenty-five aligned captures (five board regions at 1×, 4×, 8×, 12×, and 16×) were compared. The previous scene in WebKit loses ink in both reconstructed-stroke regions from 4× upward and differs in a pixel-traced region at 12×. With per-path transforms or board points, every WebKit capture has Chromium's dark-pixel fraction, and at most 0.0001 of pixels differ in luma by more than `96`.
- Fine WebKit sweeps from 10× to 16× in 0.5× steps change ink smoothly after the fix: `0.129` to `0.197` and `0.0048` to `0.0194` at two stroke points, compared with `0` throughout before.
- Uncapped Chromium continuous zoom on the GCP build, with vsync and the frame-rate limit disabled: the previous scene has a 7 to 13 ms median frame, per-path transforms 16 to 17 ms, and board points 4 to 6 ms. The first review found that capped 30-frame-per-second timing hid the per-path cost.

## Acceptance

The linked BDR scenarios pass, the reviewed fix is merged, and the GCP consumer deployment succeeds and serves the corrected viewer.
