import { Navigate, useParams } from 'react-router-dom'
import { ArticleCard } from '@/components/content/article-card'
import { SectionTitle } from '@/components/home/section-title'
import { FloatingBackButton } from '@/components/navigation/floating-back-button'
import { useCMSState } from '@/hooks/use-cms'
import {
  articleCategoryOptions,
  getArticleCategoryFromFolderSlug,
  getArticleCategoryMeta,
} from '@/lib/diversos'

const validFolders = new Set(articleCategoryOptions.map((option) => option.folderSlug))

export function ArticleCategoryPage() {
  const { folderSlug } = useParams()
  const { data } = useCMSState()

  if (!folderSlug || !validFolders.has(folderSlug)) {
    return <Navigate to="/artigos" replace />
  }

  if (!data) {
    return <div className="px-4 py-16 text-stone-700">Carregando pasta...</div>
  }

  const category = getArticleCategoryFromFolderSlug(folderSlug)
  if (!category) {
    return <Navigate to="/artigos" replace />
  }

  const meta = getArticleCategoryMeta(category)
  const filteredArticles = data.articles.filter((article) => article.category === category)

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 pb-24">
      <FloatingBackButton to="/artigos" label="Voltar para as pastas de artigos" />

      <SectionTitle
        eyebrow="pasta"
        title={meta.label}
        body={meta.description}
      />

      <div className="grid gap-5 lg:grid-cols-2">
        {filteredArticles.map((article) => (
          <ArticleCard key={article.id} article={article} />
        ))}
      </div>

      {filteredArticles.length === 0 ? (
        <div className="rounded-[26px] border border-dashed border-stone-300 bg-white/70 p-6 text-sm leading-6 text-stone-600">
          Nenhum artigo foi publicado nesta pasta ainda.
        </div>
      ) : null}
    </section>
  )
}
