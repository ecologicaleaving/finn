// Amount parsing for receipt OCR text.
//
// Pure module: no Deno or remote imports, so it can be unit-tested with
// `node --experimental-strip-types --test amount_parser.test.ts`.

/**
 * Regex source for a single amount token (capturing group).
 *
 * Supports both plain amounts ("12,50", "12.50") and thousands-grouped
 * amounts in Italian ("1.234,56") or English ("1,234.56") notation.
 * The grouped alternative comes first so "1.234,56" is never cut to "1.23".
 * The digit boundaries prevent matching a fragment of a longer number.
 */
export const AMOUNT_TOKEN =
  String.raw`(?<!\d[.,]?)(\d{1,3}(?:[.,]\d{3})+[.,]\d{2}|\d+[.,]\d{2})(?![.,]?\d)`;

const AMOUNT_TOKEN_NON_CAPTURING = AMOUNT_TOKEN.replace(
  '(\\d{1,3}',
  '(?:\\d{1,3}',
);

const TOTAL_KEYWORDS = String.raw`(?:TOTALE|TOT\.?|TOTAL|DA PAGARE|IMPORTO)`;

// Patterns to EXCLUDE (subtotals, not final totals)
const excludePatterns: RegExp[] = [
  new RegExp(
    String.raw`(?:SUB[\s\-]?TOTALE|SUBTOT|IMPONIBILE|IVA\s+ESCLUSA|IVA\s+ESCL|TOTALE\s+PARZIALE)\s*[:=]?\s*(?:EUR|€)?\s*` +
      AMOUNT_TOKEN_NON_CAPTURING,
    'gi',
  ),
];

// Amount patterns for Italian receipts - ordered by priority (most specific first)
const amountPatterns: RegExp[] = [
  // PRIORITY 0: Total with "IVA INCLUSA" or "IVA COMPRESA" (absolute highest priority)
  new RegExp(
    TOTAL_KEYWORDS +
      String.raw`\s+(?:IVA\s+INCLUSA|IVA\s+COMPRESA|IVA\s+INCL|COMPRENSIVO|CON\s+IVA)\s*[:=]?\s*(?:EUR|€|EURO)?\s*` +
      AMOUNT_TOKEN,
    'gi',
  ),

  // PRIORITY 1: Explicit total with currency
  new RegExp(
    TOTAL_KEYWORDS +
      String.raw`\s+(?:COMPLESSIVO|GENERALE|FINALE?)?\s*(?:EUR|€|EURO)\s*` +
      AMOUNT_TOKEN,
    'gi',
  ),

  // PRIORITY 2: Total keywords without explicit currency
  new RegExp(TOTAL_KEYWORDS + String.raw`\s*[:=]?\s*` + AMOUNT_TOKEN, 'gi'),

  // PRIORITY 3: Payment keywords
  new RegExp(
    String.raw`(?:PAGATO|CONTANTI|CONTANTE|CARTA|BANCOMAT|POS)\s*[:=]?\s*(?:EUR|€)?\s*` +
      AMOUNT_TOKEN,
    'gi',
  ),

  // PRIORITY 4: Currency symbols with amount
  new RegExp(String.raw`(?:EUR|€)\s*` + AMOUNT_TOKEN, 'gi'),

  // PRIORITY 5: Amount followed by currency
  new RegExp(AMOUNT_TOKEN + String.raw`\s*(?:EUR|€)`, 'gi'),

  // PRIORITY 6: Standalone amount at end of line (least specific)
  new RegExp(String.raw`^\s*` + AMOUNT_TOKEN + String.raw`\s*$`, 'gm'),
];

const AMOUNT_ONLY_LINE = new RegExp(String.raw`^` + AMOUNT_TOKEN + String.raw`$`);

/**
 * Converts an amount token to a number.
 *
 * The last '.' or ',' followed by exactly two final digits is the decimal
 * separator; every other '.' or ',' is a thousands separator and is removed.
 */
export function normalizeAmount(token: string): number {
  const trimmed = token.trim();
  const match = /^(.*)[.,](\d{2})$/.exec(trimmed);
  if (!match) {
    return NaN;
  }
  const integerPart = match[1].replace(/[.,]/g, '');
  if (!/^\d+$/.test(integerPart)) {
    return NaN;
  }
  return parseFloat(`${integerPart}.${match[2]}`);
}

/** True when the whole line is a single amount (e.g. "12,50" or "1.234,56"). */
export function isAmountOnlyLine(line: string): boolean {
  return AMOUNT_ONLY_LINE.test(line);
}

/** Extracts the most likely total amount from receipt text. */
export function extractAmount(text: string): number | null {
  // First, identify positions of subtotals to exclude
  const excludePositions = new Set<number>();
  excludePatterns.forEach((pattern) => {
    pattern.lastIndex = 0;
    let match;
    while ((match = pattern.exec(text)) !== null) {
      // Mark this position range as excluded
      for (let i = match.index; i < match.index + match[0].length; i++) {
        excludePositions.add(i);
      }
    }
  });

  const candidates: Array<{ amount: number; priority: number; position: number }> = [];

  // Search with all patterns and collect candidates
  amountPatterns.forEach((pattern, priority) => {
    // Reset regex state
    pattern.lastIndex = 0;

    let match;
    while ((match = pattern.exec(text)) !== null) {
      // Skip if this match overlaps with an excluded region
      if (excludePositions.has(match.index)) {
        continue;
      }

      const amount = normalizeAmount(match[1]);

      if (!isNaN(amount) && amount > 0 && amount < 100000) {
        candidates.push({
          amount,
          priority,
          position: match.index,
        });
      }
    }
  });

  if (candidates.length === 0) {
    return null;
  }

  // Sort by priority (lower is better), then by position (later in text), then by amount (higher)
  candidates.sort((a, b) => {
    if (a.priority !== b.priority) {
      return a.priority - b.priority;
    }
    if (a.position !== b.position) {
      return b.position - a.position;
    }
    return b.amount - a.amount;
  });

  // Return the best candidate (highest priority, latest in text, highest amount)
  return candidates[0].amount;
}
