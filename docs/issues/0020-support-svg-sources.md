---
type: Issue
title: Support SVG sources
description: Accept one self-contained SVG as the source document, make the documentation source-neutral, and validate the first real export.
status: In Progress
timestamp: 2026-10-17
---
# Support SVG Sources

## Evidence and Scope

On 2026-10-17 the owner reported moving from Apple Freeform PDF exports to a note application that exports SVG. They asked the factory to keep PDF behavior, to use an SVG as it is, and to describe both formats. No production SVG export is available yet. The known consumers `notes-algos-for-slow-learners`, `notes-gcp-storage-and-data-processing-engines`, and `notes-website-template` contain no `.svg` file, so widening discovery does not change their builds.

Implements [PRD 0011](/prd/0011-reusable-pdf-and-svg-site-factory.md), [ADR 0017](/adr/0017-isolated-svg-source-images.md), and [BDR 0024](/bdr/0024-pdf-and-svg-build-contract.md).

## Plan

1. Rename the generator package from `freeform-site` to `notes-site`.
2. Add discovery of one PDF or SVG, `Factory.Svg`, the `svg-document` node and its viewer rendering, the Chromium reference, and the SVG fixture.
3. Add the `source-directory` input and the SVG fixture CI run.
4. Make active documentation source-neutral and record the decisions.
5. Validate the first real SVG export and record its evidence.

## Verification

- Baseline: `make test` passes 110 tests, and `make evaluate` passes with zero difference at 18 and 72 DPI. After the change, all 136 tests pass, and `make test` inspects and builds both fixtures.
- PDF fixture: `make evaluate` still passes with zero difference at both scales, and the report names Poppler.
- SVG fixture: `make evaluate` passes. At 18 and 72 DPI, mean error is `0.0017` and `0.0005`, pixels within tolerance are `0.991` and `0.997`, and ink ratios are `1.005` and `1.002`. All six zoom-detail crops have zero difference. The remaining differences are glyph antialiasing in the fixture's text and the partial last pixel row, where the viewer background shows through a third of a pixel beyond the board edge.
- A first reference drew the source with an HTML `<img>` and gave an 18 DPI mean error of `0.0084`. Chromium snapped that box to 427 pixels for the 426.667-pixel board, which moved the reference's bottom border 0.33 pixels; the generated border matched the geometry. The reference now uses an SVG coordinate window.
- The built fixture's `svg-document` `href` decodes to the exact source bytes, and the site has no `assets/` directory.
- CLI checks: a PDF together with an SVG fails with "expected exactly one PDF or SVG source file, found 2", and an empty directory reports 0. An external `<image href="photo.png">` and an `<a>` hyperlink each fail with a typed `unsupported SVG content` error.
- The resolve step, extracted from the workflow file and run locally, accepts `.`, an empty value, a nested directory, and a symlink to a nested directory. It rejects `..`, a symlink that escapes the checkout, a missing directory, a file, and `/etc`.
- The close-zoom runtime regression fails when the SVG document is drawn as a unit square with a scaling transform.
- WebKit: the local WPE WebKit build (Playwright revision 2336) renders the built SVG fixture site as sharp vectors at 1×, 4×, 8×, and 16× around a stroke anchor and a text anchor. Compared with Chromium captures of the same views, ink coverage differs by at most `0.0013` of the pixels, and at most `0.0194` of the pixels differ in luma by more than `96`, all at 16× glyph edges.
- Factory CI on the first PR push: [CI run 39040077447](https://github.com/bajor/notes-website-factory-workflow/actions/runs/39040077447) for the PDF fixture and [CI SVG run 39040077503](https://github.com/bajor/notes-website-factory-workflow/actions/runs/39040077503) for the SVG fixture both passed and uploaded `github-pages` and `pdf-site-evaluation`.
- First review: the validator matched only SVG-namespace element names and literal XLink attributes. An XHTML `script`, which Chromium runs when the asset is opened directly, an XHTML `style` with `@import`, and an `xlink:href` under a namespace declared through an entity all passed. `-.5` in a `viewBox` failed, and a `<use>` with a `data:` target passed but draws nothing. Element names are now matched in every namespace, entity references in namespace declarations fail, `<use>` must reference a fragment, and signed short numbers parse. Each case has a unit test, and each crafted file fails or builds through the CLI as expected.
- [CI run 39041266435](https://github.com/bajor/notes-website-factory-workflow/actions/runs/39041266435) and [CI SVG run 39041266440](https://github.com/bajor/notes-website-factory-workflow/actions/runs/39041266440) passed after the first review fixes.
- Second review: about 35 crafted files and realistic exports from Inkscape 1.3, Excalidraw, tldraw, draw.io, Illustrator, Figma, and Affinity, checked by building them and rendering them in Chromium. The exports build, except legacy Illustrator files that use entity-declared namespaces. The review found more forms the validator missed: XHTML `iframe` and `meta` elements, DTD `<!ATTLIST>` defaults, a namespace that contains an entity reference, CSS escapes, `image-set()`, `<style>` text split by a comment, and `data:` targets on `<textPath>` and gradients. Chromium runs some of these when an SVG file is opened directly. The SVG is now embedded as a `data:` URI instead of being published as `assets/board.svg`, so no browser opens it as a document. XHTML elements, namespaces containing `&`, split style text, and `data:` targets outside `image` and `feImage` now fail with unit tests. DTD defaults, CSS escapes, and `image-set()` are documented limitations.
- After embedding, both evaluations give the same results as before, and WebKit still matches Chromium at every captured zoom: ink differs by at most `0.0012` of the pixels.
- Pending: the first real SVG export.

## Acceptance

The linked BDR scenarios pass, the reviewed change is merged, existing PDF consumers keep building without caller changes, and the first real SVG export builds or fails with a documented typed error.
