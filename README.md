# Notes Website Factory

Notes Website Factory turns a one-page Apple Freeform PDF into a responsive, zoomable static website. A consumer repository supplies the PDF, a site title, and a GitHub Actions caller workflow. This repository supplies the Haskell generator, shared viewer, visual evaluation, and deployable Pages artifact.

The generated site renders scene data, inline SVG artwork, links, and extracted raster assets. It does not ship or parse the source PDF in the browser.

## What You Can Use It For

- Publish a one-page Freeform board as a website without maintaining a backend.
- Share visual study notes, diagrams, or mixed screenshot-and-handwriting boards with topic navigation, fit, zoom, and pan interactions.
- Rebuild and visually validate the site whenever the source PDF changes.
- Keep source content and deployment policy in a separate repository while reusing one build pipeline.

This is not a general-purpose PDF converter, document editor, or optical character recognition tool.

## Pros and Cons

### Pros

- Produces static files that can be hosted under any GitHub Pages project path.
- Validates the generated page against Poppler reference renders before publishing it.
- Preserves screenshots as raster images and traces supported Freeform artwork into scalable SVG.
- Supports mouse, touch, keyboard, fit-to-screen, zoom, pan, and build-time topic navigation.
- Keeps deployment credentials and policy out of the reusable build workflow.
- Fails the build instead of publishing a Pages artifact when parsing, validation, or visual evaluation fails.

### Cons

- Accepts one-page PDFs from the documented Apple Freeform export profile, not arbitrary PDFs.
- Does not recover editable Freeform objects or semantic handwriting. SVG tracing is deterministic but lossy.
- Does not support PDF text, page rotation, general image transforms, or several valid PDF structures.
- Documents outside the supported profile are not guaranteed to build or render correctly.
- Topic labels use best-effort English handwriting OCR and can contain recognition mistakes.
- The hosted setup targets GitHub Actions and GitHub Pages. Other deployment systems require a separate integration.
- Referencing the workflow at `@main` picks up future factory changes; pin a full commit SHA when immutable behavior is required.

See the [Apple Freeform PDF support profile](docs/pdf-investigation.md) for the exact supported features and limitations.

## Requirements

A consumer repository needs:

- exactly one non-symlink PDF discovered recursively outside `.git`, `build`, `dist`, `dist.building`, `dist.previous`, `dist-newstyle`, and `node_modules` directories;
- exactly one page in that PDF;
- a non-empty `site-title` without control characters;
- GitHub Pages configured with **GitHub Actions** as its source.

Other files may remain in the consumer repository. The reusable workflow needs only `contents: read`; the consumer's deployment job owns Pages and OpenID Connect permissions.

## How to Use It

Start with the [Notes Website Template](https://github.com/bajor/notes-website-template) to get the caller workflow. After creating a repository from it, enable GitHub Pages with **GitHub Actions** as its source and add one supported PDF.

To configure an existing repository instead, create `.github/workflows/pages.yml` with the workflow below.

```yaml
name: Publish Notes

on:
  pull_request:
  push:
    branches: [main]

permissions: {}

concurrency:
  group: pages-${{ github.ref }}
  cancel-in-progress: false

jobs:
  build:
    permissions:
      contents: read
    uses: bajor/notes-website-factory-workflow/.github/workflows/build-pdf-site.yml@main
    with:
      site-title: My Notes

  deploy:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    needs: build
    permissions:
      pages: write
      id-token: write
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/configure-pages@983d7736d9b0ae728b81ab479565c72886d7745b # v5
      - id: deployment
        uses: actions/deploy-pages@d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e # v4
```

The workflow at `@main` can change between runs. Within each run, `job.workflow_sha` keeps the workflow and checked-out factory implementation on the same commit. Replace `main` with a full factory commit SHA to pin behavior.

## Outputs

On success, the reusable workflow uploads:

| Artifact | Contents |
| --- | --- |
| `github-pages` | The validated static site, ready for `actions/deploy-pages`. |
| `pdf-site-evaluation` | Reference renders, browser renders, difference images, metrics, and `report.html`. |

The reusable workflow does not deploy either artifact. If evaluation fails, it withholds `github-pages` and uploads available evaluation evidence when possible.

The site includes `index.html`, `runtime.js`, `styles.css`, `scene.generated.js`, and `scene-summary.json`. An `assets/` directory is added only when the board contains raster assets. Detected highlighter-framed headings appear under `Topics`; the viewer keeps direct wheel, pinch, drag, and keyboard navigation while its visible controls are `Topics` and `Fit`. YouTube links activate privacy-enhanced embeds; supported Algo Arcade game links open in a new tab with an accessible gamepad affordance.

The parser intentionally supports only the observed Apple Freeform subset: unrotated zero-origin pages; JPEG and 8-bit Flate images; affine image transforms; clipping and native paths; common device and named one/three-component ICC-based colors; stroke miter and dash state under non-singular similarity transforms; Freeform opacity resources; and HTTP or HTTPS URI annotations. Unsupported structures, including PDF text, fail explicitly.

## Local Use

The CI-supported toolchain uses GHC 9.6.6, Cabal 3.10.3.0, `zlib1g-dev`, Poppler, English-language Tesseract, and a Chromium-compatible browser. Poppler and Tesseract build the topic index; Python 3 is needed only for the local server.

Run the synthetic fixture:

```bash
make test      # Compile, run unit tests, inspect the fixture, and validate a build.
make evaluate  # Build, compare browser and PDF renders, and test the browser runtime.
make serve     # Build and serve the site at http://localhost:8000.
```

`make evaluate` does not run the unit-test suite, so run both `make test` and `make evaluate` when validating implementation changes.

Evaluate another source directory:

```bash
make evaluate \
  SOURCE=/absolute/path/to/consumer \
  DIST=/absolute/path/to/output/site \
  REPORT=/absolute/path/to/output/evaluation \
  SITE_TITLE='My Notes'
```

`SOURCE` must satisfy the PDF requirements above. `TEMPLATES` defaults to this repository's `site/` directory. `DIST`, its staging and backup paths, and `REPORT` must be non-symlink paths that do not overlap the source, templates, or each other. `make evaluate` also reserves `build/runtime-test`; do not overlap that path with `SOURCE`, `TEMPLATES`, `DIST`, or `REPORT`, and do not make `build` or `build/runtime-test` symlinks.

## Documentation

- [Architecture](docs/architecture.md): workflow, data flow, module ownership, and safety boundaries.
- [Apple Freeform PDF support profile](docs/pdf-investigation.md): supported parsing behavior, evidence, and limitations.
