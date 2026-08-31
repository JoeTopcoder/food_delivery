// automation-workflow-runner — Workflow Station (7Dash AI Operations)
//
// This is the native-Supabase equivalent of an n8n workflow: a pg_cron
// schedule calls this function on a bearer secret (not a user JWT — cron has
// no admin session), which runs a registered pipeline: pull real data →
// generate content with AI → store a draft → notify admins for review.
// Nothing is ever auto-published; every workflow here ends at a draft, same
// human-approval discipline as every other agent this session.
//
// To add a new scheduled workflow: add a case to WORKFLOWS below, insert a
// row into automation_workflows, and schedule it with cron.schedule() in a
// migration (see 20260711000001_workflow_station.sql for the pattern).
// Deploy: supabase functions deploy automation-workflow-runner --no-verify-jwt

import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'
import { getCrossAgentContext } from '../stripe-shared/agent_context.ts'
import { sendEmail } from '../_shared/resend.ts'
import { publishToAllPlatforms } from '../_shared/social.ts'

const RUNNER_SECRET = Deno.env.get('AUTOMATION_RUNNER_SECRET') ?? ''
const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const MARKETING_FROM_EMAIL = Deno.env.get('SALES_FROM_EMAIL') ?? '7Dash Marketing <onboarding@resend.dev>'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

/** See matching helper in ops-report-agent — in-app push fallback while the
 *  Resend sending domain is unverified. */
