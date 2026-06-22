import {
  buildArticleCategorySubscriptionHtml,
  buildArticleCategorySubscriptionSubject,
  buildArticlePublicationHtml,
  buildArticlePublicationSubject,
  buildCommentNotificationHtml,
  buildCommentNotificationSubject,
  buildThreadSubscriptionHtml,
  buildThreadSubscriptionSubject,
  buildUserCredentialsHtml,
  buildUserCredentialsSubject,
} from './comment-email'

interface GatewayEnv {
  ALLOWED_ORIGINS: string
  SUPABASE_STORAGE_BUCKET: string
  VITE_SUPABASE_URL: string
  VITE_SUPABASE_ANON_KEY: string
  VITE_SUPABASE_SERVICE_ROLE_KEY: string
  ADMIN_NOTIFICATION_EMAIL?: string
  APP_BASE_URL?: string
  SITE_NAME?: string
  ZEPTO_MAIL_FROM_EMAIL?: string
  ZEPTO_MAIL_FROM_NAME?: string
}

type CommentContentType = 'article' | 'encounter'
type CommentAuthorKind = 'guest' | 'admin' | 'catequista'
type CommentSubscriptionSource = 'opt_in' | 'admin_auto'
type ArticleCategory = 'general' | 'saints-life' | 'biblical' | 'catechism'
type ArticleStatus = 'draft' | 'published'
type ArticleSubscriptionSource = 'manual_form'
type UserRole = 'admin' | 'catequista'
const CATEQUETICO_APP_CODE = 'catequetico'

interface AuthUser {
  id: string
  email?: string
  profile?: CatequeticoUserRow | null
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

function toPublicComment(comment: CommentRow) {
  return {
    id: comment.id,
    content_type: comment.content_type,
    content_id: comment.content_id,
    parent_comment_id: comment.parent_comment_id,
    root_comment_id: comment.root_comment_id,
    author_kind: comment.author_kind,
    author_name: comment.author_name,
    body: comment.body,
    notify_replies: comment.notify_replies,
    created_at: comment.created_at,
    updated_at: comment.updated_at,
  }
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

interface ContentContext {
  contentLabel: string
  title: string
  url: string
}

interface ArticleRow {
  id: string
  slug: string
  title: string
  excerpt?: string | null
  category?: ArticleCategory | null
  status?: ArticleStatus | null
  author_user_id?: string | null
  card_image_url?: string | null
  cover_image_url?: string | null
  featured?: boolean | null
  tags?: string[] | null
  published_at?: string | null
  content_html?: string | null
}

interface ArticleInput {
  id?: string
  slug?: string
  title?: string
  excerpt?: string
  contentHtml?: string
  category?: string
  status?: string
  tags?: unknown
  featured?: boolean
  coverImageUrl?: string
  cardImageUrl?: string
  sources?: unknown
  publishedAt?: string
}

interface ArticleSubscriptionRow {
  id: string
  category: ArticleCategory
  email: string
  subscriber_name: string
  source: ArticleSubscriptionSource
  unsubscribe_token: string
  unsubscribed_at: string | null
}

interface ArticleNotificationEventInsert {
  article_id?: string | null
  subscription_id?: string | null
  category: ArticleCategory
  event_type:
    | 'subscription_created'
    | 'already_subscribed'
    | 'publication_created'
    | 'email_queued'
    | 'email_failed'
    | 'unsubscribe'
  recipient_email?: string | null
  payload?: Record<string, unknown>
}

interface ArticleSubscriptionRequestBody {
  category?: string
  email?: string
  subscriberName?: string
}

interface EncounterRow {
  id: string
  slug: string
  title: string
  class_group_id: string
}

interface ClassGroupRow {
  id: string
  slug: string
  name: string
}

interface ZeptoMailRpcResponse {
  success: boolean
  message?: string
  request_id?: number
  destinatario?: string
  error?: string
  sqlstate?: string
}

interface SharedUserRow {
  id: string
  email: string
  nome: string
  ativo: boolean
  created_at: string
  updated_at: string
}

interface SharedUserRowRaw {
  id: string
  email: string
  nome: string
  ativo: boolean
  created_at: string
  updated_at: string
}

interface UserAppAccessRow {
  user_id: string
  app_code: string
  role: UserRole
  ativo: boolean
  created_at: string
  updated_at: string
}

interface UserAppAccessRowRaw {
  user_id: string
  app_code: string
  role: string
  ativo: boolean
  created_at: string
  updated_at: string
}

interface CatequeticoUserRow {
  id: string
  email: string
  nome: string
  role: UserRole
  ativo: boolean
  created_at: string
  updated_at: string
}

interface AdminUserResponse {
  user?: {
    id: string
    email?: string
    user_metadata?: Record<string, unknown>
  }
  error?: {
    message?: string
  }
  message?: string
  msg?: string
  code?: string
  details?: string
  hint?: string
}

interface CreateUserRequestBody {
  email?: string
  password?: string
  role?: string
  name?: string
}

interface UpdateUserRequestBody {
  role?: string
  name?: string
}

function buildCatequeticoAuthMetadata(input: { name: string; role: UserRole }) {
  return {
    name: input.name,
    role: input.role,
    app_context: CATEQUETICO_APP_CODE,
    app_code: CATEQUETICO_APP_CODE,
  }
}

const articleCategoryMeta = {
  general: {
    label: 'Gerais',
    folderSlug: 'gerais',
  },
  'saints-life': {
    label: 'Vida dos Santos',
    folderSlug: 'vida-dos-santos',
  },
  biblical: {
    label: 'Bíblica',
    folderSlug: 'biblica',
  },
  catechism: {
    label: 'Catecismo',
    folderSlug: 'catecismo',
  },
} satisfies Record<ArticleCategory, { label: string; folderSlug: string }>

function corsHeaders(origin: string | null, env: GatewayEnv) {
  const allowedOrigins = env.ALLOWED_ORIGINS.split(',').map((item) => item.trim())
  const allowOrigin = origin && allowedOrigins.includes(origin) ? origin : allowedOrigins[0] ?? '*'

  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Access-Control-Allow-Methods': 'GET,POST,PATCH,DELETE,OPTIONS',
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
  return (
    typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
  )
}

function normalizeBaseUrl(value?: string | null) {
  return (value?.trim() || '').replace(/\/+$/, '')
}

function getSiteName(env: GatewayEnv) {
  return env.SITE_NAME?.trim() || 'Catequético'
}

function buildAppThreadUrl(baseUrl: string, route: string, threadId: string) {
  const normalizedRoute = route.startsWith('/') ? route : `/${route}`
  return `${baseUrl}/#${normalizedRoute}?thread=${encodeURIComponent(threadId)}`
}

function normalizeArticleCategory(value?: string | null): ArticleCategory | null {
  if (
    value === 'general' ||
    value === 'saints-life' ||
    value === 'biblical' ||
    value === 'catechism'
  ) {
    return value
  }

  return null
}

function normalizeArticleStatus(value?: string | null): ArticleStatus {
  return value === 'draft' ? 'draft' : 'published'
}

function slugify(value: string) {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

function getArticleCategoryDetails(category: ArticleCategory) {
  return articleCategoryMeta[category]
}

function buildArticleCategoryUrl(baseUrl: string, category: ArticleCategory) {
  const { folderSlug } = getArticleCategoryDetails(category)
  return `${baseUrl}/#/artigos/pasta/${encodeURIComponent(folderSlug)}`
}

function buildArticleUrl(baseUrl: string, slug: string) {
  return `${baseUrl}/#/artigos/${encodeURIComponent(slug)}`
}

function sanitizeStringArray(value: unknown) {
  if (!Array.isArray(value)) return []

  return value
    .map((item) => (typeof item === 'string' ? item.trim() : ''))
    .filter(Boolean)
}

function formatArticlePublishedAtLabel(value?: string | null) {
  const date = value ? new Date(value) : new Date()

  if (Number.isNaN(date.getTime())) {
    return 'Publicado recentemente'
  }

  return new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'long',
    timeZone: 'America/Sao_Paulo',
  }).format(date)
}

function buildSubscriberName(email: string, subscriberName?: string | null) {
  const normalizedName = subscriberName?.trim() ?? ''

  if (normalizedName) {
    return normalizedName
  }

  return email.trim().split('@')[0] || 'Participante'
}

async function parseJson<T>(request: Request) {
  try {
    return (await request.json()) as T
  } catch {
    return null
  }
}

function safeParseJson<T>(value: string) {
  try {
    return JSON.parse(value) as T
  } catch {
    return null
  }
}

function extractErrorMessage(payload: unknown) {
  if (!payload) return null

  if (typeof payload === 'string') {
    const message = payload.trim()
    return message || null
  }

  if (typeof payload !== 'object') {
    return null
  }

  const record = payload as {
    message?: unknown
    msg?: unknown
    error?: unknown
    details?: unknown
    hint?: unknown
    code?: unknown
  }

  const parts = [
    typeof record.message === 'string' ? record.message.trim() : '',
    typeof record.msg === 'string' ? record.msg.trim() : '',
    typeof record.error === 'string' ? record.error.trim() : '',
    typeof record.error === 'object' &&
    record.error &&
    'message' in record.error &&
    typeof (record.error as { message?: unknown }).message === 'string'
      ? ((record.error as { message?: string }).message ?? '').trim()
      : '',
    typeof record.details === 'string' ? record.details.trim() : '',
    typeof record.hint === 'string' ? record.hint.trim() : '',
    typeof record.code === 'string' ? `code ${record.code.trim()}` : '',
  ].filter(Boolean)

  return parts.length > 0 ? parts.join(' | ') : null
}

function buildRemoteErrorMessage(response: Response, payload: unknown, fallback: string) {
  const remoteMessage = extractErrorMessage(payload)

  if (remoteMessage) {
    return `${fallback} ${remoteMessage}`
  }

  return `${fallback} Status ${response.status}.`
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
    data = safeParseJson<T>(text)
  }

