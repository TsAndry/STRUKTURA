import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  add,
  angleBetween,
  angleOf,
  closestPointOnSegment,
  cross,
  degToRad,
  distance,
  dot,
  fromPolar,
  intersectSegments,
  lengthOf,
  lineIntersection,
  normalize,
  normalizeAngle,
  radToDeg,
  rotate,
  rotateAround,
  segmentDirection,
  segmentLength,
  segmentMidpoint,
  sub,
} from '../index';

const seg = (ax: number, ay: number, bx: number, by: number) => ({ a: { x: ax, y: ay }, b: { x: bx, y: by } });

describe('вектори', () => {
  it('відстань і довжина (3-4-5)', () => {
    assert.equal(distance({ x: 0, y: 0 }, { x: 3, y: 4 }), 5);
    assert.equal(lengthOf({ x: 3, y: 4 }), 5);
  });

  it('додавання, віднімання, скалярний і векторний добуток', () => {
    assert.deepEqual(add({ x: 1, y: 2 }, { x: 3, y: 4 }), { x: 4, y: 6 });
    assert.deepEqual(sub({ x: 5, y: 7 }, { x: 3, y: 4 }), { x: 2, y: 3 });
    assert.equal(dot({ x: 1, y: 2 }, { x: 3, y: 4 }), 11);
    assert.equal(cross({ x: 1, y: 0 }, { x: 0, y: 1 }), 1);
    assert.equal(cross({ x: 0, y: 1 }, { x: 1, y: 0 }), -1);
  });

  it('нормалізація; нульовий вектор → null (без NaN)', () => {
    const n = normalize({ x: 3, y: 4 });
    assert.ok(n !== null);
    assert.ok(Math.abs(n.x - 0.6) < 1e-15 && Math.abs(n.y - 0.8) < 1e-15);
    assert.equal(normalize({ x: 0, y: 0 }), null);
    assert.equal(normalize({ x: 1e-6, y: 0 }), null); // менше за допуск 0,001 мм
  });

  it('поворот на 90° дає ТОЧНО вертикальний вектор', () => {
    const r = rotate({ x: 1, y: 0 }, Math.PI / 2);
    assert.ok(r.x === 0, `x має бути 0, а не ${r.x}`);
    assert.ok(r.y === 1);
    const r2 = rotate({ x: 4000, y: 0 }, degToRad(90));
    assert.ok(r2.x === 0 && r2.y === 4000);
    const r3 = rotate({ x: 4000, y: 0 }, degToRad(180));
    assert.ok(r3.x === -4000 && r3.y === 0);
    const r4 = rotate({ x: 4000, y: 0 }, degToRad(270));
    assert.ok(r4.x === 0 && r4.y === -4000);
  });

  it('поворот навколо центру', () => {
    const p = rotateAround({ x: 2000, y: 1000 }, { x: 1000, y: 1000 }, Math.PI / 2);
    assert.ok(p.x === 1000 && p.y === 2000);
  });

  it('кути: atan2, знаковий кут між векторами, нормалізація', () => {
    assert.ok(Math.abs(angleOf({ x: 0, y: 1 }) - Math.PI / 2) < 1e-15);
    assert.ok(Math.abs(angleBetween({ x: 1, y: 0 }, { x: 0, y: 1 }) - Math.PI / 2) < 1e-15);
    assert.ok(Math.abs(angleBetween({ x: 0, y: 1 }, { x: 1, y: 0 }) + Math.PI / 2) < 1e-15);
    assert.ok(Math.abs(normalizeAngle(-Math.PI / 2) - (3 * Math.PI) / 2) < 1e-15);
    assert.ok(Math.abs(radToDeg(degToRad(37.5)) - 37.5) < 1e-12);
  });

  it('fromPolar: довжина 4000 мм під кутом 90° — точно вертикально', () => {
    const v = fromPolar(4000, degToRad(90));
    assert.ok(v.x === 0 && v.y === 4000);
    const h = fromPolar(4000, degToRad(180));
    assert.ok(h.x === -4000 && h.y === 0);
  });

  it('fromPolar для 0°, 45°, 135° зберігає довжину', () => {
    for (const deg of [0, 45, 90, 135, 180, 225, 270, 315, 17.3]) {
      const v = fromPolar(4000, degToRad(deg));
      assert.ok(Math.abs(lengthOf(v) - 4000) < 1e-9, `кут ${deg}°`);
    }
  });
});

describe('відрізки — довжина (тести 1, 2, 3, 6)', () => {
  it('Тест 1: (0,0)-(3000,0) = 3000 мм', () => {
    assert.equal(segmentLength(seg(0, 0, 3000, 0)), 3000);
  });
  it('Тест 2: (0,0)-(0,5000) = 5000 мм', () => {
    assert.equal(segmentLength(seg(0, 0, 0, 5000)), 5000);
  });
  it('Тест 3: (0,0)-(3000,4000) = 5000 мм', () => {
    assert.equal(segmentLength(seg(0, 0, 3000, 4000)), 5000);
  });
  it('Тест 6: поворот відрізка 4000 мм на 90° — довжина 4000 мм, кінець (0, 4000)', () => {
    const s = seg(0, 0, 4000, 0);
    const b = rotate(s.b, Math.PI / 2);
    assert.equal(segmentLength({ a: s.a, b }), 4000);
    assert.ok(b.x === 0 && b.y === 4000);
  });
  it('середина і напрямок', () => {
    assert.deepEqual(segmentMidpoint(seg(0, 0, 3000, 4000)), { x: 1500, y: 2000 });
    const d = segmentDirection(seg(0, 0, 0, 5000));
    assert.ok(d !== null && d.x === 0 && d.y === 1);
    assert.equal(segmentDirection(seg(10, 10, 10, 10)), null);
  });
});

