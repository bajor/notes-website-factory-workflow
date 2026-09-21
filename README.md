# Notes Website Factory

Notes Website Factory turns a one-page Apple Freeform PDF into a responsive, zoomable static website. A consumer repository supplies the PDF, a site title, and a GitHub Actions caller workflow. This repository supplies the Haskell generator, shared viewer, visual evaluation, and deployable Pages artifact.

The generated site renders scene data, inline SVG artwork, links, and extracted raster assets. It does not ship or parse the source PDF in the browser. It is not a general-purpose PDF converter, editor, or OCR tool; see the [Apple Freeform PDF support profile](docs/pdf-investigation.md) for the supported export profile and limitations.

## Requirements

A consumer repository needs:

- exactly one non-symlink, one-page PDF;
- a non-empty `site-title` without control characters;
- GitHub Pages configured with **GitHub Actions** as its source.

Other files may remain in the consumer repository. PDF discovery exclusions, the supported profile, and failure behavior are defined in the [support profile](docs/pdf-investigation.md). The reusable workflow needs only `contents: read`; the consumer's deployment job owns Pages and OpenID Connect permissions.

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

The evaluation report includes sampled 4× and 8× detail comparisons for visual inspection alongside the fixed whole-board checks. See the [zoom-detail contract](docs/bdr/0018-zoom-detail-evidence.md) for selection and evidence filenames.

The site includes `index.html`, `runtime.js`, `styles.css`, `scene.generated.js`, and `scene-summary.json`. An `assets/` directory is added only when the board contains raster assets. The viewer keeps direct wheel, pinch, drag, and keyboard navigation; its visible control is `Fit`. YouTube links activate privacy-enhanced embeds; supported Algo Arcade game links open in a new tab with an accessible gamepad affordance.

The parser intentionally supports only the observed Apple Freeform subset: unrotated zero-origin pages; JPEG and 8-bit Flate images; affine image transforms; clipping and native paths; common device and named one/three-component ICC-based colors; stroke miter and dash state under non-singular similarity transforms; Freeform opacity resources; and HTTP or HTTPS URI annotations. Unsupported structures, including PDF text, fail explicitly.

## Local Use

The CI-supported toolchain uses GHC 9.6.6, Cabal 3.10.3.0, `zlib1g-dev`, Poppler, and a Chromium-compatible browser. Poppler supplies development evaluation references; Python 3 is needed only for the local server.

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

- [Changelog](CHANGELOG.md): unreleased user-visible changes.
- [Architecture](docs/architecture.md): workflow, data flow, module ownership, and safety boundaries.
- [Apple Freeform PDF support profile](docs/pdf-investigation.md): supported parsing behavior, evidence, and limitations.
