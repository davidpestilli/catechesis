interface GatewayEnv {
  ALLOWED_ORIGINS: string
  SUPABASE_STORAGE_BUCKET: string
  VITE_SUPABASE_URL: string
  VITE_SUPABASE_ANON_KEY: string
  VITE_SUPABASE_SERVICE_ROLE_KEY: string
  ADMIN_NOTIFICATION_EMAIL?: string
}

type CommentContentType = 'article' | 'encounter'
type CommentAuthorKind = 'guest' | 'admin'
type CommentSubscriptionSource = 'opt_in' | 'admin_auto'

interface AuthUser {
  id: string
  email?: string
}

interface CommentRow {
  id: string
  content_type: CommentContentType
  content_id: string
  parent_comment_id: string | null
  root_comment_id: string
  author_kind: CommentAuthorKind
  admin_user_id: string | null
  author_name: string
  author_email: string | null
  body: string
  notify_replies: boolean
  created_at: string
  updated_at: string
}

interface CommentSubscriptionRow {
  id: string
  root_comment_id: string
  email: string
  subscriber_name: string
  source: CommentSubscriptionSource
  unsubscribe_token: string
  unsubscribed_at: string | null
}

interface CommentEventInsert {
  comment_id?: string | null
  root_comment_id?: string | null
  event_type:
    | 'comment_created'
    | 'subscription_created'
    | 'email_queued'
    | 'email_sent'
    | 'email_failed'
    | 'email_deferred'
    | 'unsubscribe'
  recipient_email?: string | null
  payload?: Record<string, unknown>
}

interface CommentRequestBody {
  contentType?: string
  contentId?: string
  parentCommentId?: string
  authorName?: string
  authorEmail?: string
  body?: string
  notifyReplies?: boolean
}

function corsHeaders(origin: string | null, env: GatewayEnv) {
  const allowedOrigins = env.ALLOWED_ORIGINS.split(',').map((item) => item.trim())
  const allowOrigin = origin && allowedOrigins.includes(origin) ? origin : allowedOrigins[0] ?? '*'

  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
  }
}

function json(data: unknown, status: number, headers: Record<string, string>) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...headers,
    },
  })
}

function html(markup: string, status: number, headers: Record<string, string>) {
  return new Response(markup, {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      ...headers,
    },
  })
}

function escapeHtml(value: string) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
}

function isValidEmail(value: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)
}

function isUuid(value?: string | null): value is string {
  return typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
}

async function parseJson<T>(request: Request) {
  try {
    return (await request.json()) as T
  } catch {
    return null
  }
}

async function supabaseRest<T>(
  env: GatewayEnv,
  path: string,
  init: RequestInit = {},
  options: { serviceRole?: boolean } = {},
) {
  const headers = new Headers(init.headers)
  const useServiceRole = options.serviceRole ?? true
  const key = useServiceRole ? env.VITE_SUPABASE_SERVICE_ROLE_KEY : env.VITE_SUPABASE_ANON_KEY

  headers.set('apikey', key)
  headers.set('Authorization', `Bearer ${key}`)

  if (init.body && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json')
  }

  const response = await fetch(`${env.VITE_SUPABASE_URL}/rest/v1${path}`, {
    ...init,
    headers,
  })

  let data: T | null = null
  const text = await response.text()

  if (text) {
    data = JSON.parse(text) as T
  }

  return { response, data }
}

async function getAuthenticatedUser(request: Request, env: GatewayEnv): Promise<AuthUser | null> {
  const authorization = request.headers.get('Authorization')

  if (!authorization?.startsWith('Bearer ')) {
    return null
  }

  const response = await fetch(`${env.VITE_SUPABASE_URL}/auth/v1/user`, {
    headers: {
      apikey: env.VITE_SUPABASE_ANON_KEY,
      Authorization: authorization,
    },
  })

  if (!response.ok) {
    return null
  }

  const payload = (await response.json()) as { id: string; email?: string }
  return {
    id: payload.id,
    email: payload.email,
  }
}

