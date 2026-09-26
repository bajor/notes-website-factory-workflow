# Changelog

## Unreleased

### Fixed

- Redraw sub-pixel handwriting from downsampled Freeform artwork as crisp vector ink instead of a raster that blurs at high zoom.
- Trace thin low-resolution lettering at its source weight as smooth curves instead of bold, blocky polygons.
- Keep sub-pixel handwriting from downsampled Freeform artwork as a source raster residual instead of tracing it into disconnected fragments.
- Prevent faint or cutoff-alpha fragments from degrading neighboring handwriting into pixel-grid outlines or disappearing during tracing.

### Changed

- Include bounded 4× and 8× handwriting-detail comparisons in evaluation reports.
- Trace SVG artwork at interpolated source-alpha crossings with a tight fixed simplification bound, replacing low-polygon pixel-cell contours.
- Retain source alpha `88` through `95` as a faint SVG layer within otherwise traceable artwork.

### Removed

- Removed build-time OCR, highlighter-frame topic recognition, generated topic metadata, and the viewer's Topics menu.
- Removed the Tesseract dependency from the reusable build workflow.
