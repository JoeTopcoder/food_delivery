// Shared cross-agent memory. No message bus — agents read/write the same
// audit trail (ai_agent_runs) that already exists for compliance, so any
// agent can ask "what have other agents already found about this
// order/driver/restaurant/user" before acting.

import { serviceClient } from './supabase.ts'

export interface EntityRef {
  type: string
  id: string
}

export interface RelatedRun {
  agent_name: string
  entity_type: string
  entity_id: string
  output: unknown
  created_at: string
}

/** Recent runs (from any agent) that touched any of the given entities,
 *  either as their primary subject or as a tagged related_entity. */
export async function getCrossAgentContext(refs: EntityRef[], limit = 10): Promise<RelatedRun[]> {
  const ids = refs.map((r) => r.id).filter(Boolean)
  if (ids.length === 0) return []

  const { data } = await serviceClient
    .from('ai_agent_runs')
    .select('agent_name, entity_type, entity_id, related_entities, output, created_at')
    .eq('status', 'completed')
    .order('created_at', { ascending: false })
    .limit(200)

  const rows = data ?? []
  const matches = rows.filter((r) => {
    if (ids.includes(r.entity_id as string)) return true
    const related = (r.related_entities as EntityRef[] | null) ?? []
    return related.some((e) => ids.includes(e.id))
  })

  return matches.slice(0, limit).map((r) => ({
    agent_name: r.agent_name as string,
    entity_type: r.entity_type as string,
    entity_id: r.entity_id as string,
    output: r.output,
    created_at: r.created_at as string,
  }))
}

/** Condense related runs into a short block safe to drop into a prompt. */
export function summarizeCrossAgentContext(runs: RelatedRun[]): string {
  if (runs.length === 0) return 'No prior activity from other agents on this order/customer/driver/restaurant.'
  return runs
    .map((r) => `- [${r.agent_name} · ${r.entity_type} · ${new Date(r.created_at).toISOString().slice(0, 10)}] ${JSON.stringify(r.output)}`)
    .join('\n')
}
