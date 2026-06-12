import { FolderOpen, ScrollText } from 'lucide-react'
import { Link } from 'react-router-dom'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'

interface ArticleFolderCardProps {
  title: string
  description: string
  count: number
  to: string
}

export function ArticleFolderCard({ title, description, count, to }: ArticleFolderCardProps) {
  return (
    <Link to={to} className="block transition hover:-translate-y-1">
      <Card className="h-full">
        <div className="flex items-start justify-between gap-4">
          <div className="rounded-2xl bg-stone-100 p-3 text-stone-700">
            <FolderOpen className="h-6 w-6" />
          </div>
          <span className="inline-flex items-center gap-2 rounded-full bg-stone-100 px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-stone-600">
            <ScrollText className="h-3.5 w-3.5" />
            {count} {count === 1 ? 'artigo' : 'artigos'}
          </span>
        </div>
        <CardTitle className="mt-5">{title}</CardTitle>
        <CardDescription className="mt-3">{description}</CardDescription>
      </Card>
    </Link>
  )
}
