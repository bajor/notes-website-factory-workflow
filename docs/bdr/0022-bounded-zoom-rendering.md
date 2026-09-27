---
type: BDR
title: Bounded zoom rendering
description: Keep the visual rendering surface within the viewport while preserving zoom anchors and overlay alignment.
status: Accepted
timestamp: 2026-09-26
---
# Bounded Zoom Rendering

## Context and Behavior

The GCP consumer reports disappearing regions during close-up zoom. The viewer must fulfill the direct-navigation requirement in [PRD 0010](/prd/0010-remove-topic-recognition-and-navigation.md) without enlarging its SVG rendering surface with the board.

The SVG occupies the viewport at every supported zoom. Its coordinate window selects the visible board region. Wheel and pinch input preserve their zoom anchor, and drag, keyboard navigation, Fit, and evaluation offsets position the visual scene and HTML overlays together. Source geometry, source order, clipping, and the white board background are preserved. Readiness-only evaluation removes all scene content before serialization.

The review-only diagram `visual-explanations/0022-bounded-zoom-rendering.svg` shows the former scaled SVG and the viewport-sized replacement. [ADR 0015](/adr/0015-viewport-sized-svg.md) owns the rendering mechanism.

Reviewers should verify the viewport bound, anchored navigation, overlay alignment, and unchanged source fidelity. The existing cleanup workflow deletes the SVG from `main` after merge.

## Scenarios and Test Design

| Given / When / Then | Instrument and proof |
| --- | --- |
| 1. Given a large synthetic board, when repeatedly zoomed between 4× and 16×, then the SVG surface stays within the viewport and the selected board point stays under the zoom anchor. | Chromium interaction regression checks rendered bounds and projected source coordinates after each wheel event. |
| 2. Given a visual mark and a link at the same board position, when zoomed and panned, then they remain aligned. | The same browser regression compares SVG screen coordinates with the link's rendered bounds. |
| 3. Given a fitted board or an evaluation offset, when rendered, then source order, affine placement, clipping, background, and evaluation readiness remain correct. | Existing runtime checks and the fixed 18 and 72 DPI evaluation gates. |
| 4. Given the real GCP consumer, when zoomed closely, then artwork remains visible throughout zoom. | Inspect normal-mode animation captures and the consumer's evaluation report before deployment; verify the deployed viewer separately. |

# References

1. [Direct-navigation requirements](/prd/0010-remove-topic-recognition-and-navigation.md)
2. [Rendering decision](/adr/0015-viewport-sized-svg.md)
3. [Implementation record](/issues/0018-stabilize-close-zoom.md)