async function sendPushToCustomer(userId: string, title: string, body: string, data: Record<string, string>): Promise<boolean> {
  const { data: user } = await serviceClient.from('users').select('fcm_token').eq('id', userId).maybeSingle()
  const token = user?.fcm_token as string | undefined
  if (!token) return false
  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/send-fcm-notification`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        token,
        title: title.slice(0, 100),
        body: body.length > 150 ? `${body.slice(0, 147)}...` : body,
        data: { ...data, user_id: userId },
      }),
    })
    return res.ok
  } catch (e) {
    console.error('sendPushToCustomer failed', e)
    return false
  }
}

/** See matching helper in ops-report-agent — generates a real, single-use
 *  promo code for a retention win-back email. Only called from the
 *  auto-approve path here; a human-reviewed draft gets its code minted by
 *  ops-report-agent's retentionApproveOutreach when actually approved. */
async function createRetentionPromoCode(discountPercent: number): Promise<{ code: string; discountValue: number } | null> {
  const discountValue = Math.min(20, Math.max(10, Math.round(discountPercent) || 15))
  let code = ''
  for (let attempt = 0; attempt < 5; attempt++) {
    const candidate = `WELCOME${Math.random().toString(36).slice(2, 7).toUpperCase()}`
    const { data: existing } = await serviceClient.from('promo_codes').select('id').eq('code', candidate).maybeSingle()
    if (!existing) { code = candidate; break }
  }
  if (!code) return null

  const expiresAt = new Date(Date.now() + 14 * 86400000).toISOString()
  const { error: insertErr } = await serviceClient.from('promo_codes').insert({
    code,
    description: 'Personal win-back offer — Customer Retention',
    discount_type: 'percentage',
    discount_value: discountValue,
    max_uses: 1,
    usage_count: 0,
    expires_at: expiresAt,
    restaurant_id: null,
    is_active: true,
  })
  if (insertErr) {
    console.error('weekly_retention_outreach: failed to create promo code', insertErr.message)
    return null
  }
  return { code, discountValue }
}

/** See matching helper in ops-report-agent — notifies customers of a newly
 *  created promo via FCM (push + in-app notifications row). Only reached
 *  from weeklyPromotionScan's auto-approve path; a human-reviewed proposal
 *  gets its notification sent by ops-report-agent's approvePromotion when
 *  actually approved. */
async function notifyCustomersOfPromo(promo: { code: string; description: string | null; discount_type: string; discount_value: number; restaurant_id: string | null }): Promise<{ notified: number }> {
  let customerIds: string[] = []
  if (promo.restaurant_id) {
    const { data: orders } = await serviceClient.from('orders').select('user_id').eq('restaurant_id', promo.restaurant_id)
    customerIds = [...new Set((orders ?? []).map((o) => o.user_id as string).filter(Boolean))]
  } else {
    const { data: customers } = await serviceClient.from('users').select('id').eq('role', 'customer').limit(300)
    customerIds = (customers ?? []).map((c) => c.id as string)
  }
  if (customerIds.length === 0) return { notified: 0 }

  const discountLabel = promo.discount_type === 'percentage' ? `${promo.discount_value}% off` : `$${promo.discount_value} off`
  const title = `🎉 New promo: ${discountLabel}`
  const body = promo.description || `Use code ${promo.code} at checkout — ${discountLabel}.`

  let notified = 0
  for (const customerId of customerIds) {
    const sent = await sendPushToCustomer(customerId, title, body, { type: 'promotion', promo_code: promo.code })
    if (sent) notified++
  }
  return { notified }
}

async function isAutoApproved(workflowId: string): Promise<boolean> {
  const { data } = await serviceClient.from('automation_workflows').select('auto_approve').eq('id', workflowId).maybeSingle()
  return data?.auto_approve === true
}

interface WorkflowResult {
  summary: string
  marketingContentId?: string
}

/** Two legitimate callers: pg_cron (bearer secret, no user session) and an
 *  admin manually hitting "Run Now" in the app (real Supabase session). */
async function requireRunnerAuth(req: Request): Promise<void> {
  const auth = req.headers.get('Authorization') ?? ''
  const token = auth.replace(/^Bearer\s+/i, '')
  if (RUNNER_SECRET && token === RUNNER_SECRET) return
  await requireAdmin(req) // throws UNAUTHORIZED/FORBIDDEN if not a real admin session
}

async function getAdminEmails(): Promise<string[]> {
  const { data } = await serviceClient.from('users').select('email').eq('role', 'admin').not('email', 'is', null)
  return (data ?? []).map((u) => u.email as string).filter(Boolean)
}

/** Uploads generated image bytes to Supabase Storage so drafts stay viewable
 *  in the app (OpenAI's temporary URLs, when returned, expire quickly). */
async function uploadImageBytes(bytes: Uint8Array, path: string): Promise<string | null> {
  try {
    const { error } = await serviceClient.storage.from('marketing-content').upload(path, bytes, {
      contentType: 'image/png',
      upsert: true,
    })
    if (error) return null
    const { data } = serviceClient.storage.from('marketing-content').getPublicUrl(path)
    return data.publicUrl
  } catch {
    return null
  }
}

function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}

function round2(n: number): number {
  return Math.round(n * 100) / 100
}

function escapeHtml(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

async function notifyAdminsOfNewDrafts(subject: string, summaryHtml: string): Promise<void> {
  if (!RESEND_API_KEY) return
  const admins = await getAdminEmails()
  if (admins.length === 0) return
  const html = `<!DOCTYPE html><html><body style="font-family:-apple-system,sans-serif;max-width:560px;margin:0 auto;padding:24px;">
    ${summaryHtml}
    <p style="color:#999;font-size:12px;margin-top:24px;">Review and approve in the AI Ops Hub → Workflow Station. Nothing has been sent or created automatically.</p>
  </body></html>`
  await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: MARKETING_FROM_EMAIL, to: admins, subject, html }),
  }).catch(() => {})
}

// ── weekly_social_campaign ───────────────────────────────────────────────
// Draws from your ACTUAL menu catalog (menus table, real restaurants only —
// is_mock_data excluded on both restaurants and menus), not just order
// history. Order counts from the last 90 days are used only as a secondary
// ranking signal to surface genuine favorites when there's enough order
// volume — with only a handful of real orders platform-wide, requiring
// order history would mean recycling the same 1-2 restaurants forever.
async function weeklySocialCampaign(workflowId: string): Promise<WorkflowResult> {
  const ninetyDaysAgo = new Date(Date.now() - 90 * 86400000).toISOString()

  const [{ data: menuItems }, { data: orderItems }] = await Promise.all([
    serviceClient
      .from('menus')
      .select('id, name, restaurant_id, restaurants!inner(name, status, is_mock_data)')
      .or('is_mock_data.is.null,is_mock_data.eq.false')
      .eq('restaurants.status', 'approved')
      .or('is_mock_data.is.null,is_mock_data.eq.false', { foreignTable: 'restaurants' }),
    serviceClient.from('order_items').select('menu_item_id').gte('created_at', ninetyDaysAgo),
  ])

  const orderCounts = new Map<string, number>()
  for (const oi of orderItems ?? []) {
    if (!oi.menu_item_id) continue
    orderCounts.set(oi.menu_item_id, (orderCounts.get(oi.menu_item_id) ?? 0) + 1)
  }

  const catalog = (menuItems ?? []) as { id: string; name: string; restaurants: { name: string } | null }[]
  const ranked = catalog
    .map((m) => ({ name: m.name, restaurant: m.restaurants?.name ?? 'Unknown', order_count: orderCounts.get(m.id) ?? 0 }))
    .sort((a, b) => b.order_count - a.order_count)
  // When there's real order signal, feature the actual top sellers. When
  // there isn't (order_count all 0), still feature real menu items — just
  // without claiming a popularity number we don't have.
  const hasOrderSignal = ranked.some((r) => r.order_count > 0)
  const popularItems = ranked.slice(0, 5)

  const usingFallback = popularItems.length === 0
  const promptContext = usingFallback
    ? 'No menu items on file yet — write a general brand-awareness post inviting people to try 7Dash for the first time.'
    : hasOrderSignal
      ? `Actual best-selling items this quarter, from real order data: ${popularItems.map((i) => `${i.name} from ${i.restaurant} (ordered ${i.order_count} times)`).join(', ')}.`
      : `Real current menu items to feature (no order-volume data yet to rank by popularity, so do NOT claim these are "best sellers" or cite an order count): ${popularItems.map((i) => `${i.name} from ${i.restaurant}`).join(', ')}.`

  if (!OPENAI_API_KEY) throw new Error('OPENAI_API_KEY not configured')

  const captionRes = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: `You write social media captions for 7Dash, a food delivery app. Given real menu/order data (never invent a dish, restaurant, or order count not given to you), write exactly 3 distinct ready-to-post captions (Instagram/Facebook style, with relevant emoji, under 200 characters each). If no order-count data is provided, describe the items as menu highlights, not "best sellers" or "most popular". Respond ONLY with JSON: { "captions": [string, string, string] }`,
        },
        { role: 'user', content: promptContext },
      ],
      response_format: { type: 'json_object' },
      temperature: 0.7,
    }),
  })
  if (!captionRes.ok) throw new Error(`Caption generation failed: ${await captionRes.text()}`)
  const captionCompletion = await captionRes.json()
  const parsed = JSON.parse(captionCompletion.choices?.[0]?.message?.content ?? '{}')
  const captions: string[] = Array.isArray(parsed.captions) ? parsed.captions.slice(0, 3) : []

  let imageUrl: string | null = null
  let imageDebug: string | null = null
  const imagePrompt = usingFallback
    ? 'Vibrant, appetizing flat-lay food delivery promo image, warm inviting colors, no text overlay'
    : `Vibrant, appetizing promo image featuring ${popularItems[0].name}, food delivery theme, warm inviting colors, no text overlay`
  try {
    const imageRes = await fetch('https://api.openai.com/v1/images/generations', {
      method: 'POST',
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'gpt-image-1', prompt: imagePrompt, n: 1, size: '1024x1024' }),
    })
    if (imageRes.ok) {
      const imageData = await imageRes.json()
      const b64 = imageData.data?.[0]?.b64_json as string | undefined
      const rawUrl = imageData.data?.[0]?.url as string | undefined
      if (b64) {
        imageUrl = await uploadImageBytes(base64ToBytes(b64), `weekly-social/${Date.now()}.png`)
        if (!imageUrl) imageDebug = 'upload_failed'
      } else if (rawUrl) {
        const fetched = await fetch(rawUrl)
        if (fetched.ok) {
          imageUrl = await uploadImageBytes(new Uint8Array(await fetched.arrayBuffer()), `weekly-social/${Date.now()}.png`)
        }
        if (!imageUrl) imageDebug = 'url_fetch_or_upload_failed'
      } else {
        imageDebug = `no_image_data_in_response: ${JSON.stringify(imageData).slice(0, 500)}`
      }
    } else {
      imageDebug = `openai_error_${imageRes.status}: ${(await imageRes.text()).slice(0, 500)}`
    }
  } catch (e) {
    imageDebug = `exception: ${e instanceof Error ? e.message : String(e)}`
  }

  const { data: content, error: insertErr } = await serviceClient
    .from('marketing_content')
    .insert({
      workflow_id: workflowId,
      content_type: 'social',
      captions,
      image_url: imageUrl,
      source_data: { featured_items: popularItems, has_order_signal: hasOrderSignal, used_fallback: usingFallback },
      status: 'draft',
    })
    .select('id')
    .single()
  if (insertErr) throw new Error(`Failed to save draft: ${insertErr.message}`)

  await serviceClient.from('ai_agent_runs').insert({
    agent_name: 'marketing_content',
    entity_type: 'automation_workflow',
    entity_id: content.id,
    related_entities: [],
    input: { workflow: 'weekly_social_campaign', featured_items: popularItems, has_order_signal: hasOrderSignal, used_fallback: usingFallback },
    output: { captions, image_url: imageUrl },
    model: 'gpt-4o-mini + gpt-image-1',
    status: 'completed',
  })

  const autoApprove = await isAutoApproved(workflowId)
  let publishResults: Record<string, { ok: boolean; url?: string; error?: string }> | null = null
  if (autoApprove && captions.length > 0) {
    publishResults = await publishMarketingContent(content.id, 0)
  }
  const anyPublished = publishResults ? Object.values(publishResults).some((r) => r.ok) : false

  if (RESEND_API_KEY) {
    const admins = await getAdminEmails()
    if (admins.length > 0) {
      const platformLines = publishResults
        ? Object.entries(publishResults).map(([platform, r]) => `<li>${platform}: ${r.ok ? `✅ posted${r.url ? ` (<a href="${r.url}">${r.url}</a>)` : ''}` : `❌ ${escapeHtml(r.error ?? 'not configured')}`}</li>`).join('')
        : ''
      const html = `<!DOCTYPE html><html><body style="font-family:-apple-system,sans-serif;max-width:560px;margin:0 auto;padding:24px;">
        <h2>Weekly Social Media Campaign — ${autoApprove ? (anyPublished ? 'Published Automatically' : 'Auto-Publish Attempted') : 'Draft Ready'}</h2>
        ${imageUrl ? `<img src="${imageUrl}" style="width:100%;border-radius:8px;margin:16px 0;" />` : ''}
        ${captions.map((c, i) => `<p><b>Option ${i + 1}:</b> ${c}</p>`).join('')}
        ${platformLines ? `<ul>${platformLines}</ul>` : ''}
        <p style="color:#999;font-size:12px;margin-top:24px;">${autoApprove ? 'Auto-approve is ON for this workflow — see results above. Turn it off in Workflow Station to require approval again.' : 'Review and approve in the AI Ops Hub → Workflow Station before posting. Nothing has been published automatically.'}</p>
      </body></html>`
      await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          from: MARKETING_FROM_EMAIL,
          to: admins,
          subject: `Weekly Social Media Campaign — ${autoApprove ? (anyPublished ? 'Published' : 'Auto-Publish Attempted') : 'Draft Ready for Review'}`,
          html,
        }),
      }).catch(() => {})
    }
  }

  return {
    summary: usingFallback
      ? 'Generated fallback brand-awareness draft (no order data yet).'
      : `Generated draft featuring ${popularItems[0].name} and ${captions.length} caption options.${imageDebug ? ` [image_debug: ${imageDebug}]` : ''}${autoApprove ? (anyPublished ? ' Published automatically.' : ' Auto-publish attempted — no platform succeeded (check credentials).') : ''}`,
    marketingContentId: content.id,
  }
}

// Publishes an existing marketing_content draft to every configured social
// platform (skips any without credentials), records the outcome, and marks
// the draft published/publish_failed. Called both from an admin's "Approve"
// click (via the publish_content_id request branch below) and from
// weeklySocialCampaign's auto-approve path above — same function either way,
// so there's one place that ever actually posts externally.
async function publishMarketingContent(contentId: string, captionIndex: number): Promise<Record<string, { ok: boolean; url?: string; error?: string }>> {
  const { data: content, error: fetchErr } = await serviceClient
    .from('marketing_content')
    .select('captions, image_url')
    .eq('id', contentId)
    .single()
  if (fetchErr || !content) throw new Error('Marketing content not found')

  const captions = (content.captions ?? []) as string[]
  const caption = captions[captionIndex] ?? captions[0]
  if (!caption) throw new Error('No caption to publish')

  const results = await publishToAllPlatforms(caption, content.image_url as string | null)
  const anySuccess = Object.values(results).some((r) => r.ok)

  await serviceClient.from('marketing_content').update({
    posted_caption: caption,
    publish_results: results,
    published_at: anySuccess ? new Date().toISOString() : null,
    status: anySuccess ? 'published' : 'publish_failed',
  }).eq('id', contentId)

  await serviceClient.from('ai_agent_runs').insert({
    agent_name: 'marketing_content',
    entity_type: 'marketing_content',
    entity_id: contentId,
    related_entities: [],
    input: { action: 'publish', caption_index: captionIndex },
    output: { caption, results },
    status: anySuccess ? 'completed' : 'failed',
  })

  return results
}

// ── weekly_retention_outreach ────────────────────────────────────────────
// Same at-risk computation and drafting prompt as ops-report-agent's
// customer_retention / customer_retention_outreach (admin-triggered
// versions) — this just runs it on a schedule instead of waiting for an
// admin to click through. Drafts are logged exactly the same way (same
// agent_name, same ai_agent_runs shape), so the Workflow Station and the
// Customer Retention screen both surface them identically. Skips anyone
// Fraud & Risk flagged or already drafted/sent to in the last 5 days.
async function weeklyRetentionOutreach(workflowId: string): Promise<WorkflowResult> {
  if (!OPENAI_API_KEY) throw new Error('OPENAI_API_KEY not configured')
  const autoApprove = await isAutoApproved(workflowId)

  const [{ data: customers }, { data: orders }] = await Promise.all([
    serviceClient.from('users').select('id, name, email, fcm_token').eq('role', 'customer'),
    serviceClient.from('orders').select('user_id, ordered_at, total_amount'),
  ])

  const orderRows = orders ?? []
  const lastOrderByUser = new Map<string, string>()
  const orderCountByUser = new Map<string, number>()
  const totalSpentByUser = new Map<string, number>()
  for (const o of orderRows) {
    if (!o.user_id) continue
    orderCountByUser.set(o.user_id, (orderCountByUser.get(o.user_id) ?? 0) + 1)
    totalSpentByUser.set(o.user_id, (totalSpentByUser.get(o.user_id) ?? 0) + (Number(o.total_amount) || 0))
    const existing = lastOrderByUser.get(o.user_id)
    if (!existing || new Date(o.ordered_at) > new Date(existing)) lastOrderByUser.set(o.user_id, o.ordered_at)
  }

  const now = Date.now()
  const atRisk = (customers ?? [])
    .map((c) => {
      const orderCount = orderCountByUser.get(c.id) ?? 0
      const lastOrder = lastOrderByUser.get(c.id)
      const daysSinceLastOrder = lastOrder ? Math.round((now - new Date(lastOrder).getTime()) / 86400000) : null
      return { id: c.id, name: c.name, email: c.email, fcmToken: c.fcm_token, orderCount, daysSinceLastOrder, lifetimeSpend: round2(totalSpentByUser.get(c.id) ?? 0) }
    })
    .filter((c) => c.orderCount > 0 && c.daysSinceLastOrder != null && c.daysSinceLastOrder >= 21 && (c.email || c.fcmToken))
    .sort((a, b) => (b.daysSinceLastOrder ?? 0) - (a.daysSinceLastOrder ?? 0))

  const fiveDaysAgo = new Date(now - 5 * 86400000).toISOString()
  const { data: recentOutreachRuns } = await serviceClient
    .from('ai_agent_runs')
    .select('entity_id')
    .eq('agent_name', 'customer_retention_outreach')
    .gte('created_at', fiveDaysAgo)
  const recentlyContacted = new Set((recentOutreachRuns ?? []).map((r) => r.entity_id as string))

  const drafted: { name: string; days_since_last_order: number | null }[] = []
  for (const c of atRisk) {
    if (drafted.length >= 5) break
    if (recentlyContacted.has(c.id)) continue

    const related = await getCrossAgentContext([{ type: 'user', id: c.id }], 20)
    if (related.some((run) => run.agent_name === 'fraud_risk')) continue

    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: `You are the 7Dash Customer Retention drafting assistant. Draft a short, warm win-back email to a returning customer who hasn't ordered in a while. Rules:
- Use ONLY the real stats given (lifetime orders, days since last order) — reference them naturally if it helps ("we've missed having you order with us").
- Propose a modest, personal win-back discount between 10 and 20 (percent). Reference it in the body using the LITERAL tokens [DISCOUNT] and [PROMO_CODE] exactly as written — e.g. "enjoy [DISCOUNT]% off your next order with code [PROMO_CODE]" — never write a real number or code yourself; those tokens get replaced with a real, one-time code before sending.
- Warm, personal tone — this is a 1:1 email, not a mass blast. 3-4 short paragraphs, end with a clear call to action (open the app / order again).
- Sign off as "The 7Dash Team".
Respond ONLY with JSON: { "subject": string, "body": string, "discount_percent": number }`,
          },
          { role: 'user', content: JSON.stringify({ customer: { name: c.name, email: c.email }, lifetime_orders: c.orderCount, lifetime_spend: c.lifetimeSpend, days_since_last_order: c.daysSinceLastOrder }) },
        ],
        response_format: { type: 'json_object' },
        temperature: 0.6,
      }),
    })
    if (!res.ok) continue
    const completion = await res.json()
    const parsed = JSON.parse(completion.choices?.[0]?.message?.content ?? '{}')
    const subject = String(parsed.subject ?? 'We miss you at 7Dash').slice(0, 200)
    const body = String(parsed.body ?? '').slice(0, 4000)
    const discountPercent = Math.min(20, Math.max(10, Math.round(Number(parsed.discount_percent) || 15)))
    if (!body) continue

    let finalSubject = subject
    let finalBody = body
    let emailSent = false
    let pushSent = false
    let resendError: string | null = null
    let promoCode: { code: string; discountValue: number } | null = null
    if (autoApprove) {
      // Only a fully unattended send needs the placeholder filled here — a
      // draft awaiting human review in Workflow Station stays untouched, and
      // gets its real code minted by ops-report-agent's retentionApproveOutreach
      // when an admin actually approves it (same discipline as everywhere else).
      if (body.includes('[DISCOUNT]') || body.includes('[PROMO_CODE]')) {
        promoCode = await createRetentionPromoCode(discountPercent)
        if (promoCode) {
          finalSubject = subject.replaceAll('[DISCOUNT]', String(promoCode.discountValue)).replaceAll('[PROMO_CODE]', promoCode.code)
          finalBody = body.replaceAll('[DISCOUNT]', String(promoCode.discountValue)).replaceAll('[PROMO_CODE]', promoCode.code)
        }
      }
      if (c.email) {
        const html = `<!DOCTYPE html><html><body style="font-family:-apple-system,sans-serif;max-width:560px;margin:0 auto;padding:24px;">
          <p style="white-space:pre-wrap;line-height:1.6;">${escapeHtml(finalBody)}</p>
        </body></html>`
        const result = await sendEmail({ to: [c.email], subject: finalSubject, html })
        emailSent = result.ok
        if (!result.ok) {
          resendError = result.error ?? null
          console.error('weekly_retention_outreach: auto-send failed', resendError)
        }
      }
      // In-app push fallback while the Resend sending domain is unverified —
      // tried regardless of email outcome, same reasoning as ops-report-agent.
      pushSent = await sendPushToCustomer(c.id, finalSubject, finalBody, { type: 'retention_outreach' })
    }
    const delivered = emailSent || pushSent

    await serviceClient.from('ai_agent_runs').insert({
      agent_name: 'customer_retention_outreach',
      entity_type: 'user',
      entity_id: c.id,
      related_entities: [{ type: 'user', id: c.id }],
      input: {
        customer_id: c.id, lifetime_orders: c.orderCount, lifetime_spend: c.lifetimeSpend, days_since_last_order: c.daysSinceLastOrder,
        source: 'weekly_retention_outreach',
        ...(autoApprove ? { decision: 'approve', auto_approved: true } : {}),
      },
      output: {
        subject: autoApprove ? finalSubject : subject, body: autoApprove ? finalBody : body,
        discount_percent: discountPercent, email_sent: emailSent, push_sent: pushSent,
        promo_code: promoCode?.code ?? null,
      },
      model: 'gpt-4o-mini',
      status: autoApprove ? (delivered ? 'completed' : 'failed') : 'completed',
      error: resendError,
    })
    drafted.push({ name: c.name, days_since_last_order: c.daysSinceLastOrder })
  }

  if (drafted.length > 0) {
    await notifyAdminsOfNewDrafts(
      autoApprove
        ? `Weekly Retention Outreach — ${drafted.length} email${drafted.length === 1 ? '' : 's'} auto-sent`
        : `Weekly Retention Outreach — ${drafted.length} draft${drafted.length === 1 ? '' : 's'} ready for review`,
      `<h2>Weekly Retention Outreach — ${autoApprove ? 'Sent Automatically' : 'Drafts Ready'}</h2>
       <ul>${drafted.map((d) => `<li>${escapeHtml(d.name ?? 'Customer')} — ${d.days_since_last_order} days since last order</li>`).join('')}</ul>
       ${autoApprove ? '<p style="color:#999;font-size:12px;">Auto-approve is ON for this workflow — these were sent without review. Turn it off in Workflow Station to require approval again.</p>' : ''}`,
    )
  }

  return {
    summary: drafted.length === 0
      ? 'No eligible at-risk customers this week.'
      : autoApprove
        ? `Auto-sent ${drafted.length} win-back email(s).`
        : `Drafted ${drafted.length} win-back email(s).`,
  }
}

// ── weekly_promotion_scan ────────────────────────────────────────────────
// Only drafts something if the data actually supports it (a real
// promo_opportunity from Marketing Strategy, or a notable retention
// at-risk count) — same conditional-honesty pattern as weeklySocialCampaign's
// fallback. No opportunity this week means no draft, not a forced one.
async function weeklyPromotionScan(workflowId: string): Promise<WorkflowResult> {
  if (!OPENAI_API_KEY) throw new Error('OPENAI_API_KEY not configured')
  const autoApprove = await isAutoApproved(workflowId)

  const [{ data: strategyRun }, { data: retentionRun }, { data: existingPromos }] = await Promise.all([
    serviceClient.from('ai_agent_runs').select('output').eq('agent_name', 'marketing_strategy').eq('status', 'completed').order('created_at', { ascending: false }).limit(1).maybeSingle(),
    serviceClient.from('ai_agent_runs').select('output').eq('agent_name', 'customer_retention').eq('status', 'completed').order('created_at', { ascending: false }).limit(1).maybeSingle(),
    serviceClient.from('promo_codes').select('code').eq('is_active', true),
  ])
  const strategyMetrics = (strategyRun?.output as Record<string, unknown> | null)?.metrics as Record<string, unknown> | undefined
  const retentionMetrics = (retentionRun?.output as Record<string, unknown> | null)?.metrics as Record<string, unknown> | undefined
  const promoOpportunities = (strategyMetrics?.promo_opportunities as { restaurant_id: string; restaurant: string; at_risk_score: number }[] | undefined) ?? []
  const retentionAtRiskCount = (retentionMetrics?.at_risk_count as number | undefined) ?? 0
  const existingCodes = new Set((existingPromos ?? []).map((p) => (p.code as string).toUpperCase()))

  const topOpportunity = promoOpportunities[0]
  if (!topOpportunity && retentionAtRiskCount < 10) {
    return { summary: 'No strong promotion opportunity this week — skipped.' }
  }
  const targetRestaurant = topOpportunity ? { id: topOpportunity.restaurant_id, name: topOpportunity.restaurant } : null

  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: `You are the 7Dash Promotion Agent. Propose ONE new promo code, grounded only in the real context given: promo_opportunities (from the Marketing Strategy agent — at-risk restaurants without an active promo) and retention_at_risk_count (from the Customer Retention agent). If a target_restaurant is given, scope the promo to that restaurant specifically and explain why in the rationale. If not, propose a modest platform-wide promo justified by retention_at_risk_count.
Rules:
- discount_type must be "percentage" (1-30) or "fixed" (1-15, in dollars). Keep discounts modest — this is a small delivery marketplace, not a discount house.
- max_uses: a sensible bounded number (10-200), never unlimited.
- expires_in_days: 7-30.
- code: 6-10 uppercase letters/numbers, no spaces, on-brand (7DASH-flavored is fine but not required).
- rationale: 1-2 sentences citing the actual data point that justifies this, not a generic marketing pitch.
Respond ONLY with JSON: { "code": string, "description": string, "discount_type": "percentage"|"fixed", "discount_value": number, "max_uses": number, "expires_in_days": number, "rationale": string }`,
        },
        { role: 'user', content: JSON.stringify({ target_restaurant: targetRestaurant, promo_opportunities: promoOpportunities, retention_at_risk_count: retentionAtRiskCount, existing_active_promo_count: existingCodes.size }) },
      ],
      response_format: { type: 'json_object' },
      temperature: 0.5,
    }),
  })
  if (!res.ok) throw new Error(`Promotion drafting failed: ${await res.text()}`)
  const completion = await res.json()
  const parsed = JSON.parse(completion.choices?.[0]?.message?.content ?? '{}')

  const PROMO_CODE_RE = /^[A-Z0-9]{4,20}$/
  let code = String(parsed.code ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 20)
  if (!PROMO_CODE_RE.test(code) || existingCodes.has(code)) {
    code = `PROMO${Math.random().toString(36).slice(2, 7).toUpperCase()}`
  }
  const discountType = parsed.discount_type === 'fixed' ? 'fixed' : 'percentage'
  const discountValue = discountType === 'percentage'
    ? Math.min(30, Math.max(1, Number(parsed.discount_value) || 10))
    : Math.min(15, Math.max(1, Number(parsed.discount_value) || 5))
  const maxUses = Math.min(200, Math.max(10, Math.round(Number(parsed.max_uses) || 50)))
  const expiresInDays = Math.min(30, Math.max(7, Math.round(Number(parsed.expires_in_days) || 14)))
  const description = String(parsed.description ?? '').slice(0, 300)
  const rationale = String(parsed.rationale ?? '').slice(0, 500)

  const proposal = {
    code, description, discount_type: discountType, discount_value: discountValue,
    max_uses: maxUses, expires_in_days: expiresInDays, restaurant_id: targetRestaurant?.id ?? null,
    restaurant_name: targetRestaurant?.name ?? null, rationale,
  }

  let created: Record<string, unknown> | null = null
  let notified = 0
  if (autoApprove) {
    const expiresAt = new Date(Date.now() + expiresInDays * 86400000).toISOString()
    const { data: insertedPromo, error: insertErr } = await serviceClient
      .from('promo_codes')
      .insert({
        code, description: description || null, discount_type: discountType, discount_value: discountValue,
        max_uses: maxUses, usage_count: 0, expires_at: expiresAt, restaurant_id: targetRestaurant?.id ?? null, is_active: true,
      })
      .select()
      .single()
    if (insertErr) throw new Error(`Auto-create promo failed: ${insertErr.message}`)
    created = insertedPromo
    notified = (await notifyCustomersOfPromo(insertedPromo as { code: string; description: string | null; discount_type: string; discount_value: number; restaurant_id: string | null })).notified
  }

  await serviceClient.from('ai_agent_runs').insert({
    agent_name: 'promotion_agent',
    entity_type: created ? 'promo_code' : 'promo_proposal',
    entity_id: created ? (created.id as string) : crypto.randomUUID(),
    related_entities: targetRestaurant ? [{ type: 'restaurant', id: targetRestaurant.id }] : [],
    input: {
      promo_opportunities: promoOpportunities, retention_at_risk_count: retentionAtRiskCount, source: 'weekly_promotion_scan',
      ...(autoApprove ? { decision: 'approve', auto_approved: true } : {}),
    },
    output: created ? { ...proposal, promo_code: created, customers_notified: notified } : proposal,
    model: 'gpt-4o-mini',
    status: 'completed',
  })

  await notifyAdminsOfNewDrafts(
    autoApprove ? `Weekly Promotion Scan — promo "${code}" created automatically` : `Weekly Promotion Scan — new proposal ready for review`,
    `<h2>Weekly Promotion Scan — ${autoApprove ? 'Created Automatically' : 'Draft Ready'}</h2>
     <p><b>Code:</b> ${escapeHtml(code)}<br/>
     <b>Discount:</b> ${discountType === 'percentage' ? `${discountValue}% off` : `$${discountValue} off`}<br/>
     ${targetRestaurant ? `<b>Restaurant:</b> ${escapeHtml(targetRestaurant.name)}<br/>` : '<b>Scope:</b> Platform-wide<br/>'}
     <b>Why:</b> ${escapeHtml(rationale)}</p>
     ${autoApprove ? `<p style="color:#999;font-size:12px;">Auto-approve is ON for this workflow — this promo is already live and ${notified} customer${notified === 1 ? '' : 's'} were notified in-app. Turn it off in Workflow Station to require approval again.</p>` : ''}`,
  )

  return {
    summary: autoApprove
      ? `Auto-created promo "${code}" (${targetRestaurant ? `for ${targetRestaurant.name}` : 'platform-wide'}), notified ${notified} customers.`
      : `Drafted promo "${code}" (${targetRestaurant ? `for ${targetRestaurant.name}` : 'platform-wide'}).`,
  }
}

// ── daily_birthday_wishes ────────────────────────────────────────────────
// No AI drafting — a fixed, personalized template, so this sends
// automatically every morning (auto_approve = true on this workflow's row,
// set in the migration) rather than going through the draft/review path the
// other workflows use. Reward = a freshly minted single-use promo_codes row
// (same mold as createRetentionPromoCode), not a parallel redemption engine
// — checkout already knows how to apply any promo code. birthday_rewards is
// only a log for idempotency + admin reporting; redemption truth always
// lives on the linked promo_codes row.
async function getConfigValue(key: string, fallback: string): Promise<string> {
  const { data } = await serviceClient.from('app_config').select('value').eq('key', key).maybeSingle()
  return (data?.value as string | undefined) ?? fallback
}

/** Mints a one-time, fixed-amount birthday discount code, valid through the
 *  end of today in Cayman time (fixed UTC-5, no DST — matches
 *  lib/utils/est_datetime.dart). Returns the new promo_codes row's id too,
 *  so the caller can link it from birthday_rewards. */
async function createBirthdayPromoCode(
  discountAmount: number,
  minOrderAmount: number,
): Promise<{ id: string; code: string } | null> {
  let code = ''
  for (let attempt = 0; attempt < 5; attempt++) {
    const candidate = `BDAY${Math.random().toString(36).slice(2, 7).toUpperCase()}`
    const { data: existing } = await serviceClient.from('promo_codes').select('id').eq('code', candidate).maybeSingle()
    if (!existing) { code = candidate; break }
  }
  if (!code) return null

  const nowCayman = new Date(Date.now() - 5 * 3600000)
  const endOfDayCaymanAsUtcInstant = new Date(
    Date.UTC(nowCayman.getUTCFullYear(), nowCayman.getUTCMonth(), nowCayman.getUTCDate(), 23, 59, 59) + 5 * 3600000,
  )

  const { data: inserted, error: insertErr } = await serviceClient
    .from('promo_codes')
    .insert({
      code,
      description: 'Happy Birthday reward — 7Dash',
      discount_type: 'fixed',
      discount_value: discountAmount,
      min_order_amount: minOrderAmount,
      max_uses: 1,
      usage_count: 0,
      expires_at: endOfDayCaymanAsUtcInstant.toISOString(),
      restaurant_id: null,
      is_active: true,
    })
    .select('id')
    .single()
  if (insertErr || !inserted) {
    console.error('daily_birthday_wishes: failed to create promo code', insertErr?.message)
    return null
  }
  return { id: inserted.id as string, code }
}

async function dailyBirthdayWishes(_workflowId: string): Promise<WorkflowResult> {
  const enabled = (await getConfigValue('birthday_campaign_enabled', 'true')) === 'true'
  if (!enabled) return { summary: 'Birthday campaign is disabled in app_config — skipped.' }

  const discountAmount = Number(await getConfigValue('birthday_discount_amount', '500')) || 500
  const minOrderAmount = Number(await getConfigValue('birthday_min_order_amount', '2000')) || 2000
  const titleTemplate = await getConfigValue('birthday_notification_title', '🎂 Happy Birthday!')
  const bodyTemplate = await getConfigValue(
    'birthday_notification_body',
    "Happy Birthday, {first_name}! 🎉 We've got a special reward waiting for you.",
  )

  // "Today" in Cayman time — fixed UTC-5 offset, no DST.
  const nowCayman = new Date(Date.now() - 5 * 3600000)
  const month = nowCayman.getUTCMonth() + 1
  const day = nowCayman.getUTCDate()
  const birthdayDate = nowCayman.toISOString().slice(0, 10)

  const { data: users, error: usersErr } = await serviceClient
    .from('users')
    .select('id, name, birthday')
    .eq('is_active', true)
    .not('birthday', 'is', null)
  if (usersErr) throw new Error(`Failed to query users: ${usersErr.message}`)

  // Month/day match done in JS rather than a SQL EXTRACT filter because the
  // Supabase JS client has no clean way to express that predicate — the
  // users table is small enough platform-wide that this is fine; a raw SQL
  // function would be the next step if it ever isn't.
  const todaysBirthdays = (users ?? []).filter((u) => {
    if (!u.birthday) return false
    const parts = String(u.birthday).split('-').map(Number)
    return parts[1] === month && parts[2] === day
  })

  let wished = 0
  let alreadyProcessed = 0
  let failed = 0

  for (const user of todaysBirthdays) {
    // Idempotency gate: UNIQUE(user_id, birthday_date) — if a row already
    // exists (this ran earlier today, or twice), this insert no-ops and we
    // skip. Running the workflow twice in one day never double-rewards.
    const { data: logRow } = await serviceClient
      .from('birthday_rewards')
      .insert({ user_id: user.id, birthday_date: birthdayDate })
      .select('id')
      .maybeSingle()
    if (!logRow) { alreadyProcessed++; continue }

    const promo = await createBirthdayPromoCode(discountAmount, minOrderAmount)
    if (!promo) { failed++; continue }

    await serviceClient.from('birthday_rewards').update({ promo_code_id: promo.id }).eq('id', logRow.id)

    const firstName = (user.name ?? 'there').split(' ')[0]
    const body = bodyTemplate.replaceAll('{first_name}', firstName)
    const sent = await sendPushToCustomer(user.id, titleTemplate, body, {
      type: 'birthday',
      promo_code: promo.code,
      discount_amount: String(discountAmount),
    })
    if (sent) {
      await serviceClient
        .from('birthday_rewards')
        .update({ notification_sent: true, notification_sent_at: new Date().toISOString() })
        .eq('id', logRow.id)
    }
    wished++
  }

  return {
    summary:
      todaysBirthdays.length === 0
        ? 'No birthdays today.'
        : `Wished ${wished} customer(s) happy birthday.` +
          (alreadyProcessed > 0 ? ` ${alreadyProcessed} already processed earlier today.` : '') +
          (failed > 0 ? ` ${failed} failed to get a promo code.` : ''),
  }
}

const WORKFLOWS: Record<string, (workflowId: string) => Promise<WorkflowResult>> = {
  weekly_social_campaign: weeklySocialCampaign,
  weekly_retention_outreach: weeklyRetentionOutreach,
  weekly_promotion_scan: weeklyPromotionScan,
  daily_birthday_wishes: dailyBirthdayWishes,
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    await requireRunnerAuth(req)
    const { workflow_slug, publish_content_id, caption_index } = await req.json()

    if (publish_content_id) {
      const results = await publishMarketingContent(publish_content_id, Number(caption_index) || 0)
      return json({ success: true, results, any_success: Object.values(results).some((r) => r.ok) })
    }

    const { data: workflow, error: wfErr } = await serviceClient
      .from('automation_workflows')
      .select('id, is_active')
      .eq('slug', workflow_slug)
      .single()
    if (wfErr || !workflow) return json({ error: 'Unknown workflow' }, 404)
    if (!workflow.is_active) return json({ error: 'Workflow is paused' }, 403)

    const runner = WORKFLOWS[workflow_slug]
    if (!runner) return json({ error: `No handler registered for '${workflow_slug}'` }, 400)

    try {
      const result = await runner(workflow.id)
      await serviceClient
        .from('automation_workflows')
        .update({ last_run_at: new Date().toISOString(), last_run_status: 'success', last_run_summary: result.summary })
        .eq('id', workflow.id)
      return json({ success: true, ...result })
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e)
      await serviceClient
        .from('automation_workflows')
        .update({ last_run_at: new Date().toISOString(), last_run_status: 'failed', last_run_summary: message })
        .eq('id', workflow.id)
      return json({ error: 'Workflow run failed', details: message }, 500)
    }
  } catch (e) {
    return errorResponse(e)
  }
})
