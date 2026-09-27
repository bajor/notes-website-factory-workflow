import { scene } from './scene.generated.js';

const mark = { x: 27000, y: 17000, width: 4, height: 4 };
scene.width = 30000;
scene.height = 20000;
const markRight = mark.x + mark.width;
const markBottom = mark.y + mark.height;
const markClip = [
  { kind: 'move', point: { x: mark.x, y: mark.y } },
  { kind: 'line', point: { x: markRight, y: mark.y } },
  { kind: 'line', point: { x: markRight, y: markBottom } },
  { kind: 'line', point: { x: mark.x, y: markBottom } },
  { kind: 'close' },
];
scene.nodes.push({
  kind: 'vector-artwork',
  shapes: [{ path: `M${mark.x},${mark.y}H${markRight}V${markBottom}H${mark.x}Z`, color: { r: 0, g: 0, b: 0 }, opacity: 1 }],
  opacity: 1,
  clips: [{ rule: 'nonzero', commands: markClip }],
}, {
  kind: 'link',
  target: { kind: 'external', url: 'https://example.com/zoom-marker' },
  bounds: mark,
});

try {
  await import('./runtime.js');
  while (!document.body.dataset.ready) {
    if (document.body.dataset.failed) throw new Error('Scene failed to initialize');
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  const viewport = document.querySelector('#viewport');
  const svg = document.querySelector('.scene-svg');
  const link = document.querySelector('a[href="https://example.com/zoom-marker"]');
  const markPath = [...document.querySelectorAll('.scene-vector-artwork path')].at(-1);
  const fittedScale = svg.getScreenCTM().a;
  const markCenter = new DOMPoint(mark.x + mark.width / 2, mark.y + mark.height / 2);
  const fittedCenter = markCenter.matrixTransform(svg.getScreenCTM());
  const anchor = new DOMPoint(Math.round(fittedCenter.x), Math.round(fittedCenter.y));
  const point = anchor.matrixTransform(svg.getScreenCTM().inverse());
  for (const scale of [4, 5, 8, 12, 16, 12, 8, 4]) {
    viewport.dispatchEvent(new WheelEvent('wheel', {
      clientX: anchor.x,
      clientY: anchor.y,
      deltaY: -Math.log(scale / svg.getScreenCTM().a) / 0.0015,
      cancelable: true,
    }));
    assertPresentation(anchor, scale);
  }
  assertBoardUnits();
  viewport.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true }));
  assertPresentation({ x: anchor.x + 48, y: anchor.y }, 4);
  document.querySelector('[data-action="fit"]').click();
  assertPresentation(anchor, fittedScale);
  document.body.dataset.zoomTest = 'passed';

  function assertPresentation(expected, scale) {
    const tolerance = 0.5;
    const scaleTolerance = 0.0001;
    if (Math.abs(svg.getScreenCTM().a - scale) > scaleTolerance) {
      throw new Error('Navigation did not reach the requested zoom');
    }
    const surface = svg.getBoundingClientRect();
    if (surface.width > viewport.clientWidth + tolerance || surface.height > viewport.clientHeight + tolerance) {
      throw new Error('Zoom enlarged the SVG rendering surface beyond the viewport');
    }
    const actual = point.matrixTransform(svg.getScreenCTM());
    if (Math.hypot(actual.x - expected.x, actual.y - expected.y) > tolerance) {
      throw new Error('Zoom anchor changed');
    }
    const visual = markPath.getBoundingClientRect();
    const overlay = link.getBoundingClientRect();
    if (Math.hypot(overlay.x + overlay.width / 2 - (visual.x + visual.width / 2), overlay.y + overlay.height / 2 - (visual.y + visual.height / 2)) > tolerance) {
      throw new Error('Visual/link alignment changed');
    }
  }

  // WebKit culls SVG content against a paint rectangle kept in 1/64 of the
  // local unit, so vector containers and paths must not rescale board points.
  function assertBoardUnits() {
    const matrixTolerance = 1e-6;
    const board = svg.getScreenCTM();
    for (const element of svg.querySelectorAll('g[clip-path], .scene-vector-artwork, .scene-vector-artwork path')) {
      const local = element.getScreenCTM();
      if (['a', 'b', 'c', 'd', 'e', 'f'].some((key) => Math.abs(local[key] - board[key]) > matrixTolerance)) {
        throw new Error('Vector content left board units');
      }
    }
  }
} catch (error) {
  document.body.dataset.zoomTest = 'failed';
  document.body.append(document.createTextNode(error.message));
  throw error;
}
