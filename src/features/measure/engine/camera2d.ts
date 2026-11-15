import type { BoundingBox2D, Point2D } from './types';

/**
 * Модель 2D-камери — єдине місце, де світові координати (мм, Y вгору) стикуються з екраном
 * (пікселі, Y вниз). Камера НЕ володіє геометрією: масштабування й панорамування змінюють лише
 * ці п'ять чисел, модельні координати лишаються незмінними.
 *
 * Стан камери — незмінний (immutable); усі операції повертають нову камеру.
 */
export interface Camera2D {
  /** Світова координата X точки, що знаходиться в центрі вікна перегляду, мм. */
  readonly centerX: number;
  /** Світова координата Y центру, мм. */
  readonly centerY: number;
  /** Масштаб: пікселів на 1 мм. */
  readonly zoom: number;
  /** Розмір вікна перегляду, px. */
  readonly width: number;
  readonly height: number;
}

/** 1 px = 1 м. */
export const MIN_ZOOM = 0.001;
/** 1 мм = 50 px. */
export const MAX_ZOOM = 50;
/** Початковий масштаб: 1 px = 10 мм (екран 1000 px показує 10 м). */
export const DEFAULT_ZOOM = 0.1;

export function clampZoom(zoom: number, min: number = MIN_ZOOM, max: number = MAX_ZOOM): number {
  if (!Number.isFinite(zoom)) return DEFAULT_ZOOM;
  return Math.min(max, Math.max(min, zoom));
}

/** Початковий вигляд: початок координат у центрі вікна. */
export function initialCamera(width: number, height: number): Camera2D {
  return { centerX: 0, centerY: 0, zoom: DEFAULT_ZOOM, width, height };
}

export function worldToScreen(cam: Camera2D, p: Point2D): Point2D {
  return {
    x: (p.x - cam.centerX) * cam.zoom + cam.width / 2,
    y: cam.height / 2 - (p.y - cam.centerY) * cam.zoom,
  };
}

export function screenToWorld(cam: Camera2D, s: Point2D): Point2D {
  return {
    x: cam.centerX + (s.x - cam.width / 2) / cam.zoom,
    y: cam.centerY - (s.y - cam.height / 2) / cam.zoom,
  };
}

/**
 * Масштабування відносно точки екрана (курсор/центр жесту): світова точка під курсором
 * лишається під курсором. factor > 1 — наближення.
 */
export function zoomAt(cam: Camera2D, screenPoint: Point2D, factor: number): Camera2D {
  if (!Number.isFinite(factor) || factor <= 0) return cam;
  const newZoom = clampZoom(cam.zoom * factor);
  if (newZoom === cam.zoom) return cam;
  const world = screenToWorld(cam, screenPoint);
  return {
    ...cam,
    zoom: newZoom,
    centerX: world.x - (screenPoint.x - cam.width / 2) / newZoom,
    centerY: world.y + (screenPoint.y - cam.height / 2) / newZoom,
  };
}

/** Панорамування: перетягування вмісту на (dx, dy) пікселів екрана. */
export function panByScreen(cam: Camera2D, dxPx: number, dyPx: number): Camera2D {
  return {
    ...cam,
    centerX: cam.centerX - dxPx / cam.zoom,
    centerY: cam.centerY + dyPx / cam.zoom,
  };
}

/** Зміна розміру вікна: центр і масштаб (світові) лишаються тими самими. */
export function resizeCamera(cam: Camera2D, width: number, height: number): Camera2D {
  return { ...cam, width, height };
}

/** Видима область у світових координатах. */
export function visibleWorldBox(cam: Camera2D): BoundingBox2D {
  const a = screenToWorld(cam, { x: 0, y: 0 });
  const b = screenToWorld(cam, { x: cam.width, y: cam.height });
  return {
    min: { x: Math.min(a.x, b.x), y: Math.min(a.y, b.y) },
    max: { x: Math.max(a.x, b.x), y: Math.max(a.y, b.y) },
  };
}

/** Камера, що вміщує область box з полями paddingPx. Для вироджених областей — початковий масштаб. */
export function fitToBox(cam: Camera2D, box: BoundingBox2D, paddingPx: number = 40): Camera2D {
  const w = box.max.x - box.min.x;
  const h = box.max.y - box.min.y;
  const availW = Math.max(1, cam.width - 2 * paddingPx);
  const availH = Math.max(1, cam.height - 2 * paddingPx);
  const zoom = w <= 0 && h <= 0 ? DEFAULT_ZOOM : clampZoom(Math.min(w > 0 ? availW / w : Infinity, h > 0 ? availH / h : Infinity));
  return {
    ...cam,
    zoom,
    centerX: (box.min.x + box.max.x) / 2,
    centerY: (box.min.y + box.max.y) / 2,
  };
}

/** Скільки мм світу припадає на 1 піксель (для порогів прив'язок і hit-test, що задаються в px). */
export function mmPerPixel(cam: Camera2D): number {
  return 1 / cam.zoom;
}
