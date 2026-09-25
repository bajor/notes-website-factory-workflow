---
type: Issue
title: Raster residual for untraceable strokes
description: Stop sub-pixel handwriting from fragmenting and redeploy both consumers.
status: Done
timestamp: 2026-09-25
---
# Raster Residual for Untraceable Strokes

## Evidence and Scope

Implements [BDR 0019](/bdr/0019-raster-residual-for-untraceable-strokes.md) using the [component raster residual decision](/adr/0012-component-raster-residual.md). The deployed GCP site from consumer revision `152473810213e651424845f2e79e9f5e7d59c1e8` still rendered readable handwriting as disconnected black and grey fragments after [Issue 0014](/issues/0014-preserve-local-traced-detail.md). Examples are "automatically switches > 90 days" and "very limited compared to enterprise".

The GCP PDF contains 575 soft-masked images. 542 are at 180 pixels per inch or more and lose on average about 4 percent of their ink to the alpha-`88` floor, which is ordinary edge anti-aliasing. Freeform downsampled the largest artwork groups to 4,096 pixels per side, so 19 images are below 100 pixels per inch. The fragmented handwriting sits in `Im31`, a 3,109 × 4,096 image at 45 pixels per inch. Its 176 components visible at alpha `16` split into 754 components at alpha `88`, and the thresholded source reproduces the deployed fragments exactly.

Prototypes of four and six nested opacity bands restored continuity but produced haloed, bloated strokes. [Issue 0013](/issues/0013-alpha-layer-traced-svg-artwork.md) had already measured the scene-size cost of lower floors.

## Plan

1. Partition traceable images into 8-connected components and select the untraced-ink bound from real components.
2. Emit untraceable components as a PNG residual beside unchanged vector artwork.
3. Add focused regressions, living documentation, and the PR-only review SVG.
4. Compare real-source crops with the Poppler reference, run the factory and consumer gates, merge, and redeploy both consumers.

## Acceptance

The BDR test design passes, `make test` and `make evaluate` pass, both consumers pass their evaluation gates, and the motivating crops read like the source PDF.

## Verification

- Bound selection: components losing 19 to 25 percent of their ink traced into readable letters. Components losing 25 to 35 percent already showed broken or blotchy vector strokes. At `0.25` the partition moves 0.14 percent of GCP traced ink, in 15 resources, to raster; a disconnection criterion would have moved 9.3 percent.
- `make test`: 95 tests passed, including 8 added regressions; fixture inspection and distribution validation passed.
- Factory `make evaluate`: 18 and 72 DPI both passed with zero mean error, full within-tolerance fraction, and ink ratio `1`.
- GCP build: 575 vector artworks and 16 raster assets (previously 1), including 15 residual PNGs totaling about 0.75 MB. The scene script shrank from 39,572,106 to 38,857,777 bytes, and build time was unchanged at about 3.6 minutes. Rebuilt 288 DPI crops of both deployed failures are continuous and match the Poppler reference.
- Algorithms build: 41 vector artworks and 11 raster assets (previously 9). The two residuals are 14-pixel specks. `make evaluate` passed: 18 DPI `0.002828299`, `0.982929377`, `1.094038948`, and 72 DPI `0.002168049`, `0.984938977`, `1.140308725` (mean error, within-tolerance fraction, ink ratio).
- GCP `make evaluate` passed against the unchanged consumer revision: 18 DPI `0.002250068`, `0.992076326`, `1.017644684`, and 72 DPI `0.001416881`, `0.994935032`, `1.045841351`. Both error metrics improved on Issue 0014's values, and distribution validation passed. Of the three inspected zoom-detail crops, two match the reference. The third shows low-resolution lettering that stays traceable and renders bolder and blockier than the reference; that behavior is unchanged by this issue.
- [PR #34](https://github.com/bajor/notes-website-factory-workflow/pull/34) delivers the change.
- Local evaluation needs Playwright's `headless_shell`. The container's new-headless `chrome` returned a viewport shorter than `--window-size`, which made the unmodified `main` fixture fail too.
