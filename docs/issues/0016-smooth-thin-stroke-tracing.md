---
type: Issue
title: Smooth thin-stroke tracing
description: Replace bold, blocky low-resolution lettering with weight-true curves and redeploy both consumers.
status: Done
timestamp: 2026-09-26
---
# Smooth Thin-Stroke Tracing

## Evidence and Scope

Implements [BDR 0020](/bdr/0020-smooth-thin-stroke-tracing.md) using the [supersampled thin-stroke tracing decision](/adr/0013-supersampled-thin-stroke-tracing.md). After [Issue 0015](/issues/0015-raster-residual-for-untraceable-strokes.md), one GCP zoom-detail crop still showed lettering that renders bolder and blockier than its Poppler reference: *INFORMATION_SCHEMA, JOBS, RESERVATIONS, CAPACITY_COMMITMENTS, TABLE_STORAGE* in the 45-pixels-per-inch image `Im31`. On that crop the pixel trace carried 1.21 times the reference ink.

The same investigation revisited the soft raster residual. Opaque vector reconstructions of its sub-pixel strokes fragmented again. Translucent reconstructions that stay connected turned the handwriting into wide, faint, illegible strokes. The residual therefore stays raster; detail finer than a source pixel can only come from a higher-resolution Freeform export.

## Plan

1. Prototype contour level, supersampling, blur, simplification, and curve variants against the Poppler reference.
2. Classify thin single-color components by stroke thickness and trace them from a supersampled field at their ink-area level.
3. Emit bounded cubic curves, add focused regressions, and update the living documentation and review SVG.
4. Compare real-source crops, run the factory and consumer gates, merge, and redeploy both consumers.

## Acceptance

The BDR test design passes, `make test` and `make evaluate` pass, both consumers pass their evaluation gates, and the motivating lettering reads closer to its reference without new artifacts.

## Verification

- Prototype selection: contour level `127.5` without supersampling broke strokes (ink 0.82 times the reference). A bicubic ×4 field with a per-component ink-area level stayed connected, at 0.91 to 0.95 times the reference ink. Gaussian pre-blur made no visible difference.
- Curves: uniform Catmull-Rom curves hollowed the solid dots at connector ends into hooks. Handles bounded by their own segment, with sharp turns kept as corners, restored them; a regression covers the bound.
- Component split: thickness below three pixels covers about 89 percent of traceable components under 100 pixels per inch and under 1 percent at 180 pixels per inch or more. On GCP, 874 components are smooth-traced; 8 thin multicolor components keep pixel tracing.
- `make test`: 102 tests passed; fixture inspection and distribution validation passed. Factory `make evaluate` passed with zero error at 18 and 72 DPI.
- GCP build: 575 vector artworks and 16 raster assets, as before. The scene script grew from 38,857,777 to 39,463,001 bytes, and build time grew from about 3.6 to 3.9 minutes.
- GCP `make evaluate` passed and improved on Issue 0015: 18 DPI `0.002231784`, `0.992120699`, `1.006931336`, and 72 DPI `0.001406227`, `0.994949783`, `1.034701034` (mean error, within-tolerance fraction, ink ratio). Distribution validation passed. The JOBS zoom-detail crop is smooth and legible; the two native-resolution crops still match their references.
- Algorithms `make evaluate` passed and improved: 18 DPI `0.002817522`, `0.98296802`, `1.089427704`, and 72 DPI `0.00216203`, `0.984945075`, `1.135111725`. The 72 DPI ink ratio moved further below the fixed `1.15` maximum.
- Spot checks at 105 to 155 pixels per inch showed equal or smoother strokes with no new artifacts.
