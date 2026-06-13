import { env } from '@/lib/env'
import { supabase } from '@/lib/supabase'
import type {
  Comment,
  CommentDraft,
  CommentPage,
  CommentContentType,
  CreateCommentResult,
} from '@/types/content'

const COMMENTS_PAGE_SIZE = 20

interface CommentRow {
  id: string
  content_type: CommentContentType
  content_id: string
  parent_comment_id: string | null
  root_comment_id: string
  author_kind: 'guest' | 'admin'
  admin_user_id?: string | null
  author_name: string
  author_email?: string | null
  body: string
  notify_replies?: boolean
  created_at: string
  updated_at: string
}

function mapComment(row: CommentRow, replies: Comment[] = []): Comment {
  return {
    id: row.id,
    contentType: row.content_type,
    contentId: row.content_id,
    parentCommentId: row.parent_comment_id ?? undefined,
    rootCommentId: row.root_comment_id,
    authorKind: row.author_kind,
    adminUserId: row.admin_user_id ?? undefined,
    authorName: row.author_name,
    authorEmail: row.author_email ?? undefined,
    body: row.body,
    notifyReplies: row.notify_replies ?? false,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    replies,
  }
}

async function getAuthToken() {
  if (!supabase) return null

  const { data } = await supabase.auth.getSession()
  return data.session?.access_token ?? null
}

export const commentService = {
  isAvailable() {
    return Boolean(supabase && env.workerUrl)
  },

  async listComments(contentType: CommentContentType, contentId: string, page = 1): Promise<CommentPage> {
    if (!supabase) {
      return {
        roots: [],
        total: 0,
        page,
        pageSize: COMMENTS_PAGE_SIZE,
        hasMore: false,
      }
    }

    const from = Math.max(page - 1, 0) * COMMENTS_PAGE_SIZE
    const to = from + COMMENTS_PAGE_SIZE - 1

    const rootsResponse = await supabase
      .from('comments_public')
      .select('*', { count: 'exact' })
      .eq('content_type', contentType)
      .eq('content_id', contentId)
      .is('parent_comment_id', null)
      .order('created_at', { ascending: false })
      .range(from, to)

    if (rootsResponse.error) {
      throw new Error(rootsResponse.error.message)
    }

    const roots = (rootsResponse.data as CommentRow[] | null) ?? []
    const rootIds = roots.map((comment) => comment.id)

    const repliesResponse =
      rootIds.length > 0
        ? await supabase
            .from('comments_public')
            .select('*')
            .in('root_comment_id', rootIds)
            .not('parent_comment_id', 'is', null)
            .order('created_at', { ascending: true })
        : null

    if (repliesResponse?.error) {
      throw new Error(repliesResponse.error.message)
    }

    const replies = ((repliesResponse?.data as CommentRow[] | null) ?? []).map((row) => mapComment(row))
    const repliesByRoot = new Map<string, Comment[]>()

    for (const reply of replies) {
      const list = repliesByRoot.get(reply.rootCommentId) ?? []
      list.push(reply)
      repliesByRoot.set(reply.rootCommentId, list)
    }

    const total = rootsResponse.count ?? 0

    return {
      roots: roots.map((row) => mapComment(row, repliesByRoot.get(row.id) ?? [])),
      total,
      page,
      pageSize: COMMENTS_PAGE_SIZE,
      hasMore: from + roots.length < total,
    }
  },

  async createComment(input: CommentDraft): Promise<CreateCommentResult> {
    if (!env.workerUrl) {
      throw new Error('A URL do Worker nao foi configurada.')
    }

    const token = await getAuthToken()
    const response = await fetch(`${env.workerUrl}/comments`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify(input),
    })

    const payload = (await response.json().catch(() => null)) as
      | { comment?: CommentRow; error?: string; subscriptionConfirmationNeeded?: boolean }
      | null

    if (!response.ok || !payload?.comment) {
      throw new Error(payload?.error ?? 'Nao foi possivel publicar o comentario.')
    }

    return {
      comment: mapComment(payload.comment),
      subscriptionConfirmationNeeded: Boolean(payload.subscriptionConfirmationNeeded),
    }
  },
}
