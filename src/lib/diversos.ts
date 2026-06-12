import type { Article, ArticleCategory } from '@/types/content'

export const articleCategoryOptions: {
  value: ArticleCategory
  label: string
  description: string
  folderSlug: string
}[] = [
  {
    value: 'general',
    label: 'Gerais',
    description: 'Artigos de temas variados para formacao e apoio pastoral.',
    folderSlug: 'gerais',
  },
  {
    value: 'saints-life',
    label: 'Vida dos Santos',
    description: 'Artigos dedicados a historias, testemunhos e espiritualidade dos santos.',
    folderSlug: 'vida-dos-santos',
  },
]

const articleCategoryMeta = new Map(
  articleCategoryOptions.map((option) => [option.value, option]),
)

export function normalizeArticleCategory(value: unknown): ArticleCategory {
  return value === 'saints-life' ? 'saints-life' : 'general'
}

export function getArticleCategoryMeta(category: ArticleCategory) {
  return articleCategoryMeta.get(category) ?? articleCategoryMeta.get('general')!
}

export function getArticleCategoryPath(category: ArticleCategory) {
  return `/artigos/pasta/${getArticleCategoryMeta(category).folderSlug}`
}

export function getArticleCategoryFromFolderSlug(folderSlug: string) {
  return articleCategoryOptions.find((option) => option.folderSlug === folderSlug)?.value ?? null
}

export function getArticlePath(article: Pick<Article, 'slug'>) {
  return `/artigos/${article.slug}`
}
