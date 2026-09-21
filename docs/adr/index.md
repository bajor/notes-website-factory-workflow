# Architecture Decisions

- [ADR 0001: Vector-first mixed rendering](/adr/0001-vector-first-mixed-rendering.md) - Accepted. Use traced SVG artwork with preserved raster screenshots.
- [ADR 0002: Separate factory and consumer repositories](/adr/0002-separate-factory-and-consumers.md) - Accepted. Keep production content and deployment outside the factory.
- [ADR 0003: Build artifacts with a reusable workflow](/adr/0003-build-artifacts-with-a-reusable-workflow.md) - Accepted. Centralize verified artifact production while consumers deploy.
- [ADR 0004: Preserve near-opaque linked cards and type exact game routes](/adr/0004-linked-game-cards.md) - Accepted. Use measured mask and URL trust boundaries.
- [ADR 0005: Preserve low-alpha soft masks as raster](/adr/0005-preserve-low-alpha-soft-masks-as-raster.md) - Superseded by ADR 0009.
- [ADR 0006: Tile oversized browser evaluations](/adr/0006-tile-oversized-browser-evaluations.md) - Accepted. Bound Chromium viewports and stitch complete evaluation images.
- [ADR 0007: Build topic navigation with source-pixel detection and local OCR](/adr/0007-build-time-topic-ocr.md) - Superseded by ADR 0008.
- [ADR 0008: Detect topics from a composited build render](/adr/0008-composited-topic-detection.md) - Superseded by ADR 0010.
- [ADR 0009: Render recognized highlighter strokes as opaque](/adr/0009-opaque-highlighter-strokes.md) - Accepted. Add a narrow exception to low-alpha preservation.
- [ADR 0010: Remove topic recognition and navigation](/adr/0010-remove-topic-recognition-and-navigation.md) - Accepted. Keep the generated scene source-derived and the viewer focused on direct navigation.
- [ADR 0011: Bounded zoom-detail evidence](/adr/0011-bounded-zoom-detail-evidence.md) - Accepted. Supplement whole-board gates with enlarged handwriting crops.
