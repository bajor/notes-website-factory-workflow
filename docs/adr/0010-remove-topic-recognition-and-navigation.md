---
type: ADR
title: Remove topic recognition and navigation
description: Delete recognition-derived build metadata and viewer controls.
status: Accepted
supersedes: "0008"
timestamp: 2026-09-16
---
# Remove Topic Recognition and Navigation

## Context

The topic feature adds Poppler detection renders, Tesseract OCR, scene metadata, and a browser menu without changing PDF-derived board rendering. The requested product no longer includes that feature.

## Decision

Delete `Factory.Ocr` and `Factory.Topic`, remove topic types from `Factory.Domain`, and emit only source-derived nodes and assets. The shared viewer retains direct navigation and the `Fit` action, but no recognition-derived controls. Poppler remains an evaluation dependency; Tesseract is removed from the factory and reusable workflow.

## Rejected Alternatives

- Keep frame detection without OCR: it retains build work and metadata with no user-visible purpose.
- Keep the menu with generic labels: it preserves UI that is explicitly being removed.
- Leave Tesseract installed but unused: it obscures the actual build contract.

## Consequences

Builds no longer fail because recognition tools are unavailable, and scene serialization has no topic schema. The opaque-highlighter rule remains owned by ADR 0009 and does not depend on topic detection.

# References

1. [Superseded decision](/adr/0008-composited-topic-detection.md)
2. [Current requirements](/prd/0010-remove-topic-recognition-and-navigation.md)
3. [Current behavior](/bdr/0013-remove-topic-navigation.md)
4. [Implementation issue](/issues/0010-remove-ocr-topic-navigation.md)
