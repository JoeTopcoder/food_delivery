import { userClient } from './supabase.ts'

export interface AuthUser {
  id: string
  email: string
}

export async function requireAuth(req: Request): Promise<AuthUser> {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) throw new Error('UNAUTHORIZED')
  const client = userClient(authHeader)
  const { data: { user }, error } = await client.auth.getUser()
  if (error || !user) throw new Error('UNAUTHORIZED')
  return { id: user.id, email: user.email ?? '' }
}

export async function requireAdmin(req: Request): Promise<AuthUser> {
  const user = await requireAuth(req)
  const client = userClient(req.headers.get('Authorization') ?? '')
  const { data } = await client.from('users').select('role').eq('id', user.id).single()
  if (data?.role !== 'admin') throw new Error('FORBIDDEN')
  return user
}
