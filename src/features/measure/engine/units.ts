/**
 * Нормалізація введення та відображення довжин і кутів.
 *
 * Внутрішня одиниця довжини — міліметр (мм). Парсер перетворює «3 м», «300 см», «3000 мм»,
 * «3,5 м», «3.5 м» на мм БЕЗ накопичення похибок: десяткове число розбирається як ціле,
 * помножене на коефіцієнт одиниці й поділене на степінь десяти (одна операція ділення),
 * тому 1,1 м → рівно 1100 мм, а не 1100.0000000000002.
 *
 * Це межа UI: математичні функції рушія приймають лише мм.
 */

export type LengthUnit = 'mm' | 'cm' | 'm';

const UNIT_FACTOR_MM: Record<LengthUnit, number> = { mm: 1, cm: 10, m: 1000 };

const UNIT_ALIASES: Readonly<Record<string, LengthUnit>> = {
  мм: 'mm',
  mm: 'mm',
  см: 'cm',
  cm: 'cm',
  м: 'm',
  m: 'm',
};

export type ParseError =
  | 'empty'
  | 'invalid_format'
  | 'unknown_unit'
  | 'not_positive'
  | 'out_of_range';

export type ParseResult<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: ParseError };

export const PARSE_ERROR_MESSAGES_UK: Readonly<Record<ParseError, string>> = {
  empty: 'Введіть значення.',
  invalid_format: 'Невірний формат. Приклади: 3500, 350 см, 3,5 м.',
  unknown_unit: 'Невідома одиниця. Використовуйте мм, см або м.',
  not_positive: 'Значення має бути більшим за нуль.',
  out_of_range: 'Значення поза допустимими межами.',
};

export interface ParseLengthOptions {
  /** Одиниця для числа без позначення одиниці. За замовчуванням 'mm'. */
  readonly defaultUnit?: LengthUnit;
  /** Дозволити від'ємні значення (для координат). За замовчуванням false. */
  readonly allowNegative?: boolean;
  /** Дозволити нуль. За замовчуванням false. */
  readonly allowZero?: boolean;
  /** Максимальне за модулем значення, мм. За замовчуванням 1 000 000 (1 км). */
  readonly maxMm?: number;
}

const MAX_DIGITS = 12;

interface DecimalParts {
  readonly negative: boolean;
  readonly int: string;
  readonly frac: string;
  readonly unit: string;
  readonly trailingDot: boolean;
}

const DECIMAL_RE = /^([+-]?)(?:(\d+)(?:[.,](\d+))?|[.,](\d+))\s*(\p{L}*)(\.?)$/u;

function splitDecimal(input: string): DecimalParts | null {
  const cleaned = input.replace(/[   ]/g, ' ').trim();
  const m = DECIMAL_RE.exec(cleaned);
  if (!m) return null;
  return {
    negative: m[1] === '-',
    int: m[2] ?? '0',
    frac: m[3] ?? m[4] ?? '',
    unit: (m[5] ?? '').toLowerCase(),
    trailingDot: m[6] === '.',
  };
}

/** Точне значення (ціле n·factor / 10^k) з однією операцією ділення. */
function exactDecimal(parts: DecimalParts, factor: number): number | null {
  const digits = (parts.int + parts.frac).replace(/^0+(?=\d)/, '');
  if (digits.length > MAX_DIGITS) return null;
  const n = Number(digits);
  const k = parts.frac.length;
  const value = (n * factor) / 10 ** k;
  return parts.negative && value !== 0 ? -value : value;
}

/** Розбір довжини → міліметри. Не кидає винятків; помилку повертає значенням. */
export function parseLengthMm(input: string, options: ParseLengthOptions = {}): ParseResult<number> {
  const { defaultUnit = 'mm', allowNegative = false, allowZero = false, maxMm = 1_000_000 } = options;
  if (typeof input !== 'string' || input.trim() === '') return { ok: false, error: 'empty' };

  const parts = splitDecimal(input);
  if (!parts) return { ok: false, error: 'invalid_format' };
  if (parts.trailingDot && parts.unit === '') return { ok: false, error: 'invalid_format' };

  let unit: LengthUnit = defaultUnit;
  if (parts.unit !== '') {
    const u = UNIT_ALIASES[parts.unit];
    if (u === undefined) return { ok: false, error: 'unknown_unit' };
    unit = u;
  }

  const mm = exactDecimal(parts, UNIT_FACTOR_MM[unit]);
  if (mm === null || !Number.isFinite(mm)) return { ok: false, error: 'out_of_range' };
  if (mm < 0 && !allowNegative) return { ok: false, error: 'not_positive' };
  if (mm === 0 && !allowZero) return { ok: false, error: 'not_positive' };
  if (Math.abs(mm) > maxMm) return { ok: false, error: 'out_of_range' };
  return { ok: true, value: mm };
}

/**
 * Відображення довжини (мм → текст українською з десятковою комою). Лише для показу:
 * внутрішнє значення не змінюється й не залежить від округлення тексту.
 */
export function formatLengthMm(mm: number, unit: LengthUnit = 'm', decimals?: number): string {
  const defaults: Record<LengthUnit, number> = { mm: 0, cm: 1, m: 2 };
  const d = decimals ?? defaults[unit];
  const label: Record<LengthUnit, string> = { mm: 'мм', cm: 'см', m: 'м' };
  const raw = (mm / UNIT_FACTOR_MM[unit]).toFixed(d);
  const text = /^-0(\.0+)?$/.test(raw) ? raw.slice(1) : raw;
  return `${text.replace('.', ',')} ${label[unit]}`;
}

const ANGLE_RE = /^([+-]?)(?:(\d+)(?:[.,](\d+))?|[.,](\d+))\s*(°|º|град\.?|deg\.?)?$/iu;

/** Розбір кута в ГРАДУСАХ: «90», «90°», «45,5», «-30». Діапазон [-720, 720]. */
export function parseAngleDegrees(input: string): ParseResult<number> {
  if (typeof input !== 'string' || input.trim() === '') return { ok: false, error: 'empty' };
  const cleaned = input.replace(/[   ]/g, ' ').trim();
  const m = ANGLE_RE.exec(cleaned);
  if (!m) return { ok: false, error: 'invalid_format' };
  const parts: DecimalParts = {
    negative: m[1] === '-',
    int: m[2] ?? '0',
    frac: m[3] ?? m[4] ?? '',
    unit: '',
    trailingDot: false,
  };
  const deg = exactDecimal(parts, 1);
  if (deg === null || !Number.isFinite(deg) || Math.abs(deg) > 720) return { ok: false, error: 'out_of_range' };
  return { ok: true, value: deg };
}

/** Приведення кута в градусах до [0, 360). */
export function normalizeDegrees(deg: number): number {
  const r = ((deg % 360) + 360) % 360;
  return r === 0 ? 0 : r;
}

export function formatAngleDegrees(deg: number, decimals: number = 1): string {
  const raw = normalizeDegrees(deg).toFixed(decimals).replace('.', ',');
  return `${raw}°`;
}
