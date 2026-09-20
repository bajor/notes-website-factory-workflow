---
type: BDR
title: Preserve local traced detail
description: Keep faint and cutoff-alpha contours local and interpolated.
status: Accepted
supersedes: "0016"
timestamp: 2026-09-20
---
# Preserve Local Traced Detail

## Context

The motivating GCP export contains readable handwriting that becomes broken pixel-grid outlines after tracing. BDR 0016's implementation sends every faint layer through a threshold it cannot reach, and one collapsed contour can replace all contours of the same style with pixel boundaries. The investigation and consumer revision are recorded in [Issue 0014](/issues/0014-preserve-local-traced-detail.md).

## Description

The existing color quantization, two opacity layers, resource classification, ordering, clipping, affine presentation, and complexity limit remain in force. Within each layer, contour crossings use that layer's lower alpha boundary between adjacent integer sample values. Sub-threshold samples of the same quantized color remain available for edge interpolation. Adjacent selected styles meet at their shared boundary. A cutoff-alpha component stays representable beside stronger components, and simplification of one contour cannot change another contour or replace an entire style with pixel-grid geometry.

Normalized coordinate precision increases for large source dimensions so serialization does not collapse retained subpixel contours.

`visual-explanations/0017-local-tracing.svg` contrasts the former style-wide pixel fallback with layer-aware interpolation and contour-local simplification. `Factory.Vectorize` owns both flows; `Factory.Pdf` and `site/runtime.js` continue to consume the same vector shapes. Reviewers must verify that faint layers interpolate, cutoff components survive beside opaque artwork, and the real handwriting crop improves. The existing SVG cleanup workflow deletes this PR-only artifact from `main` after merge.

## Scenarios and Test Design

| Given / When / Then | Instrument and proof |
| --- | --- |
| 1. Given a faint stroke beside opaque artwork, when traced, then the faint outline has fractional source-pixel crossings. | Pure `traceImage` regression checks the faint contour coordinates. |
| 2. Given an isolated cutoff-alpha component beside opaque artwork, when traced, then both components remain. | Pure regression counts separate nonempty contours. |
| 3. Given a cutoff-alpha pair beside opaque artwork, when traced, then the opaque contour is identical to its isolated trace. | Pure regression compares the unaffected contour. |
| 4. Given sub-threshold edge coverage of the same color, when traced, then the source alpha contributes to interpolation. | Pure alpha-ramp regression checks the crossing position. |
| 5. Given a thin cutoff stroke, when simplified, then it retains a filled outline rather than collapsing to a line. | Pure regression verifies the contour retains a polygon. |
| 6. Given the motivating consumer, when rebuilt, then the PRUNING handwriting loses the pixel-grid stair steps at enlarged viewing scales. | Real-source before/after crop inspection plus the unchanged whole-board gates. |
| 7. Given a cutoff component in a wide source image, when serialized, then its SVG contour retains nonzero area. | Pure 20,000-pixel-wide regression measures emitted polygon area. |

# References

1. [Reusable factory requirements](/prd/0002-reusable-freeform-site-factory.md)
2. [Vector-first rendering decision](/adr/0001-vector-first-mixed-rendering.md)
3. [Superseded alpha-layer behavior](/bdr/0016-alpha-layer-traced-svg-artwork.md)
