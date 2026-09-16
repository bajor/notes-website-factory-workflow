---
type: Issue
title: Remove OCR topic navigation
description: Delete recognition-derived build behavior, metadata, and viewer controls.
status: Done
timestamp: 2026-09-16
---
# Remove OCR Topic Navigation

## Scope

Implement [ADR 0010](/adr/0010-remove-topic-recognition-and-navigation.md) and every scenario in [BDR 0013](/bdr/0013-remove-topic-navigation.md). Preserve direct board navigation, links, visual thresholds, and opaque highlighter output.

## Acceptance Criteria

- `Factory.Ocr`, `Factory.Topic`, their types, scene metadata, tests, fixtures, and browser UI are removed.
- The reusable workflow no longer installs Tesseract; Poppler remains only for evaluation.
- Current documentation records the removal and retains prior decision history as superseded records.
- `make test` and `make evaluate` pass, and the evaluation report is inspected.

## Completion Evidence

- `make test` passed with 68 focused unit tests, fixture inspection, and output validation.
- `make evaluate` passed at 18 and 72 DPI with mean normalized channel error `0.0`, pixels-within-tolerance ratio `1.0`, and ink ratio `1.0`.
- `build/evaluation/report.html` was inspected on 2026-09-16.

# References

1. [Current requirements](/prd/0010-remove-topic-recognition-and-navigation.md)
2. [Current decision](/adr/0010-remove-topic-recognition-and-navigation.md)
3. [Current behavior](/bdr/0013-remove-topic-navigation.md)
