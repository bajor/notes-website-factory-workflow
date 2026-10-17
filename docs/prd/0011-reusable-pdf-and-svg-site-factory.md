---
type: PRD
title: Reusable PDF and SVG site factory
description: Requirements for visually validated Pages artifacts built from one PDF or SVG source document.
status: Accepted
supersedes: "0002"
timestamp: 2026-10-17
---
# Reusable PDF and SVG Site Factory

## Problem

[PRD 0002](/prd/0002-reusable-freeform-site-factory.md) accepts exactly one one-page Apple Freeform PDF. The owner is moving to Ahmni: Infinite Canvas, an iPad note application that exports a canvas as an SVG. An SVG already holds the board as browser-native vector content, so tracing or reinterpreting it would add loss and code without benefit. The factory, its workflow, and its documentation describe only the Freeform PDF case.

## Goals

- Let any repository containing one supported source document, either a one-page PDF within the [PDF support profile](/pdf-investigation.md) or a self-contained SVG, build the shared zoomable viewer by calling one reusable workflow.
- Keep PDF behavior unchanged.
- Show an SVG source unchanged.
- Keep consumer input, factory implementation, generated site, and evaluation evidence isolated.
- Emit a standard Pages artifact and visual evidence without requesting deployment permissions.
- Keep the fixed visual thresholds for both formats.

## Non-Goals

- General PDF compatibility outside the PDF support profile.
- SVG sanitization: content that an isolated image would lose fails instead of being removed.
- SVG hyperlinks, scripts, and external resources.
- Exporter-specific SVG behavior, including for Ahmni, before a real export has been observed.
- Multi-page or multi-file boards.
- Consumer-owned HTML, CSS, JavaScript, themes, or evaluation thresholds.
- Deployment from the reusable workflow.
- Renaming the published workflow file or artifacts.

## Requirements

1. The searched consumer directory contains exactly one non-symlink `.pdf` or `.svg` file. A PDF has exactly one page.
2. `site-title` is the only required workflow input. The optional `source-directory` input selects a directory inside the consumer checkout and defaults to the repository root.
3. A PDF source follows the PDF support profile and its accepted behavior decisions.
4. An SVG source ships byte for byte, embedded in the scene rather than as a standalone file, and is drawn as an isolated image in board units. Content that the image would drop without an error fails the build, as the [SVG support profile](/svg-support.md) lists.
5. The workflow checks out the consumer and the exact called-workflow commit into separate directories.
6. The workflow uploads `github-pages` only after build and evaluation pass, and uploads available evidence as `pdf-site-evaluation` for either format.
7. The factory contains no production source document and no consumer-specific filename, dimension, count, resource name, repository name, or URL.
8. Unsupported structures fail explicitly and produce no deployable artifact.
9. `build-pdf-site.yml`, `site-title`, `github-pages`, `pdf-site-evaluation`, and existing generated filenames keep their names.

## Quality Attributes

| Attribute | Scenario | Instrument |
| --- | --- | --- |
| Reusability | Boards in either format, with different dimensions and content, build with the unchanged workflow. | Both fixture CI runs and consumer runs. |
| Fidelity | A PDF matches Poppler, and an SVG matches Chromium's rendering of the source outside the viewer, at whole-board and native-point scales. | `make evaluate` at 18 and 72 DPI for each fixture. |
| Isolation | Only the selected consumer directory participates in discovery, and an SVG cannot affect the page around it. | Reusable-workflow fixture runs and isolated `<image>` rendering. |
| Safety | A `source-directory` outside the checkout, or a removable path overlapping a protected root, fails before mutation. | Resolve-step checks and focused path tests. |
| Compatibility | Existing consumers keep building without changing their caller. | Default `source-directory` and unchanged public names. |

## Acceptance

Both fixtures pass `make test` and `make evaluate`. Factory CI calls the reusable workflow for each fixture. Existing PDF consumers need no caller change. Active documentation describes both formats. The first real SVG export builds or fails with a documented typed error.

# References

1. [Superseded PRD 0002](/prd/0002-reusable-freeform-site-factory.md)
2. [ADR 0017](/adr/0017-isolated-svg-source-images.md)
3. [BDR 0024](/bdr/0024-pdf-and-svg-build-contract.md)
4. [Issue 0020](/issues/0020-support-svg-sources.md)
5. [SVG support profile](/svg-support.md)
