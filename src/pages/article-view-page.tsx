import DOMPurify from 'dompurify'
import { Navigate, useParams } from 'react-router-dom'
import { EditorShortcutCard } from '@/components/content/editor-shortcut-card'
import { FloatingBackButton } from '@/components/navigation/floating-back-button'
import { Badge } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'
import { useCMSState } from '@/hooks/use-cms'
import { getArticleCategoryMeta, getArticleCategoryPath } from '@/lib/diversos'
import { formatDate } from '@/lib/utils'

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
        </div>
      </Card>

      <div className="mt-6">
        <EditorShortcutCard
          title="Editar este artigo"
          description="Com a sessao autenticada, voce pode voltar ao painel e atualizar este conteudo sempre que precisar."
        />
      </div>
    </section>
  )
}