async function ensureContentExists(env: GatewayEnv, contentType: CommentContentType, contentId: string) {
  const table = contentType === 'article' ? 'articles' : 'encounters'
  const { response, data } = await supabaseRest<{ id: string }[]>(
    env,
    `/${table}?select=id&id=eq.${contentId}&limit=1`,
    { method: 'GET' },
  )

  return response.ok && Array.isArray(data) && data.length > 0
}

async function getCommentById(env: GatewayEnv, commentId: string) {
  const { response, data } = await supabaseRest<CommentRow[]>(
    env,
    `/comments?select=*&id=eq.${commentId}&limit=1`,
    { method: 'GET' },
  )

  if (!response.ok || !Array.isArray(data) || data.length === 0) {
    return null
  }

  return data[0]
}

async function insertComment(env: GatewayEnv, payload: Record<string, unknown>) {
  const { response, data } = await supabaseRest<CommentRow[]>(
    env,
    '/comments',
    {
      method: 'POST',
      headers: {
        Prefer: 'return=representation',
      },
      body: JSON.stringify(payload),
    },
  )

  if (!response.ok || !Array.isArray(data) || data.length === 0) {
    throw new Error('Nao foi possivel salvar o comentario.')
  }

  return data[0]
}

async function ensureSubscription(
  env: GatewayEnv,
  input: {
    rootCommentId: string
    email: string
    subscriberName: string
    source: CommentSubscriptionSource
  },
) {
  const normalizedEmail = input.email.trim().toLowerCase()
  const { response, data } = await supabaseRest<CommentSubscriptionRow[]>(
    env,
    `/comment_subscriptions?select=*&root_comment_id=eq.${input.rootCommentId}&email=eq.${normalizedEmail}&limit=1`,
    { method: 'GET' },
  )

  if (!response.ok) {
    throw new Error('Nao foi possivel consultar as inscricoes da thread.')
  }

  if (Array.isArray(data) && data.length > 0) {
    const existing = data[0]

    if (!existing.unsubscribed_at && existing.subscriber_name === input.subscriberName && existing.source === input.source) {
      return { subscription: existing, created: false }
    }

    const { response: updateResponse, data: updateData } = await supabaseRest<CommentSubscriptionRow[]>(
      env,
      `/comment_subscriptions?id=eq.${existing.id}`,
      {
        method: 'PATCH',
        headers: {
          Prefer: 'return=representation',
        },
        body: JSON.stringify({
          subscriber_name: input.subscriberName,
          source: input.source,
          unsubscribed_at: null,
        }),
      },
    )

    if (!updateResponse.ok || !Array.isArray(updateData) || updateData.length === 0) {
      throw new Error('Nao foi possivel atualizar a inscricao da thread.')
    }

    return { subscription: updateData[0], created: true }
  }

  const { response: insertResponse, data: insertData } = await supabaseRest<CommentSubscriptionRow[]>(
    env,
    '/comment_subscriptions',
    {
      method: 'POST',
      headers: {
        Prefer: 'return=representation',
      },
      body: JSON.stringify({
        root_comment_id: input.rootCommentId,
        email: normalizedEmail,
        subscriber_name: input.subscriberName,
        source: input.source,
      }),
    },
  )

  if (!insertResponse.ok || !Array.isArray(insertData) || insertData.length === 0) {
    throw new Error('Nao foi possivel criar a inscricao da thread.')
  }

  return { subscription: insertData[0], created: true }
}

async function listActiveSubscriptions(env: GatewayEnv, rootCommentId: string) {
  const { response, data } = await supabaseRest<CommentSubscriptionRow[]>(
    env,
    `/comment_subscriptions?select=*&root_comment_id=eq.${rootCommentId}&unsubscribed_at=is.null`,
    { method: 'GET' },
  )

  if (!response.ok) {
    throw new Error('Nao foi possivel carregar as inscricoes da thread.')
  }

  return Array.isArray(data) ? data : []
}

