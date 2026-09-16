---
type: BDR
title: Remove topic navigation
description: Observable browser and build behavior after recognition-derived navigation removal.
status: Accepted
supersedes: "0012"
timestamp: 2026-09-16
---
# Remove Topic Navigation

## Behavior Flow

```mermaid
flowchart LR
  PDF[One-page PDF] --> Parse[Parse and validate scene]
  Parse --> Emit[Emit assets and source-derived nodes]
  Emit --> Viewer[Viewer with Fit and direct navigation]
```

## Description

The build does not detect topic frames or perform OCR. The browser receives no topic data and exposes the existing Fit control, direct pan and zoom interaction, keyboard navigation, and typed link activation.

## Scenarios

1. Given a supported PDF, when the factory builds it, then no OCR or topic-detection process runs.
2. Given an emitted scene, when its JavaScript module and summary are inspected, then neither contains topic metadata.
3. Given normal browser mode, when the page is ready, then Fit is visible and no Topics button or topic panel exists.
4. Given evaluation mode, when Chromium captures the board, then controls remain hidden and visual output remains source-derived.
5. Given a low-alpha highlighter stroke, when the scene is built, then its existing opaque-highlighter behavior is unchanged.

## Test Design

| Scenario | Instrument | Proof |
| --- | --- | --- |
| 1, 2 | Build artifact assertions and source inspection | No recognition implementation, subprocess, or serialized field remains. |
| 3, 4 | Chromium runtime DOM tests | Fit and evaluation behavior remain while topic chrome is absent. |
| 5 | Existing vectorization unit tests and visual evaluation | Topic removal does not change the independent highlighter policy. |

# References

1. [Current requirements](/prd/0010-remove-topic-recognition-and-navigation.md)
2. [Current decision](/adr/0010-remove-topic-recognition-and-navigation.md)
3. [Superseded behavior](/bdr/0012-searchable-topic-menu.md)
4. [Implementation issue](/issues/0010-remove-ocr-topic-navigation.md)
