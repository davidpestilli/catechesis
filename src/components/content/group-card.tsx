import { Link } from 'react-router-dom'
import { ArrowRight, Flame, Layers3 } from 'lucide-react'
import type { ClassGroup } from '@/types/content'
import { Badge } from '@/components/ui/badge'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'

interface GroupCardProps {
  group: ClassGroup
  encounterCount: number
  coverImageUrl?: string
}

export function GroupCard({ group, encounterCount, coverImageUrl }: GroupCardProps) {
  return (
    <Card className="group overflow-hidden p-0">
      {coverImageUrl ? (
        <img
          src={coverImageUrl}
          alt={group.name}
          className="h-52 w-full object-cover transition duration-500 group-hover:scale-[1.03]"
        />
      ) : null}
      <div className="space-y-4 p-5">
        <Badge>Turma</Badge>
        <div>
          <CardTitle>{group.name}</CardTitle>
          <CardDescription className="mt-3">
            {group.battleCry || 'Acesse os encontros, resumos, materiais e quizzes desta turma.'}
          </CardDescription>
        </div>
        <div className="flex flex-wrap gap-3 text-xs text-stone-500">
          <span className="inline-flex items-center gap-1">
            <Layers3 className="h-3.5 w-3.5" />
            {encounterCount} encontro(s)
          </span>
          {group.battleCry ? (
            <span className="inline-flex items-center gap-1">
              <Flame className="h-3.5 w-3.5" />
              Brado ativo
            </span>
          ) : null}
        </div>
        <Link
          to={`/encontros/${group.slug}`}
          className="inline-flex items-center gap-2 text-sm font-semibold text-stone-900"
        >
          Abrir turma
          <ArrowRight className="h-4 w-4" />
        </Link>
      </div>
    </Card>
  )
}
