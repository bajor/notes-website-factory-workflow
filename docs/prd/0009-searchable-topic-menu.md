---
type: PRD
title: Searchable topic menu
description: Requirements for compact topic discovery and navigation from a circular board control.
status: Superseded
supersedes: "0007"
superseded_by: "0010"
timestamp: 2026-08-30
---
# Searchable Topic Menu

## Problem

A permanently open topic panel consumes board space even when the reader is not navigating. A long topic list also becomes difficult to scan without filtering.

## Requirements

1. The build must detect closed, thick, chromatic frames from a temporary composited page render without depending on hue, filename, dimensions, resource names, or expected count.
2. Detection must not OCR the full page. Tesseract must receive only each accepted frame interior at OCR resolution.
3. Topics must be grouped into overlapping visual rows, ordered top-to-bottom by row and left-to-right within each row, then serialized with valid board-space bounds.
4. Empty OCR output must become `Topic N`; Poppler or Tesseract failure must abort the build.
5. Normal controls must contain adjacent circular `Topics` and `Fit` buttons; scenes without topics must show only `Fit`.
6. The topic menu must start closed, open from the `Topics` button, and close after a topic is selected on every viewport size.
7. The topic menu must expose a case-insensitive label search only when the scene contains more than 10 topics and must report when the search has no matches.
8. Selection must frame local context in about 450 milliseconds, allow direct interaction to cancel motion, and honor reduced motion.
9. Evaluation mode must hide all controls. Temporary renders and crops must remain outside the site artifact.

## Quality Attributes

| Attribute | Scenario | Instrument |
| --- | --- | --- |
| Reusability | Frame hue and board size differ. | Synthetic detector tests and real-consumer inspection. |
| Accessibility | Keyboard or reduced-motion readers use the circular controls and topic menu. | Chromium runtime tests and manual inspection. |
| Discoverability | A scene contains at least 11 topics. | Chromium assertion for conditional search. |
| Fidelity | Topic metadata and controls are enabled. | Fixed `make evaluate` thresholds and report inspection. |

## Acceptance

The motivating consumer exposes all 12 visually observed frames, conditionally exposes search, closes the menu after selection, passes factory and consumer gates, and ships no PDF, detection raster, crop, or OCR executable in the Pages artifact.

# References

1. [Superseded requirements](/prd/0007-composited-ocr-topic-navigation.md)
2. [Composited detection decision](/adr/0008-composited-topic-detection.md)
3. [Current topic behavior](/bdr/0012-searchable-topic-menu.md)
4. [Implementation issue](/issues/0008-add-ocr-topic-navigation.md)
