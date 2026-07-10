/** Safe integer cents addition */
export function addCents(a: number, b: number): number {
  return Math.round(a) + Math.round(b)
}

/** Format cents to display string */
export function formatCents(cents: number, currency = 'usd'): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency', currency: currency.toUpperCase(),
  }).format(cents / 100)
}
