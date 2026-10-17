---
type: PRD
title: Reusable Freeform site factory
description: Requirements for source-independent, visually validated Pages artifacts.
status: Superseded
supersedes: "0001"
superseded_by: "0011"
timestamp: 2026-08-23
---
# Reusable Freeform Site Factory

## Problem

The original repository combined one production PDF, its branded site, generator source, evaluation evidence, and deployment policy. Reusing the generator required copying implementation files and retained assumptions about one source's title, resource counts, repository, and Pages URL.

## Goals

- Let any repository containing one supported one-page Apple Freeform PDF build the shared zoomable viewer by calling one reusable workflow.
- Keep consumer input, factory implementation, generated site, and evaluation evidence isolated.
- Emit a standard Pages artifact and visual evidence without requesting deployment permissions.
- Keep the current typed parser, mixed SVG/raster renderer, responsive viewer, and fixed visual thresholds.

## Non-Goals

- General PDF compatibility outside the documented Apple Freeform profile.
- Multi-page navigation.
- Consumer-owned HTML, CSS, JavaScript, themes, or evaluation thresholds.
- Deployment from the reusable workflow.
- Stable semantic-version tags; known consumers currently choose the moving `main` reference.

## Requirements

- The consumer source contains exactly one non-symlink PDF with exactly one page.
- `site-title` is the only required workflow input and is validated before output generation.
- The workflow checks out the consumer and the exact called-workflow commit into separate directories.
- The factory owns templates, parsing, rendering, validation, and evaluation.
- The workflow uploads `github-pages` only after build and evaluation pass.
- The workflow uploads available evaluation evidence as `pdf-site-evaluation`.
- The factory contains no production notes PDF and no consumer-specific filename, dimension, count, resource name, repository name, or URL.
- Unsupported structures fail explicitly and produce no deployable artifact.

## Quality Attributes

| Attribute | Scenario | Instrument |
| --- | --- | --- |
| Reusability | A different supported Freeform board has different dimensions and scene counts. The unchanged workflow builds it. | Consumer-path integration run. |
| Fidelity | A supported source is rendered at whole-board and native-point scales. | `make evaluate` at 18 and 72 DPI. |
| Isolation | Factory and consumer both contain repository files. Only the consumer root participates in PDF discovery. | Reusable-workflow two-checkout smoke run. |
| Safety | A removable path overlaps a protected root or another independently owned output root. The command fails before removal. | Focused path-validation tests. |
| Compatibility | A consumer references `main`. Workflow implementation and source resolve to one commit. | Checkout uses `job.workflow_sha`. |

## Acceptance

The requirement is accepted when the factory fixture passes `make test` and `make evaluate`, factory CI successfully calls the reusable workflow, a real Algorithms consumer produces and deploys the artifact, and active factory files contain no production-source assumptions.

# References

1. [Superseded PRD 0001](/prd/0001-vector-first-static-site.md)
2. [ADR 0002](/adr/0002-separate-factory-and-consumers.md)
3. [ADR 0003](/adr/0003-build-artifacts-with-a-reusable-workflow.md)
4. [BDR 0002](/bdr/0002-reusable-workflow-build-contract.md)
5. [BDR 0004](/bdr/0004-interactive-linked-card-output.md)
