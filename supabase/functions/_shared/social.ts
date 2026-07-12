// _shared/social.ts — publish a caption + image to real social platforms.
//
// Every function here is safe to call unconditionally: if a platform's
// credentials aren't configured, it returns { ok: false, error: 'not
// configured' } immediately rather than throwing, exactly like sendEmail()
// behaves when RESEND_API_KEY is missing. That means weekly_social_campaign
// can call all four in parallel and just skip whichever aren't set up yet.
//
// Required secrets per platform (npx supabase secrets set ...):
//   Facebook   — META_PAGE_ACCESS_TOKEN, META_PAGE_ID
//   Instagram  — META_PAGE_ACCESS_TOKEN (or META_IG_ACCESS_TOKEN), META_IG_USER_ID
//   X/Twitter  — TWITTER_API_KEY, TWITTER_API_SECRET, TWITTER_ACCESS_TOKEN, TWITTER_ACCESS_SECRET
//   TikTok     — TIKTOK_ACCESS_TOKEN
//
// TikTok caveat: the Content Posting API only does true "direct post" (goes
// straight to the public feed) for apps TikTok has audited for that scope.
// An unaudited app's posts land in the creator's TikTok inbox as a draft for
// them to manually confirm in-app — that's a TikTok platform restriction,
// not something fixable from here.

// @ts-ignore: Deno ESM import
import OAuth from 'https://esm.sh/oauth-1.0a@2.2.6'
// @ts-ignore: Deno ESM import
import CryptoJS from 'https://esm.sh/crypto-js@4.2.0'

declare const Deno: { env: { get(key: string): string | undefined } }

export interface PublishResult {
  ok: boolean
  url?: string
  error?: string
}

const META_PAGE_ACCESS_TOKEN = Deno.env.get('META_PAGE_ACCESS_TOKEN') ?? ''
const META_PAGE_ID = Deno.env.get('META_PAGE_ID') ?? ''
const META_IG_ACCESS_TOKEN = Deno.env.get('META_IG_ACCESS_TOKEN') ?? META_PAGE_ACCESS_TOKEN
const META_IG_USER_ID = Deno.env.get('META_IG_USER_ID') ?? ''
const TWITTER_API_KEY = Deno.env.get('TWITTER_API_KEY') ?? ''
const TWITTER_API_SECRET = Deno.env.get('TWITTER_API_SECRET') ?? ''
const TWITTER_ACCESS_TOKEN = Deno.env.get('TWITTER_ACCESS_TOKEN') ?? ''
const TWITTER_ACCESS_SECRET = Deno.env.get('TWITTER_ACCESS_SECRET') ?? ''
const TIKTOK_ACCESS_TOKEN = Deno.env.get('TIKTOK_ACCESS_TOKEN') ?? ''

// ── Facebook Page ───────────────────────────────────────────────────────────
export async function publishToFacebook(caption: string, imageUrl: string | null): Promise<PublishResult> {
  if (!META_PAGE_ACCESS_TOKEN || !META_PAGE_ID) return { ok: false, error: 'not configured' }
  try {
    const endpoint = imageUrl
      ? `https://graph.facebook.com/v19.0/${META_PAGE_ID}/photos`
      : `https://graph.facebook.com/v19.0/${META_PAGE_ID}/feed`
    const params = new URLSearchParams({
      access_token: META_PAGE_ACCESS_TOKEN,
      ...(imageUrl ? { url: imageUrl, caption } : { message: caption }),
    })
    const res = await fetch(endpoint, { method: 'POST', body: params })
    const data = await res.json()
    if (!res.ok) return { ok: false, error: JSON.stringify(data.error ?? data) }
    const postId = data.post_id ?? data.id
    return { ok: true, url: postId ? `https://www.facebook.com/${postId}` : undefined }
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) }
  }
}

// ── Instagram Business/Creator account (via Graph API) ──────────────────────
export async function publishToInstagram(caption: string, imageUrl: string | null): Promise<PublishResult> {
  if (!META_IG_ACCESS_TOKEN || !META_IG_USER_ID || !imageUrl) return { ok: false, error: !imageUrl ? 'Instagram requires an image' : 'not configured' }
  try {
    const createRes = await fetch(`https://graph.facebook.com/v19.0/${META_IG_USER_ID}/media`, {
      method: 'POST',
      body: new URLSearchParams({ image_url: imageUrl, caption, access_token: META_IG_ACCESS_TOKEN }),
    })
    const createData = await createRes.json()
    if (!createRes.ok || !createData.id) return { ok: false, error: JSON.stringify(createData.error ?? createData) }

    const publishRes = await fetch(`https://graph.facebook.com/v19.0/${META_IG_USER_ID}/media_publish`, {
      method: 'POST',
      body: new URLSearchParams({ creation_id: createData.id, access_token: META_IG_ACCESS_TOKEN }),
    })
    const publishData = await publishRes.json()
    if (!publishRes.ok) return { ok: false, error: JSON.stringify(publishData.error ?? publishData) }
    return { ok: true, url: publishData.id ? `https://www.instagram.com/p/${publishData.id}/` : undefined }
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) }
  }
}

