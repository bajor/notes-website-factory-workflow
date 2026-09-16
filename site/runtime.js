import { scene } from './scene.generated.js';

const viewport = document.querySelector('#viewport');
const board = document.querySelector('#board');
const status = document.querySelector('#status');
const controls = document.querySelector('#controls');
const evaluationParameters = new URLSearchParams(window.location.search);
const evaluationDpi = Number(evaluationParameters.get('evaluation'));
const evaluationX = Number(evaluationParameters.get('evaluation-x')) || 0;
const evaluationY = Number(evaluationParameters.get('evaluation-y')) || 0;
const evaluationMode = Number.isFinite(evaluationDpi) && evaluationDpi > 0;
const readinessMode = evaluationMode && evaluationParameters.has('readiness');
const svgNamespace = 'http://www.w3.org/2000/svg';

const view = { scale: 1, x: 0, y: 0 };
const pointers = new Map();
let dragStart = null;
let pinchStart = null;
let sceneSvg;
let clipDefinitions;
let clipSequence = 0;

void initialize();

async function initialize() {
  try {
    if (evaluationMode) {
      controls.hidden = true;
      // PDF coordinates use 72 points per inch, so DPI / 72 gives the
      // matching browser scale for each evaluation resolution.
      view.scale = evaluationDpi / 72;
      view.x = -evaluationX;
      view.y = -evaluationY;
      applyView();
    } else {
      installControls();
      fitBoard();
    }
    await buildScene();
    await document.fonts.ready;
    if (readinessMode) board.replaceChildren();
    status.remove();
    document.body.dataset.ready = 'true';
  } catch (error) {
    status.textContent = `Scene failed: ${error.message}`;
    document.body.dataset.failed = 'true';
    throw error;
  }
}

async function buildScene() {
  board.style.width = `${scene.width}px`;
  board.style.height = `${scene.height}px`;
  sceneSvg = createSvgElement('svg');
  sceneSvg.classList.add('scene-svg');
  sceneSvg.setAttribute('viewBox', `0 0 ${scene.width} ${scene.height}`);
  sceneSvg.setAttribute('aria-hidden', 'true');
  clipDefinitions = createSvgElement('defs');
  sceneSvg.append(clipDefinitions);
  board.append(sceneSvg);

  const assets = new Map(scene.assets.map((asset) => [asset.id, asset]));
  const imageLoads = [];

  for (const node of scene.nodes) {
    if (node.kind === 'image') imageLoads.push(addImage(node, assets));
    if (node.kind === 'vector-artwork') addVectorArtwork(node);
    if (node.kind === 'path') addPath(node);
    if (node.kind === 'text') addText(node);
    if (node.kind === 'link') addLink(node);
  }

  await Promise.all(imageLoads);
  document.body.dataset.vectorArtworks = scene.nodes.filter((node) => node.kind === 'vector-artwork').length;
  document.body.dataset.rasterImages = scene.nodes.filter((node) => node.kind === 'image').length;
}

function addImage(node, assets) {
  const asset = assets.get(node.asset);
  if (!asset) throw new Error(`Missing generated asset ${node.asset}`);

  const image = createSvgElement('image');
  image.classList.add('scene-image');
  image.setAttribute('x', 0);
  image.setAttribute('y', 0);
  image.setAttribute('width', 1);
  image.setAttribute('height', 1);
  image.setAttribute('opacity', node.opacity);
  image.setAttribute('preserveAspectRatio', 'none');
  image.setAttribute('transform', cssMatrix(imagePresentationMatrix(node.matrix)));
  const loaded = new Promise((resolve, reject) => {
    image.addEventListener('load', resolve, { once: true });
    image.addEventListener('error', () => reject(new Error(`Could not load ${asset.file}`)), { once: true });
  });
  image.setAttribute('href', asset.file);
  appendVisual(image, node.clips);
  return loaded;
}

function addVectorArtwork(node) {
  const group = createSvgElement('g');
  group.classList.add('scene-vector-artwork');
  group.setAttribute('opacity', node.opacity);
  group.setAttribute('transform', cssMatrix(imagePresentationMatrix(node.matrix)));
  for (const shape of node.shapes) {
    const path = createSvgElement('path');
    path.setAttribute('d', shape.path);
    path.setAttribute('fill', cssColor(shape.color));
    path.setAttribute('fill-opacity', shape.opacity);
    path.setAttribute('fill-rule', 'evenodd');
    group.append(path);
  }
  appendVisual(group, node.clips);
}

