import { LENGTH_EPS_MM } from './tolerance';
import type { Point2D, Segment2D } from './types';
import { cross, distance, dot, midpoint, normalize, sub } from './vector';
import type { Vector2D } from './types';

/** Довжина відрізка, мм. Завжди обчислюється з координат, ніколи не кешується окремо. */
export function segmentLength(s: Segment2D): number {
  return distance(s.a, s.b);
}

export function segmentMidpoint(s: Segment2D): Point2D {
  return midpoint(s.a, s.b);
}

/** Одиничний напрямок a→b; null для виродженого відрізка. */
export function segmentDirection(s: Segment2D, eps: number = LENGTH_EPS_MM): Vector2D | null {
  return normalize(sub(s.b, s.a), eps);
}

export interface ClosestPoint {
  readonly point: Point2D;
  /** Параметр уздовж відрізка, 0 = a, 1 = b. */
  readonly t: number;
  readonly distance: number;
}

/** Найближча до p точка відрізка. */
export function closestPointOnSegment(s: Segment2D, p: Point2D): ClosestPoint {
  const d = sub(s.b, s.a);
  const len2 = dot(d, d);
  let t = 0;
  if (len2 > 0) {
    t = dot(sub(p, s.a), d) / len2;
    t = Math.min(1, Math.max(0, t));
  }
  const point: Point2D = { x: s.a.x + d.x * t, y: s.a.y + d.y * t };
  return { point, t, distance: distance(p, point) };
}

export function distanceToSegment(s: Segment2D, p: Point2D): number {
  return closestPointOnSegment(s, p).distance;
}

export type SegmentIntersection =
  | { readonly kind: 'none' }
  | {
      readonly kind: 'point';
      readonly point: Point2D;
      /** Параметр на першому відрізку [0,1]. */
      readonly t: number;
      /** Параметр на другому відрізку [0,1]. */
      readonly u: number;
      /** true — перетин усередині обох відрізків (не в кінцях). false — торкання кінцем (L/T-стик). */
      readonly proper: boolean;
    }
  | {
      /** Колінеарні відрізки, що перекриваються на ділянці from→to. */
      readonly kind: 'overlap';
      readonly from: Point2D;
      readonly to: Point2D;
    };

/**
 * Перетин двох відрізків з допуском eps (мм).
 * Розрізняє: немає перетину / одна точка (внутрішня або в кінці) / колінеарне перекриття.
 */
export function intersectSegments(
  s1: Segment2D,
  s2: Segment2D,
  eps: number = LENGTH_EPS_MM,
): SegmentIntersection {
  const r = sub(s1.b, s1.a);
  const s = sub(s2.b, s2.a);
  const len1 = Math.hypot(r.x, r.y);
  const len2 = Math.hypot(s.x, s.y);
  if (len1 <= eps || len2 <= eps) return { kind: 'none' };

  const qp = sub(s2.a, s1.a);
  const denom = cross(r, s);
  const tEps = eps / len1;
  const uEps = eps / len2;

  // паралельні (синус кута між напрямками дуже малий)
  if (Math.abs(denom) <= 1e-12 * len1 * len2) {
    // відстань s2.a до прямої s1
    const offset = Math.abs(cross(qp, r)) / len1;
    if (offset > eps) return { kind: 'none' };
    // колінеарні: проєкції на r у параметрах t першого відрізка
    const t0 = dot(qp, r) / (len1 * len1);
    const t1 = t0 + dot(s, r) / (len1 * len1);
    const lo = Math.max(0, Math.min(t0, t1));
    const hi = Math.min(1, Math.max(t0, t1));
    if (hi < lo - tEps) return { kind: 'none' };
    if (hi - lo <= tEps) {
      const t = (lo + hi) / 2;
      const point: Point2D = { x: s1.a.x + r.x * t, y: s1.a.y + r.y * t };
      const u = dot(sub(point, s2.a), s) / (len2 * len2);
      return { kind: 'point', point, t, u: Math.min(1, Math.max(0, u)), proper: false };
    }
    return {
      kind: 'overlap',
      from: { x: s1.a.x + r.x * lo, y: s1.a.y + r.y * lo },
      to: { x: s1.a.x + r.x * hi, y: s1.a.y + r.y * hi },
    };
  }

  const t = cross(qp, s) / denom;
  const u = cross(qp, r) / denom;
  if (t < -tEps || t > 1 + tEps || u < -uEps || u > 1 + uEps) return { kind: 'none' };

  const tc = Math.min(1, Math.max(0, t));
  const uc = Math.min(1, Math.max(0, u));
  const point: Point2D = { x: s1.a.x + r.x * tc, y: s1.a.y + r.y * tc };
  const proper = t > tEps && t < 1 - tEps && u > uEps && u < 1 - uEps;
  return { kind: 'point', point, t: tc, u: uc, proper };
}

/**
 * Перетин нескінченних ліній, що проходять через відрізки (для прив'язки до перетину
 * продовжень, 2.2). null, якщо лінії паралельні.
 */
export function lineIntersection(s1: Segment2D, s2: Segment2D): Point2D | null {
  const r = sub(s1.b, s1.a);
  const s = sub(s2.b, s2.a);
  const denom = cross(r, s);
  const len1 = Math.hypot(r.x, r.y);
  const len2 = Math.hypot(s.x, s.y);
  if (len1 === 0 || len2 === 0 || Math.abs(denom) <= 1e-12 * len1 * len2) return null;
  const t = cross(sub(s2.a, s1.a), s) / denom;
  return { x: s1.a.x + r.x * t, y: s1.a.y + r.y * t };
}