// ── X (Twitter) — OAuth 1.0a user-context posting ───────────────────────────
function twitterOAuth() {
  return new OAuth({
    consumer: { key: TWITTER_API_KEY, secret: TWITTER_API_SECRET },
    signature_method: 'HMAC-SHA1',
    hash_function(baseString: string, key: string) {
      return CryptoJS.HmacSHA1(baseString, key).toString(CryptoJS.enc.Base64)
    },
  })
}

async function twitterAuthHeader(url: string, method: string, data?: Record<string, string>): Promise<string> {
  const oauth = twitterOAuth()
  const token = { key: TWITTER_ACCESS_TOKEN, secret: TWITTER_ACCESS_SECRET }
  const authorized = oauth.authorize({ url, method, data }, token)
  return oauth.toHeader(authorized).Authorization
}

async function uploadTwitterMedia(imageUrl: string): Promise<string | null> {
  const imgRes = await fetch(imageUrl)
  if (!imgRes.ok) return null
  const bytes = new Uint8Array(await imgRes.arrayBuffer())
  let binary = ''
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
  const mediaData = btoa(binary)

  const uploadUrl = 'https://upload.twitter.com/1.1/media/upload.json'
  const data = { media_data: mediaData }
  const authHeader = await twitterAuthHeader(uploadUrl, 'POST', data)
  const res = await fetch(uploadUrl, {
    method: 'POST',
    headers: { Authorization: authHeader, 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(data),
  })
  const json = await res.json()
  if (!res.ok) return null
  return json.media_id_string ?? null
}

export async function publishToTwitter(caption: string, imageUrl: string | null): Promise<PublishResult> {
  if (!TWITTER_API_KEY || !TWITTER_API_SECRET || !TWITTER_ACCESS_TOKEN || !TWITTER_ACCESS_SECRET) return { ok: false, error: 'not configured' }
  try {
    let mediaId: string | null = null
    if (imageUrl) mediaId = await uploadTwitterMedia(imageUrl)

    const tweetUrl = 'https://api.twitter.com/2/tweets'
    // Media upload/id is NOT part of the OAuth1.0a signature base for a JSON
    // body — only the oauth_* params are (there's no query string or
    // form-encoded body here), so authHeader is computed with no extra data.
    const authHeader = await twitterAuthHeader(tweetUrl, 'POST')
    const res = await fetch(tweetUrl, {
      method: 'POST',
      headers: { Authorization: authHeader, 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: caption, ...(mediaId ? { media: { media_ids: [mediaId] } } : {}) }),
    })
    const json = await res.json()
    if (!res.ok) return { ok: false, error: JSON.stringify(json.errors ?? json) }
    const id = json.data?.id
    return { ok: true, url: id ? `https://x.com/i/web/status/${id}` : undefined }
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) }
  }
}

// ── TikTok — Content Posting API (photo post, pull-from-URL) ────────────────
export async function publishToTikTok(caption: string, imageUrl: string | null): Promise<PublishResult> {
  if (!TIKTOK_ACCESS_TOKEN || !imageUrl) return { ok: false, error: !imageUrl ? 'TikTok requires an image' : 'not configured' }
  try {
    const res = await fetch('https://open.tiktokapis.com/v2/post/publish/content/init/', {
      method: 'POST',
      headers: { Authorization: `Bearer ${TIKTOK_ACCESS_TOKEN}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        post_info: { title: caption, privacy_level: 'PUBLIC_TO_EVERYONE', disable_comment: false },
        source_info: { source: 'PULL_FROM_URL', photo_cover_index: 0, photo_images: [imageUrl] },
        post_mode: 'DIRECT_POST',
        media_type: 'PHOTO',
      }),
    })
    const json = await res.json()
    if (!res.ok || json.error?.code !== 'ok') return { ok: false, error: JSON.stringify(json.error ?? json) }
    return { ok: true, url: json.data?.publish_id ? `tiktok:publish_id:${json.data.publish_id}` : undefined }
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) }
  }
}

export async function publishToAllPlatforms(caption: string, imageUrl: string | null): Promise<Record<string, PublishResult>> {
  const [facebook, instagram, twitter, tiktok] = await Promise.all([
    publishToFacebook(caption, imageUrl),
    publishToInstagram(caption, imageUrl),
    publishToTwitter(caption, imageUrl),
    publishToTikTok(caption, imageUrl),
  ])
  return { facebook, instagram, twitter, tiktok }
}
