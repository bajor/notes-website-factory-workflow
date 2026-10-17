---
type: ADR
title: Render SVG sources as isolated images
description: Validate a self-contained SVG, embed it unchanged as a data URI, draw it as an SVG image in board units, and evaluate it against Chromium.
status: Accepted
timestamp: 2026-10-17
---
# Render SVG Sources as Isolated Images

## Context

[PRD 0011](/prd/0011-reusable-pdf-and-svg-site-factory.md) adds SVG source documents. A PDF needs a parser, tracing, and raster extraction because the browser cannot show it directly. An SVG is already the format the viewer draws. The open questions were how to show it, how to keep it from affecting the page, what to validate, how to evaluate it, and how factory CI exercises two formats.

A Chromium probe showed that an SVG drawn by an SVG `<image>` element inside a zoomed viewport `viewBox` stays sharp vector output at the viewer's 16× maximum zoom.

## Decision

- **Discovery.** `Factory.Pipeline.discoverSingleSource` finds exactly one `.pdf` or `.svg` file and returns the `Source` sum type. `loadSource` sends a PDF to `Factory.Pdf` and an SVG to `Factory.Svg`.
- **Validation.** `Factory.Svg.interpretSvg` parses the file with `xml-conduit`, interprets the root size, and rejects content that an isolated SVG image would drop without an error, as the [SVG support profile](/svg-support.md) lists. `xml-conduit` gives strict, namespace-aware parsing with bounded entity expansion; a project-owned XML parser would not be small or clear.
- **Output.** `svgScene` embeds the validated bytes as a base64 `data:` URI. The scene has no raster assets and one `SvgDocumentNode` covering the board, serialized as `{"kind": "svg-document", "href": "data:image/svg+xml;base64,...", "bounds": ...}`. The site publishes no standalone SVG file, so no browser opens the source as a document. The node is not an `Asset`, because `Asset` describes raster files with pixel dimensions.
- **Rendering.** `site/runtime.js` draws the node with an SVG `<image>` whose position and size are in board units, with no transform, as [ADR 0016](/adr/0016-board-point-vector-artwork.md) requires to avoid WebKit culling. Readiness waits for the image to load.
- **Evaluation.** `Factory.Evaluation` takes a `Reference`. A PDF keeps Poppler. An SVG uses Chromium: a fixed reference page draws a copy of the source through a window-sized SVG `viewBox` at the evaluation scale and origin. It shares tiling and stitching with site capture through `capturePage`. Thresholds, scales, and filenames are unchanged.
- **Workflow.** `build-pdf-site.yml` adds the optional `source-directory` input, resolved with `realpath` and confined to the consumer checkout. `ci.yml` builds the PDF fixture. `ci-svg.yml` builds the SVG fixture in a separate run, because two calls in one run would upload two artifacts named `github-pages`.

## Rejected Alternatives

- **Inline the SVG into the page DOM.** Links would work, but the SVG's `<style>` rules, element identifiers, and event handlers would apply to the viewer page. Safe inlining needs a sanitizer.
- **Convert the SVG into existing scene nodes.** This needs a large SVG interpreter, and every unsupported feature would be lost or rejected, although browsers already render SVG.
- **Publish the SVG as `assets/board.svg`.** This was the first implementation. Two reviews found XHTML `iframe` and `script` elements, DTD attribute defaults, and entity-declared namespaces that the validator missed, and Chromium runs such content when the file is opened directly on the consumer's shared `github.io` origin. A list of rejected forms cannot be shown complete, so the source is never published as a document.
- **Strip unsupported content instead of failing.** This silently removes source content, which the constitution forbids.
- **Use `librsvg` as an independent oracle.** It adds a tool, and its text and filter rendering differs from browsers. The factory ships the source unchanged, so the browser is the intended renderer.
- **Draw the reference with an HTML `<img>`.** Chromium snaps an image box to whole pixels. On the fixture's 426.667-pixel board this stretched the reference by 0.08 percent and moved its bottom border 0.33 pixels.
- **Rename `build-pdf-site.yml` or `pdf-site-evaluation`.** Consumers reference both, and a compatibility alias would be a duplicate path.
- **Ignore `visual-explanations/` during discovery.** This hard-codes a repository convention and still leaves two fixtures in the factory checkout.

## Consequences

PDF sources behave as before. An SVG board is embedded without tracing, so build time follows the source, and the scene script is about four thirds the size of the source. The validator is a fidelity check for the content forms exporters produce, not a security boundary; the [SVG support profile](/svg-support.md) lists the forms it does not decode. An SVG with hyperlinks fails until link overlays are supported. The SVG oracle checks placement and scale rather than SVG rendering, and it uses the factory's board size, so focused unit tests cover the size rules. The dependencies on `xml-conduit`, which adds its `conduit` and `blaze` packages, and `base64-bytestring` are pinned in `cabal.project.freeze`.

# References

1. [PRD 0011](/prd/0011-reusable-pdf-and-svg-site-factory.md)
2. [BDR 0024](/bdr/0024-pdf-and-svg-build-contract.md)
3. [Issue 0020](/issues/0020-support-svg-sources.md)
4. [Board-point vector artwork](/adr/0016-board-point-vector-artwork.md)
