import { useEffect, useState, type FormEvent } from 'react'
import { ChevronDown, MessageSquare, Reply, ShieldCheck } from 'lucide-react'
import { useLocation } from 'react-router-dom'
import { toast } from 'sonner'
import { useComments, useCreateComment } from '@/hooks/use-comments'
import { cn, formatDate } from '@/lib/utils'
import { useAuth } from '@/providers/auth-provider'
import { commentService } from '@/services/comment-service'
import type { Comment, CommentContentType } from '@/types/content'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'

interface CommentSectionProps {
  contentType: CommentContentType
  contentId: string
}

interface CommentFormProps {
  contentType: CommentContentType
  contentId: string
  parentCommentId?: string
  onCancel?: () => void
  onSubmitted?: (result: { subscriptionConfirmationNeeded: boolean }) => void
  submitLabel: string
}

function isValidEmail(value: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)
}

function CommentForm({
  contentType,
  contentId,
  parentCommentId,
  onCancel,
  onSubmitted,
  submitLabel,
}: CommentFormProps) {
  const { isAuthenticated } = useAuth()
  const createComment = useCreateComment(contentType, contentId)
  const [authorName, setAuthorName] = useState('')
  const [authorEmail, setAuthorEmail] = useState('')
  const [body, setBody] = useState('')
  const [notifyReplies, setNotifyReplies] = useState(false)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()

    const trimmedName = authorName.trim()
    const trimmedEmail = authorEmail.trim().toLowerCase()
    const trimmedBody = body.trim()

    if (!trimmedName) {
      toast.error('Informe seu nome.')
      return
    }

    if (!trimmedBody) {
      toast.error('Escreva um comentario antes de enviar.')
      return
    }

    if (!isAuthenticated && trimmedEmail && !isValidEmail(trimmedEmail)) {
      toast.error('Informe um email valido.')
      return
    }

    if (!isAuthenticated && notifyReplies && !trimmedEmail) {
      toast.error('Informe seu email para acompanhar a conversa.')
      return
    }

    try {
      const result = await createComment.mutateAsync({
        contentType,
        contentId,
        parentCommentId,
        authorName: trimmedName,
        authorEmail: isAuthenticated ? undefined : trimmedEmail || undefined,
        body: trimmedBody,
        notifyReplies: isAuthenticated ? false : notifyReplies,
      })

      setBody('')

      if (!parentCommentId) {
        if (!isAuthenticated) {
          setAuthorEmail(trimmedEmail)
        }
      } else {
        setNotifyReplies(false)
      }

      toast.success(parentCommentId ? 'Resposta publicada.' : 'Comentario publicado.')
      onSubmitted?.({
        subscriptionConfirmationNeeded: result.subscriptionConfirmationNeeded,
      })
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Nao foi possivel publicar o comentario.')
    }
  }

  return (
    <form className="space-y-4" onSubmit={handleSubmit}>
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-2">
          <Label htmlFor={parentCommentId ? `reply-name-${parentCommentId}` : 'comment-name'}>Nome</Label>
          <Input
            id={parentCommentId ? `reply-name-${parentCommentId}` : 'comment-name'}
            value={authorName}
            onChange={(event) => setAuthorName(event.target.value)}
            placeholder={isAuthenticated ? 'Nome que aparecera no comentario' : 'Seu nome'}
            maxLength={80}
          />
        </div>

        {!isAuthenticated ? (
          <div className="space-y-2">
            <Label htmlFor={parentCommentId ? `reply-email-${parentCommentId}` : 'comment-email'}>
              Email
            </Label>
            <Input
              id={parentCommentId ? `reply-email-${parentCommentId}` : 'comment-email'}
              type="email"
              value={authorEmail}
              onChange={(event) => setAuthorEmail(event.target.value)}
              placeholder="voce@exemplo.com"
            />
          </div>
        ) : null}
      </div>

      <div className="space-y-2">
        <Label htmlFor={parentCommentId ? `reply-body-${parentCommentId}` : 'comment-body'}>
          {parentCommentId ? 'Resposta' : 'Comentario'}
        </Label>
        <Textarea
          id={parentCommentId ? `reply-body-${parentCommentId}` : 'comment-body'}
          value={body}
          onChange={(event) => setBody(event.target.value)}
          placeholder={parentCommentId ? 'Escreva sua resposta...' : 'Partilhe sua contribuicao para esta conversa...'}
          maxLength={5000}
        />
      </div>

      {!isAuthenticated ? (
        <label className="flex items-start gap-3 rounded-3xl border border-stone-200 bg-stone-50/80 px-4 py-3 text-sm text-stone-700">
          <input
            type="checkbox"
            className="mt-1 h-4 w-4 rounded border-stone-300 text-primary focus:ring-primary"
            checked={notifyReplies}
            onChange={(event) => setNotifyReplies(event.target.checked)}
          />
          <span>
            Quero acompanhar esta conversa por email.
            <span className="block text-xs text-stone-500">
              Se marcar esta opcao, o email passa a ser obrigatorio e voce podera sair da thread por link de descadastro.
            </span>
          </span>
        </label>
      ) : (
        <div className="rounded-3xl border border-primary/15 bg-primary/5 px-4 py-3 text-sm text-stone-700">
          Comentario administrativo. Seu email nao e exigido aqui; as notificacoes do admin sao tratadas pelo sistema.
        </div>
      )}

      <div className="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={createComment.isPending}>
          {createComment.isPending ? 'Enviando...' : submitLabel}
        </Button>
        {onCancel ? (
          <Button type="button" variant="ghost" onClick={onCancel}>
            Cancelar
          </Button>
        ) : null}
      </div>
    </form>
  )
}

