---
type: Issue
title: Reconstruct sub-pixel strokes
description: Make soft sub-pixel handwriting crisp at high zoom and redeploy both consumers.
status: Done
timestamp: 2026-09-26
---
# Reconstruct Sub-Pixel Strokes

## Evidence and Scope

Implements [BDR 0021](/bdr/0021-reconstructed-sub-pixel-strokes.md) using the [sub-pixel stroke reconstruction decision](/adr/0014-reconstruct-sub-pixel-pen-strokes.md). After [Issue 0016](/issues/0016-smooth-thin-stroke-tracing.md), GCP handwriting kept in the raster residual matched the PDF at reading zoom but blurred at high zoom. Examples: *automatically switches > 90 days*, *QUERY VALIDATOR (bytes read)*, and the *BQ itself optimizes queries* block. The site owner asked for it to be sharp.

## Plan

1. Find a representation that stays connected where a sub-pixel stroke's peak alpha dips, and test it against the soft raster on real crops.
2. Look for a guard that keeps writing too small to resolve as raster.
3. Implement the reconstruction path, focused regressions, living documentation, and the review SVG.
4. Compare real-source crops, run the factory and consumer gates, merge, and redeploy both consumers.

## Acceptance

The BDR test design passes, `make test` and `make evaluate` pass, both consumers pass their evaluation gates, and sub-pixel handwriting is crisp and continuous at 8× zoom.

## Verification

- Prototype: dividing the bicubic ×4 field by its local maximum produced continuous, legible strokes at 8× and 24×. Level `0.55` was bolder, `0.65` broke some stems, and `0.6` was chosen.
- Guard search: six component measures failed to separate the 2–3-pixel x-height note *very limited compared to enterprise* from legible handwriting: thickness, footprint fill, re-imaging correlation, gap closing, curvature, and counter opening. A contact sheet of 215 GCP residual components showed crisp, faithful results for nearly all; roughly one to three tiny notes gain no legibility. At 8× the note reads about as well as its blur; at 16× both are unreadable.
- A synthetic 2-pixel-period alternation broke the reconstruction; that pattern is harsher than real ink. The regression uses an anti-aliased stroke of slope 1/4 instead: pixel tracing splits it into several pieces, and reconstruction keeps one contour.
- `make test`: 107 tests passed; fixture inspection and distribution validation passed. Factory `make evaluate` passed with zero error at 18 and 72 DPI.
- GCP build: 575 vector artworks and 12 raster assets (previously 16), with asset bytes down from about 868 KB to 516 KB. The scene script grew from 39,463,001 to 40,106,475 bytes, and build time grew from about 3.9 to 4.3 minutes. At 8× zoom, rebuilt crops of all three motivating regions are crisp and continuous.
- GCP `make evaluate` passed: 18 DPI `0.002274209`, `0.992003643`, `1.017214088`, and 72 DPI `0.001478793`, `0.994795893`, `1.045405679` (mean error, within-tolerance fraction, ink ratio). These are slightly further from the Poppler reference than Issue 0016, because opaque reconstructed ink differs from Poppler's blur of the same strokes; all stay well inside the fixed thresholds. Distribution validation passed, and the inspected zoom-detail crops are unchanged except that a formerly soft underscore is now crisp.
- Algorithms `make evaluate` passed with metrics unchanged to five significant digits: 18 DPI `0.002817529`, `0.98296802`, `1.089428812`, and 72 DPI `0.002162035`, `0.984945058`, `1.135112513`.
