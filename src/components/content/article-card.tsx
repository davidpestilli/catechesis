import { Link } from 'react-router-dom'
import { ArrowUpRight } from 'lucide-react'
import type { Article } from '@/types/content'
import { Badge } from '@/components/ui/badge'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { getArticlePath } from '@/lib/diversos'
import { formatDate } from '@/lib/utils'

export function ArticleCard({ article }: { article: Article }) {
  const cardImageUrl = article.cardImageUrl || article.coverImageUrl

  return (
    <Card className="group overflow-hidden p-0">
      {cardImageUrl ? (
        <div className="overflow-hidden">
          <img
            src={cardImageUrl}
            alt={article.title}
            className="h-56 w-full object-cover transition duration-500 group-hover:scale-[1.03]"
          />
        </div>
      ) : null}
      <div className="p-5">
        <div className="flex flex-wrap gap-2">
          {article.featured ? <Badge>Destaque</Badge> : null}
          {article.tags.slice(0, 2).map((tag) => (
            <Badge key={tag} className="bg-stone-200 text-stone-700">
              {tag}
            </Badge>
          ))}
        </div>
        <CardTitle className="mt-5">{article.title}</CardTitle>
        <CardDescription className="mt-3">{article.excerpt}</CardDescription>
        <div className="mt-5 flex items-center justify-between text-sm text-stone-500">
          <span>{formatDate(article.publishedAt)}</span>
          <Link
            to={getArticlePath(article)}
            className="inline-flex items-center gap-2 font-semibold text-stone-900"
          >
            Ler artigo
            <ArrowUpRight className="h-4 w-4" />
          </Link>
        </div>
      </div>
    </Card>
  )
}