function addPath(node) {
  const path = createSvgElement('path');
  path.classList.add('scene-path');
  path.setAttribute('d', pathData(node.commands));
  path.setAttribute('opacity', node.style.opacity);
  if (node.style.fill) {
    path.setAttribute('fill', cssColor(node.style.fill.color));
    path.setAttribute('fill-rule', node.style.fill.rule);
  } else {
    path.setAttribute('fill', 'none');
  }
  if (node.style.stroke) {
    path.setAttribute('stroke', cssColor(node.style.stroke));
    path.setAttribute('stroke-width', node.style.lineWidth);
    path.setAttribute('stroke-miterlimit', node.style.miterLimit);
    if (node.style.dashArray.length > 0) {
      path.setAttribute('stroke-dasharray', node.style.dashArray.join(' '));
      path.setAttribute('stroke-dashoffset', node.style.dashPhase);
    }
  }
  appendVisual(path, node.clips);
}

function addText(node) {
  const text = document.createElement('span');
  text.className = 'scene-text';
  text.textContent = node.value;
  text.style.fontFamily = node.fontFamily;
  text.style.fontSize = `${node.fontSize}px`;
  text.style.opacity = node.opacity;
  text.style.transform = cssMatrix(node.matrix);
  appendHtmlWithClips(text, node.clips);
}

function addLink(node) {
  const element = document.createElement(node.target.kind === 'youtube' ? 'button' : 'a');
  element.className = 'scene-link';
  positionLink(element, node.bounds);
  if (node.target.kind !== 'youtube') {
    element.href = node.target.url;
    element.target = '_blank';
    element.rel = 'noopener noreferrer';
    const label = node.target.kind === 'game' ? gameLabel(node.target.url) : `Open ${node.target.url}`;
    element.setAttribute('aria-label', label);
    if (node.target.kind === 'game') {
      element.title = label;
      if (!evaluationMode) addGameIcon(element);
    }
  } else {
    element.type = 'button';
    element.setAttribute('aria-label', 'Play YouTube video');
    element.addEventListener('click', () => activateYouTube(element, node.target));
  }
  board.append(element);
}

function gameLabel(url) {
  const encodedRoute = new URL(url).hash.slice('#/games/'.length);
  let route;
  try {
    route = decodeURIComponent(encodedRoute);
  } catch {
    route = encodedRoute;
  }
  return `Play ${route.replaceAll('-', ' ')} in Algo Arcade`;
}

function addGameIcon(element) {
  element.classList.add('scene-game-link');
  const icon = createSvgElement('svg');
  const path = createSvgElement('path');
  icon.classList.add('scene-game-icon');
  icon.setAttribute('viewBox', '0 0 24 24');
  icon.setAttribute('aria-hidden', 'true');
  path.setAttribute('d', 'M7 8h10a4 4 0 0 1 4 4v4a2 2 0 0 1-3.2 1.6L15.7 16H8.3l-2.1 1.6A2 2 0 0 1 3 16v-4a4 4 0 0 1 4-4ZM8 11v4M6 13h4M16 12h.01M18 14h.01');
  icon.append(path);
  element.append(icon);
}

function activateYouTube(element, target) {
  const iframe = document.createElement('iframe');
  iframe.className = 'scene-link scene-embed';
  iframe.style.cssText = element.style.cssText;
  iframe.src = `https://www.youtube-nocookie.com/embed/${encodeURIComponent(target.videoId)}`;
  iframe.title = 'YouTube video player';
  iframe.allow = 'accelerometer; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share';
  iframe.allowFullscreen = true;
  element.replaceWith(iframe);
}

function positionLink(element, bounds) {
  element.style.left = `${bounds.x}px`;
  element.style.top = `${bounds.y}px`;
  element.style.width = `${bounds.width}px`;
  element.style.height = `${bounds.height}px`;
}

function appendVisual(element, clips) {
  let child = element;
  for (const clip of [...clips].reverse()) {
    const wrapper = createSvgElement('g');
    const identifier = `clip-${clipSequence++}`;
    const clipPath = createSvgElement('clipPath');
    const path = createSvgElement('path');
    clipPath.id = identifier;
    clipPath.setAttribute('clipPathUnits', 'userSpaceOnUse');
    path.setAttribute('d', pathData(clip.commands));
    path.setAttribute('clip-rule', clip.rule);
    path.setAttribute('fill-rule', clip.rule);
    clipPath.append(path);
    clipDefinitions.append(clipPath);
    wrapper.setAttribute('clip-path', `url(#${identifier})`);
    wrapper.append(child);
    child = wrapper;
  }
  sceneSvg.append(child);
}

function appendHtmlWithClips(element, clips) {
  let child = element;
  for (const clip of [...clips].reverse()) {
    const wrapper = document.createElement('div');
    wrapper.className = 'scene-layer';
    wrapper.style.inset = '0';
    wrapper.style.clipPath = `path('${pathData(clip.commands)}')`;
    wrapper.append(child);
    child = wrapper;
  }
  board.append(child);
}

