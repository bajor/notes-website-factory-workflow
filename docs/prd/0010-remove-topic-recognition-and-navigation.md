---
type: PRD
title: Remove topic recognition and navigation
description: Retire generated topic metadata and all recognition-derived navigation.
status: Accepted
supersedes: "0009"
timestamp: 2026-09-16
---
# Remove Topic Recognition and Navigation

## Problem

Recognition-derived labels and controls are not required for the generated board and add OCR tooling, metadata, and browser chrome unrelated to source rendering.

## Requirements

1. The factory must not invoke OCR, detect topic frames, or generate topic crops.
2. Generated scene data and summaries must not contain topic metadata.
3. Normal browser mode must expose only the existing `Fit` control while retaining direct pan, zoom, keyboard navigation, and link activation.
4. The build workflow must not install or depend on Tesseract.
5. The opaque highlighter-stroke policy remains unchanged.

## Acceptance

Factory source, generated artifacts, runtime tests, and active documentation contain no operational topic-recognition or OCR path. `make test` and `make evaluate` pass without weakening visual thresholds.

# References

1. [Superseded requirements](/prd/0009-searchable-topic-menu.md)
2. [Removal decision](/adr/0010-remove-topic-recognition-and-navigation.md)
3. [Removal behavior](/bdr/0013-remove-topic-navigation.md)
4. [Implementation issue](/issues/0010-remove-ocr-topic-navigation.md)
