import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  chooseGridSpec,
  clampZoom,
  distance,
  fitToBox,
  initialCamera,
  MAX_ZOOM,
  MIN_ZOOM,
  mmPerPixel,
  panByScreen,
  resizeCamera,
  screenToWorld,
  visibleGridLines,
  visibleWorldBox,
  worldToScreen,
  zoomAt,
  type Camera2D,
  type Point2D,
} from '../index';

const P = (x: number, y: number): Point2D => ({ x, y });
const near = (a: number, b: number, eps = 1e-6) => Math.abs(a - b) <= eps;

describe('камера 2D: перетворення координат', () => {
  const cam: Camera2D = { centerX: 1000, centerY: 500, zoom: 0.2, width: 800, height: 600 };

  it('центр вікна ↔ центр камери', () => {
    assert.deepEqual(worldToScreen(cam, P(1000, 500)), P(400, 300));
    assert.deepEqual(screenToWorld(cam, P(400, 300)), P(1000, 500));
  });

  it('вісь Y світу спрямована вгору, екрана — вниз', () => {
    const above = worldToScreen(cam, P(1000, 1500));
    assert.ok(above.y < 300);
    const right = worldToScreen(cam, P(2000, 500));
    assert.ok(right.x > 400);
  });

  it('прямий і зворотний шлях збігаються', () => {
    for (const p of [P(0, 0), P(3000, 4000), P(-12345.678, 99999.5)]) {
      const back = screenToWorld(cam, worldToScreen(cam, p));
      assert.ok(near(back.x, p.x, 1e-9) && near(back.y, p.y, 1e-9));
    }
  });
});

describe('масштабування й панорамування', () => {
  const base = initialCamera(1000, 700);

  it('zoomAt: світова точка під курсором не рухається', () => {
    const cursor = P(250, 180);
    const before = screenToWorld(base, cursor);
    const z = zoomAt(base, cursor, 2.5);
    const after = screenToWorld(z, cursor);
    assert.ok(near(before.x, after.x) && near(before.y, after.y));
    assert.ok(near(z.zoom, base.zoom * 2.5, 1e-12));
  });

  it('межі масштабу (clamp)', () => {
    assert.equal(zoomAt(base, P(0, 0), 1e9).zoom, MAX_ZOOM);
    assert.equal(zoomAt(base, P(0, 0), 1e-9).zoom, MIN_ZOOM);
    assert.equal(clampZoom(NaN), base.zoom);
    assert.equal(zoomAt(base, P(0, 0), -1), base);
    assert.equal(zoomAt(base, P(0, 0), 0), base);
  });

  it('panByScreen: вміст зсувається на задані пікселі', () => {
    const w = P(2000, 1000);
    const s0 = worldToScreen(base, w);
    const panned = panByScreen(base, 120, -45);
    const s1 = worldToScreen(panned, w);
    assert.ok(near(s1.x, s0.x + 120, 1e-9) && near(s1.y, s0.y - 45, 1e-9));
  });

  it('resize: центр і масштаб лишаються, змінюється лише вікно', () => {
    const r = resizeCamera(base, 1400, 900);
    assert.equal(r.centerX, base.centerX);
    assert.equal(r.zoom, base.zoom);
    assert.deepEqual(screenToWorld(r, P(700, 450)), P(base.centerX, base.centerY));
  });

  it('Тест 7: 20 циклів zoom/pan не змінюють світових координат стін', () => {
    const walls = Object.freeze([
      Object.freeze({ a: Object.freeze(P(0, 0)), b: Object.freeze(P(3000, 0)) }),
      Object.freeze({ a: Object.freeze(P(3000, 0)), b: Object.freeze(P(3000, 5000)) }),
    ]);
    const snapshot = JSON.stringify(walls);
    let cam = base;
    for (let i = 0; i < 20; i++) {
      cam = zoomAt(cam, P(100 + i * 31, 80 + i * 17), i % 2 === 0 ? 1.37 : 1 / 1.21);
      cam = panByScreen(cam, (i % 5) * 13 - 20, (i % 7) * 9 - 25);
      // кожен цикл: екран → світ → екран повертає ту саму точку; модель не чіпали
      for (const w of walls) {
        for (const p of [w.a, w.b]) {
          const back = screenToWorld(cam, worldToScreen(cam, p));
          assert.ok(near(back.x, p.x, 1e-6) && near(back.y, p.y, 1e-6), `цикл ${i}`);
        }
      }
    }
    assert.equal(JSON.stringify(walls), snapshot);
  });

  it('довжина 3000 мм однакова при масштабах 50% і 200% (екранна довжина / масштаб)', () => {
    for (const zoom of [0.05, 0.1, 0.2]) {
      const cam: Camera2D = { ...base, zoom };
      const a = worldToScreen(cam, P(0, 0));
      const b = worldToScreen(cam, P(3000, 0));
      assert.ok(near(distance(a, b) / zoom, 3000, 1e-9));
      assert.ok(near(distance(screenToWorld(cam, a), screenToWorld(cam, b)), 3000, 1e-9));
    }
  });

  it('fitToBox вміщує область і центрує її', () => {
    const box = { min: P(0, 0), max: P(10000, 5000) };
    const cam = fitToBox(base, box, 50);
    const vis = visibleWorldBox(cam);
    assert.ok(vis.min.x <= 0 && vis.max.x >= 10000 && vis.min.y <= 0 && vis.max.y >= 5000);
    assert.deepEqual(P(cam.centerX, cam.centerY), P(5000, 2500));
    assert.ok(mmPerPixel(cam) > 0);
  });
});

describe('сітка', () => {
  it('крок обирається так, щоб екранний інтервал ≥ 14 px; щільність змінюється з масштабом', () => {
    assert.deepEqual(chooseGridSpec(0.1), { minorMm: 200, majorMm: 2000 });
    let prev = Infinity;
    for (const zoom of [0.002, 0.01, 0.05, 0.2, 1, 5, 20]) {
      const spec = chooseGridSpec(zoom);
      assert.ok(spec.minorMm * zoom >= 14 || spec.minorMm === 100000, `zoom=${zoom}`);
      assert.ok(spec.minorMm <= prev, 'при збільшенні масштабу крок не зростає');
      assert.equal(spec.majorMm % spec.minorMm, 0);
      prev = spec.minorMm;
    }
  });

  it('позиції ліній — точні кратні кроку, початок координат — основна лінія', () => {
    const cam: Camera2D = { centerX: 123.456, centerY: -77.7, zoom: 0.1, width: 1000, height: 700 };
    const g = visibleGridLines(cam);
    assert.ok(g.vertical.length > 0 && g.horizontal.length > 0);
    for (const l of [...g.vertical, ...g.horizontal]) {
      assert.ok(l.value % g.spec.minorMm === 0); // не assert.equal: (-200 % 200) дає -0
      assert.ok(!Object.is(l.value, -0), 'значення лінії не має бути -0');
      assert.equal(l.major, l.value % g.spec.majorMm === 0);
    }
    const zeroV = g.vertical.find((l) => l.value === 0);
    assert.ok(zeroV !== undefined && zeroV.major === true);
  });

  it('кількість ліній обмежена навіть для величезного вікна', () => {
    const cam: Camera2D = { centerX: 0, centerY: 0, zoom: MIN_ZOOM, width: 8000, height: 8000 };
    const g = visibleGridLines(cam, 14, 300);
    assert.ok(g.vertical.length <= 300 + 1 && g.horizontal.length <= 300 + 1);
  });
});
