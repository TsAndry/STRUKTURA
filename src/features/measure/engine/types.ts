/**
 * Базові геометричні типи. Усі значення — у міліметрах (мм), якщо не сказано інше.
 * Система координат: X праворуч, Y ВГОРУ (математична), кути проти годинникової стрілки,
 * 0 рад = напрямок +X. Перетворення на екранну систему (Y вниз) робить лише camera2d.
 *
 * Модуль не залежить від React чи DOM.
 */

export interface Point2D {
  readonly x: number;
  readonly y: number;
}

export interface Vector2D {
  readonly x: number;
  readonly y: number;
}

export interface Segment2D {
  readonly a: Point2D;
  readonly b: Point2D;
}

/**
 * Простий полігон як кільце вершин БЕЗ повторення першої вершини в кінці.
 * (Перевірка «чи замкнений контур, заданий послідовністю точок» — isClosedRing у polygon.ts.)
 */
export interface Polygon2D {
  readonly points: readonly Point2D[];
}

export interface BoundingBox2D {
  readonly min: Point2D;
  readonly max: Point2D;
}

/**
 * Афінне перетворення 2D:
 *   x' = a·x + c·y + e
 *   y' = b·x + d·y + f
 */
export interface Transform2D {
  readonly a: number;
  readonly b: number;
  readonly c: number;
  readonly d: number;
  readonly e: number;
  readonly f: number;
}
