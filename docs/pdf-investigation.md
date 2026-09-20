---
type: Reference
title: Apple Freeform PDF support profile
description: Historical evidence, supported parsing, classification policy, and explicit limitations.
timestamp: 2026-09-20
---
# Apple Freeform PDF Support Profile

## Historical Production Evidence

[`Algos.pdf`](https://github.com/bajor/algos-for-slow-learners) was exported by the iOS Quartz PDF context and motivated the supported profile. The consumer repository now owns that production input. The observed file has:

- 1 page;
- PDF version 1.4;
- page dimensions `6179.635 x 6144.439` points;
- zero-origin, matching MediaBox and CropBox;
- page rotation `0`;
- 534 content operators;
- 44 image XObjects;
- 35 substantially transparent soft-masked artwork resources;
- 8 opaque raster resources and 1 near-opaque soft-masked screenshot;
- 1 HTTP URI annotation that identifies a YouTube video;
- no PDF font resources or text-showing operators;
- no painted native vector paths in the resulting scene.

The board's visible handwriting and shapes are already raster data inside image XObjects. Their original Freeform geometry is not present in the PDF. The generator traces eligible artwork pixels into SVG contours; this improves zoom behavior but is deterministic and lossy. Production parsing rejects PDF text until font decoding, glyph metrics, and positioning are implemented.

The consumer revision `cac4d34` supplied a second production observation on 2026-08-23. `Algos 2.pdf` has 41 image XObjects, 34 substantially transparent artwork resources, 5 opaque screenshots, 2 near-opaque linked cards, and 2 URI annotations. The annotations identify one YouTube video and `https://bajor.github.io/algo-arcade/#/games/next-greater-element`. The linked cards' non-opaque sample fractions are `0.008181576` and `0.008124226`; the least-transparent artwork resource is `0.033626205`. These values establish a measured gap without becoming expected reusable-workflow counts.

The consumer revision `1bdf230` supplied a third production observation on 2026-08-24. One image has a `134784`-sample soft mask with `108924` nonzero samples, a range from `0` through `89`, and no sample at or above the vector tracer's alpha cutoff of `96`. PDF renderers retain the faint image, but vector tracing would remove every pixel. This observation establishes the source-independent low-alpha raster branch without hard-coding its resource name, dimensions, or consumer identity in production logic.

One low-alpha raster in revision `1bdf230` is an elongated yellow highlighter stroke. The product requirement makes positively identified highlighter strokes opaque while preserving RGB, geometry, and transparent pixels. Compact chromatic images and other low-alpha content retain source alpha.

A second consumer supplied a fourth production observation on 2026-08-28. Its one-page Freeform export contains 715 operators and 145 image XObjects, producing 144 vector artworks, 1 raster image, and 5 native paths. It sets miter limit `4` with `M`, a `[28 28]` dash array at phase `0` with `d`, and stroke and fill colors through `CS`/`SC` and `cs`/`sc` using a three-component ICC-based resource. Its artwork matrices also include rotation or shear. This observation establishes reusable graphics-state and affine-image support without adding consumer-specific values or identities to production logic.

## Observed Resource Classification

The observed source deterministically produces 35 vector artwork nodes and 9 raster image nodes. `Im29`, `Im31`, `Im33`, `Im35`, `Im37`, `Im39`, `Im41`, `Im43`, and `Im44` remain raster. The first eight are opaque screenshots or diagrams. `Im44` is a rounded-corner YouTube screenshot whose soft mask is near-opaque. These values are evidence, not reusable-workflow acceptance counts.

Classification uses the soft-mask samples before tracing, in this order:

- no soft mask: preserve raster;
- an empty or all-zero soft mask: fail as unsupported;
- nonzero samples with no sample at alpha `96` or higher: preserve raster with source alpha;
- traceable masks with a non-opaque sample fraction at most `0.01`: preserve raster;
- traceable masks with a non-opaque sample fraction below `0.02` but above `0.01`: fail as ambiguous;
- traceable masks with a non-opaque sample fraction of at least `0.02`: trace as vector.

Tracing quantizes RGB channels in steps of 32 and uses a faint SVG layer for source alpha `88` through `95`. The image-classification cutoff remains `96`. Contours cross between integer alpha samples at `87.5` for the faint layer and `95.5` for the opaque layer, avoiding collapsed geometry at exact cutoff samples. Same-color sub-threshold edge samples contribute to interpolation, and adjacent opacity layers share their source-alpha crossing. Matching color-and-opacity boundaries become normalized even-odd paths. The fixed `0.25` square-pixel simplification bound applies independently to each contour; a simplification that destroys its signed area retains the unsimplified contour. There is no style-wide pixel-grid fallback. Low-alpha raster pixels become opaque only when the accepted highlighter profile applies. The browser restores each image XObject's PDF transform when it renders the SVG path data. [BDR 0017](/bdr/0017-preserve-local-traced-detail.md) owns local-detail behavior.

## Selected Library

The production parser uses the Haskell `pdf-toolbox` packages:

- `pdf-toolbox-document` opens the file, walks the page tree, resolves objects, and decodes streams;
- `pdf-toolbox-content` parses content streams into operators;
- `pdf-toolbox-core` supplies PDF objects, names, references, arrays, and dictionaries.

The project, not the library, owns the graphics-state interpreter. This keeps coordinate conversion, clipping, opacity, scene validation, and unsupported-operator behavior visible in the educational Haskell code.

## Supported Export Profile

The parser currently supports the subset required by the observed Freeform export:

- graphics save and restore, affine image transforms, clipping, path construction, common paint operators, and stroke miter limits and dash patterns under non-singular similarity transforms;
- grayscale, RGB, and CMYK color operators plus named one/three-component ICC-based path color spaces;
- Freeform opacity resources;
- JPEG image streams and 8-bit Flate streams using DeviceGray, DeviceRGB, or one/three-component ICCBased color spaces;
- Flate soft masks with matching dimensions;
- deterministic soft-mask classification, lossless low-alpha raster preservation, and SVG contour tracing for the observed transparent artwork profile;
- opaque materialization of translucent, elongated, overwhelmingly chromatic highlighter strokes;
- URI link annotations and validated HTTP/HTTPS URLs;
- typed game links for HTTPS `bajor.github.io` URLs with path `/algo-arcade/`, no credentials or explicit port, and a non-empty `#/games/` fragment route;
- explicit rejection of PDF text until font decoding and metrics are implemented.

The browser composes each image's complete PDF matrix with the opposite vertical orientation used by browser image data. The same affine presentation path supports raster images and normalized traced artwork. Native stroked paths accept non-singular similarity transforms, which preserve angles while scaling line width and dash lengths uniformly; non-uniform scale and shear fail explicitly because a scalar browser stroke cannot represent them faithfully after path coordinates are flattened into board space.

## Factory Fixture

`generator/test/fixtures/minimal/minimal-freeform.pdf` is a synthetic one-page compatibility fixture. It exercises page discovery, native path interpretation, vector-only output, template rendering, browser readiness, and evaluation without retaining production notes. Focused tests cover raster resources, soft-mask boundaries, vector tracing, structural game-link classification, graphics state, browser stroke attributes, affine scene validation and runtime placement, and mixed source order.

The fixture does not broaden the support claim beyond Apple Freeform exports. New parser behavior still requires evidence from a real consumer source.

## Explicit Limitations

The following valid PDF features are not yet generalized:

- non-zero page-box origins, differing CropBox values, and page rotation;
- inherited page resources;
- Form XObjects;
- Indexed, four-component ICC, color-managed ICC transforms, or other complex image color spaces and decode arrays;
- line cap and line join graphics state;
- non-uniform scale or shear applied when a native path is stroked;
- PDF font encoding, embedded fonts, glyph widths, and `ToUnicode` handling;
- separate stroke and fill alpha values;
- internal destinations and non-URI annotation actions.
- game providers, custom domains, or `bajor.github.io` pages outside the exact Algo Arcade game-route profile; these remain ordinary external links.

Tracing does not recover semantic strokes, editable handwriting, original Freeform objects, gradients, or subpixel source geometry. Pixels at supported transparency levels become opaque quantized SVG fills. Low-alpha content remains raster; only positively identified highlighter strokes replace nonzero alpha with `255`. Opaque content remains raster rather than being guessed into vectors.

Unsupported operators fail with a typed error. Some unsupported structures have dedicated errors, while others are rejected by scene validation. A future parser increment should begin with a real source file demonstrating one missing feature, then add one focused test and one minimal implementation.

## Evaluation Oracle

Poppler's `pdftoppm` renders reference PNGs at 18 and 72 DPI for development evaluation. Headless Chromium renders the generated site at matching evaluation dimensions. Dimensions beyond the `8192`-pixel width or `4096`-pixel height capture limits are captured in deterministic tiles and stitched before comparison so browser surface limits do not constrain supported board dimensions. `Factory.Evaluation` checks browser readiness, compares every pixel, measures total ink, and writes:

```text
build/evaluation/
|-- difference-18.png
|-- difference-72.png
|-- evaluation.json
|-- generated-18.png
|-- generated-72.png
|-- reference-18.png
|-- reference-72.png
`-- report.html
```

These files are ignored build evidence. The reusable workflow uploads them as `pdf-site-evaluation`; they never enter `github-pages`, and the generated browser product has no dependency on Poppler. Evaluation mode does not draw the gamepad badge because that affordance has no source-PDF pixels. Consumer validation separately inspects the normal-mode anchor, accessible label, secure new-tab attributes, and badge.
