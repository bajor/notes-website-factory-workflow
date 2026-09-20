---
type: Issue
title: Preserve local traced detail
description: Repair localized pixelation and retain zoomed visual evidence.
status: In Progress
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

## Acceptance

The linked behavior's test design passes, `make test` and `make evaluate` pass, real-consumer evidence is inspected, and the PR contains the review-only SVG and current documentation.

## Verification

- Baseline `make test`: 75 tests passed; fixture inspection and distribution validation passed.
- Tracer correction: all 80 tests and synthetic `make evaluate` passed. The inspected factory report has zero error at both scales. Five added pure regressions cover the independent failures described in the BDR.
- A rebuilt real-source PRUNING crop removes the previous pixel-grid steps. The existing two-opacity-layer approximation remains lossy; this change does not recover original Freeform geometry.