function CommentCard({ comment, children }: { comment: Comment; children?: React.ReactNode }) {
  const isAdmin = comment.authorKind === 'admin'

  return (
    <article
      id={`comment-${comment.id}`}
      className={[
        'rounded-[28px] border p-5 shadow-[0_18px_45px_rgba(74,61,35,0.07)]',
        isAdmin
          ? 'border-primary/20 bg-[linear-gradient(180deg,rgba(231,241,233,0.96),rgba(255,255,255,0.98))]'
          : 'border-stone-200 bg-white/90',
      ].join(' ')}
    >
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-semibold text-stone-900">{comment.authorName}</span>
        {isAdmin ? (
          <Badge className="bg-primary text-primary-foreground">
            <ShieldCheck className="mr-1 h-3.5 w-3.5" />
            Admin
          </Badge>
        ) : null}
        <span className="text-xs uppercase tracking-[0.18em] text-stone-500">
          {formatDate(comment.createdAt)}
        </span>
      </div>
      <p className="mt-3 whitespace-pre-line text-[15px] leading-7 text-stone-700">{comment.body}</p>
      {children ? <div className="mt-4">{children}</div> : null}
    </article>
  )
}

function CommentThread({
  contentType,
  contentId,
  root,
  onSubscriptionNoticeNeeded,
}: {
  contentType: CommentContentType
  contentId: string
  root: Comment
  onSubscriptionNoticeNeeded: () => void
}) {
  const [isReplying, setIsReplying] = useState(false)

  return (
    <div className="space-y-4">
      <CommentCard comment={root}>
        <Button type="button" variant="ghost" size="sm" onClick={() => setIsReplying((current) => !current)}>
          <Reply className="mr-2 h-4 w-4" />
          {isReplying ? 'Fechar resposta' : 'Responder'}
        </Button>
      </CommentCard>

      {isReplying ? (
        <div className="ml-0 rounded-[28px] border border-stone-200 bg-white/80 p-4 sm:ml-8">
          <CommentForm
            contentType={contentType}
            contentId={contentId}
            parentCommentId={root.id}
            onCancel={() => setIsReplying(false)}
            onSubmitted={(result) => {
              setIsReplying(false)

              if (result.subscriptionConfirmationNeeded) {
                onSubscriptionNoticeNeeded()
              }
            }}
            submitLabel="Publicar resposta"
          />
        </div>
      ) : null}

      {root.replies.length > 0 ? (
        <div className="space-y-3 border-l border-stone-200 pl-0 sm:ml-8 sm:pl-5">
          {root.replies.map((reply) => (
            <CommentCard key={reply.id} comment={reply} />
          ))}
        </div>
      ) : null}
    </div>
  )
}

