---
type: Issue
title: Add OCR topic navigation
description: Detect highlighter-framed headings, label them with local OCR, and navigate to their board positions.
status: Done
timestamp: 2026-08-29
---
# Add OCR Topic Navigation

## Scope

Implement [ADR 0008](/adr/0008-composited-topic-detection.md) and every scenario in [BDR 0012](/bdr/0012-searchable-topic-menu.md). Preserve direct pan and zoom interaction, workflow permissions, artifact names, and visual thresholds.

## Acceptance Criteria

- Source-independent relative geometry detects highlighter frames from a temporary composited render and rejects unrelated artwork.
- Local English Tesseract emits a label or deterministic fallback for each topic.
- The scene stores validated labels and board-space bounds separately from source nodes.
- Normal controls expose circular `Topics` and `Fit` actions, conditional topic search, and accessible smooth navigation.
- Focused tests, `make test`, `make evaluate`, and test audit pass.
- Consumer revision `1bdf230` exposes all 12 observed frames and passes visual evaluation.
- Factory CI and the real consumer workflow pass without new workflow inputs or permissions.

## Plan

1. Record the constitutional exception, requirements, decision, behavior, architecture, and vocabulary.
2. Add pure frame detection and typed topic metadata.
3. Add a low-resolution composited detection render, bounded OCR crops, Tesseract execution, cleanup, and workflow tooling.
4. Replace viewer buttons with the responsive topic index and animated target navigation.
5. Verify the synthetic fixture, normal/evaluation browser modes, visual fidelity, and real consumer.

## Completion Evidence

- Factory `make test` and `make evaluate` pass with 78 unit tests plus Chromium coverage for topic-menu interaction, mixed-case search, empty results, selection, direct-interaction cancellation, reduced motion, short viewports, empty topics, evaluation mode, and readiness mode.
- Consumer revision `1bdf230` produces 12 ordered topics.
- Consumer evaluation passes at 18 and 72 DPI with mean error `0.0028092643247973966`, pixels-within-tolerance ratio `0.9831241454574124`, and ink ratio `1.1380772632157787`.
- `build/consumer-evaluation/report.html` and both difference images were inspected on 2026-08-30.

# References

1. [Searchable topic menu requirements](/prd/0009-searchable-topic-menu.md)
2. [Composited detection decision](/adr/0008-composited-topic-detection.md)
3. [Searchable topic behavior](/bdr/0012-searchable-topic-menu.md)