async function insertEvents(env: GatewayEnv, events: CommentEventInsert[]) {
  if (events.length === 0) return

  await supabaseRest(
    env,
    '/comment_events',
    {
      method: 'POST',
      body: JSON.stringify(
        events.map((event) => ({
          comment_id: event.comment_id ?? null,
          root_comment_id: event.root_comment_id ?? null,
          event_type: event.event_type,
          recipient_email: event.recipient_email ?? null,
          payload: event.payload ?? {},
        })),
      ),
    },
  )
}

async function notifyThreadParticipants(env: GatewayEnv, comment: CommentRow) {
  const rootCommentId = comment.root_comment_id
  const adminEmail = env.ADMIN_NOTIFICATION_EMAIL?.trim().toLowerCase()
  const events: CommentEventInsert[] = []

  if (adminEmail) {
    const adminSubscription = await ensureSubscription(env, {
      rootCommentId,
      email: adminEmail,
      subscriberName: 'Notificacoes administrativas',
      source: 'admin_auto',
    })

    if (adminSubscription.created) {
      events.push({
        comment_id: comment.id,
        root_comment_id: rootCommentId,
        event_type: 'subscription_created',
        recipient_email: adminEmail,
        payload: {
          source: 'admin_auto',
        },
      })
    }
  }

  const subscriptions = await listActiveSubscriptions(env, rootCommentId)
  const recipients = new Map<string, CommentSubscriptionRow>()

  for (const subscription of subscriptions) {
    recipients.set(subscription.email.trim().toLowerCase(), subscription)
  }

  const authorEmail = comment.author_email?.trim().toLowerCase() ?? null

  if (authorEmail) {
    recipients.delete(authorEmail)
  }

  if (comment.author_kind === 'admin') {
    for (const [email, subscription] of recipients.entries()) {
      if (subscription.source === 'admin_auto') {
        recipients.delete(email)
      }
    }
  }

  for (const subscription of recipients.values()) {
    events.push({
      comment_id: comment.id,
      root_comment_id: rootCommentId,
      event_type: 'email_deferred',
      recipient_email: subscription.email,
      payload: {
        reason: 'zeptomail_not_configured_in_this_project_yet',
        source: subscription.source,
        unsubscribeToken: subscription.unsubscribe_token,
      },
    })
  }

  await insertEvents(env, events)
}

