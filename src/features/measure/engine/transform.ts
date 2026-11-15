import type { Point2D, Transform2D, Vector2D } from './types';
import { sinCos } from './vector';

export const IDENTITY: Transform2D = { a: 1, b: 0, c: 0, d: 1, e: 0, f: 0 };

export function translation(dx: number, dy: number): Transform2D {
  return { a: 1, b: 0, c: 0, d: 1, e: dx, f: dy };
}

export function scaling(sx: number, sy: number = sx): Transform2D {
  return { a: sx, b: 0, c: 0, d: sy, e: 0, f: 0 };
}

/** Поворот проти годинникової навколо початку координат (кути, кратні 90°, точні). */
export function rotation(rad: number): Transform2D {
  const { sin, cos } = sinCos(rad);
  return { a: cos, b: sin, c: -sin, d: cos, e: 0, f: 0 };
}

/** Композиція: result(p) = m1(m2(p)) — спочатку застосовується m2. */
export function multiply(m1: Transform2D, m2: Transform2D): Transform2D {
  return {
    a: m1.a * m2.a + m1.c * m2.b,
    b: m1.b * m2.a + m1.d * m2.b,
    c: m1.a * m2.c + m1.c * m2.d,
    d: m1.b * m2.c + m1.d * m2.d,
    e: m1.a * m2.e + m1.c * m2.f + m1.e,
    f: m1.b * m2.e + m1.d * m2.f + m1.f,
  };
}

export function determinant(m: Transform2D): number {
  return m.a * m.d - m.b * m.c;
}

/** Обернене перетворення; null, якщо матриця вироджена. */
export function invert(m: Transform2D): Transform2D | null {
  const det = determinant(m);
  if (!Number.isFinite(det) || Math.abs(det) < 1e-300) return null;
  const a = m.d / det;
  const b = -m.b / det;
  const c = -m.c / det;
  const d = m.a / det;
  return { a, b, c, d, e: -(a * m.e + c * m.f), f: -(b * m.e + d * m.f) };
}

export function applyToPoint(m: Transform2D, p: Point2D): Point2D {
  return { x: m.a * p.x + m.c * p.y + m.e, y: m.b * p.x + m.d * p.y + m.f };
}

/** Застосування лише лінійної частини (без зсуву) — для векторів. */
export function applyToVector(m: Transform2D, v: Vector2D): Vector2D {
  return { x: m.a * v.x + m.c * v.y, y: m.b * v.x + m.d * v.y };
}
