/**
 * Числові допуски геометричного рушія.
 *
 * Усі довжини й координати — у МІЛІМЕТРАХ (див. docs/ARCHITECTURE.md, розділ 7).
 * Прямe порівняння чисел з плаваючою комою (===) для геометрії заборонене:
 * використовуйте функції цього модуля.
 */

/** Допуск збігу довжин/координат: 0,001 мм (1 мкм). */
export const LENGTH_EPS_MM = 1e-3;

/** Допуск збігу кутів, радіани. */
export const ANGLE_EPS_RAD = 1e-9;

/** Допуск для знакової площі (мм²) при визначенні виродженого полігона. */
export const AREA_EPS_MM2 = 1e-6;

export function nearlyEqual(a: number, b: number, eps: number = LENGTH_EPS_MM): boolean {
  return Math.abs(a - b) <= eps;
}

export function isNearlyZero(value: number, eps: number = LENGTH_EPS_MM): boolean {
  return Math.abs(value) <= eps;
}

/**
 * Округлення до кроку (за замовчуванням 0,001 мм). Використовується лише на межі
 * «фіксації» значення (введення користувача, запис), не всередині обчислень.
 */
export function quantize(value: number, step: number = 1e-3): number {
  const q = Math.round(value / step) * step;
  // уникаємо -0 і хвостів на кшталт 3000.0000000000005
  const decimals = Math.max(0, Math.ceil(-Math.log10(step)));
  const r = Number(q.toFixed(decimals));
  return r === 0 ? 0 : r;
}
