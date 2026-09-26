---
type: Context
title: Project glossary
description: Definitions for PDF rendering, workflow reuse, artifacts, and evaluation.
timestamp: 2026-09-26
---
# Glossary

## Image XObject

A named PDF image resource invoked by a content-stream `Do` operator.

## Soft Mask

A grayscale PDF image that supplies per-pixel opacity for another image resource.

## Traceable Alpha Sample

A soft-mask sample at or above alpha `96` that selects its image resource for component partitioning and vector tracing. Within a selected resource, samples from `88` through `95` are retained in a fixed-opacity SVG layer. A resource with no traceable sample remains raster; a positively identified highlighter stroke has a separate opacity policy.

## Vector Artwork

A scene node containing normalized, closed SVG paths traced from an eligible embedded image.

## Untraceable Component

An 8-connected group of nonzero-alpha pixels in a traceable image whose alpha below `88` exceeds a quarter of its total alpha. Such strokes are narrower than one source pixel and cannot be traced without losing or distorting them.

## Thin Component

A traceable 8-connected component whose count of pixels at alpha `128` or above, doubled, is less than three times the count of those pixels bordering lower alpha. It identifies strokes up to about three source pixels wide. A single-color thin component is smooth-traced: from a supersampled bicubic field, at the contour level that preserves its ink area, as closed cubic curves.

## Raster Residual

A PNG asset holding a traceable image's untraceable components with source RGB and alpha. It is drawn immediately after the image's vector artwork with the same matrix, opacity, and clips.

## Raster Asset

An extracted PNG or JPEG file whose source pixels remain pixels in the generated site.

## Miter Limit

A PDF graphics-state value that limits the length of sharp corners formed by miter-joined strokes. The dimensionless value remains unchanged under a supported similarity transform and is emitted as SVG `stroke-miterlimit`.

## Dash Pattern

A PDF graphics-state pair containing a nonnegative segment-length array and a numeric phase. A supported similarity transform scales both uniformly before the factory emits SVG `stroke-dasharray` and `stroke-dashoffset`.

## Similarity Transform

A non-singular affine transform whose linear part combines translation, rotation, reflection, and uniform scale without shear or non-uniform scale. Such a transform preserves angles and allows a PDF native stroke to remain representable by scalar SVG line-width and dash values.

## Named Color Space

A color space selected by a resource name in a PDF content stream. The supported profile resolves one-component and three-component ICC-based resources to grayscale or RGB component interpretation.

## Affine Image Transform

A six-number matrix that can translate, scale, rotate, or shear embedded artwork. The browser composes this PDF matrix with the opposite vertical orientation used by image samples and DOM images.

## Game Link

A typed scene link whose structurally parsed URI matches the documented HTTPS Algo Arcade game-route profile. The normal viewer marks it with a gamepad badge and opens the original URI in a new tab.

## Evaluation Mode

The non-interactive browser rendering mode selected by the evaluator at a specific dots-per-inch scale. It hides controls and synthesized game badges so screenshots contain only PDF-derived scene content.

## Evaluation Oracle

Poppler's development-only rendering of the source PDF, used as an independent visual reference for Chromium output.

## Highlighter Stroke

A translucent, elongated Freeform image whose visible pixels are overwhelmingly chromatic. The factory preserves its RGB and geometry but emits nonzero pixels at full opacity.

## Factory Repository

The `notes-website-factory` repository that owns generator source, shared viewer templates, evaluation policy, synthetic fixtures, and the reusable build workflow.

## Consumer Repository

A repository that owns exactly one production PDF, its site title, caller trigger, and Pages deployment policy.

## Reusable Workflow

A workflow declared with GitHub Actions `workflow_call` and invoked as a job from another workflow.

## Caller Workflow

The consumer-owned workflow that selects event triggers, passes `site-title`, grants permissions, and invokes the reusable workflow.

## Pages Artifact

The artifact named `github-pages` that contains the validated static site in the format expected by GitHub Pages deployment actions.

## Evaluation Artifact

The artifact named `pdf-site-evaluation` that contains visual references, generated screenshots, difference images, metrics, and the HTML report.

## Workflow SHA

The commit identifier exposed as `job.workflow_sha` for the workflow file defining a reusable-workflow job. The factory uses it to check out matching implementation source.

## OIDC

OpenID Connect, the token protocol used by GitHub Pages to verify deployment identity. Only the consumer deployment job receives permission to request this token.
