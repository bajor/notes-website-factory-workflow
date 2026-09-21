---
type: ADR
title: Bounded zoom-detail evidence
description: Supplement whole-board gates with source-independent enlarged handwriting crops.
status: Accepted
tags: [testing]
timestamp: 2026-09-20
---
# Bounded Zoom-Detail Evidence

## Decision and Rationale

Keep the whole-board gates and add bounded zoomed comparisons to the evaluation report, owned by `Factory.Evaluation`. Select regions from reference handwriting and observed differences rather than consumer-specific coordinates. [BDR 0018](/bdr/0018-zoom-detail-evidence.md) owns selection, scales, outputs, and failure behavior.

The pixelation investigation demonstrated that a whole-board pass can hide broken handwriting. Full-board rendering at reading zoom would multiply already large evaluation images and browser captures. Raising global thresholds would conceal regressions. Applying whole-page mean-error thresholds to deliberately ink-dense crops would impose a different, uncalibrated fidelity contract. Therefore zoom crops are explicitly inspection evidence, while pure tracing regressions and the unchanged full-board checks remain automatic gates. Crop production failures still fail evaluation.

## Consequences

At most six bounded comparisons are added per run. Reviewers must inspect them for rendering changes; a global pass alone does not certify local readability. Selection tests enforce deterministic bounded sampling, and factory evaluation exercises crop rendering. Sampled evidence cannot prove that every note is readable.

# References

1. [Reusable factory requirements](/prd/0002-reusable-freeform-site-factory.md)
2. [Implementation issue](/issues/0014-preserve-local-traced-detail.md)
