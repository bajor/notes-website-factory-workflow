export const scene = {
  width: 200,
  height: 140,
  assets: [
    {
      id: 'asymmetric-raster',
      file: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 2 1'%3E%3Cpath fill='red' d='M0 0h1v1H0z'/%3E%3Cpath fill='blue' d='M1 0h1v1H1z'/%3E%3C/svg%3E",
      width: 2,
      height: 1,
    },
  ],
  nodes: [
    {
      kind: 'path',
      commands: [
        { kind: 'move', point: { x: 10, y: 10 } },
        { kind: 'line', point: { x: 80, y: 10 } },
      ],
      style: {
        fill: null,
        stroke: { r: 0.25, g: 0.5, b: 0.75 },
        lineWidth: 2,
        miterLimit: 4,
        dashArray: [6, 3],
        dashPhase: 1,
        opacity: 1,
      },
      clips: [],
    },
    {
      kind: 'vector-artwork',
      shapes: [{ path: 'M0,0L1,0L0,1Z', color: { r: 1, g: 0, b: 0 }, opacity: 1 }],
      matrix: { a: 0, b: 20, c: -30, d: 0, e: 80, f: 90 },
      opacity: 1,
      clips: [],
    },
    {
      kind: 'image',
      asset: 'asymmetric-raster',
      matrix: { a: 40, b: 10, c: -5, d: 20, e: 15, f: 25 },
      opacity: 1,
      clips: [],
    },
    {
      kind: 'link',
      target: { kind: 'game', url: 'https://bajor.github.io/algo-arcade/#/games/example-game' },
      bounds: { x: 20, y: 20, width: 60, height: 60 },
    },
    {
      kind: 'link',
      target: { kind: 'youtube', videoId: 'abcdefghijk' },
      bounds: { x: 100, y: 20, width: 60, height: 60 },
    },
    {
      kind: 'link',
      target: { kind: 'game', url: 'https://bajor.github.io/algo-arcade/#/games/%FF' },
      bounds: { x: 20, y: 100, width: 60, height: 20 },
    },
  ],
};
