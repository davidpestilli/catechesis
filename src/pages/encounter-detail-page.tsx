import { Link, Navigate, useParams } from 'react-router-dom'
import { Download, FileQuestion, Images, ScrollText } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { useCMSState } from '@/hooks/use-cms'

export function EncounterDetailPage() {
  const { slug } = useParams()
  const { data } = useCMSState()
  const encounter = data?.encounters.find((item) => item.slug === slug)

  if (data && !encounter) {
    return <Navigate to="/encontros" replace />
  }

  if (!encounter) {
    return <div className="px-4 py-16 text-stone-700">Carregando encontro...</div>
  }

  const firstSummary = encounter.assets.find((asset) => asset.kind === 'summary')

  return (
    <section className="mx-auto max-w-5xl px-4 py-10 pb-24">
      <div className="grid gap-8 lg:grid-cols-[1.3fr_0.9fr]">
        <div className="space-y-6">
          <Badge>{encounter.theme || 'Encontro'}</Badge>
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
          {encounter.bodyHtml ? (
            <Card>
              <CardTitle>Texto-base do encontro</CardTitle>
              <div
                className="prose-catechesis mt-4"
                dangerouslySetInnerHTML={{ __html: encounter.bodyHtml }}
              />
            </Card>
          ) : null}
        </div>

        <div className="space-y-4">
          <Card>
            <CardTitle>Explorar este encontro</CardTitle>
            <CardDescription className="mt-2">
              Abra o resumo, revise o quiz e consulte os materiais extras.
            </CardDescription>
            <div className="mt-5 grid gap-3">
              <Button asChild>
                <Link to={`/encontros/${encounter.slug}/resumo`}>
                  <ScrollText className="mr-2 h-4 w-4" />
                  Resumo do encontro
                </Link>
              </Button>
              <Button asChild variant="outline">
                <Link to={`/encontros/${encounter.slug}/quiz`}>
                  <FileQuestion className="mr-2 h-4 w-4" />
                  Quiz
                </Link>
              </Button>
              {encounter.assets
                .filter((asset) => asset.kind === 'support')
                .map((asset) => (
                  <Button key={asset.id} asChild variant="ghost" className="justify-start">
                    <Link to={`/encontros/${encounter.slug}/material/${asset.id}`}>
                      <Images className="mr-2 h-4 w-4" />
                      {asset.title}
                    </Link>
                  </Button>
                ))}
            </div>
          </Card>

          {firstSummary ? (
            <Card>
              <CardTitle>Download rapido</CardTitle>
              <CardDescription className="mt-2">
                Baixe o resumo principal para enviar ou projetar offline.
              </CardDescription>
              <Button asChild variant="outline" className="mt-4 w-full">
                <a href={firstSummary.url} target="_blank" rel="noreferrer">
                  <Download className="mr-2 h-4 w-4" />
                  Baixar resumo
                </a>
              </Button>
            </Card>
          ) : null}

        </div>
      </div>
    </section>
  )
}
