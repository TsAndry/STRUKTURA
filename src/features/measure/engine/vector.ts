import { ANGLE_EPS_RAD, LENGTH_EPS_MM } from './tolerance';
import type { Point2D, Vector2D } from './types';

export function vec(x: number, y: number): Vector2D {
  return { x, y };
}

export function add(u: Vector2D, v: Vector2D): Vector2D {
  return { x: u.x + v.x, y: u.y + v.y };
}

export function sub(u: Vector2D, v: Vector2D): Vector2D {
  return { x: u.x - v.x, y: u.y - v.y };
}

export function scale(v: Vector2D, k: number): Vector2D {
  return { x: v.x * k, y: v.y * k };
}

export function dot(u: Vector2D, v: Vector2D): number {
  return u.x * v.x + u.y * v.y;
}

/** Z-компонента векторного добутку (орієнтована площа паралелограма). */
export function cross(u: Vector2D, v: Vector2D): number {
  return u.x * v.y - u.y * v.x;
}

export function lengthOf(v: Vector2D): number {
  return Math.hypot(v.x, v.y);
}

/**
 * Одиничний вектор. Повертає null для нульового вектора (довжина ≤ eps),
 * щоб виклик не міг непомітно отримати NaN.
 */
export function normalize(v: Vector2D, eps: number = LENGTH_EPS_MM): Vector2D | null {
  const len = lengthOf(v);
  if (len <= eps) return null;
  return { x: v.x / len, y: v.y / len };
}

export function distance(p: Point2D, q: Point2D): number {
  return Math.hypot(q.x - p.x, q.y - p.y);
}

export function midpoint(p: Point2D, q: Point2D): Point2D {
  return { x: (p.x + q.x) / 2, y: (p.y + q.y) / 2 };
}

/** Лінійна інтерполяція p→q при t∈[0,1]. */
export function lerp(p: Point2D, q: Point2D, t: number): Point2D {
  return { x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t };
}

/** Вектор, повернутий на +90° (проти годинникової). */
export function perpendicular(v: Vector2D): Vector2D {
  return { x: -v.y, y: v.x };
}

/**
 * sin і cos із «прилипанням» до точних значень 0, ±1 для кутів, кратних 90°
 * (з допуском ANGLE_EPS_RAD). Це гарантує, що поворот на 90° дає ТОЧНО вертикальний
 * напрямок, а не (6e-17, 1).
 */
export function sinCos(rad: number): { sin: number; cos: number } {
  let s = Math.sin(rad);
  let c = Math.cos(rad);
  if (Math.abs(s) <= ANGLE_EPS_RAD) s = 0;
  if (Math.abs(c) <= ANGLE_EPS_RAD) c = 0;
  if (Math.abs(Math.abs(s) - 1) <= ANGLE_EPS_RAD) s = Math.sign(s);
  if (Math.abs(Math.abs(c) - 1) <= ANGLE_EPS_RAD) c = Math.sign(c);
  return { sin: s, cos: c };
}

/** Поворот вектора на кут rad (проти годинникової) навколо початку координат. */
export function rotate(v: Vector2D, rad: number): Vector2D {
  const { sin, cos } = sinCos(rad);
  return { x: v.x * cos - v.y * sin, y: v.x * sin + v.y * cos };
}

/** Поворот точки навколо центру. */
export function rotateAround(p: Point2D, center: Point2D, rad: number): Point2D {
  const r = rotate(sub(p, center), rad);
  return { x: center.x + r.x, y: center.y + r.y };
}

/** Полярний кут вектора, радіани, (−π, π]. Для нульового вектора повертає 0. */
export function angleOf(v: Vector2D): number {
  return Math.atan2(v.y, v.x);
}

/** Знаковий кут від u до v, радіани, (−π, π]. */
export function angleBetween(u: Vector2D, v: Vector2D): number {
  return Math.atan2(cross(u, v), dot(u, v));
}

/** Нормалізація кута до [0, 2π). */
export function normalizeAngle(rad: number): number {
  const twoPi = 2 * Math.PI;
  let r = rad % twoPi;
  if (r < 0) r += twoPi;
  return r === 0 ? 0 : r;
}

export function degToRad(deg: number): number {
  return (deg * Math.PI) / 180;
}

export function radToDeg(rad: number): number {
  return (rad * 180) / Math.PI;
}

/** Вектор заданої довжини під кутом (рад) — для «довжина + кут». Для кутів 0/90/180/270 результат точний. */
export function fromPolar(length: number, rad: number): Vector2D {
  const { sin, cos } = sinCos(rad);
  return { x: length * cos, y: length * sin };
}