async function handleCreateComment(request: Request, env: GatewayEnv, headers: Record<string, string>) {
  const body = await parseJson<CommentRequestBody>(request)

  if (!body) {
    return json({ error: 'Corpo invalido.' }, 400, headers)
  }

  const contentType = body.contentType === 'article' || body.contentType === 'encounter' ? body.contentType : null
  const contentId = typeof body.contentId === 'string' ? body.contentId.trim() : ''
  const parentCommentId = typeof body.parentCommentId === 'string' ? body.parentCommentId.trim() : ''
  const authorName = typeof body.authorName === 'string' ? body.authorName.trim() : ''
  const authorEmail = typeof body.authorEmail === 'string' ? body.authorEmail.trim().toLowerCase() : ''
  const commentBody = typeof body.body === 'string' ? body.body.trim() : ''
  const notifyReplies = Boolean(body.notifyReplies)
  const authUser = await getAuthenticatedUser(request, env)
  const isAdmin = Boolean(authUser)

  if (!contentType || !isUuid(contentId)) {
    return json({ error: 'Conteudo invalido.' }, 400, headers)
  }

  if (!authorName) {
    return json({ error: 'Informe o nome do autor.' }, 400, headers)
  }

  if (!commentBody) {
    return json({ error: 'Escreva um comentario.' }, 400, headers)
  }

  if (!isAdmin && authorEmail && !isValidEmail(authorEmail)) {
    return json({ error: 'Informe um email valido.' }, 400, headers)
  }

  if (!isAdmin && notifyReplies && !authorEmail) {
    return json({ error: 'Informe um email para acompanhar a conversa.' }, 400, headers)
  }

  const contentExists = await ensureContentExists(env, contentType, contentId)

  if (!contentExists) {
    return json({ error: 'O conteudo informado nao foi encontrado.' }, 404, headers)
  }

  let parentComment: CommentRow | null = null

  if (parentCommentId) {
    if (!isUuid(parentCommentId)) {
      return json({ error: 'Comentario pai invalido.' }, 400, headers)
    }

    parentComment = await getCommentById(env, parentCommentId)

    if (!parentComment) {
      return json({ error: 'Comentario pai nao encontrado.' }, 404, headers)
    }

    if (parentComment.parent_comment_id) {
      return json({ error: 'Nao e permitido responder uma resposta.' }, 400, headers)
    }

    if (parentComment.content_type !== contentType || parentComment.content_id !== contentId) {
      return json({ error: 'A resposta nao pertence a este conteudo.' }, 400, headers)
    }
  }

  const commentId = crypto.randomUUID()
  const rootCommentId = parentComment?.root_comment_id ?? commentId

  try {
    const comment = await insertComment(env, {
      id: commentId,
      content_type: contentType,
      content_id: contentId,
      parent_comment_id: parentComment?.id ?? null,
      root_comment_id: rootCommentId,
      author_kind: isAdmin ? 'admin' : 'guest',
      admin_user_id: authUser?.id ?? null,
      author_name: authorName,
      author_email: isAdmin ? null : authorEmail || null,
      body: commentBody,
      notify_replies: isAdmin ? false : notifyReplies,
    })

    const events: CommentEventInsert[] = [
      {
        comment_id: comment.id,
        root_comment_id: comment.root_comment_id,
        event_type: 'comment_created',
        payload: {
          authorKind: comment.author_kind,
          notifyReplies: comment.notify_replies,
        },
      },
    ]

    if (!isAdmin && notifyReplies && authorEmail) {
      const subscription = await ensureSubscription(env, {
        rootCommentId,
        email: authorEmail,
        subscriberName: authorName,
        source: 'opt_in',
      })

      if (subscription.created) {
        events.push({
          comment_id: comment.id,
          root_comment_id: rootCommentId,
          event_type: 'subscription_created',
          recipient_email: authorEmail,
          payload: {
            source: 'opt_in',
          },
        })
      }
    }

    await insertEvents(env, events)
    await notifyThreadParticipants(env, comment)

    return json({ ok: true, comment }, 201, headers)
  } catch (error) {
    return json(
      {
        error: error instanceof Error ? error.message : 'Nao foi possivel publicar o comentario.',
      },
      400,
      headers,
    )
  }
}

async function handleUnsubscribe(request: Request, env: GatewayEnv, headers: Record<string, string>) {
  const url = new URL(request.url)
  const token = url.searchParams.get('token')?.trim() ?? ''

  if (!isUuid(token)) {
    return html(
      `<main style="font-family:system-ui;padding:32px;max-width:640px;margin:0 auto;"><h1>Link invalido</h1><p>O token de descadastro informado nao e valido.</p></main>`,
      400,
      headers,
    )
  }

  const { response, data } = await supabaseRest<CommentSubscriptionRow[]>(
    env,
    `/comment_subscriptions?select=*&unsubscribe_token=eq.${token}&limit=1`,
    { method: 'GET' },
  )

  if (!response.ok || !Array.isArray(data) || data.length === 0) {
    return html(
      `<main style="font-family:system-ui;padding:32px;max-width:640px;margin:0 auto;"><h1>Inscricao nao encontrada</h1><p>Este link nao corresponde a uma assinatura ativa.</p></main>`,
      404,
      headers,
    )
  }

  const subscription = data[0]

  if (!subscription.unsubscribed_at) {
    await supabaseRest(
      env,
      `/comment_subscriptions?id=eq.${subscription.id}`,
      {
        method: 'PATCH',
        body: JSON.stringify({
          unsubscribed_at: new Date().toISOString(),
        }),
      },
    )

    await insertEvents(env, [
      {
        root_comment_id: subscription.root_comment_id,
        event_type: 'unsubscribe',
        recipient_email: subscription.email,
        payload: {
          source: subscription.source,
        },
      },
    ])
  }

  return html(
    `<main style="font-family:system-ui;padding:32px;max-width:640px;margin:0 auto;"><h1>Descadastro concluido</h1><p>O endereco <strong>${escapeHtml(subscription.email)}</strong> nao recebera mais notificacoes desta conversa.</p></main>`,
    200,
    headers,
  )
}

