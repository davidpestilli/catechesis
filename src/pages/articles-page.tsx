import { ArticleCard } from '@/components/content/article-card'
import { SectionTitle } from '@/components/home/section-title'
import { useCMSState } from '@/hooks/use-cms'

export function ArticlesPage() {
  const { data } = useCMSState()

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 pb-24">
      <SectionTitle
        eyebrow=""
        title="Artigos"
        body=""
      />
      <div className="grid gap-5 lg:grid-cols-2">
        {data?.articles.map((article) => (
          <ArticleCard key={article.id} article={article} />
        ))}
      </div>
    </section>
  )
}
