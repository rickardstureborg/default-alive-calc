// JS twin of Sources/DefaultAliveCore (same names, formulas, rounding) so the browser
// preview shows the numbers the app will. design/presets.json pins both sides: change
// wording or math in one and `make test` fails until the other (and the `expect`s) match.

const SUFFIXES = { k: 1e3, m: 1e6, b: 1e9 };
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// ── Parsing.swift ────────────────────────────────────────────────────────────

// Digits with at most one decimal point and an optional leading minus. Number() alone
// also accepts "Infinity", "1e3" and hex, none of which belong in a money field.
function plainNumber(s) {
  const body = s.startsWith("-") ? s.slice(1) : s;
  if (!/^\d*\.?\d*$/.test(body) || !/\d/.test(body)) return null;
  return Number(s);
}

export function parseAmount(text) {
  let s = text.trim().toLowerCase();
  if (s.startsWith("$")) s = s.slice(1);
  s = s.replaceAll(",", "");
  let multiplier = 1;
  const last = s.at(-1);
  if (last && Object.hasOwn(SUFFIXES, last)) {
    multiplier = SUFFIXES[last];
    s = s.slice(0, -1);
  }
  const n = plainNumber(s.trim());
  return n === null ? null : n * multiplier;
}

export function parsePercent(text) {
  let s = text.trim();
  if (s.endsWith("%")) s = s.slice(0, -1);
  const n = plainNumber(s.trim());
  return n === null ? null : n / 100;
}

// ── Readout.swift (field ranges) ─────────────────────────────────────────────

export function amountValue(text) {
  const n = parseAmount(text);
  return n !== null && n >= 0 ? n : null;
}

export function growthValue(text) {
  const n = parsePercent(text);
  return n !== null && n > -1 ? n : null;
}

// ── Projection.swift ─────────────────────────────────────────────────────────
// inputs: { cash, expenses, revenue, growth }, all monthly; growth is a fraction.

export function cumulativeBurn({ expenses: E, revenue: R, growth: g }, t) {
  const r = Math.log1p(g);
  const revenueSoFar = r === 0 ? R * t : (R * Math.expm1(r * t)) / r;
  return E * t - revenueSoFar;
}

export function project(inputs) {
  const { cash, expenses: E, revenue: R, growth: g } = inputs;
  if (![cash, E, R, g].every(Number.isFinite) || cash < 0 || E < 0 || R < 0 || g <= -1) return null;

  if (R >= E) {
    return { verdict: "alive", monthsToProfitability: 0, capitalNeeded: 0, cushion: cash, runwayMonths: null };
  }

  const r = Math.log1p(g);
  if (!(R > 0 && r > 0)) {
    const runway = R === 0 || r === 0
      ? cash / (E - R)
      : monthsUntilBurned(cash, inputs, cash / E, cash / (E - R));
    return { verdict: "dead", monthsToProfitability: null, capitalNeeded: null, cushion: null, runwayMonths: runway };
  }

  const T = Math.log(E / R) / r;
  const C = E * T - (E - R) / r;
  if (C <= cash) {
    return { verdict: "alive", monthsToProfitability: T, capitalNeeded: C, cushion: cash - C, runwayMonths: null };
  }
  const runway = monthsUntilBurned(cash, inputs, cash / E, T);
  return { verdict: "dead", monthsToProfitability: T, capitalNeeded: C, cushion: cash - C, runwayMonths: runway };
}

function monthsUntilBurned(target, inputs, low, high) {
  if (!(target > 0)) return 0;
  let lo = low, hi = high;
  for (let i = 0; i < 200; i++) {
    const mid = (lo + hi) / 2;
    if (mid <= lo || mid >= hi) break;
    if (cumulativeBurn(inputs, mid) < target) lo = mid; else hi = mid;
  }
  return (lo + hi) / 2;
}

// ── Formatting.swift ─────────────────────────────────────────────────────────

// Math.round on positives is ties-away-from-zero, matching Swift's .toNearestOrAwayFromZero.
const oneDecimal = (x) => (Math.round(x * 10) / 10).toFixed(1);

export function formatMoney(value) {
  const v = Math.abs(value);
  if (v < 0.5) return "$0";
  const sign = value < 0 ? "-" : "";
  for (const [scale, suffix] of [[1e9, "B"], [1e6, "M"], [1e3, "k"]]) {
    if (v >= scale - scale / 2000) {
      const x = v / scale;
      const digits = x < 99.95 ? oneDecimal(x) : String(Math.round(x));
      return `${sign}$${digits.endsWith(".0") ? digits.slice(0, -2) : digits}${suffix}`;
    }
  }
  return `${sign}$${Math.round(v)}`;
}

export const formatMonths = (months) => `${oneDecimal(months)} months`;

export function formatMonthYear(months, start) {
  const whole = Math.floor(months);
  // Calendar.date(byAdding: .month) clamps to the month's last day (Jan 31 + 1 → Feb 28);
  // Date.setMonth would overflow into March.
  const y = start.getFullYear();
  const m = start.getMonth() + whole;
  const lastDay = new Date(y, m + 1, 0).getDate();
  const base = new Date(y, m, Math.min(start.getDate(), lastDay),
    start.getHours(), start.getMinutes(), start.getSeconds(), start.getMilliseconds());
  const date = new Date(base.getTime() + (months - whole) * 30.436875 * 86_400_000);
  return `${MONTHS[date.getMonth()]} ${date.getFullYear()}`;
}

// ── Readout.swift ────────────────────────────────────────────────────────────
// raw: { cash, expenses, revenue, growth } as typed. Returns { tone, headline, line1, line2 }.

export function readout(raw, now) {
  const cash = amountValue(raw.cash);
  const expenses = amountValue(raw.expenses);
  const revenue = amountValue(raw.revenue);
  const growth = growthValue(raw.growth);
  const p = [cash, expenses, revenue, growth].includes(null) ? null : project({ cash, expenses, revenue, growth });
  if (!p) {
    const filledIn = ![raw.cash, raw.expenses, raw.revenue, raw.growth].some((s) => s.trim() === "");
    return { tone: "neutral", headline: "—", line1: filledIn ? "Check the numbers in red" : "Enter all four numbers", line2: "" };
  }

  if (p.verdict === "alive") {
    const T = p.monthsToProfitability ?? 0;
    if (T === 0) {
      return { tone: "alive", headline: "DEFAULT ALIVE", line1: "Already profitable", line2: "Revenue covers expenses" };
    }
    return {
      tone: "alive", headline: "DEFAULT ALIVE",
      line1: `Profitable in ${formatMonths(T)} · ${formatMonthYear(T, now)}`,
      line2: `Needs ${formatMoney(p.capitalNeeded ?? 0)} · ${formatMoney(p.cushion ?? 0)} to spare`,
    };
  }

  const runway = p.runwayMonths ?? 0;
  const line1 = runway === 0
    ? "Out of cash now"
    : `Out of cash in ${formatMonths(runway)} · ${formatMonthYear(runway, now)}`;
  const line2 = p.capitalNeeded !== null && p.cushion !== null
    ? `Needs ${formatMoney(p.capitalNeeded)} · ${formatMoney(-p.cushion)} short`
    : "Never profitable at this growth";
  return { tone: "dead", headline: "DEFAULT DEAD", line1, line2 };
}
