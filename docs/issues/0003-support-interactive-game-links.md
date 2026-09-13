---
type: Issue
title: Support interactive Algo Arcade game links
description: Accept the refreshed consumer cards, type exact game routes, render a badge, and redeploy the consumer.
status: Done
timestamp: 2026-08-23
---
# Support Interactive Algo Arcade Game Links

## Scope

Implement [ADR 0004](/adr/0004-linked-game-cards.md) and every scenario in [BDR 0004](/bdr/0004-interactive-linked-card-output.md) without changing workflow inputs, artifact names, visual thresholds, or deployment ownership.

## Acceptance Criteria

- The observed `Im38` and `Im39` soft masks classify as near-opaque raster.
- The ambiguity interval remains explicit and unit tested.
- Exact Algo Arcade game routes serialize as typed game targets.
- Non-game pages and deceptive hosts remain generic external targets.
- The normal viewer shows an accessible gamepad badge and opens the original website securely.
- A Chromium runtime smoke test verifies normal-mode and evaluation-mode link behavior without loading a remote game.
- Evaluation screenshots omit the badge and pass at 18 and 72 DPI.
- `make test`, `make evaluate`, factory CI, and the real consumer workflow pass.
- The consumer Pages deployment completes from its own workflow.

## Completion Evidence

To be completed with the factory pull request and consumer workflow run before this issue is marked `Done`.

# References

1. [Interactive game-link requirements](/prd/0003-interactive-game-links.md)
2. [Linked game card decision](/adr/0004-linked-game-cards.md)
3. [Interactive linked-card behavior](/bdr/0004-interactive-linked-card-output.md)
