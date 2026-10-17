# Notes Website Factory

Notes Website Factory turns one board document, a one-page PDF or a self-contained SVG, into a responsive, zoomable static website. A consumer repository supplies the document, a site title, and a GitHub Actions caller workflow. This repository supplies the Haskell generator, shared viewer, visual evaluation, and deployable Pages artifact.

The two formats take different paths through the generator:

- **PDF:** the generator parses the page into scene data, inline SVG artwork, links, and extracted raster assets. The site does not ship or parse the PDF in the browser. The parser supports the subset observed in Apple Freeform exports; see the [PDF support profile](docs/pdf-investigation.md).
- **SVG:** the generator validates the file and ships it unchanged. The viewer draws it as an isolated image, so scripts, hyperlinks, and external files cannot work there, and the build rejects them. See the [SVG support profile](docs/svg-support.md).

The factory is not a general-purpose PDF converter, SVG sanitizer, editor, or OCR tool.

## Requirements

A consumer repository needs:

- exactly one non-symlink source document in the searched directory: a one-page `.pdf` file or a self-contained `.svg` file;
- a non-empty `site-title` without control characters;
- GitHub Pages configured with **GitHub Actions** as its source.

Discovery searches the repository root, or the `source-directory` input, recursively and matches extensions without regard to case. It skips symbolic links and directories named `.git`, `build`, `dist`, `dist.building`, `dist.previous`, `dist-newstyle`, and `node_modules`. Other files may remain in the repository, but a PDF and an SVG together fail as ambiguous. Each support profile defines its supported content and failure behavior. The reusable workflow needs only `contents: read`; the consumer's deployment job owns Pages and OpenID Connect permissions.

## How to Use It

Start with the [Notes Website Template](https://github.com/bajor/notes-website-template) to get the caller workflow. After creating a repository from it, enable GitHub Pages with **GitHub Actions** as its source and add one supported PDF or SVG.

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

The workflow file keeps its original `build-pdf-site.yml` name and builds both formats. The workflow at `@main` can change between runs. Within each run, `job.workflow_sha` keeps the workflow and checked-out factory implementation on the same commit. Replace `main` with a full factory commit SHA to pin behavior.

| Input | Required | Default | Meaning |
| --- | --- | --- | --- |
| `site-title` | Yes | None | Browser title and accessible name of the board. |
| `source-directory` | No | `.` | Consumer-relative directory searched for the source document. It must resolve inside the repository; otherwise the build fails before it starts. |

To switch a consumer from PDF to SVG, replace the PDF with the exported SVG. The caller workflow does not change.

## Outputs

On success, the reusable workflow uploads:

| Artifact | Contents |
| --- | --- |
| `github-pages` | The validated static site, ready for `actions/deploy-pages`. |
| `pdf-site-evaluation` | Reference renders, browser renders, difference images, metrics, and `report.html`. The name predates SVG support and covers both formats. |

The reusable workflow does not deploy either artifact. If evaluation fails, it withholds `github-pages` and uploads available evaluation evidence when possible.

The reference render is Poppler's rendering of a PDF, or Chromium's direct rendering of an SVG. The evaluation report names the reference and includes sampled 4× and 8× detail comparisons for visual inspection alongside the fixed whole-board checks. See the [zoom-detail contract](docs/bdr/0018-zoom-detail-evidence.md) for selection and evidence filenames.

The site includes `index.html`, `runtime.js`, `styles.css`, `scene.generated.js`, and `scene-summary.json`. An `assets/` directory is added when a PDF board contains raster assets, and for an SVG source it holds the unchanged `assets/board.svg`. The viewer keeps direct wheel, pinch, drag, and keyboard navigation; its visible control is `Fit`. In PDF boards, YouTube links activate privacy-enhanced embeds, and supported Algo Arcade game links open in a new tab with an accessible gamepad affordance.

The PDF parser intentionally supports only the observed Apple Freeform subset: unrotated zero-origin pages; JPEG and 8-bit Flate images; affine image transforms; clipping and native paths; common device and named one/three-component ICC-based colors; stroke miter and dash state under non-singular similarity transforms; Freeform opacity resources; and HTTP or HTTPS URI annotations. Unsupported structures, including PDF text, fail explicitly.

An SVG source must be well-formed XML with an `svg` root in the SVG namespace, and its references must be `#fragment` targets or `data:` URIs. Scripts, event handlers, hyperlinks, `foreignObject`, external resources, and stylesheet imports fail explicitly.

## Local Use

The CI-supported toolchain uses GHC 9.6.6, Cabal 3.10.3.0, `zlib1g-dev`, Poppler, and a Chromium-compatible browser. Poppler supplies PDF evaluation references; Python 3 is needed only for the local server.

Run the synthetic fixtures:

```bash
make test      # Compile, run unit tests, and inspect and build the PDF and SVG fixtures.
make evaluate  # Build the PDF fixture, compare browser and reference renders, and test the browser runtime.
make serve     # Build and serve the PDF fixture site at http://localhost:8000.
make evaluate SOURCE="$PWD/generator/test/fixtures/svg"  # Evaluate the SVG fixture.
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

`SOURCE` must satisfy the requirements above. `TEMPLATES` defaults to this repository's `site/` directory. `DIST`, its staging and backup paths, and `REPORT` must be non-symlink paths that do not overlap the source, templates, or each other. `make evaluate` also reserves `build/runtime-test`; do not overlap that path with `SOURCE`, `TEMPLATES`, `DIST`, or `REPORT`, and do not make `build` or `build/runtime-test` symlinks.

## Documentation

- [Changelog](CHANGELOG.md): unreleased user-visible changes.
- [Architecture](docs/architecture.md): workflow, data flow, module ownership, and safety boundaries.
- [PDF support profile](docs/pdf-investigation.md): supported PDF parsing behavior, Apple Freeform evidence, and limitations.
- [SVG support profile](docs/svg-support.md): accepted and rejected SVG content, board size, rendering, and evaluation.
