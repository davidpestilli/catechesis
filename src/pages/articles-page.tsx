import { ArticleFolderCard } from '@/components/content/article-folder-card'
import { EditorShortcutCard } from '@/components/content/editor-shortcut-card'
import { SectionTitle } from '@/components/home/section-title'
import { useCMSState } from '@/hooks/use-cms'
import { articleCategoryOptions, getArticleCategoryMeta, getArticleCategoryPath } from '@/lib/diversos'

export function ArticlesPage() {
  const { data } = useCMSState()

  if (!data) {
    return <div className="px-4 py-16 text-stone-700">Carregando artigos...</div>
  }

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 pb-24">
      <SectionTitle
        eyebrow="biblioteca"
        title="Artigos"
        body="Escolha uma pasta para navegar pelos artigos publicados."
      />

      <div className="grid gap-5 lg:grid-cols-2">
        {articleCategoryOptions.map((option) => {
          const meta = getArticleCategoryMeta(option.value)
          const count = data.articles.filter((article) => article.category === option.value).length

          return (
            <ArticleFolderCard
              key={option.value}
              title={meta.label}
              description={meta.description}
              count={count}
              to={getArticleCategoryPath(option.value)}
            />
          )
        })}
      </div>

      <div className="mt-6">
        <EditorShortcutCard
          title="Editar pastas e artigos"
          description="Como voce esta logado, pode abrir o painel para criar novos artigos ou reorganizar o conteudo das pastas."
        />
      </div>
    </section>
  )
}