  return { response, data, text }
}

async function supabaseRpc<T>(env: GatewayEnv, rpcName: string, payload: Record<string, unknown>) {
  return supabaseRest<T>(
    env,
    `/rpc/${rpcName}`,
    {
      method: 'POST',
      body: JSON.stringify(payload),
    },
    { serviceRole: true },
  )
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
  const profile = await getCatequeticoUserById(env, payload.id)

  return {
    id: payload.id,
    email: payload.email,
    profile,
  }
}

async function getSharedUserById(env: GatewayEnv, userId: string) {
  const { response, data } = await supabaseRest<SharedUserRowRaw[]>(
    env,
    `/users?select=id,email,nome,ativo,created_at,updated_at&id=eq.${userId}&limit=1`,
    { method: 'GET' },
  )

  if (!response.ok || !Array.isArray(data) || data.length === 0) {
    return null
  }

  return mapSharedUserRow(data[0])
}

async function getSharedUserByEmail(env: GatewayEnv, email: string) {
  const normalizedEmail = email.trim().toLowerCase()
  const { response, data } = await supabaseRest<SharedUserRowRaw[]>(
    env,
    `/users?select=id,email,nome,ativo,created_at,updated_at&email=eq.${encodeURIComponent(normalizedEmail)}&limit=1`,
    { method: 'GET' },
  )

  if (!response.ok || !Array.isArray(data) || data.length === 0) {
    return null
  }

  return mapSharedUserRow(data[0])
}

function normalizeUserRole(value?: string | null): UserRole | null {
  if (value === 'admin') return 'admin'
  if (value === 'catequista') return 'catequista'
  if (value === 'user') return 'catequista'
  return null
}

function buildDisplayName(email: string, name?: string | null) {
  const normalizedName = name?.trim() ?? ''

  if (normalizedName) {
    return normalizedName
  }

  return email.trim().split('@')[0] || 'Catequista'
}

function isAdminUser(user: AuthUser | null) {
  return user?.profile?.ativo === true && user.profile.role === 'admin'
}

function isEditorUser(user: AuthUser | null) {
  return user?.profile?.ativo === true && (user.profile.role === 'admin' || user.profile.role === 'catequista')
}

function mapSharedUserRow(row: SharedUserRowRaw): SharedUserRow {
  return row
}

function mapUserAppAccessRow(row: UserAppAccessRowRaw): UserAppAccessRow {
  return {
    ...row,
    role: normalizeUserRole(row.role) ?? 'catequista',
  }
}

function mapCatequeticoUser(input: {
  sharedUser: SharedUserRow
  access: UserAppAccessRow
}): CatequeticoUserRow {
  return {
    id: input.sharedUser.id,
    email: input.sharedUser.email,
    nome: input.sharedUser.nome,
    role: input.access.role,
    ativo: input.sharedUser.ativo && input.access.ativo,
    created_at: input.access.created_at,
    updated_at: input.access.updated_at,
  }
}

async function getUserAppAccessByUserId(env: GatewayEnv, userId: string) {
  const { response, data } = await supabaseRest<UserAppAccessRowRaw[]>(
    env,
    `/user_app_access?select=user_id,app_code,role,ativo,created_at,updated_at&app_code=eq.${CATEQUETICO_APP_CODE}&user_id=eq.${userId}&limit=1`,
    { method: 'GET' },
  )

  if (!response.ok || !Array.isArray(data) || data.length === 0) {
    return null
  }

  return mapUserAppAccessRow(data[0])
}

async function getCatequeticoUserById(env: GatewayEnv, userId: string) {
  const [sharedUser, access] = await Promise.all([
    getSharedUserById(env, userId),
    getUserAppAccessByUserId(env, userId),
  ])

  if (!sharedUser || !access) {
    return null
  }

  return mapCatequeticoUser({
    sharedUser,
    access,
  })
}

async function listCatequeticoUsers(env: GatewayEnv) {
  const { response, data, text } = await supabaseRest<UserAppAccessRowRaw[]>(
    env,
    `/user_app_access?select=user_id,app_code,role,ativo,created_at,updated_at&app_code=eq.${CATEQUETICO_APP_CODE}&order=created_at.desc`,
    { method: 'GET' },
  )

  if (!response.ok || !Array.isArray(data)) {
    throw new Error(
      buildRemoteErrorMessage(
        response,
        data ?? text,
        'Não foi possível carregar os usuários do Catequético.',
      ),
    )
  }

  const accessRows = data.map(mapUserAppAccessRow)

  if (accessRows.length === 0) {
    return []
  }

  const userIds = accessRows.map((row) => row.user_id)
  const { response: usersResponse, data: usersData, text: usersText } = await supabaseRest<SharedUserRowRaw[]>(
    env,
    `/users?select=id,email,nome,ativo,created_at,updated_at&id=in.(${userIds.join(',')})`,
    { method: 'GET' },
  )

  if (!usersResponse.ok || !Array.isArray(usersData)) {
    throw new Error(
      buildRemoteErrorMessage(
        usersResponse,
        usersData ?? usersText,
        'Não foi possível carregar os perfis compartilhados dos usuários.',
      ),
    )
  }

  const sharedUsersById = new Map(
    usersData.map((row) => {
      const sharedUser = mapSharedUserRow(row)
      return [sharedUser.id, sharedUser] as const
    }),
  )

  return accessRows.flatMap((access) => {
    const sharedUser = sharedUsersById.get(access.user_id)
    if (!sharedUser) return []

    return [
      mapCatequeticoUser({
        sharedUser,
        access,
      }),
    ]
  })
}

