// JS twin of Sources/DefaultAliveCore (same names, formulas, rounding) so the browser
// preview shows the numbers the app will. design/presets.json pins both sides: change
// wording or math in one and `make test` fails until the other (and the `expect`s) match.

const SUFFIXES = { k: 1e3, m: 1e6, b: 1e9 };
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
export const KEYS = ["cash", "expenses", "revenue", "growth"];

// ── Parsing.swift ────────────────────────────────────────────────────────────

// "250k", "$1.2M", "1,500", "-$1.6k", and arithmetic on those ("163+5") → number.
export const parseAmount = (text) => evaluate(text, false);

// "8", "8%", "-3", "8+2" → fraction.
export function parsePercent(text) {
  const v = evaluate(text, true);
  return v === null ? null : v / 100;
}

// Arithmetic over the boxes' number syntax: + − * / × ÷ and parentheses, with unary minus
// only at the start of an expression or a parenthesis, so "--5" and "5--3" stay invalid.
// Amounts take "$" and k/m/b; percentages take "%".
export function evaluate(text, percent) {
  const s = [...text];
  let i = 0;
  const peek = () => {
    while (i < s.length && (s[i] === " " || s[i] === "\t")) i++;
    return i < s.length ? s[i] : null;
  };
  const number = () => {
    if (!percent && peek() === "$") i++;
    peek();
    const start = i;
    while (i < s.length && /[0-9.,]/.test(s[i])) i++;
    const n = plainNumber(s.slice(start, i).join("").replaceAll(",", ""));
    if (n === null) return null;
    if (percent) {
      if (peek() === "%") i++;
      return n;
    }
    const suffix = s[i]?.toLowerCase();
    if (suffix && Object.hasOwn(SUFFIXES, suffix)) {
      i++;
      return n * SUFFIXES[suffix];
    }
    return n;
  };
  const factor = () => {
    if (peek() !== "(") return number();
    i++;
    const v = expression();
    if (v === null || peek() !== ")") return null;
    i++;
    return v;
  };
  const term = () => {
    let value = factor();
    if (value === null) return null;
    for (let op = peek(); op !== null && "*×/÷".includes(op); op = peek()) {
      i++;
      const rhs = factor();
      if (rhs === null) return null;
      value = op === "*" || op === "×" ? value * rhs : value / rhs;
      if (!Number.isFinite(value)) return null;
    }
    return value;
  };
  const expression = () => {
    const negate = peek() === "-";
    if (negate) i++;
    let value = term();
    if (value === null) return null;
    if (negate) value = -value;
    for (let op = peek(); op === "+" || op === "-"; op = peek()) {
      i++;
      const rhs = term();
      if (rhs === null) return null;
      value = op === "+" ? value + rhs : value - rhs;
    }
    return value;
  };
  const v = expression();
  return v !== null && peek() === null && Number.isFinite(v) ? v : null;
}

// Digits with at most one decimal point. Number() alone also accepts "Infinity", "1e3"
// and hex, none of which belong in a money field.
function plainNumber(s) {
  if (!/^\d*\.?\d*$/.test(s) || !/\d/.test(s)) return null;
  return Number(s);
}

// If `text` is arithmetic ("163+5"), its result in the field's shortest exact form
// ("168", "85k", "10%", "$2k"); null for plain numbers and anything that doesn't evaluate.
export function compactField(row, text, linear) {
  const t = text.trim();
  if (!(t.startsWith("(") || /[+\-*/×÷()]/.test(t.slice(1)))) return null;
  const percent = row === "growth" && !linear;
  const v = evaluate(t, percent);
  if (v === null) return null;
  const sign = v < 0 ? "-" : "";
  if (percent) return `${sign}${compactNumber(Math.abs(v))}%`;
  const dollar = (row === "growth" && linear) || t.startsWith("$") || t.startsWith("-$");
  return `${sign}${dollar ? "$" : ""}${compactNumber(Math.abs(v))}`;
}

// Shortest exact spelling: 168, 85k, 1.234k, 1.2M; otherwise up to four decimals.
function compactNumber(a) {
  for (const [scale, suffix] of [[1e9, "B"], [1e6, "M"], [1e3, "k"]]) {
    if (a >= scale) {
      const x = a / scale;
      const r = Math.round(x * 1000) / 1000;
      if (Math.abs(x - r) < 1e-9 * Math.max(1, x)) return `${trimZeros(r.toFixed(3))}${suffix}`;
    }
  }
  return trimZeros((Math.round(a * 10_000) / 10_000).toFixed(4));
}

