---
type: Reference
title: SVG support profile
description: Supported SVG source content, rejected content, board size, rendering, evaluation, and limitations.
timestamp: 2026-10-17
---
# SVG Support Profile

An SVG source is a consumer's one board exported as a single `.svg` file. The factory validates the file and embeds its exact bytes in the scene as a base64 `data:` URI, and the viewer draws it as an isolated SVG image over the board. [ADR 0017](/adr/0017-isolated-svg-source-images.md) records the design, and [BDR 0024](/bdr/0024-pdf-and-svg-build-contract.md) owns the observable contract.

No production SVG export has been observed yet. This profile follows the rules browsers apply to SVG images. [Issue 0020](/issues/0020-support-svg-sources.md) tracks validation of the first real export.

## Board Size

The board is measured in CSS pixels, at 96 per inch. One board unit is one SVG user unit of an untransformed root.

| Root `width` and `height` | Board size |
| --- | --- |
| Both absolute lengths: unitless, `px`, `pt`, `pc`, `in`, `cm`, or `mm` | The two lengths, converted to CSS pixels. |
| Neither absolute: missing or a percentage | The width and height of the four-number `viewBox`. |
| Exactly one absolute | The build fails. |

Other units, such as `em`, fail. The width and height must be finite and positive. Example: `width="480pt" height="320pt"` gives a board of 640 by 426.667 CSS pixels.

## Accepted Content

The file must be well-formed XML whose root element is `svg` in the `http://www.w3.org/2000/svg` namespace. Internal DTD entities are expanded up to the default size limit of `xml-conduit`, except in namespace declarations: `xml-conduit` keeps such a reference as literal text while browsers expand it, so a namespace declared through an entity fails.

Other content that a browser draws inside an SVG image is accepted, including shapes, paths, text, gradients, patterns, filters, masks, clip paths, `<use>`, `<style>` rules, animations, and embedded images. References must stay inside the file: every `href` and `xlink:href` value, and the target of every CSS `url(...)` in an attribute or `<style>` element, must be a same-document fragment such as `#gradient` or a `data:` URI. Only `image` and `feImage` elements may use a `data:` URI in `href`; on every other element, such as `<use>`, `<textPath>`, or a gradient, `href` must be a fragment.

## Rejected Content

A browser draws an SVG image without scripts, interaction, or external files, and it drops them without reporting an error. The build therefore fails with a typed `unsupported SVG content` error when the SVG contains any of the following. Elements in the XHTML namespace are rejected, and the element rules below match names in every namespace, because browsers act on XHTML content inside SVG.

| Content | Reason |
| --- | --- |
| A `script` element or an `on...` event-handler attribute | Scripts never run. |
| An `a` hyperlink | Links cannot be followed. |
| A `foreignObject` element or any element in the XHTML namespace | Embedded HTML is outside the supported profile. |
| An `href`, `xlink:href`, or CSS `url(...)` target other than `#...` or `data:` | External images, fonts, stylesheets, and `<use>` targets never load. |
| An `href` other than a `#...` fragment on an element other than `image` or `feImage` | Browsers draw nothing for a `data:` target. |
| An `@import` rule in a `<style>` element | Imported stylesheets never load. |
| An `xml-stylesheet` processing instruction | External stylesheets never load. |

Malformed XML, a namespace declared through an entity reference, a root outside the SVG namespace, and an unusable board size fail with a typed `invalid SVG` error.

## Rendering

The viewer draws the embedded `data:` URI with an SVG `<image>` element placed in [board units](/context/glossary.md#board-unit), with no transform. The browser renders it as vector content at every zoom level. Because the image is isolated, its styles, element identifiers, and scripts cannot reach the page. The viewer's white board background shows through transparent areas.

The site publishes no standalone SVG file. A browser therefore never opens the source as a document, so content the validator does not recognize can at most fail to display; it cannot run. The validator protects fidelity, not the page.

## Factory Fixture

`generator/test/fixtures/svg/minimal.svg` is a synthetic board. Its root uses `pt` lengths and a `viewBox`. It contains strokes, text, a gradient referenced by `url(#...)`, `<use>` in both `href` forms, a `<style>` rule, and a `data:` PNG image. `make test` builds it, and `ci-svg.yml` runs it through the reusable workflow.

## Evaluation Oracle

Chromium renders the source SVG as the reference, as an isolated image in the same mode the viewer uses. A fixed reference page, which uses neither the viewer runtime nor the scene data, draws a copy of the source at the factory's board size with `dpi / 72` output pixels per board unit. It places the source through a window-sized SVG coordinate window, because Chromium snaps an HTML image box to whole pixels, which stretches a fractional board. The comparison uses the PDF thresholds, scales, tiling, zoom-detail crops, and evidence filenames. `evaluation.json` and `report.html` name the reference renderer.

The factory ships the SVG unchanged, so this oracle checks what the factory adds: board size, placement, scale, tiling, and loading. It does not check how the browser renders SVG features. It also cannot detect a board-size interpretation error, because the reference uses the same size; focused unit tests cover the size rules.

## Limitations

- Hyperlinks fail instead of becoming link overlays. Support needs a real export that shows how links are encoded.
- Text renders with the fonts available on the visitor's device unless the SVG embeds them as `data:` URIs.
- `data:` URIs that contain another SVG are not inspected for external references.
- References set by SVG animation values, such as `<set attributeName="href">`, are not inspected.
- The validator inspects the parsed document, not DTD declarations, so `<!ATTLIST>` attribute defaults are not checked.
- CSS escapes, such as `u\72l(...)`, and CSS functions other than `url(...)`, such as `image-set(...)`, are not decoded. An external file referenced only in those forms does not load and is not reported.
- Legacy Adobe Illustrator files that declare namespaces through `ns_*` entities and use them, for example in slicing metadata, fail. Current Illustrator exports pass.
- The embedded `data:` URI makes `scene.generated.js` about four thirds the size of the source.
- The factory does not compress, optimize, or rewrite the SVG. A large file ships at its full size.
