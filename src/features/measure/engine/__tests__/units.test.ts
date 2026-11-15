import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  formatAngleDegrees,
  formatLengthMm,
  normalizeDegrees,
  parseAngleDegrees,
  parseLengthMm,
} from '../index';

const mm = (s: string, opts?: Parameters<typeof parseLengthMm>[1]): number | string => {
  const r = parseLengthMm(s, opts);
  return r.ok ? r.value : r.error;
};

describe('parseLengthMm: нормалізація до мм', () => {
  it('рівнозначні записи 3 м / 300 см / 3000 мм → 3000', () => {
    assert.equal(mm('3 м'), 3000);
    assert.equal(mm('300 см'), 3000);
    assert.equal(mm('3000 мм'), 3000);
    assert.equal(mm('3000'), 3000); // за замовчуванням мм
  });

  it('приклади з ТЗ: 3500 мм / 350 см / 3.5 м / 3,5 м → 3500', () => {
    for (const s of ['3500 мм', '350 см', '3.5 м', '3,5 м', '3500мм', '3,5м', '3.5 M', '350 CM', ' 3500 ']) {
      assert.equal(mm(s), 3500, s);
    }
  });

  it('latin і кирилиця однаково, крапка після одиниці', () => {
    assert.equal(mm('3 m'), 3000);
    assert.equal(mm('3 м.'), 3000);
    assert.equal(mm('3 м'), 3000); // нерозривний пробіл
  });

  it('defaultUnit застосовується до числа без одиниці', () => {
    assert.equal(mm('3', { defaultUnit: 'm' }), 3000);
    assert.equal(mm('300', { defaultUnit: 'cm' }), 3000);
    assert.equal(mm('3', { defaultUnit: 'm' }), 3000);
  });

  it('точність: відомі «проблемні» числа дають рівні цілі мм (не 2998/3002/1100.0000000000002)', () => {
    assert.equal(mm('1,1 м'), 1100);
    assert.equal(mm('0,3 м'), 300);
    assert.equal(mm('2,675 м'), 2675);
    assert.equal(mm('0,001 м'), 1);
    assert.equal(mm('4,35 м'), 4350);
    assert.equal(mm('8,2 м'), 8200);
    assert.equal(mm('12,345 м'), 12345);
  });

  it('усі цілі мм від 1 до 20000: запис у метрах з 3 знаками повертає те саме число', () => {
    for (let k = 1; k <= 20000; k++) {
      const text = `${(k / 1000).toFixed(3)} м`;
      const r = parseLengthMm(text);
      assert.ok(r.ok && r.value === k, `${text} → ${r.ok ? r.value : r.error}`);
    }
  });

  it('усі цілі мм від 1 до 20000: запис у сантиметрах з 1 знаком', () => {
    for (let k = 1; k <= 20000; k++) {
      const text = `${(k / 10).toFixed(1)} см`;
      const r = parseLengthMm(text);
      assert.ok(r.ok && r.value === k, `${text} → ${r.ok ? r.value : r.error}`);
    }
  });

  it('дробові міліметри зберігаються', () => {
    assert.equal(mm('0,5 мм'), 0.5);
    assert.equal(mm('12,25 мм'), 12.25);
  });

  it('помилки: порожнє, формат, одиниця, нуль, від\'ємне, діапазон', () => {
    assert.equal(mm(''), 'empty');
    assert.equal(mm('   '), 'empty');
    assert.equal(mm('abc'), 'invalid_format');
    assert.equal(mm('3..5'), 'invalid_format');
    assert.equal(mm('3.'), 'invalid_format');
    assert.equal(mm('3 500'), 'invalid_format'); // розділювач тисяч не підтримується (щоб не прочитати як 3)
    assert.equal(mm('3 км'), 'unknown_unit');
    assert.equal(mm('3 ft'), 'unknown_unit');
    assert.equal(mm('0'), 'not_positive');
    assert.equal(mm('-5 м'), 'not_positive');
    assert.equal(mm('2000 м'), 'out_of_range');
    assert.equal(mm('1234567890123'), 'out_of_range');
    assert.equal(mm('Infinity'), 'invalid_format');
    assert.equal(mm('NaN'), 'invalid_format');
    assert.equal(mm('1e3'), 'invalid_format'); // експоненційний запис не підтримується
  });

  it('allowNegative / allowZero для координат', () => {
    assert.equal(mm('-1,5 м', { allowNegative: true }), -1500);
    assert.equal(mm('0', { allowZero: true }), 0);
    assert.equal(mm('-0', { allowZero: true, allowNegative: true }), 0);
  });
});

describe('formatLengthMm: відображення', () => {
  it('3500 мм → «3,50 м» (приклад із ТЗ)', () => {
    assert.equal(formatLengthMm(3500), '3,50 м');
    assert.equal(formatLengthMm(3500, 'cm'), '350,0 см');
    assert.equal(formatLengthMm(3500, 'mm'), '3500 мм');
    assert.equal(formatLengthMm(3500, 'm', 3), '3,500 м');
  });
  it('без «-0»', () => {
    assert.equal(formatLengthMm(-0.0001), '0,00 м');
    assert.equal(formatLengthMm(-1250), '-1,25 м');
  });
  it('округлення тексту не впливає на значення (формат лише читає)', () => {
    const value = 3333.3333;
    formatLengthMm(value);
    assert.equal(value, 3333.3333);
  });
});

describe('кути', () => {
  it('parseAngleDegrees', () => {
    const a = (s: string) => {
      const r = parseAngleDegrees(s);
      return r.ok ? r.value : r.error;
    };
    assert.equal(a('90'), 90);
    assert.equal(a('90°'), 90);
    assert.equal(a('45,5'), 45.5);
    assert.equal(a('45.5 °'), 45.5);
    assert.equal(a('-30'), -30);
    assert.equal(a('135 град'), 135);
    assert.equal(a(''), 'empty');
    assert.equal(a('abc'), 'invalid_format');
    assert.equal(a('800'), 'out_of_range');
  });
  it('нормалізація та формат', () => {
    assert.equal(normalizeDegrees(-90), 270);
    assert.equal(normalizeDegrees(360), 0);
    assert.equal(normalizeDegrees(450), 90);
    assert.equal(formatAngleDegrees(450), '90,0°');
    assert.equal(formatAngleDegrees(-90, 0), '270°');
  });
});