// ── Units.swift ──────────────────────────────────────────────────────────────
// The model runs in months; each flow field can be typed per week, month or year.
// Weeks per month is TLB's 365.2425/7/12. % growth compounds per period, so 8%/mo is
// 1.79%/wk and 152%/yr (not 2% and 96%). $ growth means the per-period revenue figure
// rises by that much each period ("+$10k MRR a month"), so it scales with period².

export const UNITS = {
  week: { months: 12 * 7 / 365.2425 },
  month: { months: 1 },
  year: { months: 12 },
};
export const NEXT_UNIT = { week: "month", month: "year", year: "week" };
export const MONTHLY = { expenses: "month", revenue: "month", growth: "month" };
const per = (unit) => UNITS[unit].months;
export const amountToUnit = (monthly, unit) => monthly * per(unit);
export const amountFromUnit = (perUnit, unit) => perUnit / per(unit);
export const growthToUnit = (monthly, unit) => Math.expm1(Math.log1p(monthly) * per(unit));
export const growthFromUnit = (perUnit, unit) => Math.expm1(Math.log1p(perUnit) / per(unit));
export const linearToUnit = (monthly, unit) => monthly * per(unit) ** 2;
export const linearFromUnit = (perUnit, unit) => perUnit / per(unit) ** 2;

// ── Projection.swift ─────────────────────────────────────────────────────────
// inputs: { cash, expenses, revenue, growth, linear }, all monthly. Compounding growth
// is a fraction per month; linear growth is $ of monthly revenue added per month.

export function cumulativeBurn(inputs, t) {
  return inputs.linear ? linearBurn(inputs, t) : compoundingBurn(inputs, t);
}

export function project(inputs) {
  return inputs.linear ? projectLinear(inputs) : projectCompounding(inputs);
}

function compoundingBurn({ expenses: E, revenue: R, growth: g }, t) {
  const r = Math.log1p(g);
  const revenueSoFar = r === 0 ? R * t : (R * Math.expm1(r * t)) / r;
  return E * t - revenueSoFar;
}

function projectCompounding(inputs) {
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
    if (compoundingBurn(inputs, mid) < target) lo = mid; else hi = mid;
  }
  return (lo + hi) / 2;
}

// Linear: revenue R + a·t. Closed forms: T = (E−R)/a, capital needed C = (E−R)²/(2a).
function linearBurn({ expenses: E, revenue: R, growth: a }, t) {
  // Shrinking revenue stops at zero; after that the whole expense line burns.
  const t0 = a < 0 ? R / -a : Infinity;
  const s = Math.min(t, t0);
  return (E - R) * s - (a * s * s) / 2 + E * Math.max(0, t - t0);
}

function projectLinear(inputs) {
  const { cash, expenses: E, revenue: R, growth: a } = inputs;
  if (![cash, E, R, a].every(Number.isFinite) || cash < 0 || E < 0 || R < 0) return null;
  if (R >= E) return { verdict: "alive", monthsToProfitability: 0, capitalNeeded: 0, cushion: cash, runwayMonths: null };
  // Smaller root of (a/2)t² − (E−R)t + cash = 0, written so it stays exact as a → 0.
  let runway = (2 * cash) / ((E - R) + Math.sqrt((E - R) ** 2 - 2 * a * cash));
  if (a > 0) {
    const T = (E - R) / a;
    const C = (E - R) ** 2 / (2 * a);
    if (C <= cash) return { verdict: "alive", monthsToProfitability: T, capitalNeeded: C, cushion: cash - C, runwayMonths: null };
    return { verdict: "dead", monthsToProfitability: T, capitalNeeded: C, cushion: cash - C, runwayMonths: runway };
  }
  const t0 = a < 0 ? R / -a : Infinity;
  if (runway > t0) runway = t0 + (cash - linearBurn(inputs, t0)) / E;
  return { verdict: "dead", monthsToProfitability: null, capitalNeeded: null, cushion: null, runwayMonths: runway };
}

// ── Breakevens.swift ─────────────────────────────────────────────────────────
// For each input: the value that makes capital needed exactly equal cash, holding the
// other three fixed. Capital needed is monotone in every input (up in expenses, down in
// cash/revenue/growth), so each has one crossing. Monthly units. Each result is a
// number, "never" (no value works) or "any" (every value works).

function compoundingCapital(E, R, r) {
  if (R >= E) return 0;
  if (!(R > 0 && r > 0)) return Infinity;
  return E * (Math.log(E / R) / r) - (E - R) / r;
}

