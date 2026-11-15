import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  applyToPoint,
  applyToVector,
  boundingBoxOf,
  boxContains,
  boxesOverlap,
  determinant,
  expandBox,
  IDENTITY,
  invert,
  isClosedRing,
  isSimplePolygon,
  multiply,
  orientation,
  pointInPolygon,
  polygonArea,
  rotation,
  scaling,
  signedArea,
  toPolygon,
  translation,
  type Point2D,
} from '../index';

const P = (x: number, y: number): Point2D => ({ x, y });
const rect = (x: number, y: number, w: number, h: number): Point2D[] => [P(x, y), P(x + w, y), P(x + w, y + h), P(x, y + h)];

describe('площа полігона (shoelace)', () => {
  it('прямокутник 3000×4000 = 12 000 000 мм² точно', () => {
    assert.equal(polygonArea(rect(0, 0, 3000, 4000)), 12_000_000);
  });
  it('далеко від початку координат площа та сама (стійкість)', () => {
    assert.equal(polygonArea(rect(1_000_000, 2_000_000, 3000, 4000)), 12_000_000);
  });
  it('Г-подібна форма: 12 000 000 мм²', () => {
    const l = [P(0, 0), P(4000, 0), P(4000, 2000), P(2000, 2000), P(2000, 4000), P(0, 4000)];
    assert.equal(polygonArea(l), 12_000_000);
  });
  it('трикутник 3-4-5: 6 000 000 мм²', () => {
    assert.equal(polygonArea([P(0, 0), P(3000, 0), P(0, 4000)]), 6_000_000);
  });
  it('менше трьох точок → 0', () => {
    assert.equal(signedArea([P(0, 0), P(1, 1)]), 0);
  });
});

describe('орієнтація', () => {
  it('CCW додатна, CW від\'ємна, колінеарні — degenerate', () => {
    const ccw = rect(0, 0, 1000, 1000);
    assert.equal(orientation(ccw), 'ccw');
    assert.ok(signedArea(ccw) > 0);
    assert.equal(orientation([...ccw].reverse()), 'cw');
    assert.ok(signedArea([...ccw].reverse()) < 0);
    assert.equal(orientation([P(0, 0), P(1000, 0), P(2000, 0)]), 'degenerate');
  });
});

describe('замкненість контуру', () => {
  it('замкнений: перша ≈ остання', () => {
    const ring = [...rect(0, 0, 3000, 4000), P(0, 0)];
    assert.equal(isClosedRing(ring), true);
    assert.equal(isClosedRing([...rect(0, 0, 3000, 4000), P(0.0004, 0)]), true); // у межах допуску
  });
  it('не замкнений: розрив або замало точок', () => {
    assert.equal(isClosedRing(rect(0, 0, 3000, 4000)), false);
    assert.equal(isClosedRing([...rect(0, 0, 3000, 4000), P(0, 5)]), false);
    assert.equal(isClosedRing([P(0, 0), P(10, 0), P(0, 0)]), false);
  });
  it('toPolygon прибирає замикальну вершину та дублікати', () => {
    const poly = toPolygon([P(0, 0), P(3000, 0), P(3000, 0), P(3000, 4000), P(0, 4000), P(0, 0)]);
    assert.ok(poly !== null);
    assert.equal(poly.points.length, 4);
    assert.equal(toPolygon(rect(0, 0, 10, 10)), null);
  });
});

describe('простота полігона', () => {
  it('прямокутник і Г-форма — прості', () => {
    assert.equal(isSimplePolygon(rect(0, 0, 3000, 4000)), true);
    assert.equal(isSimplePolygon([P(0, 0), P(4000, 0), P(4000, 2000), P(2000, 2000), P(2000, 4000), P(0, 4000)]), true);
  });
  it('«метелик» (самоперетин) — не простий', () => {
    assert.equal(isSimplePolygon([P(0, 0), P(1000, 1000), P(1000, 0), P(0, 1000)]), false);
  });
  it('виродженi: дубльована вершина, колінеарні точки, ребро, що повертається назад', () => {
    assert.equal(isSimplePolygon([P(0, 0), P(0, 0), P(1000, 0), P(0, 1000)]), false);
    assert.equal(isSimplePolygon([P(0, 0), P(1000, 0), P(2000, 0)]), false);
    assert.equal(isSimplePolygon([P(0, 0), P(2000, 0), P(1000, 0), P(1000, 1000)]), false);
  });
});