export default {
  async fetch(request, env): Promise<Response> {
    const runtimeEnv = env as GatewayEnv
    const url = new URL(request.url)
    const headers = corsHeaders(request.headers.get('Origin'), runtimeEnv)

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers })
    }

    if (url.pathname === '/health') {
      return json({ ok: true, service: 'catechesis-gateway' }, 200, headers)
    }

    if (url.pathname === '/config') {
      return json(
        {
          ok: true,
          site: 'Catequético',
          storageBucket: runtimeEnv.SUPABASE_STORAGE_BUCKET,
          note: 'A service_role permanece no Worker. A anon key nao e devolvida por este endpoint.',
        },
        200,
        headers,
      )
    }

    if (url.pathname === '/comments' && request.method === 'POST') {
      return handleCreateComment(request, runtimeEnv, headers)
    }

    if (url.pathname === '/comments/unsubscribe' && request.method === 'GET') {
      return handleUnsubscribe(request, runtimeEnv, headers)
    }

    if (url.pathname === '/media') {
      const path = url.searchParams.get('path')

      if (!path) {
        return json({ error: 'Informe ?path=...' }, 400, headers)
      }

      const mediaUrl = `${runtimeEnv.VITE_SUPABASE_URL}/storage/v1/object/public/${runtimeEnv.SUPABASE_STORAGE_BUCKET}/${path}`
      const response = await fetch(mediaUrl, {
        headers: {
          apikey: runtimeEnv.VITE_SUPABASE_ANON_KEY,
        },
      })

      return new Response(response.body, {
        status: response.status,
        headers: {
          ...headers,
          'Content-Type': response.headers.get('Content-Type') ?? 'application/octet-stream',
          'Cache-Control': 'public, max-age=300',
        },
      })
    }

    if (url.pathname === '/signed-download' && request.method === 'GET') {
      const path = url.searchParams.get('path')
      if (!path) {
        return json({ error: 'Informe ?path=...' }, 400, headers)
      }

      const signedUrlResponse = await fetch(
        `${runtimeEnv.VITE_SUPABASE_URL}/storage/v1/object/sign/${runtimeEnv.SUPABASE_STORAGE_BUCKET}/${path}`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            apikey: runtimeEnv.VITE_SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${runtimeEnv.VITE_SUPABASE_SERVICE_ROLE_KEY}`,
          },
          body: JSON.stringify({ expiresIn: 120 }),
        },
      )

      const payload = (await signedUrlResponse.json()) as { signedURL?: string; error?: string }

      if (!signedUrlResponse.ok || !payload.signedURL) {
        return json({ error: payload.error ?? 'Nao foi possivel assinar o download.' }, 400, headers)
      }

      return json(
        {
          url: `${runtimeEnv.VITE_SUPABASE_URL}/storage/v1${payload.signedURL}`,
        },
        200,
        headers,
      )
    }

    return json({ error: 'Rota nao encontrada.' }, 404, headers)
  },
} satisfies ExportedHandler<GatewayEnv>