// x where f(x) crosses target, given f(lo) and f(hi) straddle it.
function bisect(f, target, lo, hi) {
  const up = f(hi) > f(lo);
  for (let i = 0; i < 200; i++) {
    const mid = (lo + hi) / 2;
    if (mid <= lo || mid >= hi) break;
    if ((f(mid) < target) === up) lo = mid; else hi = mid;
  }
  return (lo + hi) / 2;
}

export function breakevens(inputs) {
  const { cash, expenses: E, revenue: R, growth: g } = inputs;
  if (inputs.linear) {
    // √(2a·cash) is the revenue gap that cash can carry all the way to profitability.
    const reach = g > 0 ? Math.sqrt(2 * g * cash) : 0;
    return {
      cash: R >= E ? 0 : g > 0 ? (E - R) ** 2 / (2 * g) : "never",
      expenses: R + reach,
      revenue: E - reach <= 0 ? "any" : E - reach,
      growth: R >= E ? "any" : cash === 0 ? "never" : (E - R) ** 2 / (2 * cash),
    };
  }

  const r = Math.log1p(g);
  const C = compoundingCapital(E, R, r);

  let maxExpenses = R;
  if (R > 0 && r > 0) {
    let hi = Math.max(E, R) * 2;
    for (let i = 0; i < 100 && compoundingCapital(hi, R, r) <= cash; i++) hi *= 2;
    maxExpenses = bisect((e) => compoundingCapital(e, R, r), cash, R, hi);
  }

  // Searched in log space, since the answer can sit many orders below E.
  let minRevenue = E;
  if (r > 0 && E > 0) {
    minRevenue = Math.exp(bisect((x) => compoundingCapital(E, Math.exp(x), r), cash, Math.log(E) - 40, Math.log(E)));
  }

  // None needed if already profitable; none suffices from zero revenue or zero cash.
  let minGrowth;
  if (R >= E) minGrowth = "any";
  else if (R === 0 || cash === 0) minGrowth = "never";
  else {
    let hi = 0.01;
    for (let i = 0; i < 100 && compoundingCapital(E, R, Math.log1p(hi)) > cash; i++) hi *= 2;
    minGrowth = bisect((x) => compoundingCapital(E, R, Math.log1p(x)), cash, 0, hi);
  }

  return { cash: Number.isFinite(C) ? C : "never", expenses: maxExpenses, revenue: minRevenue, growth: minGrowth };
}

// ── Formatting.swift ─────────────────────────────────────────────────────────

// Math.round on positives is ties-away-from-zero, matching Swift's .toNearestOrAwayFromZero.
const oneDecimal = (x) => (Math.round(x * 10) / 10).toFixed(1);
const trimZeros = (s) => (s.includes(".") ? s.replace(/0+$/, "").replace(/\.$/, "") : s);

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

// 0.0179 → "1.79%", 0.105 → "10.5%", 1.52 → "152%": three significant digits.
export function formatPercent(fraction) {
  const v = fraction * 100;
  const places = Math.abs(v) >= 100 ? 0 : Math.abs(v) >= 10 ? 1 : 2;
  return `${trimZeros((Math.round(v * 10 ** places) / 10 ** places).toFixed(places))}%`;
}

// Breakeven hints round toward the safe side ("≥" up, "≤" down), so the shown value
// really flips the verdict: $241.04 needed must read "≥ $242", never "≥ $241". They also
// carry one more digit than formatMoney ($7.46k, $252.1k) so the rounding costs little.
// The 1e-9 slack keeps an exact grid value (360000) from stepping to the next one.
const STEPS = [[1e10, 1e8], [1e9, 1e7], [1e7, 1e5], [1e6, 1e4], [1e4, 100], [1e3, 10], [0, 1]];

export function formatMoneyBound(value, roundUp) {
  const v = Math.max(0, value);
  const step = STEPS.find(([from]) => v >= from)[1];
  const r = (roundUp ? Math.ceil(v / step - 1e-9) : Math.floor(v / step + 1e-9)) * step;
  for (const [scale, suffix] of [[1e9, "B"], [1e6, "M"], [1e3, "k"]]) {
    if (r >= scale) {
      const x = r / scale;
      return `$${trimZeros(x.toFixed(x < 10 ? 2 : 1))}${suffix}`;
    }
  }
  return `$${r}`;
}

export function formatPercentBound(fraction, roundUp) {
  const v = fraction * 100;
  const places = Math.abs(v) >= 100 ? 0 : Math.abs(v) >= 10 ? 1 : 2;
  const f = 10 ** places;
  const r = (roundUp ? Math.ceil(v * f - 1e-9) : Math.floor(v * f + 1e-9)) / f;
  return `${trimZeros(r.toFixed(places))}%`;
}