export function CommentSection({ contentType, contentId }: CommentSectionProps) {
  const [page, setPage] = useState(1)
  const [isOpen, setIsOpen] = useState(false)
  const [subscriptionNoticeVisible, setSubscriptionNoticeVisible] = useState(false)
  const isAvailable = commentService.isAvailable()
  const location = useLocation()
  const threadId = new URLSearchParams(location.search).get('thread')
  const commentsQuery = useComments(contentType, contentId, page, isOpen || Boolean(threadId))

  useEffect(() => {
    setPage(1)
    setSubscriptionNoticeVisible(false)
  }, [contentId, contentType])

  useEffect(() => {
    if (threadId) {
      setIsOpen(true)
    }
  }, [threadId])

  useEffect(() => {
    if (!commentsQuery.data) return

    if (!threadId) return

    const element = document.getElementById(`comment-${threadId}`)

    if (!element) return

    window.requestAnimationFrame(() => {
      element.scrollIntoView({ behavior: 'smooth', block: 'start' })
    })
  }, [commentsQuery.data, threadId])

  return (
    <Card className="overflow-hidden p-0">
      <button
        type="button"
        className="flex w-full items-center justify-between gap-4 px-5 py-5 text-left transition hover:bg-stone-50/60 sm:px-6"
        onClick={() => setIsOpen((current) => !current)}
        aria-expanded={isOpen}
      >
        <div className="flex min-w-0 items-center gap-3">
          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-primary/10 text-primary">
            <MessageSquare className="h-5 w-5" />
          </div>
          <div>
            <CardTitle>Comentarios</CardTitle>
            <CardDescription className="mt-1">
              {isOpen
                ? 'Publique sua mensagem ou responda a uma conversa ja iniciada.'
                : 'Toque para abrir a area de conversa deste conteudo.'}
            </CardDescription>
          </div>
        </div>

        <div className="flex shrink-0 items-center gap-3 text-sm text-stone-600">
          {commentsQuery.data ? (
            <span className="hidden sm:inline">
              {commentsQuery.data.total} comentario{commentsQuery.data.total === 1 ? '' : 's'}
            </span>
          ) : null}
          <span>{isOpen ? 'Fechar' : 'Abrir'}</span>
          <ChevronDown className={cn('h-4 w-4 transition-transform', isOpen ? 'rotate-180' : 'rotate-0')} />
        </div>
      </button>

      {isOpen ? (
        <div className="space-y-6 border-t border-stone-200/80 p-5 sm:p-6">
          {subscriptionNoticeVisible ? (
            <div className="rounded-[28px] border border-amber-300 bg-[linear-gradient(180deg,rgba(255,251,235,0.98),rgba(255,247,237,0.98))] px-5 py-4 text-sm leading-7 text-amber-950 shadow-[0_18px_45px_rgba(146,64,14,0.08)]">
              <p className="font-semibold uppercase tracking-[0.18em] text-amber-800">Verifique seu email</p>
              <p className="mt-2">
                Enviamos um email confirmando a assinatura desta thread. Ele pode levar alguns minutos para chegar.
                Se cair na caixa de spam, mova-o para a caixa principal para ajudar no recebimento dos proximos emails do sistema.
              </p>
            </div>
          ) : null}

          {isAvailable ? (
            <CommentForm
              contentType={contentType}
              contentId={contentId}
              submitLabel="Publicar comentario"
              onSubmitted={(result) => {
                setSubscriptionNoticeVisible(result.subscriptionConfirmationNeeded)
              }}
            />
          ) : (
            <div className="rounded-[28px] border border-dashed border-stone-300 bg-stone-50/90 px-5 py-4 text-sm text-stone-600">
              Comentarios indisponiveis enquanto o Supabase e o Worker nao estiverem configurados.
            </div>
          )}

          {commentsQuery.isLoading ? (
            <div className="text-sm text-stone-600">Carregando comentarios...</div>
          ) : commentsQuery.error ? (
            <div className="rounded-[24px] border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
              Nao foi possivel carregar os comentarios.
            </div>
          ) : commentsQuery.data ? (
            <>
              <div className="space-y-5">
                {commentsQuery.data.roots.length > 0 ? (
                  commentsQuery.data.roots.map((root) => (
                    <CommentThread
                      key={root.id}
                      contentType={contentType}
                      contentId={contentId}
                      root={root}
                      onSubscriptionNoticeNeeded={() => setSubscriptionNoticeVisible(true)}
                    />
                  ))
                ) : (
                  <div className="rounded-[28px] border border-stone-200 bg-stone-50/80 px-5 py-4 text-sm text-stone-600">
                    Ainda nao ha comentarios nesta pagina.
                  </div>
                )}
              </div>

              {commentsQuery.data.total > commentsQuery.data.pageSize ? (
                <div className="flex flex-wrap items-center justify-between gap-3 border-t border-stone-200 pt-2">
                  <p className="text-sm text-stone-600">
                    Pagina {commentsQuery.data.page} de {Math.max(Math.ceil(commentsQuery.data.total / commentsQuery.data.pageSize), 1)}
                  </p>
                  <div className="flex gap-2">
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={() => setPage((current) => Math.max(current - 1, 1))}
                      disabled={page === 1}
                    >
                      Anterior
                    </Button>
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={() => setPage((current) => current + 1)}
                      disabled={!commentsQuery.data.hasMore}
                    >
                      Proxima
                    </Button>
                  </div>
                </div>
              ) : null}
            </>
          ) : null}
        </div>
      ) : null}
    </Card>
  )
}
