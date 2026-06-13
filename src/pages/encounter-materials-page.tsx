import { Navigate, useParams } from 'react-router-dom'
import {
  BookOpen,
  ExternalLink,
  FileImage,
  FileText,
  Globe,
  PlayCircle,
} from 'lucide-react'
import { FloatingBackButton } from '@/components/navigation/floating-back-button'
import { Badge } from '@/components/ui/badge'
import { Card, CardDescription } from '@/components/ui/card'
import { useCMSState } from '@/hooks/use-cms'
import { getEncounterMaterialGroups } from '@/lib/encounter-materials'

export function EncounterMaterialsPage() {
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
    return <div className="px-4 py-16 text-stone-700">Carregando materiais...</div>
  }

  const materialGroups = getEncounterMaterialGroups(encounter)

  if (materialGroups.length === 0) {
    return <Navigate to={`/encontros/${groupSlug}/${encounter.slug}`} replace />
  }

  const materialIcons = {
    video: PlayCircle,
    image: FileImage,
    text: FileText,
    website: Globe,
    book: BookOpen,
  }

  return (
    <section className="mx-auto max-w-5xl px-4 py-10 pb-24">
      <FloatingBackButton to={`/encontros/${groupSlug}/${encounter.slug}`} label="Voltar ao encontro" />

      <Card className="overflow-hidden p-0">
        {encounter.coverImageUrl ? (
          <img
            src={encounter.coverImageUrl}
            alt={encounter.title}
            className="h-56 w-full object-cover sm:h-64"
          />
        ) : null}

        <div className="space-y-6 p-6 sm:p-8">
          <div className="flex flex-wrap gap-2">
            <Badge>{encounter.theme || 'Encontro'}</Badge>
            {group ? <Badge className="bg-stone-900 text-stone-50">{group.name}</Badge> : null}
          </div>

          <div className="max-w-3xl">
            <h1 className="font-display text-4xl text-stone-900 sm:text-5xl">Materiais</h1>
            <CardDescription className="mt-3 text-base leading-7 sm:text-lg">
              Links organizados para aprofundar o encontro com referencias visuais, leituras, videos e outros apoios.
            </CardDescription>
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            {materialGroups.map((group) => {
              const Icon = materialIcons[group.key]

              return (
                <section
                  key={group.key}
                  className="rounded-[28px] border border-stone-200/80 bg-[linear-gradient(180deg,rgba(255,255,255,0.98),rgba(245,240,230,0.88))] p-5 shadow-[0_18px_45px_rgba(74,61,35,0.08)]"
                >
                  <div className="flex items-start gap-3">
                    <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                      <Icon className="h-5 w-5" />
                    </div>
                    <div>
                      <h2 className="font-display text-2xl text-stone-900">{group.label}</h2>
                      <p className="mt-1 text-sm leading-6 text-stone-600">{group.description}</p>
                    </div>
                  </div>

                  <div className="mt-4 space-y-3">
                    {group.items.map((item) => (
                      <a
                        key={item.id}
                        href={item.url}
                        target="_blank"
                        rel="noreferrer"
                        className="group block rounded-[24px] border border-stone-200 bg-white/90 p-4 transition hover:border-primary/30 hover:bg-white hover:shadow-[0_14px_30px_rgba(49,92,67,0.08)]"
                      >
                        <div className="flex items-start justify-between gap-3">
                          <div>
                            <p className="font-semibold text-stone-900">{item.title}</p>
                            <p className="mt-2 text-sm leading-6 text-stone-600">{item.description}</p>
                          </div>
                          <ExternalLink className="mt-1 h-4 w-4 shrink-0 text-stone-400 transition group-hover:text-primary" />
                        </div>
                      </a>
                    ))}
                  </div>
                </section>
              )
            })}
          </div>
        </div>
      </Card>
    </section>
  )
}
