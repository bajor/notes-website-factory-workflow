---
type: Context
title: Project glossary
description: Definitions for PDF and SVG sources, rendering, workflow reuse, artifacts, and evaluation.
timestamp: 2026-10-17
---
# Glossary

## Source Document

The one consumer file a site is built from: a one-page PDF or a self-contained SVG. Discovery recognizes it by its `.pdf` or `.svg` extension, ignoring case.

## Source Directory

The consumer-relative directory searched for the source document. The optional `source-directory` workflow input selects it; it defaults to the repository root and must resolve inside the consumer checkout.

## Self-Contained SVG

An SVG whose references all point inside the file, as `#fragment` targets or `data:` URIs, and which has no scripts, event handlers, hyperlinks, or `foreignObject`. Only such an SVG renders completely as an isolated image.

## SVG Document Node

A scene node that draws a self-contained SVG file unchanged, with an SVG `<image>` element placed over a board rectangle in board units. An SVG source produces one node covering the board.

## Image XObject

A named PDF image resource invoked by a content-stream `Do` operator.

## Soft Mask

A grayscale PDF image that supplies per-pixel opacity for another image resource.

## Traceable Alpha Sample

A soft-mask sample at or above alpha `96` that selects its image resource for component partitioning and vector tracing. Within a selected resource, samples from `88` through `95` are retained in a fixed-opacity SVG layer. A resource with no traceable sample remains raster; a positively identified highlighter stroke has a separate opacity policy.

## Vector Artwork

A scene node containing closed SVG paths traced from an eligible embedded image and placed in board units.

## Untraceable Component

An 8-connected group of nonzero-alpha pixels in a traceable image whose alpha below `88` exceeds a quarter of its total alpha. Such strokes are narrower than one source pixel and cannot be traced without losing or distorting them.

## Thin Component

A traceable 8-connected component whose count of pixels at alpha `128` or above, doubled, is less than three times the count of those pixels bordering lower alpha. It identifies strokes up to about three source pixels wide. A single-color thin component is smooth-traced: from a supersampled bicubic field, at the contour level that preserves its ink area, as closed cubic curves.

## Reconstructed Stroke

An untraceable component that is narrow and single-colored at half its own peak alpha, with a peak of at least `48`. It is redrawn as opaque ink from its supersampled field divided by the field's local maximum, so its outline stays continuous where the source peak dips.

## Raster Residual

A PNG asset holding a traceable image's untraceable components that are not reconstructed strokes, with source RGB and alpha. It is drawn immediately after the image's vector artwork with the same matrix, opacity, and clips.

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

A six-number matrix that can translate, scale, rotate, or shear embedded artwork. `Factory.Geometry` composes it with the opposite vertical orientation of image samples; traced vector points are placed through the result, and raster images receive it as their presentation matrix.

## Board Unit

One PDF point of a PDF board, or one CSS pixel of an SVG board, which is one SVG user unit of its untransformed root. It is the user unit of the scene SVG, its containers, its vector paths, and SVG document nodes; only raster images apply their own affine image transform.

## Game Link

A typed scene link whose structurally parsed URI matches the documented HTTPS Algo Arcade game-route profile. The normal viewer marks it with a gamepad badge and opens the original URI in a new tab.

## Evaluation Mode

The non-interactive browser rendering mode selected by the evaluator at a specific dots-per-inch scale. It hides controls and synthesized game badges so screenshots contain only source-derived scene content.

## Evaluation Oracle

The development-only reference rendering compared with Chromium output: Poppler's rendering of a source PDF, or Chromium's direct rendering of a source SVG outside the viewer.

## Highlighter Stroke

A translucent, elongated Freeform image whose visible pixels are overwhelmingly chromatic. The factory preserves its RGB and geometry but emits nonzero pixels at full opacity.

## Factory Repository

The `notes-website-factory` repository that owns generator source, shared viewer templates, evaluation policy, synthetic fixtures, and the reusable build workflow.

## Consumer Repository

A repository that owns exactly one production source document, its site title, caller trigger, and Pages deployment policy.

## Reusable Workflow

A workflow declared with GitHub Actions `workflow_call` and invoked as a job from another workflow.

## Caller Workflow

The consumer-owned workflow that selects event triggers, passes `site-title`, grants permissions, and invokes the reusable workflow.

## Pages Artifact

The artifact named `github-pages` that contains the validated static site in the format expected by GitHub Pages deployment actions.

## Evaluation Artifact

The artifact named `pdf-site-evaluation` that contains visual references, generated screenshots, difference images, metrics, and the HTML report. The name predates SVG sources and covers both formats.

## Workflow SHA

The commit identifier exposed as `job.workflow_sha` for the workflow file defining a reusable-workflow job. The factory uses it to check out matching implementation source.

## OIDC

OpenID Connect, the token protocol used by GitHub Pages to verify deployment identity. Only the consumer deployment job receives permission to request this token.
