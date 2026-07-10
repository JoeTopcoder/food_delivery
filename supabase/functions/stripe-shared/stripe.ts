import Stripe from 'npm:stripe@14'

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY') ?? ''

if (!STRIPE_SECRET_KEY) throw new Error('STRIPE_SECRET_KEY is not set')

export const stripe = new Stripe(STRIPE_SECRET_KEY, {
  apiVersion: '2024-06-20',
  typescript: true,
})
