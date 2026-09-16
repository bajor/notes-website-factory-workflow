---
type: ADR
title: Detect topics from a composited build render
description: Use a temporary low-resolution page render for frame geometry and bounded high-resolution crops for OCR.
status: Superseded
supersedes: "0007"
superseded_by: "0010"
timestamp: 2026-08-29
---
# Detect Topics from a Composited Build Render

## Context

Real-consumer validation showed that a visible frame can span overlapping image XObjects. Per-resource detection reported the expected count only because one unrelated small shape replaced the missing `ARRAYS/STRINGS` frame.

## Decision

`Factory.Ocr` asks Poppler for a temporary first-page render at fixed `36 DPI`, decodes it with JuicyPixels, and passes it to pure `Factory.Topic` geometry detection. Normalized frame rectangles map directly to board dimensions. Accepted interiors are then rendered individually at `216 DPI` for `tesseract -l eng --psm 7`. `Factory.Pipeline` owns scratch paths and promotion; no temporary image is emitted.

## Rejected Alternatives

- Keep per-XObject detection: it cannot represent a frame assembled by composition.
- OCR one high-resolution full page: it is expensive and exposes unrelated handwriting to OCR.
- Detect in the browser: it adds a runtime parser and recognition toolchain.
- Require exactly 12 frames: the count is consumer evidence, not reusable policy.

## Consequences

Poppler is a production build dependency for detection and bounded OCR. Detection reflects visible composition and no longer changes parser or interpreter ownership. Antialiasing is controlled by fixed DPI and chroma thresholds verified against synthetic and real evidence.

# References

1. [Current requirements](/prd/0007-composited-ocr-topic-navigation.md)
2. [Superseded decision](/adr/0007-build-time-topic-ocr.md)
3. [Current behavior](/bdr/0010-composited-topic-index-navigation.md)
4. [Observed PDF profile](/pdf-investigation.md)