describe('найближча точка', () => {
  it('усередині відрізка, до кінців (затискання)', () => {
    const s = seg(0, 0, 1000, 0);
    const mid = closestPointOnSegment(s, { x: 400, y: 300 });
    assert.deepEqual(mid.point, { x: 400, y: 0 });
    assert.equal(mid.distance, 300);
    assert.equal(mid.t, 0.4);
    const before = closestPointOnSegment(s, { x: -50, y: 0 });
    assert.deepEqual(before.point, { x: 0, y: 0 });
    assert.equal(before.t, 0);
    const after = closestPointOnSegment(s, { x: 1500, y: 0 });
    assert.deepEqual(after.point, { x: 1000, y: 0 });
    assert.equal(after.t, 1);
  });
  it('вироджений відрізок не дає NaN', () => {
    const r = closestPointOnSegment(seg(5, 5, 5, 5), { x: 8, y: 9 });
    assert.deepEqual(r.point, { x: 5, y: 5 });
    assert.equal(r.distance, 5);
  });
});

describe('перетин відрізків (основа з\'єднань L / T / X)', () => {
  it('X: хрест — внутрішній (proper) перетин у (1500, 1500)', () => {
    const r = intersectSegments(seg(0, 1500, 3000, 1500), seg(1500, 0, 1500, 3000));
    assert.equal(r.kind, 'point');
    if (r.kind === 'point') {
      assert.deepEqual(r.point, { x: 1500, y: 1500 });
      assert.equal(r.proper, true);
      assert.equal(r.t, 0.5);
      assert.equal(r.u, 0.5);
    }
  });

  it('T: кінець однієї стіни на тілі іншої — не proper', () => {
    const r = intersectSegments(seg(0, 0, 3000, 0), seg(1000, 0, 1000, 2000));
    assert.equal(r.kind, 'point');
    if (r.kind === 'point') {
      assert.deepEqual(r.point, { x: 1000, y: 0 });
      assert.equal(r.proper, false);
      assert.equal(r.u, 0);
    }
  });

  it('L: спільний кінець', () => {
    const r = intersectSegments(seg(0, 0, 3000, 0), seg(3000, 0, 3000, 5000));
    assert.equal(r.kind, 'point');
    if (r.kind === 'point') {
      assert.deepEqual(r.point, { x: 3000, y: 0 });
      assert.equal(r.proper, false);
      assert.equal(r.t, 1);
      assert.equal(r.u, 0);
    }
  });

  it('пряме продовження: колінеарні, торкаються кінцем — одна точка', () => {
    const r = intersectSegments(seg(0, 0, 1000, 0), seg(1000, 0, 3000, 0));
    assert.equal(r.kind, 'point');
    if (r.kind === 'point') assert.deepEqual(r.point, { x: 1000, y: 0 });
  });

  it('колінеарне перекриття повертає ділянку', () => {
    const r = intersectSegments(seg(0, 0, 3000, 0), seg(2000, 0, 5000, 0));
    assert.equal(r.kind, 'overlap');
    if (r.kind === 'overlap') {
      assert.deepEqual(r.from, { x: 2000, y: 0 });
      assert.deepEqual(r.to, { x: 3000, y: 0 });
    }
  });

  it('паралельні та роз\'єднані — none', () => {
    assert.equal(intersectSegments(seg(0, 0, 3000, 0), seg(0, 200, 3000, 200)).kind, 'none');
    assert.equal(intersectSegments(seg(0, 0, 1000, 0), seg(2000, 0, 3000, 0)).kind, 'none');
    assert.equal(intersectSegments(seg(0, 0, 1000, 0), seg(500, 100, 500, 900)).kind, 'none');
  });

  it('допуск: кінець у 0,0005 мм від тіла вважається торканням, у 0,01 мм — ні', () => {
    const touching = intersectSegments(seg(0, 0, 3000, 0), seg(1000, 0.0005, 1000, 2000));
    assert.equal(touching.kind, 'point');
    const apart = intersectSegments(seg(0, 0, 3000, 0), seg(1000, 0.01, 1000, 2000));
    assert.equal(apart.kind, 'none');
  });

  it('нескінченні лінії: перетин продовжень і паралельні', () => {
    const p = lineIntersection(seg(0, 0, 1000, 0), seg(3000, -500, 3000, 500));
    assert.ok(p !== null && p.x === 3000 && p.y === 0);
    assert.equal(lineIntersection(seg(0, 0, 1000, 0), seg(0, 100, 1000, 100)), null);
  });
});
