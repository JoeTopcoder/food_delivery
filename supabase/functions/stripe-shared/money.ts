/** Safe integer cents addition */
export function addCents(a: number, b: number): number {
  return Math.round(a) + Math.round(b)
}

/** Format cents to display string */
export function formatCents(cents: number, currency = 'jmd'): string {
  return new Intl.NumberFormat('en-JM', {
    style: 'currency', currency: currency.toUpperCase(),
  }).format(cents / 100)
}
