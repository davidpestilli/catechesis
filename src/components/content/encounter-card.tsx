import { Link } from 'react-router-dom'
import { ArrowRight, FileQuestion, ScrollText } from 'lucide-react'
import type { Encounter } from '@/types/content'
import { Badge } from '@/components/ui/badge'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'

export function EncounterCard({ encounter }: { encounter: Encounter }) {
  return (
    <Card className="group overflow-hidden p-0">
      {encounter.coverImageUrl ? (
        <img
          src={encounter.coverImageUrl}
          alt={encounter.title}
          className="h-52 w-full object-cover transition duration-500 group-hover:scale-[1.03]"
        />
      ) : null}
      <div className="space-y-4 p-5">
        <Badge>{encounter.theme || 'Encontro'}</Badge>
        <div>
          <CardTitle>{encounter.title}</CardTitle>
          <CardDescription className="mt-3">{encounter.summary}</CardDescription>
        </div>
        <div className="flex flex-wrap gap-2 text-xs text-stone-500">
          <span className="inline-flex items-center gap-1">
            <ScrollText className="h-3.5 w-3.5" />
            {encounter.assets.filter((item) => item.kind === 'summary').length} resumo(s)
          </span>
          <span className="inline-flex items-center gap-1">
            <FileQuestion className="h-3.5 w-3.5" />
            {encounter.quiz?.questions.length ?? 0} pergunta(s)
          </span>
        </div>
        <Link
          to={`/encontros/${encounter.slug}`}
          className="inline-flex items-center gap-2 text-sm font-semibold text-stone-900"
        >
          Abrir encontro
          <ArrowRight className="h-4 w-4" />
        </Link>
      </div>
    </Card>
  )
}
