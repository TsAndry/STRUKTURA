import { visibleWorldBox, type Camera2D } from './camera2d';

/** «Гарні» кроки сітки, мм: 1-2-5 по порядках, від 1 мм до 100 м. */
const NICE_STEPS_MM: readonly number[] = [
  1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000,
];

export interface GridSpec {
  /** Дрібний крок, мм. */
  readonly minorMm: number;
  /** Основний крок, мм (завжди кратний minorMm; 10×). */
  readonly majorMm: number;
}

/**
 * Крок сітки залежно від масштабу: найменший «гарний» крок, при якому відстань між дрібними
 * лініями на екрані ≥ minPx. Таким чином щільність сітки змінюється разом із масштабом.
 */
export function chooseGridSpec(zoom: number, minPx: number = 14): GridSpec {
  let minor = NICE_STEPS_MM[NICE_STEPS_MM.length - 1] as number;
  for (const step of NICE_STEPS_MM) {
    if (step * zoom >= minPx) {
      minor = step;
      break;
    }
  }
  return { minorMm: minor, majorMm: minor * 10 };
}

export interface GridLine {
  /** Світова координата лінії, мм (завжди ціле кратне кроку: k·minorMm). */
  readonly value: number;
  readonly major: boolean;
}

export interface GridLines {
  readonly spec: GridSpec;
  /** Вертикальні лінії (x = const). */
  readonly vertical: readonly GridLine[];
  /** Горизонтальні лінії (y = const). */
  readonly horizontal: readonly GridLine[];
}

function linesInRange(min: number, max: number, spec: GridSpec): GridLine[] {
  const kMin = Math.ceil(min / spec.minorMm);
  const kMax = Math.floor(max / spec.minorMm);
  const out: GridLine[] = [];
  for (let k = kMin; k <= kMax; k++) {
    // k — ціле, тому позиції не накопичують похибку додавання кроків
    // k === 0 окремо: ceil(-0.3) дає -0, а -0 × крок = -0 (недопустиме значення координати)
    out.push({ value: k === 0 ? 0 : k * spec.minorMm, major: k % 10 === 0 });
  }
  return out;
}

/**
 * Лінії сітки, що потрапляють у видиму область. Позиції = ціле k × крок
 * (не накопичуються додаванням). Якщо ліній було б більше за maxLines на вісь —
 * крок збільшується, щоб захистити рендер.
 */
export function visibleGridLines(cam: Camera2D, minPx: number = 14, maxLines: number = 600): GridLines {
  const box = visibleWorldBox(cam);
  let minPxEff = minPx;
  let spec = chooseGridSpec(cam.zoom, minPxEff);
  for (let guard = 0; guard < 8; guard++) {
    const nx = (box.max.x - box.min.x) / spec.minorMm;
    const ny = (box.max.y - box.min.y) / spec.minorMm;
    if (nx <= maxLines && ny <= maxLines) break;
    minPxEff *= 2;
    spec = chooseGridSpec(cam.zoom, minPxEff);
  }
  return {
    spec,
    vertical: linesInRange(box.min.x, box.max.x, spec),
    horizontal: linesInRange(box.min.y, box.max.y, spec),
  };
}