async function upsertSharedUserProfile(
  env: GatewayEnv,
  input: { id: string; email: string; name: string; active?: boolean },
) {
  const { response, data, text } = await supabaseRest<SharedUserRowRaw[]>(
    env,
    '/users?on_conflict=id',
    {
      method: 'POST',
      headers: {
        Prefer: 'resolution=merge-duplicates,return=representation',
      },
      body: JSON.stringify({
        id: input.id,
        email: input.email.trim().toLowerCase(),
        nome: input.name.trim(),
        ativo: input.active ?? true,
      }),
    },
  )

  if (!response.ok || !Array.isArray(data) || data.length === 0) {
    throw new Error(buildRemoteErrorMessage(response, data ?? text, 'Não foi possível salvar o perfil do usuário.'))
  }

  return mapSharedUserRow(data[0])
}

async function upsertUserAppAccess(
  env: GatewayEnv,
  input: { userId: string; role: UserRole; active?: boolean },
) {
  const { response, data, text } = await supabaseRest<UserAppAccessRowRaw[]>(
    env,
    '/user_app_access?on_conflict=user_id,app_code',
    {
      method: 'POST',
      headers: {
        Prefer: 'resolution=merge-duplicates,return=representation',
      },
      body: JSON.stringify({
        user_id: input.userId,
        app_code: CATEQUETICO_APP_CODE,
        role: input.role,
        ativo: input.active ?? true,
      }),
    },
  )

  if (!response.ok || !Array.isArray(data) || data.length === 0) {
    throw new Error(
      buildRemoteErrorMessage(
        response,
        data ?? text,
        'Não foi possível salvar o acesso do usuário ao Catequético.',
      ),
    )
  }

  return mapUserAppAccessRow(data[0])
}

async function deleteUserAppAccess(env: GatewayEnv, userId: string) {
  const { response, data, text } = await supabaseRest(
    env,
    `/user_app_access?app_code=eq.${CATEQUETICO_APP_CODE}&user_id=eq.${userId}`,
    {
      method: 'DELETE',
    },
  )

  if (!response.ok) {
    throw new Error(
      buildRemoteErrorMessage(
        response,
        data ?? text,
        'Não foi possível remover o acesso do usuário ao Catequético.',
      ),
    )
  }
}

async function createAuthUser(
  env: GatewayEnv,
  input: { email: string; password: string; name: string; role: UserRole },
) {
  const response = await fetch(`${env.VITE_SUPABASE_URL}/auth/v1/admin/users`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: env.VITE_SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.VITE_SUPABASE_SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({
      email: input.email,
      password: input.password,
      email_confirm: true,
      user_metadata: buildCatequeticoAuthMetadata({
        name: input.name,
        role: input.role,
      }),
    }),
  })

  const payload = (await response.json().catch(() => null)) as AdminUserResponse | null

  if (!response.ok || !payload?.user?.id) {
    throw new Error(buildRemoteErrorMessage(response, payload, 'Não foi possível criar o usuário no Auth.'))
  }

  return payload.user
}

async function updateAuthUser(
  env: GatewayEnv,
  userId: string,
  input: { name: string; role: UserRole },
) {
  const response = await fetch(`${env.VITE_SUPABASE_URL}/auth/v1/admin/users/${userId}`, {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
      apikey: env.VITE_SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.VITE_SUPABASE_SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({
      user_metadata: buildCatequeticoAuthMetadata({
        name: input.name,
        role: input.role,
      }),
    }),
  })

  const payload = (await response.json().catch(() => null)) as AdminUserResponse | null

  if (!response.ok || !payload?.user?.id) {
    throw new Error(buildRemoteErrorMessage(response, payload, 'Não foi possível atualizar o usuário no Auth.'))
  }

  return payload.user
}

