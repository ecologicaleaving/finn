// Run with: node --experimental-strip-types --test supabase/functions/scan-receipt/amount_parser.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { extractAmount, isAmountOnlyLine, normalizeAmount } from './amount_parser.ts';

test('Italian thousands format is parsed fully', () => {
  assert.equal(extractAmount('TOTALE 1.234,56'), 1234.56);
});

test('plain Italian decimal amount', () => {
  assert.equal(extractAmount('TOTALE 12,50'), 12.5);
});

test('English thousands format', () => {
  assert.equal(extractAmount('TOTAL 1,234.56'), 1234.56);
});

test('subtotal is excluded in favour of the total', () => {
  assert.equal(extractAmount('SUBTOTALE 10,00\nTOTALE 12,20'), 12.2);
});

test('subtotal exclusion works with thousands-formatted amounts', () => {
  assert.equal(extractAmount('SUBTOTALE 1.000,00\nTOTALE 1.220,00'), 1220);
});

test('total with explicit currency', () => {
  assert.equal(extractAmount('TOTALE EUR 5,00'), 5);
});

test('text without amounts returns null', () => {
  assert.equal(extractAmount('SCONTRINO FISCALE\nGRAZIE E ARRIVEDERCI'), null);
});

test('amount over the 100000 cap is rejected, not truncated', () => {
  assert.equal(extractAmount('TOTALE 1.234.567,89'), null);
});

test('amount without two decimals is not an amount', () => {
  assert.equal(extractAmount('TOTALE 1,234'), null);
});

test('malformed OCR with repeated separator uses last one as decimal', () => {
  assert.equal(extractAmount('TOTALE 1.234.56'), 1234.56);
});

test('normalizeAmount', () => {
  assert.equal(normalizeAmount('1.234,56'), 1234.56);
  assert.equal(normalizeAmount('1,234.56'), 1234.56);
  assert.equal(normalizeAmount('12,50'), 12.5);
  assert.equal(normalizeAmount('12.50'), 12.5);
  assert.ok(Number.isNaN(normalizeAmount('1234')));
});

test('isAmountOnlyLine', () => {
  assert.equal(isAmountOnlyLine('12,50'), true);
  assert.equal(isAmountOnlyLine('1.234,56'), true);
  assert.equal(isAmountOnlyLine('SUPERMERCATO'), false);
  assert.equal(isAmountOnlyLine('TOTALE 12,50'), false);
});