// ── Readout.swift ────────────────────────────────────────────────────────────

export function amountValue(text) {
  const n = parseAmount(text);
  return n !== null && n >= 0 ? n : null;
}

export function growthValue(text) {
  const n = parsePercent(text);
  return n !== null && n > -1 ? n : null;
}

/// One typed field → its monthly model value, or null if unusable. $ growth may be negative.
export function fieldValue(key, text, unit, linear) {
  if (key === "cash") return amountValue(text);
  if (key === "growth" && linear) {
    const n = parseAmount(text);
    return n === null ? null : linearFromUnit(n, unit);
  }
  if (key === "growth") {
    const g = growthValue(text);
    return g === null ? null : growthFromUnit(g, unit);
  }
  const n = amountValue(text);
  return n === null ? null : amountFromUnit(n, unit);
}

/// A monthly model value → what the field shows in `unit`. Inverse of fieldValue.
/// $ growth keeps its "$" so it can't be mistaken for a percentage.
export function fieldText(key, monthly, unit, linear) {
  if (key === "growth") {
    return linear ? formatMoney(linearToUnit(monthly, unit)) : formatPercent(growthToUnit(monthly, unit));
  }
  return formatMoney(key === "cash" ? monthly : amountToUnit(monthly, unit)).replace("$", "");
}

// % ↔ $ growth: the same first-period step, measured in the growth field's own unit,
// so 8%/mo on $20k/mo revenue becomes +$1.6k/mo (8% of 20k), and back.
export function switchGrowthKind(monthlyGrowth, toLinear, monthlyRevenue, unit) {
  const revenue = amountToUnit(monthlyRevenue, unit);
  if (!(revenue > 0)) return null;
  return toLinear
    ? linearFromUnit(growthToUnit(monthlyGrowth, unit) * revenue, unit)
    : growthFromUnit(linearToUnit(monthlyGrowth, unit) / revenue, unit);
}

function hint(key, threshold, units, linear) {
  if (threshold === "never" || threshold === "any") return threshold;
  switch (key) {
    case "cash": return `≥ ${formatMoneyBound(threshold, true)}`;
    case "expenses": return `≤ ${formatMoneyBound(amountToUnit(threshold, units.expenses), false)}`;
    case "revenue": return `≥ ${formatMoneyBound(amountToUnit(threshold, units.revenue), true)}`;
    default: return linear
      ? `≥ ${formatMoneyBound(linearToUnit(threshold, units.growth), true)}`
      : `≥ ${formatPercentBound(growthToUnit(threshold, units.growth), true)}`;
  }
}

const NO_HINTS = { cash: "", expenses: "", revenue: "", growth: "" };

/// Everything the result area and the "alive if" column say, from monthly model inputs
/// (null if a field is unusable). Durations always read in months.
/// `taxes` (prototype, browser only): null, or the assumptions for withTaxes() below.
export function readoutFor(inputs, filledIn, units, now, taxes = null) {
  const taxed = inputs && taxes ? withTaxes(inputs, taxes) : null;
  const p = inputs && project(taxed?.inputs ?? inputs);
  if (!p) {
    return { tone: "neutral", headline: "—", line1: filledIn ? "Check the numbers in red" : "Enter all four numbers", line2: "", hints: NO_HINTS };
  }
  const b = taxed ? taxed.gross(breakevens(taxed.inputs)) : breakevens(inputs);
  const hints = Object.fromEntries(KEYS.map((k) => [k, hint(k, b[k], units, inputs.linear)]));

  if (p.verdict === "alive") {
    const T = p.monthsToProfitability ?? 0;
    if (T === 0) {
      return { tone: "alive", headline: "DEFAULT ALIVE", line1: "Already profitable", line2: "Revenue covers expenses", hints };
    }
    return {
      tone: "alive", headline: "DEFAULT ALIVE",
      line1: `Profitable in ${formatMonths(T)} · ${formatMonthYear(T, now)}`,
      line2: `Needs ${formatMoney(p.capitalNeeded ?? 0)} · ${formatMoney(p.cushion ?? 0)} to spare`,
      hints,
    };
  }

  const runway = p.runwayMonths ?? 0;
  const line1 = runway === 0
    ? "Out of cash now"
    : `Out of cash in ${formatMonths(runway)} · ${formatMonthYear(runway, now)}`;
  const line2 = p.capitalNeeded !== null && p.cushion !== null
    ? `Needs ${formatMoney(p.capitalNeeded)} · ${formatMoney(-p.cushion)} short`
    : "Never profitable at this growth";
  return { tone: "dead", headline: "DEFAULT DEAD", line1, line2, hints };
}

