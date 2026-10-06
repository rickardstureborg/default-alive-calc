export const meta = {
  name: 'state-tax-research',
  description: 'Research pre-profit startup taxes for all 50 states and their major cities, one agent per state',
  phases: [{ title: 'Research', detail: 'one agent per state (+ its major cities); DC with Maryland' }],
}

const STATES = [
  ['Alabama', 'Birmingham, Montgomery, Huntsville, Mobile'],
  ['Alaska', 'Anchorage'],
  ['Arizona', 'Phoenix, Tucson, Mesa, Scottsdale'],
  ['Arkansas', 'Little Rock'],
  ['California', 'Los Angeles, San Francisco, San Diego, San Jose, Oakland'],
  ['Colorado', 'Denver, Colorado Springs, Aurora, Boulder'],
  ['Connecticut', 'Stamford, Hartford, New Haven'],
  ['Delaware', 'Wilmington'],
  ['Florida', 'Miami, Jacksonville, Tampa, Orlando'],
  ['Georgia', 'Atlanta, Savannah'],
  ['Hawaii', 'Honolulu'],
  ['Idaho', 'Boise'],
  ['Illinois', 'Chicago'],
  ['Indiana', 'Indianapolis'],
  ['Iowa', 'Des Moines'],
  ['Kansas', 'Wichita, Kansas City (KS)'],
  ['Kentucky', 'Louisville, Lexington'],
  ['Louisiana', 'New Orleans, Baton Rouge'],
  ['Maine', 'Portland (ME)'],
  ['Maryland', 'Baltimore, Montgomery County, AND Washington, DC (cover DC fully as its own jurisdiction)'],
  ['Massachusetts', 'Boston, Cambridge'],
  ['Michigan', 'Detroit, Grand Rapids'],
  ['Minnesota', 'Minneapolis, St. Paul'],
  ['Mississippi', 'Jackson'],
  ['Missouri', 'Kansas City (MO), St. Louis'],
  ['Montana', 'Billings, Missoula'],
  ['Nebraska', 'Omaha, Lincoln'],
  ['Nevada', 'Las Vegas, Henderson, Reno'],
  ['New Hampshire', 'Manchester'],
  ['New Jersey', 'Newark, Jersey City'],
  ['New Mexico', 'Albuquerque, Santa Fe'],
  ['New York', 'New York City, Buffalo'],
  ['North Carolina', 'Charlotte, Raleigh, Durham'],
  ['North Dakota', 'Fargo'],
  ['Ohio', 'Columbus, Cleveland, Cincinnati'],
  ['Oklahoma', 'Oklahoma City, Tulsa'],
  ['Oregon', 'Portland (OR) incl. Multnomah County and Metro taxes'],
  ['Pennsylvania', 'Philadelphia, Pittsburgh'],
  ['Rhode Island', 'Providence'],
  ['South Carolina', 'Charleston, Columbia, Greenville'],
  ['South Dakota', 'Sioux Falls'],
  ['Tennessee', 'Nashville, Memphis, Knoxville'],
  ['Texas', 'Houston, Dallas, Austin, San Antonio'],
  ['Utah', 'Salt Lake City'],
  ['Vermont', 'Burlington'],
  ['Virginia', 'Arlington County, Fairfax County, Richmond, Virginia Beach (BPOL taxes)'],
  ['Washington', 'Seattle, Bellevue, Tacoma, Spokane'],
  ['West Virginia', 'Charleston (WV)'],
  ['Wisconsin', 'Milwaukee, Madison'],
  ['Wyoming', 'Cheyenne'],
]

