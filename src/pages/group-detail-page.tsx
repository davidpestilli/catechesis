import { Link, Navigate, useParams } from 'react-router-dom'
import { ArrowLeft, Flame } from 'lucide-react'
import { EncounterCard } from '@/components/content/encounter-card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { useCMSState } from '@/hooks/use-cms'

export function GroupDetailPage() {
  const { groupSlug } = useParams()
  const { data } = useCMSState()
  const group = data?.groups.find((item) => item.slug === groupSlug)

  if (data && !group) {
    return <Navigate to="/encontros" replace />
  }

  if (!group || !data) {
    return <div className="px-4 py-16 text-stone-700">Carregando turma...</div>
  }

  const encounters = data.encounters
    .filter((encounter) => encounter.groupId === group.id)
    .sort((first, second) => first.order - second.order)

  return (
    <section className="mx-auto max-w-6xl px-4 py-10 pb-24">
      <Button asChild variant="ghost" className="mb-6">
        <Link to="/encontros">
          <ArrowLeft className="mr-2 h-4 w-4" />
          Voltar para turmas
        </Link>
      </Button>

      <Card className="mb-8">
        <Badge>Turma</Badge>
        <div className="mt-4 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
          <div>
            <CardTitle className="text-4xl">{group.name}</CardTitle>
            <CardDescription className="mt-3 text-base">
              Selecione um encontro desta turma para abrir resumos, materiais e quizzes.
            </CardDescription>
          </div>
          {group.battleCry ? (
            <div className="rounded-[24px] bg-primary/10 px-5 py-4 text-primary">
              <p className="inline-flex items-center gap-2 text-sm font-semibold uppercase tracking-[0.2em]">
                <Flame className="h-4 w-4" />
                Brado
              </p>
              <p className="mt-2 text-lg font-semibold leading-7">{group.battleCry}</p>
            </div>
          ) : null}
        </div>
      </Card>

      {encounters.length > 0 ? (
        <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
          {encounters.map((encounter) => (
            <EncounterCard
              key={encounter.id}
              encounter={encounter}
              href={`/encontros/${group.slug}/${encounter.slug}`}
            />
          ))}
        </div>
      ) : (
        <Card>
          <CardTitle>Nenhum encontro cadastrado</CardTitle>
          <CardDescription className="mt-2">
            Use o painel interno para vincular encontros a esta turma.
          </CardDescription>
        </Card>
      )}
    </section>
  )
}