/// readoutFor, straight from the typed strings.
export function readout(raw, now, units = MONTHLY, linear = false, taxes = null) {
  const values = KEYS.map((k) => fieldValue(k, raw[k], units[k], linear));
  const inputs = values.includes(null) ? null
    : { cash: values[0], expenses: values[1], revenue: values[2], growth: values[3], linear };
  return readoutFor(inputs, KEYS.every((k) => raw[k].trim() !== ""), units, now, taxes);
}

// ── BalanceCurve.swift ───────────────────────────────────────────────────────
// Bank balance from now until the story is told: past profitability (alive), or to zero
// (dead). Returns { points: [{ t, balance }], horizon, marker, verdict } in months.

export function balanceCurve(inputs, samples = 160) {
  const p = project(inputs);
  if (!p) return null;
  let horizon, marker = null;
  if (p.verdict === "alive" && p.monthsToProfitability > 0) {
    horizon = p.monthsToProfitability * 1.35;
    marker = { t: p.monthsToProfitability, balance: p.cushion, kind: "profitable" };
  } else if (p.verdict === "alive") {
    horizon = 24;
  } else {
    horizon = Math.max(p.runwayMonths * 1.15, 1);
    marker = { t: p.runwayMonths, balance: 0, kind: "broke" };
  }
  const end = p.verdict === "dead" ? p.runwayMonths : horizon;
  const points = [];
  for (let i = 0; i <= samples; i++) {
    const t = (end * i) / samples;
    points.push({ t, balance: inputs.cash - cumulativeBurn(inputs, t) });
  }
  return { points, horizon, marker, verdict: p.verdict };
}

// ── Taxes.swift ───────────────────────────────────────────────────────────────
//
// Only taxes that cost money before profitability can change the verdict, because
// default alive asks whether you reach breakeven, and at breakeven profit is zero:
// income taxes (federal 21%, California 8.84%) are all zero on the way there.
// What's left for an Oakland company
// incorporated in Delaware and registered in WA/DE/CA (rates from oaklandca.gov,
// dor.wa.gov, corp.delaware.gov, ftb.ca.gov, checked Oct 2026):

export const TAX_RATES = {
  // Oakland business tax, Class F (professional services), 2026: 0.36% of gross
  // receipts, with no small-business exemption.
  oaklandReceipts: 0.0036,
  // Washington B&O tax on retailing (SaaS), 2026: a small business credit clears it up to
  // about $140k a year of Washington receipts; above that, 0.471% of them.
  washingtonBO: 0.00471,
  washingtonCredit: 140_000,
  // Delaware franchise tax minimum under the assumed par value capital method ($400) plus
  // the $50 annual report fee. (The authorized shares method can bill far more; file
  // with assumed par value.)
  delawarePerYear: 450,
};

/// taxes: { oaklandShare, washingtonShare } as fractions of revenue sourced there.
/// Returns { inputs, gross, revenueRate, fixedMonthly }: the inputs after taxes (revenue
/// net of receipts taxes, Delaware added to expenses), and gross() to turn breakevens
/// computed on those back into the numbers you'd type. Washington switches on from current
/// revenue only; a forecast that crosses its credit mid-way is ignored (worth ~0.05%).
export function withTaxes(inputs, { oaklandShare, washingtonShare }) {
  const overWashington = inputs.revenue * 12 * washingtonShare > TAX_RATES.washingtonCredit;
  const revenueRate = TAX_RATES.oaklandReceipts * oaklandShare + (overWashington ? TAX_RATES.washingtonBO * washingtonShare : 0);
  const fixedMonthly = TAX_RATES.delawarePerYear / 12;
  const keep = 1 - revenueRate;
  const after = {
    ...inputs,
    revenue: inputs.revenue * keep,
    // Linear growth adds taxed revenue too; a % growth rate is unchanged by a flat cut.
    growth: inputs.linear ? inputs.growth * keep : inputs.growth,
    expenses: inputs.expenses + fixedMonthly,
  };
  const gross = (b) => {
    const back = (v, f) => (typeof v === "number" ? f(v) : v);
    return {
      cash: b.cash,
      expenses: back(b.expenses, (v) => Math.max(0, v - fixedMonthly)),
      revenue: back(b.revenue, (v) => v / keep),
      growth: inputs.linear ? back(b.growth, (v) => v / keep) : b.growth,
    };
  };
  return { inputs: after, gross, revenueRate, fixedMonthly };
}
