# Agent Guide

## Scope

Maintain the reusable factory that converts a consumer repository's one-page Apple Freeform PDF into a validated static-site artifact. Keep public usage in `README.md`, architecture and module ownership in `docs/architecture.md`, and parser support in `docs/pdf-investigation.md`; link to those files instead of duplicating their facts here.

Before changing parser, workflow, rendering, or product behavior, read:

- `docs/constitution.md` for foundational constraints;
- `docs/architecture.md` for boundaries, data flow, and public contracts;
- `docs/pdf-investigation.md` for the supported export profile;
- every relevant accepted PRD, ADR, and BDR, plus linked implementation issues, reached through `docs/index.md`. Resolve its `/...` links relative to the `docs/` bundle root.

## Living Docs

enforcement: strict
onboarded: 2026-08-20

Every concept has one canonical home and remains reachable from `docs/index.md`. Supersede accepted decisions and requirements instead of rewriting their history.

## Guardrails

- Keep production notes PDFs in consumer repositories. The factory contains only synthetic test fixtures.
- Keep production parsing in Haskell with `pdf-toolbox` and project-owned interpretation and validation.
- Preserve source content without inventing text or geometry. Never turn unsupported PDF text into DOM text.
- Keep the generated product independent of the source PDF, full-page PDF rasters, browser PDF parsers, Canvas fallbacks, and a backend.
- Fail when observed content cannot be represented safely; do not silently omit it or weaken validation.
- Keep consumer input, the factory checkout, site output, and evaluation evidence in separate roots. Templates remain factory-owned and protected from removable paths.
- Never allow a removable output, staging, backup, scratch, or report path to overlap a protected root or another independently owned output root.
- Keep behavior independent of consumer filenames, dimensions, resource names, scene counts, repository names, and complete content URLs.
- Do not add Rust, TypeScript, Node, Vite, Sharp, OpenSeadragon, or a backend as a project requirement.
- Keep Chromium and Poppler in development and CI evaluation only.

## Architecture and Compatibility

- Respect the module boundaries in `docs/architecture.md`. Moving ownership or changing data flow requires an architecture update and a PR-only SVG in `visual-explanations/`.
- Treat the workflow inputs, artifact names, generated filenames, and behavior documented in `README.md` and `.github/workflows/build-pdf-site.yml` as stable public interfaces.
- Make new workflow inputs optional unless every known consumer is migrated in the same coordinated change.
- Keep factory checkout pinned to `job.workflow_sha` within each workflow run.
- Do not grant the reusable build workflow Pages write or OpenID Connect token permissions.
- Do not widen provider-specific URL trust boundaries without documented consumer evidence and the required PRD, ADR, BDR, and tests.

## Implementation Rules

- Use GHC2021, `-Wall`, `-Wcompat`, and `-Werror`.
- Prefer named domain types and sum types over primitives and boolean flags.
- Return `Either BuildError value` for expected parsing and validation failures.
- Keep deterministic transformations pure and put filesystem or process effects at module boundaries.
- Preserve deterministic ordering when reading unordered PDF dictionaries.
- Inspect the existing domain and interpreter before adding a type or PDF operator.
- Base parser changes on a real consumer PDF observation or a focused failing test.
- Add one focused unit test for each new pure behavior. Avoid duplicate assertions and real I/O in unit tests.
- Do not weaken evaluation thresholds or make them caller-configurable to accommodate another source.
- Keep functions short, single-purpose, and free of speculative abstractions or dependencies.

## Documentation Updates

| Change | Canonical update |
| --- | --- |
| Public setup, inputs, outputs, or usage | `README.md` |
| Supported PDF behavior or limitation | `docs/pdf-investigation.md` |
| Module ownership, architecture, or data flow | `docs/architecture.md` and a PR-only SVG |
| Product requirement or observable behavior | Supersede or add the relevant PRD or BDR and update its index |
| Load-bearing implementation decision | Add an ADR and update `docs/adr/index.md` |
| Implementation work or completion evidence | Add or update the linked issue and `docs/issues/index.md` |
| New project term | `docs/context/glossary.md` and its index |

Do not copy detailed requirements, decisions, test scenarios, thresholds, or module maps into multiple documents.

## Verification

| Change | Required verification |
| --- | --- |
| Documentation only | Check links, commands, public names, and consistency with executable configuration. |
| Any implementation | Run focused tests and `make test`. |
| Parser, geometry, rendering, asset, style, template, or browser runtime | Run `make test` and `make evaluate`; inspect `build/evaluation/report.html`. |
| Parser support | Validate the real consumer PDF that motivated the change and record the evidence. |
| Reusable workflow boundary | Exercise isolated consumer and factory paths through the reusable workflow. |
| Consumer migration | Run the reusable workflow against the real consumer and validate its deployment separately. |

Factory CI must call `.github/workflows/build-pdf-site.yml` against the synthetic fixture. `make evaluate` is not a substitute for `make test`.

## Repository Hygiene

Do not commit `dist/`, `build/`, `dist-newstyle/`, generated evaluation images, or Mermaid source. A change is complete when the applicable verification above passes, required evaluation reports have been inspected, living-doc records and indexes are current, consumer evidence is recorded when required, and no generated or prohibited artifact is staged.