async function deleteAuthUser(env: GatewayEnv, userId: string) {
  const response = await fetch(`${env.VITE_SUPABASE_URL}/auth/v1/admin/users/${userId}`, {
    method: 'DELETE',
    headers: {
      apikey: env.VITE_SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.VITE_SUPABASE_SERVICE_ROLE_KEY}`,
    },
  })

  if (!response.ok) {
    const payload = (await response.json().catch(() => null)) as AdminUserResponse | null
    throw new Error(buildRemoteErrorMessage(response, payload, 'Não foi possível excluir o usuário.'))
  }
}

async function sendUserCredentialsEmail(
  env: GatewayEnv,
  input: { email: string; password: string; role: UserRole; baseUrl: string },
) {
  const loginUrl = `${normalizeBaseUrl(env.APP_BASE_URL) || input.baseUrl}/#/login`
  const fromEmail = env.ZEPTO_MAIL_FROM_EMAIL?.trim() || 'noreply@catequetico.org'
  const fromName = env.ZEPTO_MAIL_FROM_NAME?.trim() || getSiteName(env)
  const profileLabel = input.role === 'admin' ? 'Admin' : 'Catequista'
  const subject = buildUserCredentialsSubject({
    loginUrl,
    profileLabel,
    recipientEmail: input.email,
    recipientPassword: input.password,
    siteName: getSiteName(env),
  })
  const bodyHtml = buildUserCredentialsHtml({
    loginUrl,
    profileLabel,
    recipientEmail: input.email,
    recipientPassword: input.password,
    siteName: getSiteName(env),
  })

  const { response, data } = await supabaseRpc<ZeptoMailRpcResponse>(env, 'enviar_email_zeptomail', {
    p_destinatario: input.email,
    p_assunto: subject,
    p_corpo_html: bodyHtml,
    p_remetente_email: fromEmail,
    p_remetente_nome: fromName,
  })

  if (!response.ok || !data?.success) {
    throw new Error(data?.error ?? `RPC retornou status ${response.status}.`)
  }

  return data.request_id ?? null
}

async function getArticleById(env: GatewayEnv, articleId: string) {
  const { response, data } = await supabaseRest<ArticleRow[]>(
    env,
    `/articles?select=*&id=eq.${articleId}&limit=1`,
    { method: 'GET' },
  )

  if (!response.ok || !Array.isArray(data) || data.length === 0) {
    return null
  }

  return data[0]
}

async function upsertArticleRow(
  env: GatewayEnv,
  payload: {
    id: string
    slug: string
    title: string
    excerpt: string
    content_html: string
    category: ArticleCategory
    status: ArticleStatus
    author_user_id: string
    tags: string[]
    featured: boolean
    cover_image_url: string | null
    card_image_url: string | null
    sources: string[]
    published_at: string | null
  },
) {
  const { response, data } = await supabaseRest<ArticleRow[]>(
    env,
    '/articles?on_conflict=id',
    {
      method: 'POST',
      headers: {
        Prefer: 'resolution=merge-duplicates,return=representation',
      },
      body: JSON.stringify(payload),
    },
  )

  if (!response.ok || !Array.isArray(data) || data.length === 0) {
    throw new Error('Não foi possível salvar o artigo.')
  }

  return data[0]
}

async function ensureArticleCategorySubscription(
  env: GatewayEnv,
  input: {
    category: ArticleCategory
    email: string
    subscriberName: string
    source: ArticleSubscriptionSource
  },
) {
  const normalizedEmail = input.email.trim().toLowerCase()
  const { response, data } = await supabaseRest<ArticleSubscriptionRow[]>(
    env,
    `/article_category_subscriptions?select=*&category=eq.${input.category}&email=eq.${encodeURIComponent(normalizedEmail)}&limit=1`,
    { method: 'GET' },
  )

  if (!response.ok) {
    throw new Error('Não foi possível consultar as inscrições desta pasta.')
  }

  if (Array.isArray(data) && data.length > 0) {
    const existing = data[0]

    if (!existing.unsubscribed_at) {
      return { subscription: existing, created: false }
    }

    const { response: updateResponse, data: updateData } = await supabaseRest<ArticleSubscriptionRow[]>(
      env,
      `/article_category_subscriptions?id=eq.${existing.id}`,
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
      throw new Error('Não foi possível reativar a inscrição desta pasta.')
    }

    return { subscription: updateData[0], created: true }
  }

  const { response: insertResponse, data: insertData } = await supabaseRest<ArticleSubscriptionRow[]>(
    env,
    '/article_category_subscriptions',
    {
      method: 'POST',
      headers: {
        Prefer: 'return=representation',
      },
      body: JSON.stringify({
        category: input.category,
        email: normalizedEmail,
        subscriber_name: input.subscriberName,
        source: input.source,
      }),
    },
  )

  if (!insertResponse.ok || !Array.isArray(insertData) || insertData.length === 0) {
    throw new Error('Não foi possível criar a inscrição desta pasta.')
  }

  return { subscription: insertData[0], created: true }
}

async function listActiveArticleCategorySubscriptions(env: GatewayEnv, category: ArticleCategory) {
  const { response, data } = await supabaseRest<ArticleSubscriptionRow[]>(
    env,
    `/article_category_subscriptions?select=*&category=eq.${category}&unsubscribed_at=is.null`,
    { method: 'GET' },
  )

  if (!response.ok) {
    throw new Error('Não foi possível carregar as inscrições desta pasta.')
  }

  return Array.isArray(data) ? data : []
}

async function insertArticleNotificationEvents(
  env: GatewayEnv,
  events: ArticleNotificationEventInsert[],
) {
  if (events.length === 0) return

  await supabaseRest(
    env,
    '/article_notification_events',
    {
      method: 'POST',
      body: JSON.stringify(
        events.map((event) => ({
          article_id: event.article_id ?? null,
          subscription_id: event.subscription_id ?? null,
          category: event.category,
          event_type: event.event_type,
          recipient_email: event.recipient_email ?? null,
          payload: event.payload ?? {},
        })),
      ),
    },
  )
}

async function queueArticleCategorySubscriptionEmail(
  env: GatewayEnv,
  input: {
    subscription: ArticleSubscriptionRow
    category: ArticleCategory
    baseUrl: string
    workerBaseUrl: string
  },
) {
  const fromEmail = env.ZEPTO_MAIL_FROM_EMAIL?.trim() || 'noreply@catequetico.org'
  const fromName = env.ZEPTO_MAIL_FROM_NAME?.trim() || getSiteName(env)
  const categoryMeta = getArticleCategoryDetails(input.category)
  const unsubscribeUrl = `${input.workerBaseUrl}/article-subscriptions/unsubscribe?token=${encodeURIComponent(input.subscription.unsubscribe_token)}`
  const categoryUrl = buildArticleCategoryUrl(input.baseUrl, input.category)
  const subject = buildArticleCategorySubscriptionSubject({
    categoryLabel: categoryMeta.label,
    categoryUrl,
    subscriberName: input.subscription.subscriber_name,
    unsubscribeUrl,
    siteName: getSiteName(env),
  })
  const bodyHtml = buildArticleCategorySubscriptionHtml({
    categoryLabel: categoryMeta.label,
    categoryUrl,
    subscriberName: input.subscription.subscriber_name,
    unsubscribeUrl,
    siteName: getSiteName(env),
  })

  const { response, data } = await supabaseRpc<ZeptoMailRpcResponse>(env, 'enviar_email_zeptomail', {
    p_destinatario: input.subscription.email,
    p_assunto: subject,
    p_corpo_html: bodyHtml,
    p_remetente_email: fromEmail,
    p_remetente_nome: fromName,
  })

  if (!response.ok || !data?.success) {
    return {
      success: false,
      error: data?.error ?? `RPC retornou status ${response.status}.`,
    }
  }

  return {
    success: true,
    requestId: data.request_id,
  }
}

async function queueArticlePublicationEmail(
  env: GatewayEnv,
  input: {
    subscription: ArticleSubscriptionRow
    article: ArticleRow
    category: ArticleCategory
    baseUrl: string
    workerBaseUrl: string
  },
) {
  const fromEmail = env.ZEPTO_MAIL_FROM_EMAIL?.trim() || 'noreply@catequetico.org'
  const fromName = env.ZEPTO_MAIL_FROM_NAME?.trim() || getSiteName(env)
  const categoryMeta = getArticleCategoryDetails(input.category)
  const unsubscribeUrl = `${input.workerBaseUrl}/article-subscriptions/unsubscribe?token=${encodeURIComponent(input.subscription.unsubscribe_token)}`
  const categoryUrl = buildArticleCategoryUrl(input.baseUrl, input.category)
  const articleUrl = buildArticleUrl(input.baseUrl, input.article.slug)
  const subject = buildArticlePublicationSubject({
    articleTitle: input.article.title,
    articleExcerpt: input.article.excerpt?.trim() || 'Um novo artigo foi publicado nesta pasta.',
    articleUrl,
    categoryLabel: categoryMeta.label,
    categoryUrl,
    cardImageUrl: input.article.card_image_url ?? input.article.cover_image_url ?? undefined,
    publishedAtLabel: formatArticlePublishedAtLabel(input.article.published_at),
    featured: Boolean(input.article.featured),
    tags: sanitizeStringArray(input.article.tags),
    unsubscribeUrl,
    siteName: getSiteName(env),
  })
  const bodyHtml = buildArticlePublicationHtml({
    articleTitle: input.article.title,
    articleExcerpt: input.article.excerpt?.trim() || 'Um novo artigo foi publicado nesta pasta.',
    articleUrl,
    categoryLabel: categoryMeta.label,
    categoryUrl,
    cardImageUrl: input.article.card_image_url ?? input.article.cover_image_url ?? undefined,
    publishedAtLabel: formatArticlePublishedAtLabel(input.article.published_at),
    featured: Boolean(input.article.featured),
    tags: sanitizeStringArray(input.article.tags),
    unsubscribeUrl,
    siteName: getSiteName(env),
  })

  const { response, data } = await supabaseRpc<ZeptoMailRpcResponse>(env, 'enviar_email_zeptomail', {
    p_destinatario: input.subscription.email,
    p_assunto: subject,
    p_corpo_html: bodyHtml,
    p_remetente_email: fromEmail,
    p_remetente_nome: fromName,
  })

  if (!response.ok || !data?.success) {
    return {
      success: false,
      error: data?.error ?? `RPC retornou status ${response.status}.`,
    }
  }

  return {
    success: true,
    requestId: data.request_id,
  }
}

async function notifyArticleCategorySubscribers(
  env: GatewayEnv,
  article: ArticleRow,
  category: ArticleCategory,
  baseUrl: string,
  workerBaseUrl: string,
) {
  const subscriptions = await listActiveArticleCategorySubscriptions(env, category)
  const events: ArticleNotificationEventInsert[] = [
    {
      article_id: article.id,
      category,
      event_type: 'publication_created',
      payload: {
        articleSlug: article.slug,
        totalSubscribers: subscriptions.length,
      },
    },
  ]

  for (const subscription of subscriptions) {
    const result = await queueArticlePublicationEmail(env, {
      subscription,
      article,
      category,
      baseUrl,
      workerBaseUrl,
    })

    events.push({
      article_id: article.id,
      subscription_id: subscription.id,
      category,
      recipient_email: subscription.email,
      event_type: result.success ? 'email_queued' : 'email_failed',
      payload: result.success
        ? {
            requestId: result.requestId ?? null,
            source: subscription.source,
          }
        : {
            source: subscription.source,
            error: result.error,
          },
    })
  }

  await insertArticleNotificationEvents(env, events)
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
    throw new Error('Não foi possível salvar o comentário.')
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
    throw new Error('Não foi possível consultar as inscrições da thread.')
  }

  if (Array.isArray(data) && data.length > 0) {
    const existing = data[0]

    if (
      !existing.unsubscribed_at &&
      existing.subscriber_name === input.subscriberName &&
      existing.source === input.source
    ) {
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
      throw new Error('Não foi possível atualizar a inscrição da thread.')
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
    throw new Error('Não foi possível criar a inscrição da thread.')
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
    throw new Error('Não foi possível carregar as inscrições da thread.')
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

async function getContentContext(env: GatewayEnv, comment: CommentRow): Promise<ContentContext | null> {
  const baseUrl = normalizeBaseUrl(env.APP_BASE_URL)

  if (!baseUrl) {
    return null
  }

  if (comment.content_type === 'article') {
    const { response, data } = await supabaseRest<ArticleRow[]>(
      env,
      `/articles?select=id,slug,title&id=eq.${comment.content_id}&limit=1`,
      { method: 'GET' },
    )

    if (!response.ok || !Array.isArray(data) || data.length === 0) {
      return null
    }

    const article = data[0]

    return {
      contentLabel: 'Artigo',
      title: article.title,
      url: buildAppThreadUrl(baseUrl, `/artigos/${encodeURIComponent(article.slug)}`, comment.root_comment_id),
    }
  }

  const { response: encounterResponse, data: encounterData } = await supabaseRest<EncounterRow[]>(
    env,
    `/encounters?select=id,slug,title,class_group_id&id=eq.${comment.content_id}&limit=1`,
    { method: 'GET' },
  )

  if (!encounterResponse.ok || !Array.isArray(encounterData) || encounterData.length === 0) {
    return null
  }

  const encounter = encounterData[0]
  const { response: groupResponse, data: groupData } = await supabaseRest<ClassGroupRow[]>(
    env,
    `/class_groups?select=id,slug,name&id=eq.${encounter.class_group_id}&limit=1`,
    { method: 'GET' },
  )

  if (!groupResponse.ok || !Array.isArray(groupData) || groupData.length === 0) {
    return null
  }

  const group = groupData[0]

  return {
    contentLabel: 'Encontro',
    title: encounter.title,
    url: buildAppThreadUrl(
      baseUrl,
      `/encontros/${encodeURIComponent(group.slug)}/${encodeURIComponent(encounter.slug)}`,
      comment.root_comment_id,
    ),
  }
}

async function queueCommentNotificationEmail(
  env: GatewayEnv,
  input: {
    recipient: CommentSubscriptionRow
    comment: CommentRow
    content: ContentContext
    workerBaseUrl: string
  },
) {
  const fromEmail = env.ZEPTO_MAIL_FROM_EMAIL?.trim() || 'noreply@catequetico.org'
  const fromName = env.ZEPTO_MAIL_FROM_NAME?.trim() || getSiteName(env)
  const unsubscribeUrl = `${input.workerBaseUrl}/comments/unsubscribe?token=${encodeURIComponent(input.recipient.unsubscribe_token)}`
  const subject = buildCommentNotificationSubject({
    contentLabel: input.content.contentLabel,
    contentTitle: input.content.title,
    contentUrl: input.content.url,
    replyAuthorName: input.comment.author_name,
    replyAuthorKind: input.comment.author_kind,
    replyBody: input.comment.body,
    unsubscribeUrl,
    siteName: getSiteName(env),
  })
  const bodyHtml = buildCommentNotificationHtml({
    contentLabel: input.content.contentLabel,
    contentTitle: input.content.title,
    contentUrl: input.content.url,
    replyAuthorName: input.comment.author_name,
    replyAuthorKind: input.comment.author_kind,
    replyBody: input.comment.body,
    unsubscribeUrl,
    siteName: getSiteName(env),
  })

  const { response, data } = await supabaseRpc<ZeptoMailRpcResponse>(env, 'enviar_email_zeptomail', {
    p_destinatario: input.recipient.email,
    p_assunto: subject,
    p_corpo_html: bodyHtml,
    p_remetente_email: fromEmail,
    p_remetente_nome: fromName,
  })

  if (!response.ok || !data?.success) {
    return {
      success: false,
      error: data?.error ?? `RPC retornou status ${response.status}.`,
    }
  }

  return {
    success: true,
    requestId: data.request_id,
  }
}

async function queueThreadSubscriptionEmail(
  env: GatewayEnv,
  input: {
    subscription: CommentSubscriptionRow
    content: ContentContext
    workerBaseUrl: string
  },
) {
  const fromEmail = env.ZEPTO_MAIL_FROM_EMAIL?.trim() || 'noreply@catequetico.org'
  const fromName = env.ZEPTO_MAIL_FROM_NAME?.trim() || getSiteName(env)
  const unsubscribeUrl = `${input.workerBaseUrl}/comments/unsubscribe?token=${encodeURIComponent(input.subscription.unsubscribe_token)}`
  const subject = buildThreadSubscriptionSubject({
    contentLabel: input.content.contentLabel,
    contentTitle: input.content.title,
    contentUrl: input.content.url,
    subscriberName: input.subscription.subscriber_name,
    unsubscribeUrl,
    siteName: getSiteName(env),
  })
  const bodyHtml = buildThreadSubscriptionHtml({
    contentLabel: input.content.contentLabel,
    contentTitle: input.content.title,
    contentUrl: input.content.url,
    subscriberName: input.subscription.subscriber_name,
    unsubscribeUrl,
    siteName: getSiteName(env),
  })

  const { response, data } = await supabaseRpc<ZeptoMailRpcResponse>(env, 'enviar_email_zeptomail', {
    p_destinatario: input.subscription.email,
    p_assunto: subject,
    p_corpo_html: bodyHtml,
    p_remetente_email: fromEmail,
    p_remetente_nome: fromName,
  })

  if (!response.ok || !data?.success) {
    return {
      success: false,
      error: data?.error ?? `RPC retornou status ${response.status}.`,
    }
  }

  return {
    success: true,
    requestId: data.request_id,
  }
}

async function notifyThreadParticipants(env: GatewayEnv, comment: CommentRow, workerBaseUrl: string) {
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

  if (recipients.size === 0) {
    await insertEvents(env, events)
    return
  }

  const content = await getContentContext(env, comment)

  if (!content) {
    for (const subscription of recipients.values()) {
      events.push({
        comment_id: comment.id,
        root_comment_id: rootCommentId,
        event_type: 'email_failed',
        recipient_email: subscription.email,
        payload: {
          reason: 'Não foi possível montar o contexto do conteúdo para o email.',
        },
      })
    }

    await insertEvents(env, events)
    return
  }

  for (const subscription of recipients.values()) {
    const result = await queueCommentNotificationEmail(env, {
      recipient: subscription,
      comment,
      content,
      workerBaseUrl,
    })

    events.push({
      comment_id: comment.id,
      root_comment_id: rootCommentId,
      recipient_email: subscription.email,
      event_type: result.success ? 'email_queued' : 'email_failed',
      payload: result.success
        ? {
            requestId: result.requestId ?? null,
            source: subscription.source,
          }
        : {
            source: subscription.source,
            error: result.error,
          },
    })
  }

  await insertEvents(env, events)
}

async function handleCreateComment(request: Request, env: GatewayEnv, headers: Record<string, string>) {
  const body = await parseJson<CommentRequestBody>(request)

  if (!body) {
    return json({ error: 'Corpo inválido.' }, 400, headers)
  }

  const contentType = body.contentType === 'article' || body.contentType === 'encounter' ? body.contentType : null
  const contentId = typeof body.contentId === 'string' ? body.contentId.trim() : ''
  const parentCommentId = typeof body.parentCommentId === 'string' ? body.parentCommentId.trim() : ''
  const authorName = typeof body.authorName === 'string' ? body.authorName.trim() : ''
  const authorEmail = typeof body.authorEmail === 'string' ? body.authorEmail.trim().toLowerCase() : ''
  const commentBody = typeof body.body === 'string' ? body.body.trim() : ''
  const notifyReplies = Boolean(body.notifyReplies)
  const authUser = await getAuthenticatedUser(request, env)
  const isAuthenticatedAuthor = Boolean(authUser)

  if (!contentType || !isUuid(contentId)) {
    return json({ error: 'Conteúdo inválido.' }, 400, headers)
  }

  if (!authorName) {
    return json({ error: 'Informe o nome do autor.' }, 400, headers)
  }

  if (!commentBody) {
    return json({ error: 'Escreva um comentário.' }, 400, headers)
  }

  if (!isAuthenticatedAuthor && authorEmail && !isValidEmail(authorEmail)) {
    return json({ error: 'Informe um email válido.' }, 400, headers)
  }

  if (!isAuthenticatedAuthor && notifyReplies && !authorEmail) {
    return json({ error: 'Informe um email para acompanhar a conversa.' }, 400, headers)
  }

  const contentExists = await ensureContentExists(env, contentType, contentId)

  if (!contentExists) {
    return json({ error: 'O conteúdo informado não foi encontrado.' }, 404, headers)
  }

  let parentComment: CommentRow | null = null

  if (parentCommentId) {
    if (!isUuid(parentCommentId)) {
      return json({ error: 'Comentário pai inválido.' }, 400, headers)
    }

    parentComment = await getCommentById(env, parentCommentId)

    if (!parentComment) {
      return json({ error: 'Comentário pai não encontrado.' }, 404, headers)
    }

    if (parentComment.parent_comment_id) {
      return json({ error: 'Não é permitido responder uma resposta.' }, 400, headers)
    }

    if (parentComment.content_type !== contentType || parentComment.content_id !== contentId) {
      return json({ error: 'A resposta não pertence a este conteúdo.' }, 400, headers)
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
      author_kind: isAuthenticatedAuthor ? 'catequista' : 'guest',
      admin_user_id: authUser?.id ?? null,
      author_name: authorName,
      author_email: isAuthenticatedAuthor ? null : authorEmail || null,
      body: commentBody,
      notify_replies: isAuthenticatedAuthor ? false : notifyReplies,
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
    let createdOptInSubscription: CommentSubscriptionRow | null = null

    if (!isAuthenticatedAuthor && notifyReplies && authorEmail) {
      const subscription = await ensureSubscription(env, {
        rootCommentId,
        email: authorEmail,
        subscriberName: authorName,
        source: 'opt_in',
      })

      if (subscription.created) {
        createdOptInSubscription = subscription.subscription
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
    const workerBaseUrl = new URL(request.url).origin

    if (createdOptInSubscription) {
      const content = await getContentContext(env, comment)

      if (!content) {
        await insertEvents(env, [
          {
            comment_id: comment.id,
            root_comment_id: rootCommentId,
            event_type: 'email_failed',
            recipient_email: createdOptInSubscription.email,
            payload: {
              kind: 'thread_subscription_confirmation',
              source: createdOptInSubscription.source,
              error: 'Não foi possível montar o contexto do conteúdo para o email de assinatura.',
            },
          },
        ])
      } else {
        const result = await queueThreadSubscriptionEmail(env, {
          subscription: createdOptInSubscription,
          content,
          workerBaseUrl,
        })

        await insertEvents(env, [
          {
            comment_id: comment.id,
            root_comment_id: rootCommentId,
            recipient_email: createdOptInSubscription.email,
            event_type: result.success ? 'email_queued' : 'email_failed',
            payload: result.success
              ? {
                  kind: 'thread_subscription_confirmation',
                  source: createdOptInSubscription.source,
                  requestId: result.requestId ?? null,
                }
              : {
                  kind: 'thread_subscription_confirmation',
                  source: createdOptInSubscription.source,
                  error: result.error,
                },
          },
        ])
      }
    }

    await notifyThreadParticipants(env, comment, workerBaseUrl)

    return json(
      {
        ok: true,
        comment: toPublicComment(comment),
        subscriptionConfirmationNeeded: Boolean(createdOptInSubscription),
      },
      201,
      headers,
    )
  } catch (error) {
    return json(
      {
        error: error instanceof Error ? error.message : 'Não foi possível publicar o comentário.',
      },
      400,
      headers,
    )
  }
}

async function handleCreateArticleSubscription(
  request: Request,
  env: GatewayEnv,
  headers: Record<string, string>,
) {
  const body = await parseJson<ArticleSubscriptionRequestBody>(request)

  if (!body) {
    return json({ error: 'Corpo inválido.' }, 400, headers)
  }

  const category = normalizeArticleCategory(body.category)
  const email = body.email?.trim().toLowerCase() ?? ''

  if (!category) {
    return json({ error: 'Pasta invalida.' }, 400, headers)
  }

  if (!isValidEmail(email)) {
    return json({ error: 'Informe um email válido.' }, 400, headers)
  }

  const subscriberName = buildSubscriberName(email, body.subscriberName)

  try {
    const result = await ensureArticleCategorySubscription(env, {
      category,
      email,
      subscriberName,
      source: 'manual_form',
    })

    if (!result.created) {
      await insertArticleNotificationEvents(env, [
        {
          subscription_id: result.subscription.id,
          category,
          recipient_email: result.subscription.email,
          event_type: 'already_subscribed',
          payload: {
            source: result.subscription.source,
          },
        },
      ])

      return json(
        {
          ok: true,
          alreadySubscribed: true,
        },
        200,
        headers,
      )
    }

    const baseUrl = normalizeBaseUrl(env.APP_BASE_URL) || new URL(request.url).origin
    const workerBaseUrl = new URL(request.url).origin
    const emailResult = await queueArticleCategorySubscriptionEmail(env, {
      subscription: result.subscription,
      category,
      baseUrl,
      workerBaseUrl,
    })

    await insertArticleNotificationEvents(env, [
      {
        subscription_id: result.subscription.id,
        category,
        recipient_email: result.subscription.email,
        event_type: 'subscription_created',
        payload: {
          source: result.subscription.source,
        },
      },
      {
        subscription_id: result.subscription.id,
        category,
        recipient_email: result.subscription.email,
        event_type: emailResult.success ? 'email_queued' : 'email_failed',
        payload: emailResult.success
          ? {
              kind: 'article_category_subscription_confirmation',
              requestId: emailResult.requestId ?? null,
              source: result.subscription.source,
            }
          : {
              kind: 'article_category_subscription_confirmation',
              source: result.subscription.source,
              error: emailResult.error,
            },
      },
    ])

    return json(
      {
        ok: true,
        alreadySubscribed: false,
      },
      201,
      headers,
    )
  } catch (error) {
    return json(
      {
        error: error instanceof Error ? error.message : 'Não foi possível registrar a inscrição.',
      },
      400,
      headers,
    )
  }
}

async function handleUpsertArticle(request: Request, env: GatewayEnv, headers: Record<string, string>) {
  const authUser = await getAuthenticatedUser(request, env)

  if (!isEditorUser(authUser)) {
    return json({ error: 'Apenas usuários autorizados podem salvar artigos.' }, 403, headers)
  }

  const body = await parseJson<ArticleInput>(request)

  if (!body) {
    return json({ error: 'Corpo inválido.' }, 400, headers)
  }

  const articleId = typeof body.id === 'string' ? body.id.trim() : ''
  const title = typeof body.title === 'string' ? body.title.trim() : ''
  const excerpt = typeof body.excerpt === 'string' ? body.excerpt.trim() : ''
  const contentHtml = typeof body.contentHtml === 'string' ? body.contentHtml.trim() : ''
  const slugInput = typeof body.slug === 'string' ? body.slug.trim() : ''
  const slug = slugInput || slugify(title)
  const category = normalizeArticleCategory(body.category) ?? 'general'
  const status = normalizeArticleStatus(body.status)
  const featured = Boolean(body.featured)
  const tags = sanitizeStringArray(body.tags)
  const sources = sanitizeStringArray(body.sources)
  const coverImageUrl =
    typeof body.coverImageUrl === 'string' && body.coverImageUrl.trim() ? body.coverImageUrl.trim() : null
  const cardImageUrl =
    typeof body.cardImageUrl === 'string' && body.cardImageUrl.trim()
      ? body.cardImageUrl.trim()
      : coverImageUrl

  if (!isUuid(articleId)) {
    return json({ error: 'Identificador do artigo inválido.' }, 400, headers)
  }

  if (!title) {
    return json({ error: 'Informe o título do artigo.' }, 400, headers)
  }

  if (!slug) {
    return json({ error: 'Informe um título ou slug válido para o artigo.' }, 400, headers)
  }

  if (status === 'published' && !contentHtml) {
    return json({ error: 'Informe o conteúdo do artigo.' }, 400, headers)
  }

  try {
    const existingArticle = await getArticleById(env, articleId)
    const adminUser = isAdminUser(authUser)

    if (!adminUser && status === 'published') {
      return json({ error: 'Apenas administradores podem publicar artigos.' }, 403, headers)
    }

    if (existingArticle && !adminUser) {
      if (existingArticle.author_user_id !== authUser?.id) {
        return json({ error: 'Você só pode editar rascunhos criados por você.' }, 403, headers)
      }

      if (existingArticle.status !== 'draft') {
        return json({ error: 'Somente administradores podem alterar artigos já publicados.' }, 403, headers)
      }
    }

    const publishedAt =
      status === 'published'
        ? typeof body.publishedAt === 'string' && !Number.isNaN(new Date(body.publishedAt).getTime())
          ? new Date(body.publishedAt).toISOString()
          : existingArticle?.published_at ?? new Date().toISOString()
        : null
    const authorUserId = existingArticle?.author_user_id ?? authUser?.id ?? ''

    const savedArticle = await upsertArticleRow(env, {
      id: articleId,
      slug,
      title,
      excerpt,
      content_html: contentHtml,
      category,
      status,
      author_user_id: authorUserId,
      tags,
      featured,
      cover_image_url: coverImageUrl,
      card_image_url: cardImageUrl,
      sources,
      published_at: publishedAt,
    })

    const shouldNotify = status === 'published' && existingArticle?.status !== 'published'

    if (shouldNotify) {
      const baseUrl = normalizeBaseUrl(env.APP_BASE_URL) || new URL(request.url).origin
      const workerBaseUrl = new URL(request.url).origin
      await notifyArticleCategorySubscribers(env, savedArticle, category, baseUrl, workerBaseUrl)
    }

    return json(
      {
        article: savedArticle,
        publicationNotificationSent: shouldNotify,
      },
      existingArticle ? 200 : 201,
      headers,
    )
  } catch (error) {
    return json(
      {
        error: error instanceof Error ? error.message : 'Não foi possível salvar o artigo.',
      },
      400,
      headers,
    )
  }
}

async function handleListUsers(request: Request, env: GatewayEnv, headers: Record<string, string>) {
  const authUser = await getAuthenticatedUser(request, env)

  if (!isAdminUser(authUser)) {
    return json({ error: 'Apenas administradores podem acessar usuários.' }, 403, headers)
  }

  try {
    const users = await listCatequeticoUsers(env)
    return json({ users }, 200, headers)
  } catch (error) {
    return json(
      {
        error: error instanceof Error ? error.message : 'Não foi possível carregar os usuários.',
      },
      400,
      headers,
    )
  }
}

async function handleCreateUser(request: Request, env: GatewayEnv, headers: Record<string, string>) {
  const authUser = await getAuthenticatedUser(request, env)

  if (!isAdminUser(authUser)) {
    return json({ error: 'Apenas administradores podem criar usuários.' }, 403, headers)
  }

  const body = await parseJson<CreateUserRequestBody>(request)

  if (!body) {
    return json({ error: 'Corpo inválido.' }, 400, headers)
  }

  const email = body.email?.trim().toLowerCase() ?? ''
  const password = body.password?.trim() ?? ''
  const role = normalizeUserRole(body.role)
  const name = buildDisplayName(email, body.name)

  if (!isValidEmail(email)) {
    return json({ error: 'Informe um email válido.' }, 400, headers)
  }

  if (password.length < 6) {
    return json({ error: 'A senha precisa ter pelo menos 6 caracteres.' }, 400, headers)
  }

  if (!role) {
    return json({ error: 'Perfil inválido.' }, 400, headers)
  }

  const existingSharedUser = await getSharedUserByEmail(env, email)

  if (existingSharedUser) {
    const existingAccess = await getUserAppAccessByUserId(env, existingSharedUser.id)

    if (existingAccess?.ativo) {
      return json({ error: 'Este email já possui acesso ao Catequético.' }, 400, headers)
    }
  }

  let createdUserId: string | null = null

  try {
    const reusedExistingAccount = Boolean(existingSharedUser)

    if (existingSharedUser) {
      await updateAuthUser(env, existingSharedUser.id, {
        name,
        role,
      })
    } else {
      const authUserRecord = await createAuthUser(env, {
        email,
        password,
        name,
        role,
      })

      createdUserId = authUserRecord.id
    }

    const targetUserId = existingSharedUser?.id ?? createdUserId

    if (!targetUserId) {
      throw new Error('Não foi possível identificar o usuário criado no Auth.')
    }

    const sharedUser = await upsertSharedUserProfile(env, {
      id: targetUserId,
      email,
      name,
      active: true,
    })
    const access = await upsertUserAppAccess(env, {
      userId: targetUserId,
      role,
      active: true,
    })
    const profile = mapCatequeticoUser({
      sharedUser,
      access,
    })

    let credentialsEmailQueued = false
    let notice: string | null = null

    if (reusedExistingAccount) {
      notice =
        'A conta já existia em outro sistema compartilhado. O acesso ao Catequético foi concedido sem alterar a senha global.'
    } else {
      try {
        await sendUserCredentialsEmail(env, {
          email,
          password,
          role,
          baseUrl: new URL(request.url).origin,
        })
        credentialsEmailQueued = true
      } catch (error) {
        notice = error instanceof Error ? error.message : 'Não foi possível enviar o email de credenciais.'
      }
    }

    return json(
      {
        user: profile,
        reusedExistingAccount,
        credentialsEmailQueued,
        notice,
      },
      reusedExistingAccount ? 200 : 201,
      headers,
    )
  } catch (error) {
    if (createdUserId) {
      try {
        await deleteAuthUser(env, createdUserId)
      } catch {
        // O rollback e melhor esforço; o erro principal continua sendo devolvido.
      }
    }

    return json(
      {
        error: error instanceof Error ? error.message : 'Não foi possível criar o usuário.',
      },
      400,
      headers,
    )
  }
}

async function handleUpdateUser(
  request: Request,
  env: GatewayEnv,
  headers: Record<string, string>,
  userId: string,
) {
  const authUser = await getAuthenticatedUser(request, env)

  if (!isAdminUser(authUser)) {
    return json({ error: 'Apenas administradores podem atualizar usuários.' }, 403, headers)
  }

  if (!isUuid(userId)) {
    return json({ error: 'Usuário inválido.' }, 400, headers)
  }

  if (authUser?.id === userId) {
    return json({ error: 'Não é permitido alterar o próprio perfil por esta tela.' }, 400, headers)
  }

  const body = await parseJson<UpdateUserRequestBody>(request)

  if (!body) {
    return json({ error: 'Corpo inválido.' }, 400, headers)
  }

  const currentUser = await getCatequeticoUserById(env, userId)

  if (!currentUser) {
    return json({ error: 'Usuário do Catequético não encontrado.' }, 404, headers)
  }

  const role = normalizeUserRole(body.role)

  if (!role) {
    return json({ error: 'Perfil inválido.' }, 400, headers)
  }

  const name = buildDisplayName(currentUser.email, body.name ?? currentUser.nome)

  try {
    await updateAuthUser(env, userId, {
      name,
      role,
    })
    const sharedUser = await upsertSharedUserProfile(env, {
      id: userId,
      email: currentUser.email,
      name,
      active: currentUser.ativo,
    })
    const access = await upsertUserAppAccess(env, {
      userId,
      role,
      active: currentUser.ativo,
    })
    const updatedUser = mapCatequeticoUser({
      sharedUser,
      access,
    })

    return json({ user: updatedUser }, 200, headers)
  } catch (error) {
    return json(
      {
        error: error instanceof Error ? error.message : 'Não foi possível atualizar o usuário.',
      },
      400,
      headers,
    )
  }
}

async function handleDeleteUser(
  request: Request,
  env: GatewayEnv,
  headers: Record<string, string>,
  userId: string,
) {
  const authUser = await getAuthenticatedUser(request, env)

  if (!isAdminUser(authUser)) {
    return json({ error: 'Apenas administradores podem excluir usuários.' }, 403, headers)
  }

  if (!isUuid(userId)) {
    return json({ error: 'Usuário inválido.' }, 400, headers)
  }

  if (authUser?.id === userId) {
    return json({ error: 'Não é permitido excluir o próprio usuário.' }, 400, headers)
  }

  const currentUser = await getCatequeticoUserById(env, userId)

  if (!currentUser) {
    return json({ error: 'Usuário do Catequético não encontrado.' }, 404, headers)
  }

  try {
    await deleteUserAppAccess(env, userId)
    return json({ ok: true }, 200, headers)
  } catch (error) {
    return json(
      {
        error: error instanceof Error ? error.message : 'Não foi possível excluir o usuário.',
      },
      400,
      headers,
    )
  }
}

async function handleArticleSubscriptionUnsubscribe(
  request: Request,
  env: GatewayEnv,
  headers: Record<string, string>,
) {
  const url = new URL(request.url)
  const token = url.searchParams.get('token')?.trim() ?? ''

  if (!isUuid(token)) {
    return html(
      `<main style="font-family:system-ui;padding:32px;max-width:640px;margin:0 auto;"><h1>Link inválido</h1><p>O token de descadastro informado não é válido.</p></main>`,
      400,
      headers,
    )
  }

  const { response, data } = await supabaseRest<ArticleSubscriptionRow[]>(
    env,
    `/article_category_subscriptions?select=*&unsubscribe_token=eq.${encodeURIComponent(token)}&limit=1`,
    { method: 'GET' },
  )

  if (!response.ok || !Array.isArray(data) || data.length === 0) {
    return html(
      `<main style="font-family:system-ui;padding:32px;max-width:640px;margin:0 auto;"><h1>Inscrição não encontrada</h1><p>Este link não corresponde a uma inscrição ativa.</p></main>`,
      404,
      headers,
    )
  }

  const subscription = data[0]

  if (!subscription.unsubscribed_at) {
    await supabaseRest(
      env,
      `/article_category_subscriptions?id=eq.${subscription.id}`,
      {
        method: 'PATCH',
        body: JSON.stringify({
          unsubscribed_at: new Date().toISOString(),
        }),
      },
    )

    await insertArticleNotificationEvents(env, [
      {
        subscription_id: subscription.id,
        category: subscription.category,
        recipient_email: subscription.email,
        event_type: 'unsubscribe',
        payload: {
          source: subscription.source,
        },
      },
    ])
  }

  const categoryLabel = getArticleCategoryDetails(subscription.category).label

  return html(
    `<main style="font-family:system-ui;padding:32px;max-width:640px;margin:0 auto;"><h1>Descadastro concluído</h1><p>O endereço <strong>${escapeHtml(subscription.email)}</strong> não receberá mais notificações de novos artigos em <strong>${escapeHtml(categoryLabel)}</strong>.</p></main>`,
    200,
    headers,
  )
}

async function handleUnsubscribe(request: Request, env: GatewayEnv, headers: Record<string, string>) {
  const url = new URL(request.url)
  const token = url.searchParams.get('token')?.trim() ?? ''

  if (!isUuid(token)) {
    return html(
      `<main style="font-family:system-ui;padding:32px;max-width:640px;margin:0 auto;"><h1>Link inválido</h1><p>O token de descadastro informado não é válido.</p></main>`,
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
      `<main style="font-family:system-ui;padding:32px;max-width:640px;margin:0 auto;"><h1>Inscrição não encontrada</h1><p>Este link não corresponde a uma assinatura ativa.</p></main>`,
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
    `<main style="font-family:system-ui;padding:32px;max-width:640px;margin:0 auto;"><h1>Descadastro concluído</h1><p>O endereço <strong>${escapeHtml(subscription.email)}</strong> não receberá mais notificações desta conversa.</p></main>`,
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
          site: getSiteName(runtimeEnv),
          storageBucket: runtimeEnv.SUPABASE_STORAGE_BUCKET,
          note: 'A service_role permanece no Worker. A anon key não é devolvida por este endpoint.',
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

    if (url.pathname === '/article-subscriptions' && request.method === 'POST') {
      return handleCreateArticleSubscription(request, runtimeEnv, headers)
    }

    if (url.pathname === '/article-subscriptions/unsubscribe' && request.method === 'GET') {
      return handleArticleSubscriptionUnsubscribe(request, runtimeEnv, headers)
    }

    if (url.pathname === '/admin/users' && request.method === 'GET') {
      return handleListUsers(request, runtimeEnv, headers)
    }

    if (url.pathname === '/admin/users' && request.method === 'POST') {
      return handleCreateUser(request, runtimeEnv, headers)
    }

    if (url.pathname.startsWith('/admin/users/')) {
      const userId = url.pathname.slice('/admin/users/'.length)

      if (request.method === 'PATCH') {
        return handleUpdateUser(request, runtimeEnv, headers, userId)
      }

      if (request.method === 'DELETE') {
        return handleDeleteUser(request, runtimeEnv, headers, userId)
      }
    }

    if (url.pathname === '/admin/articles' && request.method === 'POST') {
      return handleUpsertArticle(request, runtimeEnv, headers)
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
        return json({ error: payload.error ?? 'Não foi possível assinar o download.' }, 400, headers)
      }

      return json(
        {
          url: `${runtimeEnv.VITE_SUPABASE_URL}/storage/v1${payload.signedURL}`,
        },
        200,
        headers,
      )
    }

    return json({ error: 'Rota não encontrada.' }, 404, headers)
  },
} satisfies ExportedHandler<GatewayEnv>
