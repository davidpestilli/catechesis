import { Copy, MessageCircle, Share2 } from 'lucide-react'
import DOMPurify from 'dompurify'
import { useEffect, useState } from 'react'
import { toast } from 'sonner'
import { Navigate, useParams } from 'react-router-dom'
import { CommentSection } from '@/components/comments/comment-section'
import { FloatingBackButton } from '@/components/navigation/floating-back-button'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { useCMSState } from '@/hooks/use-cms'
import { getArticleCategoryMeta, getArticleCategoryPath, getArticlePath } from '@/lib/diversos'
import { formatDate } from '@/lib/utils'

function isHttpUrl(value: string) {
  try {
    const url = new URL(value)
    return url.protocol === 'http:' || url.protocol === 'https:'
  } catch {
    return false
  }
}

function buildArticleShareUrl(slug: string) {
  const url = new URL(window.location.href)
  url.hash = getArticlePath({ slug })
  return url.toString()
}

async function copyTextToClipboard(value: string) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(value)
    return
  }

  const textArea = document.createElement('textarea')
  textArea.value = value
  textArea.setAttribute('readonly', '')
  textArea.style.position = 'absolute'
  textArea.style.left = '-9999px'
  document.body.appendChild(textArea)
  textArea.select()

  try {
    document.execCommand('copy')
  } finally {
    document.body.removeChild(textArea)
  }
}

export function ArticleViewPage() {
  const [shareActionsVisible, setShareActionsVisible] = useState(false)
  const { slug } = useParams()
  const { data } = useCMSState()
  const article = data?.articles.find((item) => item.slug === slug)

  useEffect(() => {
    window.scrollTo({ top: 0, left: 0 })
  }, [slug])

  if (data && !article) {
    return <Navigate to="/artigos" replace />
  }

  if (!article) {
    return <div className="px-4 py-16 text-stone-700">Carregando artigo...</div>
  }

  const activeArticle = article
  const categoryMeta = getArticleCategoryMeta(activeArticle.category)
  const backPath = getArticleCategoryPath(activeArticle.category)
  const articleSources = activeArticle.sources.filter(Boolean)
  const shareUrl = buildArticleShareUrl(activeArticle.slug)

  async function handleCopyShareUrl() {
    try {
      await copyTextToClipboard(shareUrl)
      toast.success('Endereço do artigo copiado.')
    } catch {
      toast.error('Não foi possível copiar o endereço do artigo.')
    }
  }

  function handleShareOnWhatsApp() {
    const shareText = `Confira este artigo: ${activeArticle.title}\n${shareUrl}`
    const whatsappUrl = `https://wa.me/?text=${encodeURIComponent(shareText)}`

    window.open(whatsappUrl, '_blank', 'noopener,noreferrer')
  }

  return (
    <section className="mx-auto max-w-4xl px-4 py-10 pb-24">
      <FloatingBackButton to={backPath} label={`Voltar para a pasta ${categoryMeta.label}`} />

      <Card className="overflow-hidden p-0">
        {activeArticle.coverImageUrl ? (
          <img
            src={activeArticle.coverImageUrl}
            alt={activeArticle.title}
            className="h-72 w-full object-cover"
          />
        ) : null}
        <div className="space-y-5 p-6 sm:p-8">
          <div className="flex flex-wrap gap-2">
            <Badge className="bg-primary/12 text-primary">{categoryMeta.label}</Badge>
            {activeArticle.tags.map((tag) => (
              <Badge key={tag}>{tag}</Badge>
            ))}
          </div>
          <div>
            <h1 className="font-display text-4xl text-stone-900 sm:text-5xl">{activeArticle.title}</h1>
            <p className="mt-3 text-sm uppercase tracking-[0.2em] text-stone-500">
              publicado em {formatDate(activeArticle.publishedAt)}
            </p>
          </div>
          <div className="rounded-[24px] border border-stone-200 bg-stone-50/80 p-4">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p className="text-sm font-semibold text-stone-900">Compartilhar este artigo</p>
                <p className="text-sm text-stone-600">Copie o link ou envie direto pelo WhatsApp.</p>
              </div>
              <Button
                type="button"
                variant="outline"
                onClick={() => setShareActionsVisible((current) => !current)}
              >
                <Share2 className="mr-2 h-4 w-4" />
                Compartilhar
              </Button>
            </div>
            {shareActionsVisible ? (
              <div className="mt-4 flex flex-col gap-3 sm:flex-row">
                <Button type="button" onClick={handleCopyShareUrl}>
                  <Copy className="mr-2 h-4 w-4" />
                  Copiar endereço
                </Button>
                <Button type="button" variant="secondary" onClick={handleShareOnWhatsApp}>
                  <MessageCircle className="mr-2 h-4 w-4" />
                  Enviar no WhatsApp
                </Button>
              </div>
            ) : null}
          </div>
          <div
            className="prose-catechesis"
            dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(activeArticle.contentHtml) }}
          />
          {articleSources.length > 0 ? (
            <div className="rounded-[24px] border border-stone-200 bg-stone-50/80 p-5">
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-stone-500">
                Fontes utilizadas
              </p>
              <ul className="mt-3 space-y-3 text-sm leading-6 text-stone-700">
                {articleSources.map((source) => (
                  <li key={source}>
                    {isHttpUrl(source) ? (
                      <a
                        href={source}
                        target="_blank"
                        rel="noreferrer"
                        className="font-medium text-primary underline-offset-4 hover:underline"
                      >
                        {source}
                      </a>
                    ) : (
                      source
                    )}
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
        </div>
      </Card>

      <div className="mt-8">
        <CommentSection contentType="article" contentId={activeArticle.id} />
      </div>
    </section>
  )
}
