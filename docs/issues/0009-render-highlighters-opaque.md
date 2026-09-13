---
type: Issue
title: Render highlighter strokes as opaque
description: Make positively identified Freeform highlighter strokes opaque without changing unrelated low-alpha content.
status: Done
timestamp: 2026-08-29
---
# Render Highlighter Strokes as Opaque

## Scope

Implement [ADR 0009](/adr/0009-opaque-highlighter-strokes.md) and [BDR 0011](/bdr/0011-opaque-highlighter-output.md) in the existing decode and raster-materialization path.

## Acceptance Criteria

- Classification is pure and independent of hue, resource name, and consumer identity.
- Positive and compact-negative unit tests pass.
- The motivating marker is emitted with opaque nonzero pixels.
- `make test`, `make evaluate`, and real-consumer evidence are reviewed without threshold weakening.

## Completion Evidence

- Unit tests prove an elongated translucent chromatic stroke becomes opaque and a compact chromatic block does not qualify.
- Consumer `Im38.png` contains `25860` zero-alpha pixels and `108924` alpha-`255` pixels, with no intermediate alpha.
- Consumer evaluation passes unchanged thresholds with ink ratio `1.1380772632157787`; the 18 and 72 DPI difference images were inspected on 2026-08-30.

# References

1. [Opaque highlighter requirements](/prd/0008-opaque-freeform-highlighters.md)
2. [Opaque highlighter decision](/adr/0009-opaque-highlighter-strokes.md)
3. [Opaque highlighter behavior](/bdr/0011-opaque-highlighter-output.md)
