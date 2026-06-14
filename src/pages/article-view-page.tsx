import DOMPurify from 'dompurify'
import { Navigate, useParams } from 'react-router-dom'
import { CommentSection } from '@/components/comments/comment-section'
import { FloatingBackButton } from '@/components/navigation/floating-back-button'
import { Badge } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'
import { useCMSState } from '@/hooks/use-cms'
import { getArticleCategoryMeta, getArticleCategoryPath } from '@/lib/diversos'
import { formatDate } from '@/lib/utils'

function isHttpUrl(value: string) {
  try {
    const url = new URL(value)
    return url.protocol === 'http:' || url.protocol === 'https:'
  } catch {
    return false
  }
}

export function ArticleViewPage() {
  const { slug } = useParams()
  const { data } = useCMSState()
  const article = data?.articles.find((item) => item.slug === slug)

  if (data && !article) {
    return <Navigate to="/artigos" replace />
  }

  if (!article) {
    return <div className="px-4 py-16 text-stone-700">Carregando artigo...</div>
  }

  const categoryMeta = getArticleCategoryMeta(article.category)
  const backPath = getArticleCategoryPath(article.category)
  const articleSources = article.sources.filter(Boolean)

  return (
    <section className="mx-auto max-w-4xl px-4 py-10 pb-24">
      <FloatingBackButton to={backPath} label={`Voltar para a pasta ${categoryMeta.label}`} />

      <Card className="overflow-hidden p-0">
        {article.coverImageUrl ? (
          <img src={article.coverImageUrl} alt={article.title} className="h-72 w-full object-cover" />
        ) : null}
        <div className="space-y-5 p-6 sm:p-8">
          <div className="flex flex-wrap gap-2">
            <Badge className="bg-primary/12 text-primary">{categoryMeta.label}</Badge>
            {article.tags.map((tag) => (
              <Badge key={tag}>{tag}</Badge>
            ))}
          </div>
          <div>
            <h1 className="font-display text-4xl text-stone-900 sm:text-5xl">{article.title}</h1>
            <p className="mt-3 text-sm uppercase tracking-[0.2em] text-stone-500">
              publicado em {formatDate(article.publishedAt)}
            </p>
          </div>
          <div
            className="prose-catechesis"
            dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(article.contentHtml) }}
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
        <CommentSection contentType="article" contentId={article.id} />
      </div>
    </section>
  )
}
