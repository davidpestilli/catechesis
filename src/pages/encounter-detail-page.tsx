import { Link, Navigate, useParams } from 'react-router-dom'
import {
  BookOpen,
  FileQuestion,
  ScrollText,
} from 'lucide-react'
import { CommentSection } from '@/components/comments/comment-section'
import { FloatingBackButton } from '@/components/navigation/floating-back-button'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { useCMSState } from '@/hooks/use-cms'
import { getEncounterMaterialGroups } from '@/lib/encounter-materials'
import {
  getEncounterPrimarySummaryAsset,
  getEncounterSummaryContent,
} from '@/lib/encounter-summary'

export function EncounterDetailPage() {
  const { groupSlug, encounterSlug } = useParams()
  const { data } = useCMSState()
  const group = data?.groups.find((item) => item.slug === groupSlug)
  const encounter = data?.encounters.find(
    (item) => item.slug === encounterSlug && item.groupId === group?.id,
  )

  if (data && !encounter) {
    return <Navigate to="/encontros" replace />
  }

  if (!encounter) {
    return <div className="px-4 py-16 text-stone-700">Carregando encontro...</div>
  }

  const summaryContent = getEncounterSummaryContent(encounter)
  const firstSummary = getEncounterPrimarySummaryAsset(encounter)
  const materialGroups = getEncounterMaterialGroups(encounter)

  return (
    <section className="mx-auto max-w-5xl px-4 py-10 pb-24">
      {group ? <FloatingBackButton to={`/encontros/${group.slug}`} label={`Voltar para ${group.name}`} /> : null}
      <div className="grid gap-8 lg:grid-cols-[1.3fr_0.9fr]">
        <div className="space-y-6">
          <div className="flex flex-wrap gap-2">
            <Badge>{encounter.theme || 'Encontro'}</Badge>
            {group ? <Badge className="bg-stone-900 text-stone-50">{group.name}</Badge> : null}
          </div>
          <div>
            <h1 className="font-display text-4xl text-stone-900 sm:text-5xl">{encounter.title}</h1>
            <p className="mt-4 text-lg leading-8 text-stone-700">{encounter.summary}</p>
          </div>
          {encounter.coverImageUrl ? (
            <img
              src={encounter.coverImageUrl}
              alt={encounter.title}
              className="h-72 w-full rounded-[34px] object-cover shadow-halo"
            />
          ) : null}
        </div>

        <div className="space-y-4">
          <Card>
            <CardTitle>Explorar este encontro</CardTitle>
            <CardDescription className="mt-2">
              Abra o resumo, revise o quiz e consulte os materiais extras.
            </CardDescription>
            <div className="mt-5 grid gap-3">
              {summaryContent || firstSummary ? (
                <Button asChild>
                  <Link to={`/encontros/${groupSlug}/${encounter.slug}/resumo`}>
                    <ScrollText className="mr-2 h-4 w-4" />
                    Resumo do encontro
                  </Link>
                </Button>
              ) : null}
              <Button asChild variant="outline">
                <Link to={`/encontros/${groupSlug}/${encounter.slug}/quiz`}>
                  <FileQuestion className="mr-2 h-4 w-4" />
                  Quiz
                </Link>
              </Button>
              {materialGroups.length > 0 ? (
                <Button asChild variant="outline">
                  <Link to={`/encontros/${groupSlug}/${encounter.slug}/materiais`}>
                    <BookOpen className="mr-2 h-4 w-4" />
                    Materiais
                  </Link>
                </Button>
              ) : null}
            </div>
          </Card>
        </div>
      </div>

      <div className="mt-8">
        <CommentSection contentType="encounter" contentId={encounter.id} />
      </div>
    </section>
  )
}
