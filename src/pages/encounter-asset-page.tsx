import DOMPurify from 'dompurify'
import { Link, Navigate, useParams } from 'react-router-dom'
import { ArrowLeft, Download } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { useCMSState } from '@/hooks/use-cms'

export function EncounterAssetPage() {
  const { groupSlug, encounterSlug, assetId } = useParams()
  const { data } = useCMSState()
  const group = data?.groups.find((item) => item.slug === groupSlug)
  const encounter = data?.encounters.find(
    (item) => item.slug === encounterSlug && item.groupId === group?.id,
  )

  if (data && !encounter) {
    return <Navigate to="/encontros" replace />
  }

  if (!encounter) {
    return <div className="px-4 py-16 text-stone-700">Carregando conteudo...</div>
  }

  const asset =
    assetId != null
      ? encounter.assets.find((item) => item.id === assetId)
      : encounter.assets.find((item) => item.kind === 'summary')

  if (!asset && !encounter.bodyHtml) {
    return <Navigate to={`/encontros/${groupSlug}/${encounter.slug}`} replace />
  }

  return (
    <section className="mx-auto max-w-5xl px-4 py-10 pb-24">
      <Button asChild variant="ghost" className="mb-6">
        <Link to={`/encontros/${groupSlug}/${encounter.slug}`}>
          <ArrowLeft className="mr-2 h-4 w-4" />
          Voltar ao encontro
        </Link>
      </Button>

      <Card className="space-y-6">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <CardTitle>{asset?.title ?? 'Resumo em HTML'}</CardTitle>
            <CardDescription className="mt-2">
              {asset?.description ?? ''}
            </CardDescription>
          </div>
          {asset?.downloadable ? (
            <Button asChild>
              <a href={asset.url} target="_blank" rel="noreferrer">
                <Download className="mr-2 h-4 w-4" />
                Baixar
              </a>
            </Button>
          ) : null}
        </div>

        {asset?.view === 'image' ? (
          <img src={asset.url} alt={asset.title} className="max-h-[72svh] w-full rounded-[32px] object-contain" />
        ) : null}
        {asset?.view === 'pdf' ? (
          <iframe
            src={asset.url}
            title={asset.title}
            className="h-[72svh] w-full rounded-[32px] border border-stone-200"
          />
        ) : null}
        {asset?.view === 'video' ? (
          <video controls className="max-h-[72svh] w-full rounded-[32px] object-contain">
            <source src={asset.url} />
          </video>
        ) : null}
        {asset?.view === 'html' ? (
          <div
            className="prose-catechesis"
            dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(asset.url) }}
          />
        ) : null}
        {asset?.view === 'link' ? (
          <div className="rounded-[28px] bg-stone-100 p-6">
            <a className="text-primary underline" href={asset.url} target="_blank" rel="noreferrer">
              Abrir material em nova guia
            </a>
          </div>
        ) : null}

        {!asset && encounter.bodyHtml ? (
          <div
            className="prose-catechesis"
            dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(encounter.bodyHtml) }}
          />
        ) : null}
      </Card>
    </section>
  )
}