const NUM_OR_NULL = { type: ['number', 'null'] }
const SCHEMA = {
  type: 'object',
  properties: {
    state: { type: 'string' },
    jurisdictions: {
      type: 'array',
      description: 'The state itself first, then each city/county/district that has a tax worth knowing about (include cities you checked that have none, with zero rates, so absence is explicit).',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string', description: 'e.g. "California" or "San Francisco, CA"' },
          kind: { type: 'string', enum: ['state', 'city', 'county', 'district'] },
          taxYear: { type: 'string', description: 'which tax/report year the figures are for' },
          receiptsTaxes: {
            type: 'array',
            description: 'Taxes measured by gross receipts/revenue (or a receipts-like base such as gross margin) that a pre-profit company owes regardless of profit. Exclude sales/use taxes collected from customers.',
            items: {
              type: 'object',
              properties: {
                name: { type: 'string' },
                rateForSaaS: { type: 'number', description: 'effective fraction of receipts for a software/SaaS or professional-services company, e.g. 0.0036 for $3.60 per $1,000. If tiered, the rate for a startup under ~$10M revenue; describe tiers in notes.' },
                base: { type: 'string', description: 'what the rate applies to, e.g. receipts sourced/apportioned to the jurisdiction (and how sourced), or all receipts' },
                annualThreshold: { ...NUM_OR_NULL, description: 'no tax owed at or below this annual amount; null if none' },
                thresholdBasis: { type: 'string', description: 'what the threshold is measured on (total revenue everywhere, revenue sourced there, etc.) or "none"' },
                notes: { type: 'string', description: 'tiers, deductions/exclusions, filing quirks' },
              },
              required: ['name', 'rateForSaaS', 'base', 'annualThreshold', 'thresholdBasis', 'notes'],
            },
          },
          fixedAnnual: {
            type: 'array',
            description: 'Fixed or minimum amounts a pre-profit corporation owes every year (minimum franchise/privilege taxes, annual report fees, business license fees that do not scale with receipts). Use the amount for a small startup.',
            items: {
              type: 'object',
              properties: { name: { type: 'string' }, amountPerYear: { type: 'number' }, notes: { type: 'string' } },
              required: ['name', 'amountPerYear', 'notes'],
            },
          },
          profitTaxes: {
            type: 'array',
            description: 'Taxes on net income/profit (zero before profitability; informational only).',
            items: {
              type: 'object',
              properties: { name: { type: 'string' }, rate: { type: 'number' }, notes: { type: 'string' } },
              required: ['name', 'rate', 'notes'],
            },
          },
          otherNotes: { type: 'string', description: 'payroll/head taxes (these belong in expenses), SaaS sales/lease taxes collected from customers, anything else a founder should know' },
          sources: { type: 'array', items: { type: 'string' }, description: 'official URLs you actually read (revenue department, city finance, statute)' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
          calculatorOption: {
            type: 'object',
            description: 'How this jurisdiction should appear in the calculator. Model: revenueRate × (share of revenue sourced there) when the threshold is exceeded, plus fixedPerYear.',
            properties: {
              label: { type: 'string', description: 'short, e.g. "California" or "San Francisco"' },
              revenueRate: { type: 'number', description: 'fraction of sourced revenue; 0 if none' },
              thresholdPerYear: { ...NUM_OR_NULL, description: 'annual revenue at or below which the revenue rate does not apply; null if none' },
              thresholdOn: { type: 'string', enum: ['total revenue', 'sourced revenue', 'none'] },
              fixedPerYear: { type: 'number', description: 'sum of fixed annual amounts for a small pre-profit corporation' },
              defaultShare: { type: 'number', description: "suggested default share of a nationally-selling company's revenue sourced there (e.g. its share of US population), as a fraction" },
              assumptionText: { type: 'string', description: 'one plain sentence for the assumptions list, e.g. "0.36% of an Oakland office's gross receipts; no small-business exemption."' },
              worthListing: { type: 'boolean', description: 'true if this changes what a pre-profit startup pays (any receipts tax or fixed annual amount over ~$0)' },
            },
            required: ['label', 'revenueRate', 'thresholdPerYear', 'thresholdOn', 'fixedPerYear', 'defaultShare', 'assumptionText', 'worthListing'],
          },
        },
        required: ['name', 'kind', 'taxYear', 'receiptsTaxes', 'fixedAnnual', 'profitTaxes', 'otherNotes', 'sources', 'confidence', 'calculatorOption'],
      },
    },
  },
  required: ['state', 'jurisdictions'],
}

const prompt = (state, cities) => `You are researching taxes for a "default alive" startup calculator. Today is October 2026; use the most recent tax year whose rates are published (2025 or 2026).

The user is a venture-backed C corporation (incorporated in Delaware) that sells software/SaaS and professional services nationally, has employees, and is NOT yet profitable. The calculator asks whether they reach profitability before cash runs out, so the only taxes that matter are ones that cost money before profit: taxes measured by gross receipts/revenue (or a receipts-like base such as Texas's margin), and fixed or minimum annual amounts (minimum franchise taxes, annual report fees, flat business licenses). Taxes on net income are zero before profit: list them as informational only. Sales/use taxes collected from customers (including SaaS sales or lease taxes) are pass-through: mention them in notes, don't count them. Payroll/head taxes are an expense the user already counts in expenses: mention them in notes.

Research ${state} (state level, as a foreign corporation registered to do business there) and these localities: ${cities}. Add any other city in ${state} with a notable local receipts or business tax on software/services companies.

Rules:
- Use official sources (state revenue department, city/county finance department, statutes) and read them; cite the URLs you actually read. If a figure only appears in secondary sources, say so and lower your confidence.
- Get exact current rates and thresholds (e.g. Washington B&O service rate, Ohio CAT exclusion, Texas no-tax-due threshold, San Francisco gross receipts tiers for information/professional services, Philadelphia BIRT mills). Note the year they apply to.
- For a fixed minimum, give the amount a small pre-profit startup actually pays (e.g. California's $800 minimum franchise tax; for annual reports, the corporation filing fee).
- Fill calculatorOption carefully: revenueRate is the effective fraction of revenue sourced to the jurisdiction; set thresholdPerYear/thresholdOn when nothing is owed below a revenue level; defaultShare is a reasonable default share of a nationally-selling company's revenue sourced there (use share of US population if nothing better).
- Be precise and conservative; do not guess numbers. If something is genuinely uncertain, say so in notes and set confidence accordingly.`

phase('Research')
// args: optional list of state names to (re)run, e.g. after some agents were blocked.
const TODO = Array.isArray(args) ? STATES.filter(([s]) => args.includes(s)) : STATES
const results = await parallel(TODO.map(([state, cities]) => () =>
  agent(prompt(state, cities), { label: state, phase: 'Research', schema: SCHEMA })))

const done = results.filter(Boolean)
const missing = TODO.map(([s]) => s).filter((s) => !done.some((r) => r.state && r.state.toLowerCase().includes(s.toLowerCase())))
if (missing.length) log(`No result for: ${missing.join(', ')}`)
return { results: done, missing }
