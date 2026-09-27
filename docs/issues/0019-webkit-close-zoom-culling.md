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

1. Present images and place vector artwork in board points in the generator, and draw artwork without a transform.
2. Extend the close-zoom browser regression with the board-unit precondition, a clipped mark, and rendered-path alignment.
3. Compare WebKit and Chromium on the real GCP build, measure build memory and zoom frame time, run the factory gates, and review the PR.
4. Merge, redeploy the GCP consumer, and verify the published viewer.

## Verification

- Baseline: `make test` passes all 107 tests. After the change, all 110 pass. Reducing serialization to one decimal place fails both serialization tests.
- The close-zoom regression passes. It fails when an artwork group rescales board units even though its paths compensate and stay aligned.
- `make evaluate` passes with zero difference at 18 and 72 DPI, including the runtime checks.
- First review: per-path transforms, the first fix, measured "unchanged" only because headless timing was capped at 30 frames per second. Uncapped runs showed a 16 to 17 ms median frame against 7 to 13 ms before, so board points replaced them.
- Second review: a text-serializing placement design retained traced resources through lazy summary counts, split validation away from `validateScene`, and duplicated the image orientation rule in JavaScript. These were corrected before the final build.
- [Consumer verification run 36317241606](https://github.com/bajor/notes-gcp-storage-and-data-processing-engines/actions/runs/36317241606) built the real GCP board on a temporary consumer branch pinned to the PR, which cannot deploy. Results, in order mean error, within-tolerance fraction, and ink ratio: 18 DPI `0.002270884`, `0.992007129`, `1.016561687`; 72 DPI `0.001477913`, `0.994793397`, `1.044616353`. These match the deployed site within `0.0002`, including all six zoom-detail crops. The scene script grew 4.3 percent, with the same 575 vector artworks and 12 raster assets.
- On that generated site, 25 aligned Chromium captures (five board regions at 1×, 4×, 8×, 12×, and 16×) are identical to the previous build. WebKit matches Chromium in every capture: at most 0.0001 of pixels differ in luma by more than `96`. Before the change, WebKit lost ink in both reconstructed-stroke regions from 4× upward and differed in a pixel-traced region at 12×.
- Fine WebKit sweeps from 10× to 16× in 0.5× steps change ink smoothly on the generated site: `0.129` to `0.197` and `0.0048` to `0.0194` at two stroke points, compared with `0` throughout before.
- Uncapped Chromium continuous zoom over six rounds, with vsync and the frame-rate limit disabled: median frames of 3 to 9 ms on the generated site against 7 to 11 ms on the previous build, and p95 frames of 10 to 17 ms against 15 to 34 ms.
- Memory: this server cannot build the GCP board with either generator. Under a 2.3 GB heap cap, `origin/main` and the change both overflow at the same 2.33 GB live heap during tracing, which runs before placement.

## Acceptance

The linked BDR scenarios pass, the reviewed fix is merged, and the GCP consumer deployment succeeds and serves the corrected viewer.
