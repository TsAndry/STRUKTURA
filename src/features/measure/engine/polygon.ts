import { AREA_EPS_MM2, LENGTH_EPS_MM } from './tolerance';
import type { BoundingBox2D, Point2D, Polygon2D } from './types';
import { distanceToSegment, intersectSegments } from './segment';
import { cross, distance, sub } from './vector';

/**
 * Знакова площа (мм²) за формулою шнурування (shoelace).
 * Додатна — вершини проти годинникової (CCW) у системі з Y вгору.
 * Обчислюється відносно першої вершини для чисельної стійкості при великих координатах.
 * `points` — кільце БЕЗ повторення першої вершини в кінці.
 */
export function signedArea(points: readonly Point2D[]): number {
  const n = points.length;
  if (n < 3) return 0;
  const p0 = points[0] as Point2D;
  let sum = 0;
  for (let i = 1; i < n - 1; i++) {
    const pi = points[i] as Point2D;
    const pj = points[i + 1] as Point2D;
    sum += cross(sub(pi, p0), sub(pj, p0));
  }
  return sum / 2;
}

/** Абсолютна площа простого полігона, мм². НЕ перевіряє самоперетини (див. isSimplePolygon). */
export function polygonArea(points: readonly Point2D[]): number {
  return Math.abs(signedArea(points));
}

export type Orientation = 'ccw' | 'cw' | 'degenerate';

export function orientation(points: readonly Point2D[], eps: number = AREA_EPS_MM2): Orientation {
  const a = signedArea(points);
  if (Math.abs(a) <= eps) return 'degenerate';
  return a > 0 ? 'ccw' : 'cw';
}

/**
 * Чи є послідовність точок ЗАМКНЕНИМ контуром: перша й остання збігаються (з допуском)
 * і є щонайменше три різні вершини (разом ≥ 4 точки).
 */
export function isClosedRing(points: readonly Point2D[], eps: number = LENGTH_EPS_MM): boolean {
  if (points.length < 4) return false;
  const first = points[0] as Point2D;
  const last = points[points.length - 1] as Point2D;
  return distance(first, last) <= eps;
}

/**
 * Перетворює замкнений контур (першa ≈ остання) на Polygon2D: прибирає замикальну
 * вершину та послідовні дублікати. null, якщо контур не замкнений або має < 3 різних вершин.
 */
export function toPolygon(points: readonly Point2D[], eps: number = LENGTH_EPS_MM): Polygon2D | null {
  if (!isClosedRing(points, eps)) return null;
  const ring: Point2D[] = [];
  for (let i = 0; i < points.length - 1; i++) {
    const p = points[i] as Point2D;
    const prev = ring[ring.length - 1];
    if (prev === undefined || distance(prev, p) > eps) ring.push(p);
  }
  if (ring.length < 3) return null;
  return { points: ring };
}

/**
 * Простий полігон: ≥3 вершин, без нульових ребер, не вироджений за площею,
 * без самоперетинів і без накладання ребер.
 */
export function isSimplePolygon(points: readonly Point2D[], eps: number = LENGTH_EPS_MM): boolean {
  const n = points.length;
  if (n < 3) return false;

  for (let i = 0; i < n; i++) {
    if (distance(points[i] as Point2D, points[(i + 1) % n] as Point2D) <= eps) return false;
  }
  if (orientation(points) === 'degenerate') return false;

  const edge = (i: number) => ({ a: points[i] as Point2D, b: points[(i + 1) % n] as Point2D });

  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      const adjacentForward = j === i + 1;
      const adjacentWrap = i === 0 && j === n - 1;
      const res = intersectSegments(edge(i), edge(j), eps);
      if (adjacentForward || adjacentWrap) {
        if (res.kind === 'overlap') return false;
        if (res.kind === 'point') {
          const shared = adjacentForward ? (points[j] as Point2D) : (points[0] as Point2D);
          if (distance(res.point, shared) > eps) return false;
        }
      } else if (res.kind !== 'none') {
        return false;
      }
    }
  }
  return true;
}

export type PointLocation = 'inside' | 'outside' | 'boundary';

/** Положення точки відносно простого полігона (допуск eps для «на межі»). */
export function pointInPolygon(
  p: Point2D,
  points: readonly Point2D[],
  eps: number = LENGTH_EPS_MM,
): PointLocation {
  const n = points.length;
  if (n < 3) return 'outside';
  for (let i = 0; i < n; i++) {
    const seg = { a: points[i] as Point2D, b: points[(i + 1) % n] as Point2D };
    if (distanceToSegment(seg, p) <= eps) return 'boundary';
  }
  let inside = false;
  for (let i = 0, j = n - 1; i < n; j = i++) {
    const pi = points[i] as Point2D;
    const pj = points[j] as Point2D;
    if (pi.y > p.y !== pj.y > p.y) {
      const xCross = ((pj.x - pi.x) * (p.y - pi.y)) / (pj.y - pi.y) + pi.x;
      if (p.x < xCross) inside = !inside;
    }
  }
  return inside ? 'inside' : 'outside';
}

export function boundingBoxOf(points: readonly Point2D[]): BoundingBox2D | null {
  if (points.length === 0) return null;
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const p of points) {
    if (p.x < minX) minX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.x > maxX) maxX = p.x;
    if (p.y > maxY) maxY = p.y;
  }
  return { min: { x: minX, y: minY }, max: { x: maxX, y: maxY } };
}

export function boxContains(box: BoundingBox2D, p: Point2D, eps: number = 0): boolean {
  return (
    p.x >= box.min.x - eps && p.x <= box.max.x + eps && p.y >= box.min.y - eps && p.y <= box.max.y + eps
  );
}

export function boxesOverlap(a: BoundingBox2D, b: BoundingBox2D, eps: number = 0): boolean {
  return (
    a.min.x <= b.max.x + eps &&
    a.max.x >= b.min.x - eps &&
    a.min.y <= b.max.y + eps &&
    a.max.y >= b.min.y - eps
  );
}

export function expandBox(box: BoundingBox2D, margin: number): BoundingBox2D {
  return {
    min: { x: box.min.x - margin, y: box.min.y - margin },
    max: { x: box.max.x + margin, y: box.max.y + margin },
  };
}