function createSvgElement(name) {
  return document.createElementNS(svgNamespace, name);
}

function installControls() {
  document.querySelector('[data-action="fit"]').addEventListener('click', fitBoard);
  viewport.addEventListener('wheel', onWheel, { passive: false });
  viewport.addEventListener('pointerdown', onPointerDown);
  viewport.addEventListener('pointermove', onPointerMove);
  viewport.addEventListener('pointerup', onPointerEnd);
  viewport.addEventListener('pointercancel', onPointerEnd);
  viewport.addEventListener('keydown', onKeyDown);
  window.addEventListener('resize', fitBoard);
}

function onKeyDown(event) {
  if (event.target !== viewport) return;
  const panStep = 48;
  const movement = {
    ArrowUp: [0, panStep],
    ArrowDown: [0, -panStep],
    ArrowLeft: [panStep, 0],
    ArrowRight: [-panStep, 0],
  }[event.key];
  if (!movement) return;
  event.preventDefault();
  view.x += movement[0];
  view.y += movement[1];
  applyView();
}

function onWheel(event) {
  event.preventDefault();
  zoomAt(Math.exp(-event.deltaY * 0.0015), event.clientX, event.clientY);
}

function onPointerDown(event) {
  if (event.target.closest('.scene-link')) return;
  viewport.setPointerCapture(event.pointerId);
  pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
  if (pointers.size === 1) dragStart = { pointer: pointers.get(event.pointerId), x: view.x, y: view.y };
  if (pointers.size === 2) pinchStart = currentPinch();
  viewport.classList.add('is-dragging');
}

function onPointerMove(event) {
  if (!pointers.has(event.pointerId)) return;
  pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
  if (pointers.size === 1 && dragStart) {
    const pointer = pointers.get(event.pointerId);
    view.x = dragStart.x + pointer.x - dragStart.pointer.x;
    view.y = dragStart.y + pointer.y - dragStart.pointer.y;
    applyView();
  }
  if (pointers.size === 2 && pinchStart) {
    const pinch = currentPinch();
    zoomAt(pinch.distance / pinchStart.distance, pinch.center.x, pinch.center.y);
    pinchStart = pinch;
  }
}

function onPointerEnd(event) {
  pointers.delete(event.pointerId);
  if (pointers.size < 2) pinchStart = null;
  if (pointers.size === 1) {
    const pointer = [...pointers.values()][0];
    dragStart = { pointer: { ...pointer }, x: view.x, y: view.y };
  }
  if (pointers.size === 0) {
    dragStart = null;
    viewport.classList.remove('is-dragging');
  }
}

function currentPinch() {
  const [first, second] = [...pointers.values()];
  return {
    center: { x: (first.x + second.x) / 2, y: (first.y + second.y) / 2 },
    distance: Math.hypot(second.x - first.x, second.y - first.y),
  };
}

function zoomAt(factor, screenX, screenY) {
  const nextScale = Math.min(16, Math.max(0.03, view.scale * factor));
  const boardX = (screenX - view.x) / view.scale;
  const boardY = (screenY - view.y) / view.scale;
  view.x = screenX - boardX * nextScale;
  view.y = screenY - boardY * nextScale;
  view.scale = nextScale;
  applyView();
}

function fitBoard() {
  const margin = 24;
  view.scale = Math.max(0.03, Math.min((viewport.clientWidth - margin * 2) / scene.width, (viewport.clientHeight - margin * 2) / scene.height));
  view.x = (viewport.clientWidth - scene.width * view.scale) / 2;
  view.y = (viewport.clientHeight - scene.height * view.scale) / 2;
  applyView();
}

function applyView() {
  board.style.transform = `translate(${view.x}px, ${view.y}px) scale(${view.scale})`;
}

function cssMatrix(matrix) {
  return `matrix(${matrix.a}, ${matrix.b}, ${matrix.c}, ${matrix.d}, ${matrix.e}, ${matrix.f})`;
}

function imagePresentationMatrix(matrix) {
  return {
    a: matrix.a,
    b: matrix.b,
    c: -matrix.c,
    d: -matrix.d,
    e: matrix.e + matrix.c,
    f: matrix.f + matrix.d,
  };
}

function cssColor(color) {
  return `rgb(${color.r * 255} ${color.g * 255} ${color.b * 255})`;
}

function pathData(commands) {
  return commands.map((command) => {
    if (command.kind === 'move') return `M ${command.point.x} ${command.point.y}`;
    if (command.kind === 'line') return `L ${command.point.x} ${command.point.y}`;
    if (command.kind === 'curve') return `C ${command.first.x} ${command.first.y} ${command.second.x} ${command.second.y} ${command.end.x} ${command.end.y}`;
    return 'Z';
  }).join(' ');
}