describe('точка в полігоні', () => {
  const r = rect(0, 0, 3000, 4000);
  it('всередині, зовні, на межі (з допуском)', () => {
    assert.equal(pointInPolygon(P(1500, 2000), r), 'inside');
    assert.equal(pointInPolygon(P(-1, 2000), r), 'outside');
    assert.equal(pointInPolygon(P(5000, 5000), r), 'outside');
    assert.equal(pointInPolygon(P(3000, 2000), r), 'boundary');
    assert.equal(pointInPolygon(P(0, 0), r), 'boundary');
    assert.equal(pointInPolygon(P(3000.0005, 2000), r), 'boundary');
  });
  it('угнуті форми: вріз Г-подібного полігона зовні', () => {
    const l = [P(0, 0), P(4000, 0), P(4000, 2000), P(2000, 2000), P(2000, 4000), P(0, 4000)];
    assert.equal(pointInPolygon(P(3000, 3000), l), 'outside');
    assert.equal(pointInPolygon(P(1000, 3000), l), 'inside');
  });
});

describe('габаритні рамки', () => {
  it('bbox, contains, overlap, expand', () => {
    const b = boundingBoxOf([P(1, 5), P(-3, 2), P(4, -1)]);
    assert.ok(b !== null);
    assert.deepEqual(b, { min: P(-3, -1), max: P(4, 5) });
    assert.equal(boundingBoxOf([]), null);
    assert.equal(boxContains(b, P(0, 0)), true);
    assert.equal(boxContains(b, P(10, 0)), false);
    assert.equal(boxesOverlap(b, { min: P(4, 5), max: P(9, 9) }), true);
    assert.equal(boxesOverlap(b, { min: P(5, 6), max: P(9, 9) }), false);
    assert.deepEqual(expandBox(b, 1), { min: P(-4, -2), max: P(5, 6) });
  });
});

describe('афінні перетворення', () => {
  it('зсув, масштаб, поворот на 90° (точний)', () => {
    assert.deepEqual(applyToPoint(translation(10, -5), P(1, 1)), P(11, -4));
    assert.deepEqual(applyToPoint(scaling(2), P(3, 4)), P(6, 8));
    const r = applyToPoint(rotation(Math.PI / 2), P(4000, 0));
    assert.ok(r.x === 0 && r.y === 4000);
  });
  it('порядок композиції: multiply(m1, m2) застосовує m2 першим', () => {
    const m = multiply(translation(100, 0), scaling(2)); // спочатку масштаб, потім зсув
    assert.deepEqual(applyToPoint(m, P(1, 1)), P(102, 2));
    const n = multiply(scaling(2), translation(100, 0)); // спочатку зсув, потім масштаб
    assert.deepEqual(applyToPoint(n, P(1, 1)), P(202, 2));
  });
  it('обернене перетворення відновлює точку', () => {
    const m = multiply(translation(1234.5, -987.25), multiply(rotation(0.7), scaling(1.5, 0.8)));
    const inv = invert(m);
    assert.ok(inv !== null);
    for (const p of [P(0, 0), P(3000, 4000), P(-250.5, 17)]) {
      const q = applyToPoint(inv, applyToPoint(m, p));
      assert.ok(Math.abs(q.x - p.x) < 1e-9 && Math.abs(q.y - p.y) < 1e-9);
    }
  });
  it('вироджена матриця не обертається; тотожне перетворення — одиниця', () => {
    assert.equal(invert(scaling(0, 1)), null);
    assert.equal(determinant(IDENTITY), 1);
    assert.deepEqual(applyToPoint(IDENTITY, P(7, 8)), P(7, 8));
  });
  it('вектор не отримує зсуву', () => {
    assert.deepEqual(applyToVector(translation(100, 100), { x: 3, y: 4 }), { x: 3, y: 4 });
  });
});
