import DOMPurify from 'dompurify'
import { Navigate, useParams } from 'react-router-dom'
import { Download } from 'lucide-react'
import { FloatingBackButton } from '@/components/navigation/floating-back-button'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { useCMSState } from '@/hooks/use-cms'
import {
  getEncounterPrimarySummaryAsset,
  getEncounterSummaryContent,
  getEncounterSummaryDownloadAsset,
} from '@/lib/encounter-summary'

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

  const summaryContent = getEncounterSummaryContent(encounter)
  const summaryDownloadAsset = getEncounterSummaryDownloadAsset(encounter)
  const asset =
    assetId != null
      ? encounter.assets.find((item) => item.id === assetId)
      : summaryContent
        ? undefined
        : getEncounterPrimarySummaryAsset(encounter)

  if (!asset && !summaryContent) {
    return <Navigate to={`/encontros/${groupSlug}/${encounter.slug}`} replace />
  }

  const title = assetId == null ? summaryContent?.title ?? asset?.title ?? 'Resumo do encontro' : asset?.title
  const description = assetId == null ? summaryContent?.description ?? asset?.description ?? '' : asset?.description
  const downloadAsset = assetId == null ? summaryDownloadAsset : asset?.downloadable ? asset : undefined

  return (
    <section className="mx-auto max-w-5xl px-4 py-10 pb-24">
      <FloatingBackButton
        to={`/encontros/${groupSlug}/${encounter.slug}`}
        label="Voltar ao encontro"
      />

      <Card className="space-y-6">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <CardTitle>{title}</CardTitle>
            <CardDescription className="mt-2">
              {description}
            </CardDescription>
          </div>
          {downloadAsset ? (
            <Button asChild>
              <a href={downloadAsset.url} target="_blank" rel="noreferrer">
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

        {summaryContent ? (
          <div
            className="prose-catechesis"
            dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(summaryContent.html) }}
          />
        ) : null}
      </Card>
    </section>
  )
}
