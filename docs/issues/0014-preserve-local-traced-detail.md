---
type: Issue
title: Preserve local traced detail
description: Repair localized pixelation and retain zoomed visual evidence.
status: Done
timestamp: 2026-09-20
---
# Preserve Local Traced Detail

## Evidence and Scope

Implements [BDR 0017](/bdr/0017-preserve-local-traced-detail.md). GCP consumer revision `152473810213e651424845f2e79e9f5e7d59c1e8`, deployed by [run 35185046614](https://github.com/bajor/notes-gcp-storage-and-data-processing-engines/actions/runs/35185046614), reproduces broken BigQuery / PRUNING handwriting. Its `Im16` black layer contains 3,532 pixel-grid contours. Small diagnostic inputs reproduce disappearing cutoff-alpha components and style-wide fallback; all 75 baseline tests nevertheless pass.

## Plan

1. Eliminate alpha-equality collapse with layer-specific half-step crossings and preserve same-color edge samples.
2. Remove style-wide pixel fallback and keep simplification decisions local to each contour.
3. Add focused regressions and bounded zoom-detail evidence.
4. Inspect real-source improvements, run the factory gates, and merge the reviewed PR.

The implementation is split into two ordered PRs: contour correction, then bounded zoom-detail evaluation.

The second slice implements [BDR 0018](/bdr/0018-zoom-detail-evidence.md) using the [bounded-evidence decision](/adr/0011-bounded-zoom-detail-evidence.md).

## Acceptance

The linked behavior's test design passes, `make test` and `make evaluate` pass, real-consumer evidence is inspected, and the PR contains the review-only SVG and current documentation.

## Verification

- Baseline `make test`: 75 tests passed; fixture inspection and distribution validation passed.
- Tracer correction: all 80 tests and synthetic `make evaluate` passed. The inspected factory report has zero error at both scales. Five added pure regressions cover the independent failures described in the BDR.
- A rebuilt real-source PRUNING crop removes the previous pixel-grid steps. The existing two-opacity-layer approximation remains lossy; this change does not recover original Freeform geometry.
- [PR #32](https://github.com/bajor/notes-website-factory-workflow/pull/32) merged the tracer correction after 81 tests, factory evaluation, successful reusable-workflow CI, and fresh-session review. Review identified and resolved normalized-coordinate rounding in 20,000-pixel-wide images.
- The local monolithic GCP evaluation was interrupted. Equivalent all-pixel comparisons completed in bounded browser tiles against the unchanged consumer revision's CI Poppler references: 18 DPI mean error `0.002264624`, within-tolerance fraction `0.992018364`, ink ratio `1.015922787`; 72 DPI values `0.001463132`, `0.994791566`, and `1.044231496`. Both scales passed the unchanged thresholds. Scene SHA-256: `bafb8c160474c1d0c09b2541c4a9c904ee33e9fb57afa3f66775341a0c1023d6`.
- Zoom-detail implementation: 87 tests and factory `make evaluate` passed. The inspected report includes four correctly aligned synthetic detail captures with zero difference.
- Algorithms consumer revision `7ff9eb5c4acb534b35e6bdfdb14faf3b484db17e` passed the complete `make evaluate` flow, including runtime and distribution checks. The inspected report contains six detail comparisons. Whole-board 18 DPI values are `0.002828299`, `0.982929377`, and `1.094038948`; 72 DPI values are `0.002168048`, `0.984938977`, and `1.140308337` (mean error, within-tolerance fraction, ink ratio respectively).
- [PR #33](https://github.com/bajor/notes-website-factory-workflow/pull/33) supplies zoom-detail evidence. Fresh-session review found no blocking correctness issues; its color-filter coverage suggestion was incorporated without adding another test. Living Docs lint passes for all 63 documents.
